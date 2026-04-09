/**
 * @module parsers/debugfs
 * @description Debugfs Parsers for RCA Tool
 *
 * Parses files from the kernel debug filesystem (debugfs), typically found
 * under `sys/kernel/debug/` in SCC (supportconfig) or SOS (sosreport) archives.
 *
 * ### Parser Inventory
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `hvBalloonParser` | `sys/kernel/debug/hv-balloon`, `sys/kernel/debug/hv_balloon` | Parses Hyper-V Dynamic Memory balloon driver status; calculates committed and max memory from page counts |
 * | `extfragParser` | `sys/kernel/debug/extfrag/extfrag_index`, `sys/kernel/debug/extfrag/unusable_index` | Parses memory fragmentation data per NUMA node and zone; flags high fragmentation at huge-page orders |
 *
 * ### Return Shapes
 *
 * **hvBalloonParser:**
 * ```
 * {
 *   found, hostVersion, capabilities, state, stateText, pageSize,
 *   pagesAdded, pagesOnlined, pagesBallooned, totalPagesCommitted,
 *   maxDynamicPageCount, committedMemoryGB, maxDynamicMemoryGB,
 *   balloonedMemoryMB, warnings[], rawContent
 * }
 * ```
 * Warnings include "Ballooning active" (pages_ballooned > 0) and
 * "Memory near capacity" (committed > 90% of max).
 *
 * **extfragParser (multi-file):**
 * ```
 * {
 *   found, zones[], warnings[], rawContent
 * }
 * ```
 * Each zone: `{ node, zone, extfragIndex[], unusableIndex[] }`
 * Values per order 0-10 (4K through 4MB page sizes).
 * Warnings flag high fragmentation at order 9+ (huge page sizes).
 */

/* global hvBalloonParser, extfragParser */

/**
 * Parses Hyper-V Dynamic Memory (hv-balloon / hv_balloon) debugfs data.
 *
 * The balloon driver exposes key-value pairs showing the host protocol
 * version, memory state, and page-level statistics.  This parser converts
 * page counts to human-readable memory values and raises warnings when
 * the host is actively reclaiming memory via ballooning or when committed
 * memory approaches the dynamic maximum.
 *
 * @type {Object}
 * @property {RegExp} filePattern - Matches `sys/kernel/debug/hv-balloon` and `sys/kernel/debug/hv_balloon`
 * @property {Function} parse - Extracts balloon driver fields from content
 */
const hvBalloonParser = {
    filePattern: /sys\/kernel\/debug\/hv[-_]balloon$/,
    parse: function(content) {
        var result = {
            found: false,
            hostVersion: null,
            capabilities: null,
            state: null,
            stateText: null,
            pageSize: 4096,
            pagesAdded: 0,
            pagesOnlined: 0,
            pagesBallooned: 0,
            totalPagesCommitted: 0,
            maxDynamicPageCount: 0,
            committedMemoryGB: 0,
            maxDynamicMemoryGB: 0,
            balloonedMemoryMB: 0,
            warnings: [],
            rawContent: ''
        };

        if (!content || typeof content !== 'string') return result;

        var trimmed = content.trim();
        if (!trimmed) return result;

        result.rawContent = trimmed;

        // State name lookup
        var stateNames = {
            '0': 'Not configured',
            '1': 'Initialized',
            '2': 'Ready',
            '3': 'Operating',
            '4': 'Degraded'
        };

        // Parse key : value pairs (format: "key<spaces>: value")
        var lines = trimmed.split('\n');
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var match = line.match(/^(\S+(?:\s+\S+)*?)\s*:\s*(.+)$/);
            if (!match) continue;

            var key = match[1].trim().toLowerCase().replace(/[\s-]+/g, '_');
            var value = match[2].trim();

            switch (key) {
                case 'host_version':
                    result.hostVersion = value;
                    result.found = true;
                    break;
                case 'capabilities':
                    result.capabilities = value;
                    break;
                case 'state':
                    // May be "1 (Initialized)" or just "1"
                    var stateMatch = value.match(/^(\d+)/);
                    if (stateMatch) {
                        result.state = parseInt(stateMatch[1], 10);
                        var textMatch = value.match(/\(([^)]+)\)/);
                        result.stateText = textMatch ? textMatch[1] : (stateNames[stateMatch[1]] || 'Unknown');
                    }
                    break;
                case 'page_size':
                    result.pageSize = parseInt(value, 10) || 4096;
                    break;
                case 'pages_added':
                    result.pagesAdded = parseInt(value, 10) || 0;
                    break;
                case 'pages_onlined':
                    result.pagesOnlined = parseInt(value, 10) || 0;
                    break;
                case 'pages_ballooned':
                    result.pagesBallooned = parseInt(value, 10) || 0;
                    break;
                case 'total_pages_committed':
                    result.totalPagesCommitted = parseInt(value, 10) || 0;
                    break;
                case 'max_dynamic_page_count':
                    result.maxDynamicPageCount = parseInt(value, 10) || 0;
                    break;
            }
        }

        if (!result.found) return result;

        // Calculate memory from page counts
        var pageSize = result.pageSize;
        var bytesPerGB = 1024 * 1024 * 1024;
        var bytesPerMB = 1024 * 1024;

        result.committedMemoryGB = parseFloat(((result.totalPagesCommitted * pageSize) / bytesPerGB).toFixed(2));
        result.maxDynamicMemoryGB = parseFloat(((result.maxDynamicPageCount * pageSize) / bytesPerGB).toFixed(2));
        result.balloonedMemoryMB = parseFloat(((result.pagesBallooned * pageSize) / bytesPerMB).toFixed(2));

        // Warnings
        if (result.pagesBallooned > 0) {
            result.warnings.push(
                'Ballooning active: host is reclaiming ' + result.balloonedMemoryMB +
                ' MB from the guest. This can cause memory pressure and allocation failures.'
            );
        }

        if (result.maxDynamicPageCount > 0 && result.totalPagesCommitted > 0) {
            var usageRatio = result.totalPagesCommitted / result.maxDynamicPageCount;
            if (usageRatio > 0.9) {
                result.warnings.push(
                    'Memory near capacity: ' + result.committedMemoryGB + ' GB committed of ' +
                    result.maxDynamicMemoryGB + ' GB maximum (' + Math.round(usageRatio * 100) + '%).'
                );
            }
        }

        return result;
    }
};

