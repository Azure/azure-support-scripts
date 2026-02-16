/**
 * @module parsers/vmcore
 * @description Kernel crash dump (vmcore / kdump) analysis parser.
 *
 * This is a **multi-file parser**: it accumulates results from every matching
 * file via `mergeResults()`, producing a single consolidated view of all
 * crash dumps found in a sosreport.
 *
 * ### Input files
 *
 * | File | Parser method | Purpose |
 * |------|---------------|---------|
 * | `var/crash/<dir>/vmcore-dmesg.txt` | `parseVmcoreDmesg()` | Kernel dmesg at time of crash |
 * | `sos_commands/kdump/kdumpctl_status` | `parseKdumpStatus()` | Whether kdump is operational |
 * | `sos_commands/kdump/ls_-alZR_.var.crash` | `parseCrashListing()` | Vmcore file sizes on disk |
 * | `etc/kdump.conf` | `parseKdumpConf()` | Dump path, core_collector, failure_action |
 *
 * ### Extracted data per crash
 *
 * - Crash date/time (from the directory name, e.g. `127.0.0.1-2026-02-13-03:48:00`)
 * - Panic reason (`Kernel panic - not syncing: ...`)
 * - Kernel version, CPU, PID, process name (Comm), tainted flags
 * - Call trace frames
 * - Vmcore file size (matched by date between `parseCrashListing` entries
 *   and `parseVmcoreDmesg` crash objects)
 *
 * ### Merged result shape
 *
 * ```
 * {
 *   found: boolean,
 *   crashes: Array<{ date, panicReason, kernelVersion, callTrace, comm, pid, ... }>,
 *   kdumpStatus: { raw, operational },
 *   crashListing: { entries: [{ directory, crashDate, sizeBytes, sizeMB, sizeGB }],
 *                   count, totalBytes, totalGB },
 *   kdumpConf: { path, coreCollector, defaultAction, raw }
 * }
 * ```
 *
 * @see {@link module:worker} for registration in SCC_RULES
 */

// Debug logging
function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.vmcore) {
        console.log('[vmcore.js]', ...args);
    }
}

// ============================================================================
// vmcoreParser – exported global for worker.js registration
// ============================================================================
var vmcoreParser = {
    // Match vmcore-dmesg.txt, kdumpctl status, var/crash listing, kdump.conf
    filePattern: /(?:var\/crash\/[^/]+\/vmcore-dmesg\.txt|sos_commands\/kdump\/kdumpctl_status|sos_commands\/kdump\/ls_-alZR_\.var\.crash|etc\/kdump\.conf)$/,

    parse: function(content, filename) {
        debugLog('Parsing:', filename, '(' + content.length + ' bytes)');

        const result = {
            found: false,
            type: null,     // 'vmcore-dmesg' | 'kdump-status' | 'crash-listing' | 'kdump-conf'
            crash: null,    // populated for vmcore-dmesg files
            kdumpStatus: null,
            crashListing: null,
            kdumpConf: null
        };

        if (filename.includes('vmcore-dmesg.txt')) {
            result.type = 'vmcore-dmesg';
            result.crash = this.parseVmcoreDmesg(content, filename);
            result.found = true;
        } else if (filename.includes('kdumpctl_status')) {
            result.type = 'kdump-status';
            result.kdumpStatus = this.parseKdumpStatus(content);
            result.found = result.kdumpStatus !== null;
        } else if (filename.includes('ls_-alZR_')) {
            result.type = 'crash-listing';
            result.crashListing = this.parseCrashListing(content);
            result.found = result.crashListing !== null;
        } else if (filename.includes('kdump.conf')) {
            result.type = 'kdump-conf';
            result.kdumpConf = this.parseKdumpConf(content);
            result.found = result.kdumpConf !== null;
        }

        return result;
    },

    // ========================================================================
    // Parse vmcore-dmesg.txt – extract panic reason, kernel, call trace
    // ========================================================================
    parseVmcoreDmesg: function(content, filename) {
        const crash = {
            date: null,
            panicReason: null,
            kernelVersion: null,
            callTrace: [],
            hardware: null,
            comm: null,       // Process name that triggered the crash
            pid: null,
            cpu: null,
            tainted: null,
            sourceFile: filename
        };

        // Extract date from directory path: var/crash/127.0.0.1-2026-02-13-03:48:00/
        const dateMatch = filename.match(/var\/crash\/[^/]*?(\d{4}-\d{2}-\d{2}[:-]\d{2}[:-]\d{2}[:-]\d{2})/);
        if (dateMatch) {
            // Normalize separators: 2026-02-13-03:48:00 → 2026-02-13 03:48:00
            const raw = dateMatch[1];
            const parts = raw.split(/[-:]/);
            if (parts.length >= 6) {
                crash.date = `${parts[0]}-${parts[1]}-${parts[2]} ${parts[3]}:${parts[4]}:${parts[5]}`;
            } else {
                crash.date = raw;
            }
        }

        const lines = content.split('\n');
        let inCallTrace = false;
        let callTraceLines = [];

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];

            // Kernel panic line
            const panicMatch = line.match(/Kernel panic - not syncing:\s*(.+)/);
            if (panicMatch) {
                crash.panicReason = panicMatch[1].trim();
                inCallTrace = false; // reset any previous trace
                callTraceLines = [];
            }

            // Hardware name
            const hwMatch = line.match(/Hardware name:\s*(.+)/);
            if (hwMatch && !crash.hardware) {
                crash.hardware = hwMatch[1].trim().replace(/,\s*BIOS.*/, '');
            }

            // CPU/PID/Comm line after panic: "CPU: 2 PID: 71 Comm: khungtaskd Kdump: loaded Not tainted 4.18.0-..."
            const cpuMatch = line.match(/CPU:\s*(\d+)\s+PID:\s*(\d+)\s+Comm:\s*(\S+)\s+(?:Kdump:\s*\S+\s+)?(?:(Not tainted|Tainted:\s*\S*))\s+(\S+)/);
            if (cpuMatch && crash.panicReason) {
                crash.cpu = parseInt(cpuMatch[1]);
                crash.pid = parseInt(cpuMatch[2]);
                crash.comm = cpuMatch[3];
                crash.tainted = cpuMatch[4].startsWith('Not') ? null : cpuMatch[4];
                crash.kernelVersion = cpuMatch[5];
            }

            // Call Trace section (after panic)
            if (crash.panicReason) {
                if (/Call Trace:/.test(line)) {
                    inCallTrace = true;
                    callTraceLines = [];
                    continue;
                }
                if (inCallTrace) {
                    const frameMatch = line.match(/^\s*(\S.*)$/);
                    if (frameMatch) {
                        const frame = frameMatch[1].trim();
                        // Stop at blank line or non-trace line
                        if (frame === '' || /^Kernel Offset/.test(frame) || /^---\[/.test(frame)) {
                            inCallTrace = false;
                        } else {
                            callTraceLines.push(frame);
                        }
                    } else {
                        inCallTrace = false;
                    }
                }
            }
        }

        crash.callTrace = callTraceLines;
        debugLog('Parsed crash:', crash.date, crash.panicReason, 'trace frames:', callTraceLines.length);
        return crash;
    },

    // ========================================================================
    // Parse kdumpctl status output
    // ========================================================================
    parseKdumpStatus: function(content) {
        const trimmed = content.trim();
        if (!trimmed) return null;

        // "kdump: Kdump is operational"  or  "kdump: Kdump is not operational"
        const operational = /operational/i.test(trimmed) && !/not operational/i.test(trimmed);
        return {
            raw: trimmed,
            operational: operational
        };
    },

    // ========================================================================
    // Parse ls -alZR /var/crash to get vmcore sizes
    // ========================================================================
    parseCrashListing: function(content) {
        const entries = [];
        const lines = content.split('\n');
        let currentDir = null;

        for (const line of lines) {
            // Directory header: "/var/crash/127.0.0.1-2026-02-13-03:48:00:"
            // Use .+ with $ anchor because dir names contain colons (time portion)
            const dirMatch = line.match(/^(\/var\/crash\/.+):$/);
            if (dirMatch) {
                currentDir = dirMatch[1];
                continue;
            }

            if (!currentDir || currentDir === '/var/crash') continue;

            // File entry: "-rw-------. 1 root root ... 1351110790 Feb 13 03:48 vmcore"
            // Match vmcore files (but not vmcore-dmesg.txt or kexec-dmesg.log)
            const fileMatch = line.match(/\s+(\d+)\s+\w+\s+\d+\s+[\d:]+\s+(vmcore)$/);
            if (fileMatch) {
                const sizeBytes = parseInt(fileMatch[1]);
                // Extract crash date from directory name
                const crashDateMatch = currentDir.match(/(\d{4}-\d{2}-\d{2}[:-]\d{2}[:-]\d{2}[:-]\d{2})/);
                let crashDate = null;
                if (crashDateMatch) {
                    const raw = crashDateMatch[1];
                    const parts = raw.split(/[-:]/);
                    if (parts.length >= 6) {
                        crashDate = `${parts[0]}-${parts[1]}-${parts[2]} ${parts[3]}:${parts[4]}:${parts[5]}`;
                    }
                }
                entries.push({
                    directory: currentDir,
                    crashDate: crashDate,
                    sizeBytes: sizeBytes,
                    sizeMB: Math.round(sizeBytes / (1024 * 1024)),
                    sizeGB: (sizeBytes / (1024 * 1024 * 1024)).toFixed(1)
                });
            }
        }

        if (entries.length === 0) return null;
        
        // Total disk usage
        const totalBytes = entries.reduce((sum, e) => sum + e.sizeBytes, 0);
        
        return {
            entries: entries,
            count: entries.length,
            totalBytes: totalBytes,
            totalGB: (totalBytes / (1024 * 1024 * 1024)).toFixed(1)
        };
    },

    // ========================================================================
    // Parse kdump.conf – extract key configuration
    // ========================================================================
    parseKdumpConf: function(content) {
        const lines = content.split('\n');
        const conf = {
            path: '/var/crash',        // default
            coreCollector: null,
            defaultAction: null,
            raw: content.trim()
        };

        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith('#') || !trimmed) continue;

            const pathMatch = trimmed.match(/^path\s+(.+)/);
            if (pathMatch) conf.path = pathMatch[1].trim();

            const collectorMatch = trimmed.match(/^core_collector\s+(.+)/);
            if (collectorMatch) conf.coreCollector = collectorMatch[1].trim();

            const defaultMatch = trimmed.match(/^(default|failure_action)\s+(.+)/);
            if (defaultMatch) conf.defaultAction = defaultMatch[2].trim();
        }

        return conf;
    },

    // ========================================================================
    // Merge results from multiple files into the accumulated state
    // ========================================================================
    mergeResults: function(existing, newResult) {
        existing.found = existing.found || newResult.found;

        if (newResult.crash) {
            if (!existing.crashes) existing.crashes = [];
            existing.crashes.push(newResult.crash);
            // Sort by date descending (most recent first)
            existing.crashes.sort((a, b) => {
                if (!a.date) return 1;
                if (!b.date) return -1;
                return b.date.localeCompare(a.date);
            });
        }

        if (newResult.kdumpStatus) {
            existing.kdumpStatus = newResult.kdumpStatus;
        }

        if (newResult.crashListing) {
            existing.crashListing = newResult.crashListing;
        }

        if (newResult.kdumpConf) {
            existing.kdumpConf = newResult.kdumpConf;
        }
    }
};