/**
 * Parses memory fragmentation data from debugfs extfrag/ directory.
 *
 * Two files are read (multi-file parser):
 *   - `extfrag_index`: external fragmentation index per zone/order.
 *       Values near 0 = failures from lack of memory (not fragmentation).
 *       Values near 1 = failures from external fragmentation.
 *       Value of -1 = pages available, no allocation failure expected.
 *   - `unusable_index`: fraction of free memory unusable for each order.
 *       Values near 0 = most free memory is usable at that order.
 *       Values near 1 = free memory is too fragmented for that order.
 *
 * Orders 0-10 correspond to page sizes 4K, 8K, 16K, ... 4MB.
 * Order 9 = 2MB (standard huge page on x86_64).
 *
 * @type {Object}
 * @property {RegExp} filePattern - Matches extfrag_index and unusable_index
 * @property {boolean} multiFile - Accumulates data from both files
 * @property {Function} parse - Extracts per-zone fragmentation data
 */
const extfragParser = {
    filePattern: /sys\/kernel\/debug\/extfrag\/(extfrag_index|unusable_index)$/,
    multiFile: true,

    parse: function(content, filename) {
        // Self-accumulating: store zones on the parser object across calls
        if (!this._zones) {
            this._zones = [];
            this._rawParts = '';
        }

        var result = {
            found: false,
            zones: this._zones,
            warnings: [],
            rawContent: ''
        };

        if (!content || typeof content !== 'string') return result;
        var trimmed = content.trim();
        if (!trimmed) return result;

        // Determine which file we're parsing
        var isExtfrag = filename && filename.indexOf('extfrag_index') !== -1;
        var isUnusable = filename && filename.indexOf('unusable_index') !== -1;
        var fieldName = isExtfrag ? 'extfragIndex' : (isUnusable ? 'unusableIndex' : null);

        if (!fieldName) return result;

        // Append raw content with label
        if (this._rawParts) {
            this._rawParts += '\n\n';
        }
        this._rawParts += '=== ' + (isExtfrag ? 'extfrag_index' : 'unusable_index') + ' ===\n' + trimmed;
        result.rawContent = this._rawParts;

        // Parse lines: "Node X, zone   NAME val1 val2 ... val11"
        var lines = trimmed.split('\n');
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            var match = line.match(/^Node\s+(\d+),\s+zone\s+(\S+)\s+(.+)$/);
            if (!match) continue;

            var nodeNum = parseInt(match[1], 10);
            var zoneName = match[2];
            var valuesStr = match[3].trim();
            var values = valuesStr.split(/\s+/).map(function(v) {
                return parseFloat(v);
            });

            // Find or create zone entry in accumulated zones
            var zone = null;
            for (var j = 0; j < this._zones.length; j++) {
                if (this._zones[j].node === nodeNum && this._zones[j].zone === zoneName) {
                    zone = this._zones[j];
                    break;
                }
            }
            if (!zone) {
                zone = {
                    node: nodeNum,
                    zone: zoneName,
                    extfragIndex: [],
                    unusableIndex: []
                };
                this._zones.push(zone);
            }

            zone[fieldName] = values;
            result.found = true;
        }

        // Generate warnings based on accumulated data
        result.warnings = [];
        var orderLabels = ['4K', '8K', '16K', '32K', '64K', '128K', '256K', '512K', '1M', '2M', '4M'];

        for (var z = 0; z < result.zones.length; z++) {
            var zn = result.zones[z];

            // Check unusable_index at high orders (9=2MB huge pages, 10=4MB)
            if (zn.unusableIndex && zn.unusableIndex.length > 9) {
                for (var ord = 9; ord < zn.unusableIndex.length; ord++) {
                    var val = zn.unusableIndex[ord];
                    if (val > 0.5) {
                        var label = ord < orderLabels.length ? orderLabels[ord] : ('order ' + ord);
                        var severity = val > 0.8 ? 'Severe' : 'Moderate';
                        result.warnings.push(
                            severity + ' fragmentation on Node ' + zn.node + ' zone ' + zn.zone +
                            ' at ' + label + ' (order ' + ord + '): unusable index ' +
                            val.toFixed(3) + '. Huge page allocations may fail.'
                        );
                    }
                }
            }

            // Check extfrag_index for high external fragmentation at order 9+
            if (zn.extfragIndex && zn.extfragIndex.length > 9) {
                for (var ord2 = 9; ord2 < zn.extfragIndex.length; ord2++) {
                    var val2 = zn.extfragIndex[ord2];
                    // Values near 1.0 mean failures are due to fragmentation (compaction would help)
                    // Values of -1 mean no failure expected
                    if (val2 > 0.7 && val2 <= 1.0) {
                        var label2 = ord2 < orderLabels.length ? orderLabels[ord2] : ('order ' + ord2);
                        result.warnings.push(
                            'High external fragmentation on Node ' + zn.node + ' zone ' + zn.zone +
                            ' at ' + label2 + ' (order ' + ord2 + '): extfrag index ' +
                            val2.toFixed(3) + '. Memory compaction may help.'
                        );
                    }
                }
            }
        }

        return result;
    }
};
