/**
 * @module worker
 * @description Streaming XZ decompression worker using liblzma.
 *
 * This Web Worker orchestrates the entire analysis pipeline:
 * 1. Receives compressed `.tar.xz` archives from the UI thread.
 * 2. Decompresses via liblzma WASM in configurable-size chunks.
 * 3. Extracts individual files from the tar stream.
 * 4. Matches each file against all registered parser `filePattern` regexes.
 * 5. Calls `parse(content, filename)` on matching parsers.
 * 6. Accumulates results in `analysisResults` and posts them back to the UI.
 *
 * Parser registration happens in the `SCC_RULES` object. Multi-file parsers
 * (e.g. firewallRules, networkInterfaces, vmcore) use `mergeResults()` for
 * cross-file accumulation.
 *
 * @see {@link module:utils} for shared helper functions
 */

// Version is only logged when debug mode is enabled\nconst WORKER_VERSION = '2025-12-23-nested-gzip';

// Reuse the worker URL query string for all relative assets.
// This prevents GitHub Pages/CDN caches from serving a mixed set of worker
// files from different deployments during the post-deploy test window.
const WORKER_ASSET_QUERY = (() => {
    try {
        const url = new URL(self.location.href);
        return url.search || '';
    } catch (_e) {
        return '';
    }
})();

function versionedAsset(path) {
    if (!WORKER_ASSET_QUERY || /^https?:\/\//i.test(path)) {
        return path;
    }
    return path.includes('?')
        ? `${path}&${WORKER_ASSET_QUERY.slice(1)}`
        : `${path}${WORKER_ASSET_QUERY}`;
}

// Global error handler to catch uncaught exceptions
self.onerror = function(message, source, lineno, colno, error) {
    console.error('[Worker] Uncaught error:', message);
    console.error('[Worker] Source:', source, 'Line:', lineno, 'Column:', colno);
    console.error('[Worker] Error object:', error);
    if (error && error.stack) {
        console.error('[Worker] Stack trace:', error.stack);
    }
    // Try to send error message to main thread
    try {
        self.postMessage({
            error: 'Worker uncaught error: ' + message + ' at ' + source + ':' + lineno
        });
    } catch (e) {
        console.error('[Worker] Failed to send error message:', e);
    }
    return true; // Prevent default error handling
};

// Debug flag - will be set from main thread via message
// Debug configuration - set specific parsers to true to enable their debug logging
const DEBUG_CONFIG = {
    automation: false,
    azure: false,
    cluster: false,
    events: false,
    networking: false,
    packages: false,
    performance: false,
    services: false,
    storage: false,
    unix: false,
    vmcore: false,
    worker: false
};

// Debug logging wrapper - only logs if the specific debug flag is enabled
function debugLog(...args) {
    // Check if this is a parser-specific log by looking at the first argument
    const firstArg = args[0];
    if (typeof firstArg === 'string') {
        // Extract parser name from log message like "[parserName parser]"
        const parserMatch = firstArg.match(/\[(\w+)(?:\s+parser|\s+worker)?\]/);
        if (parserMatch) {
            const parserName = parserMatch[1].toLowerCase();
            if (DEBUG_CONFIG[parserName]) {
                console.log(...args);
            }
        } else if (DEBUG_CONFIG.worker) {
            // General worker logs
            console.log(...args);
        }
    }
}

// ---------------------------------------------------------------------------
// Performance tracking/reporting runtime (inlined from performance.js)
// ---------------------------------------------------------------------------

class PerformanceTracker {
    constructor() {
        this.fileEntries = [];
        this.parserEntries = [];
        this.startTime = performance.now();
        this.totalBytes = 0;
        this.totalFiles = 0;
        this._fileStart = 0;
        this._decodeMs = 0;
    }

    startFile() {
        this._fileStart = performance.now();
        this._decodeMs = 0;
    }

    recordDecode(ms) {
        this._decodeMs = ms;
    }

    recordParser(file, parser, parseMs, result, accumulatedResult) {
        this.parserEntries.push({
            file,
            parser,
            parseMs,
            events: countEvents(result),
            accumulated: accumulatedResult ? countEvents(accumulatedResult) : 0
        });
    }

    endFile(file, contentLen, parserCount) {
        this.totalBytes += contentLen;
        this.totalFiles++;
        this.fileEntries.push({
            file,
            size: contentLen,
            parsers: parserCount,
            totalMs: performance.now() - this._fileStart,
            decodeMs: this._decodeMs
        });
    }

    getReport() {
        return {
            fileEntries: this.fileEntries,
            parserEntries: this.parserEntries,
            totalTimeMs: performance.now() - this.startTime,
            totalFiles: this.totalFiles,
            totalBytes: this.totalBytes
        };
    }
}

function countEvents(result) {
    if (!result) return 0;
    if (typeof result.count === 'number') return result.count;
    if (Array.isArray(result.events)) return result.events.length;
    const migrations = result.resourceMigrations?.length || 0;
    const fencing = result.fencingEvents?.length || 0;
    if (migrations || fencing) return migrations + fencing;
    if (Array.isArray(result.errors)) return result.errors.length;
    return 0;
}

function formatPerformanceReport(perfData, memoryMB) {
    const { fileEntries, parserEntries, totalTimeMs, totalFiles, totalBytes } = perfData;
    const lines = [];
    const push = (s) => lines.push(s);

    push('');
    push('='.repeat(70));
    push('  PERFORMANCE REPORT');
    push('='.repeat(70));
    push(`  Total time: ${(totalTimeMs / 1000).toFixed(2)}s`);
    push(`  Files processed: ${totalFiles}`);
    push(`  Files parsed: ${fileEntries.length}`);
    push(`  Total content size: ${(totalBytes / (1024 * 1024)).toFixed(1)} MB`);
    if (memoryMB != null) {
        push(`  Memory peak: ${memoryMB.toFixed(1)} MB`);
    }
    push('');

    const sortedFiles = [...fileEntries].sort((a, b) => b.totalMs - a.totalMs);
    push('  Top 20 slowest files:');
    push(`  ${'File'.padEnd(60)} ${'Size'.padStart(10)} ${'Parsers'.padStart(8)} ${'Time(ms)'.padStart(10)} ${'Decode(ms)'.padStart(11)}`);
    push(`  ${'-'.repeat(60)} ${'-'.repeat(10)} ${'-'.repeat(8)} ${'-'.repeat(10)} ${'-'.repeat(11)}`);
    for (const f of sortedFiles.slice(0, 20)) {
        const shortName = f.file.length > 58 ? '...' + f.file.slice(-55) : f.file;
        const sizeStr = f.size >= 1024 * 1024
            ? `${(f.size / (1024 * 1024)).toFixed(1)}MB`
            : `${(f.size / 1024).toFixed(1)}KB`;
        push(`  ${shortName.padEnd(60)} ${sizeStr.padStart(10)} ${String(f.parsers).padStart(8)} ${f.totalMs.toFixed(1).padStart(10)} ${f.decodeMs.toFixed(1).padStart(11)}`);
    }

    const sortedParsers = [...parserEntries].sort((a, b) => b.parseMs - a.parseMs);
    push('');
    push('  Top 20 slowest parser calls:');
    push(`  ${'Parser'.padEnd(25)} ${'File'.padEnd(40)} ${'Time(ms)'.padStart(10)} ${'Events'.padStart(8)} ${'Accum'.padStart(8)}`);
    push(`  ${'-'.repeat(25)} ${'-'.repeat(40)} ${'-'.repeat(10)} ${'-'.repeat(8)} ${'-'.repeat(8)}`);
    for (const p of sortedParsers.slice(0, 20)) {
        const shortFile = p.file.length > 38 ? '...' + p.file.slice(-35) : p.file;
        push(`  ${p.parser.padEnd(25)} ${shortFile.padEnd(40)} ${p.parseMs.toFixed(1).padStart(10)} ${String(p.events).padStart(8)} ${String(p.accumulated).padStart(8)}`);
    }

    const parserAgg = {};
    for (const p of parserEntries) {
        if (!parserAgg[p.parser]) parserAgg[p.parser] = { calls: 0, totalMs: 0, totalEvents: 0 };
        parserAgg[p.parser].calls++;
        parserAgg[p.parser].totalMs += p.parseMs;
        parserAgg[p.parser].totalEvents += p.events;
    }
    const sortedAgg = Object.entries(parserAgg).sort((a, b) => b[1].totalMs - a[1].totalMs);
    push('');
    push('  Parser aggregate (all files):');
    push(`  ${'Parser'.padEnd(30)} ${'Calls'.padStart(6)} ${'Total(ms)'.padStart(10)} ${'Avg(ms)'.padStart(10)} ${'Events'.padStart(8)}`);
    push(`  ${'-'.repeat(30)} ${'-'.repeat(6)} ${'-'.repeat(10)} ${'-'.repeat(10)} ${'-'.repeat(8)}`);
    for (const [name, agg] of sortedAgg) {
        push(`  ${name.padEnd(30)} ${String(agg.calls).padStart(6)} ${agg.totalMs.toFixed(1).padStart(10)} ${(agg.totalMs / agg.calls).toFixed(1).padStart(10)} ${String(agg.totalEvents).padStart(8)}`);
    }

    push('');
    push('  --- TSV DATA (pipe stderr to file for processing) ---');
    push('FILE\tsize\tparsers\ttotal_ms\tdecode_ms');
    for (const f of sortedFiles) {
        push(`FILE\t${f.file}\t${f.size}\t${f.parsers}\t${f.totalMs.toFixed(1)}\t${f.decodeMs.toFixed(1)}`);
    }
    push('PARSER\tfile\tparser\tparse_ms\tevents\taccumulated');
    for (const p of parserEntries) {
        push(`PARSER\t${p.file}\t${p.parser}\t${p.parseMs.toFixed(1)}\t${p.events}\t${p.accumulated}`);
    }
    push('');

    return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Utility runtime
// ---------------------------------------------------------------------------

function deduplicateEvents(existingEvents, newEvents, comparisonFields, logFn) {
    const keySet = new Set();
    for (let i = 0; i < existingEvents.length; i++) {
        const evt = existingEvents[i];
        let key = '';
        for (let f = 0; f < comparisonFields.length; f++) {
            if (f > 0) key += '\0';
            key += evt[comparisonFields[f]];
        }
        keySet.add(key);
    }

    const addedEvents = [];
    let duplicateCount = 0;

    for (let i = 0; i < newEvents.length; i++) {
        const newEvent = newEvents[i];
        let key = '';
        for (let f = 0; f < comparisonFields.length; f++) {
            if (f > 0) key += '\0';
            key += newEvent[comparisonFields[f]];
        }
        if (keySet.has(key)) {
            duplicateCount++;
        } else {
            keySet.add(key);
            addedEvents.push(newEvent);
        }
    }

    if (logFn) {
        logFn(`[deduplicateEvents] Added ${addedEvents.length} new events, skipped ${duplicateCount} duplicates`);
    }

    return {
        addedEvents,
        duplicateCount
    };
}

// Runtime imports
if (typeof importScripts === 'function') {
    // Import pako for gzip decompression of nested .gz files
    try {
        importScripts('https://cdn.jsdelivr.net/npm/pako@2.1.0/dist/pako.min.js');
        debugLog('[Worker] pako library loaded for nested .gz decompression');
    } catch (e) {
        // Non-critical: nested .gz decompression will not be available
        // Only log in debug mode to avoid console noise
        debugLog('[Worker] Failed to load pako library:', e);
    }
    
    // Import fflate for ZIP archive decompression
    try {
        importScripts('https://cdn.jsdelivr.net/npm/fflate@0.8.2/umd/index.js');
        debugLog('[Worker] fflate library loaded for ZIP decompression');
    } catch (e) {
        // Non-critical: ZIP decompression will not be available
        debugLog('[Worker] Failed to load fflate library:', e);
    }
    
    // Import the supportfile WASM module (compiled from supportfile_core via
    // wasm-pack, target=no-modules).  After importScripts, `wasm_bindgen` is
    // a global initializer; we await it inside the Module init promise below
    // before sending `ready` to the main thread.  Individual parser .js shims
    // call into `wasm_bindgen.parse*` functions once initialization completes.
    try {
        importScripts(versionedAsset('supportfile-wasm/supportfile_wasm.js'));
        if (typeof WASM_BRIDGE === 'undefined') {
            importScripts(versionedAsset('wasm-bridge.js'));
        }
        debugLog('[Worker] supportfile WASM glue + bridge loaded');
    } catch (e) {
        console.error('[Worker] Failed to load supportfile WASM glue:', e);
    }

    // Fallback path for standalone worker.js execution (without the build-time
    // bundled asset that inlines parsers).
    if (typeof basicEnvironmentParser === 'undefined') {
        importScripts(versionedAsset('parsers/unix.js'));
        importScripts(versionedAsset('parsers/services.js'));
        importScripts(versionedAsset('parsers/events.js'));
        importScripts(versionedAsset('parsers/azure.js'));
        importScripts(versionedAsset('parsers/cluster.js'));
        importScripts(versionedAsset('parsers/storage.js'));
        importScripts(versionedAsset('parsers/hana.js'));
        importScripts(versionedAsset('parsers/networking.js'));
        importScripts(versionedAsset('parsers/network-interfaces.js'));
        importScripts(versionedAsset('parsers/vmcore.js'));
        importScripts(versionedAsset('parsers/debugfs.js'));
    }
    debugLog('[Worker] Running in Web Worker context');
    debugLog('[Worker] Browser:', typeof navigator !== 'undefined' ? navigator.userAgent : 'unknown');
}

function emptyPackagesResult() {
    return {
        found: false,
        packages: {},
        warnings: [],
        fipsPackages: [],
        hasDracutFips: false,
    };
}

function emptyAutomationResult() {
    return {
        found: false,
        count: 0,
        events: []
    };
}

// Inlined distro packages parser.
const distroPackagesParser = {
    filePattern: /\/(rpm\.txt|installed-rpms|package-data|dpkg_-l|dnf[_-]list[_-]installed|yum[_-]list[_-]installed|var\/log\/zypp\/history|var\/log\/(?:dnf|yum)\.log|etc\/dnf\/dnf\.conf|etc\/yum\.conf|etc\/dnf\.repo|etc\/yum\.repos\.d\/.*\.repo|etc\/dnf\/repos\.d\/.*\.repo|dnf\.conf|yum\.conf|.*\.repo)$/,

    parse: function(content, filename, _lines) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
            return emptyPackagesResult();
        }
        let result;
        try {
            result = WASM_BRIDGE.parseJson('parseDistroPackages', content, filename || '');
        } catch (err) {
            console.error('[worker.js] parseDistroPackages WASM call failed:', err);
            return emptyPackagesResult();
        }
        if (result == null) return emptyPackagesResult();
        if (result.isDpkg || result.isRpmRaw || result.isZypperHistory || result.isDnfYumLog) {
            result.filename = filename;
        }
        return result;
    }
};

// ============================================================================
// SCC REPORT ANALYSIS RULES
// ============================================================================
// Add new rules here to extract information from SCC/supportconfig reports
// Each rule defines which file to extract and how to parse it

const SCC_RULES = {
    // Utility function for merging multi-file event streams.
    deduplicateEvents: function(existingEvents, newEvents, comparisonFields) {
        return deduplicateEvents(existingEvents, newEvents, comparisonFields, debugLog);
    },
    
    // ========================================================================
    // DETECTION RULES
    // ========================================================================
    
    // Rule: Detect if archive is an SCC report, hb_report, crm_report, sosreport, or InspectIaaSDisk
    detection: {
        // Patterns to identify reports by filename
        filenamePatterns: [
            /^scc_/,           // SCC/supportconfig reports
            /^nts_/,           // NTS reports
            /^hb_report/,      // hb_report archives (older Pacemaker)
            /^crm_report/,     // crm_report archives (newer Pacemaker)
            /^sosreport-/,     // sosreport archives
            /^device_\d+\//    // InspectIaaSDisk reports
        ],
        
        // Check if filename matches any report pattern
        isSCCReport: function(filename) {
            return this.filenamePatterns.some(pattern => pattern.test(filename));
        },

        // HANA trace files (indexserver_*.trc / nameserver_*.trc) can be
        // collected on their own (e.g. a HANA log ZIP) outside any SCC /
        // sosreport bundle. Detect them so their parsers still run.
        hanaTracePattern: /\/(indexserver|nameserver)[^/]*\.trc$/,
        isHanaLog: function(filename) {
            return this.hanaTracePattern.test('/' + filename);
        }
    },
    
    // Cluster parsers are imported from parsers/cluster.js after SCC_RULES is defined

    // Rule: Detect automation tool usage (Ansible, Puppet, Chef, etc.)
    automation: {
        // Target file path patterns - messages, syslog, journalctl
        filePattern: /\/(messages|localmessages|syslog|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,

        // Rust-native parser bridge.
        parse: function(content, filename, _lines) {
            if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
                return emptyAutomationResult();
            }

            try {
                const result = WASM_BRIDGE.parseJson('parseAutomationEvents', content, filename || '');
                if (result == null) return emptyAutomationResult();
                if (typeof result.found === 'undefined') {
                    result.found = (result.count || (result.events && result.events.length) || 0) > 0;
                }
                return result;
            } catch (err) {
                console.error('[worker.js] parseAutomationEvents WASM call failed:', err);
                return emptyAutomationResult();
            }
        }
    },
    
    // distroPackages and azureSiteRecovery are provided by Rust-backed parser
    // shims (`distroPackagesParser` and `azureSiteRecoveryParser`) and
    // assigned after SCC_RULES initialization.
    
    // puppetAgent, chefClient and nvmeList are provided by Rust-backed
    // parser shims and assigned after SCC_RULES initialization.
    
    // ADD MORE RULES HERE
    // Example:
    // systemInfo: {
    //     filePattern: /\/basic-environment\.txt$/,
    //     parse: function(content) {
    //         // Extract system information
    //         return { /* parsed data */ };
    //     }
    // }
};

// ============================================================================
// END SCC RULES
// ============================================================================

// Manual parser assignments - Load external parsers after SCC_RULES is fully defined
// This avoids "SCC_RULES is not defined" errors during module loading

// Distro packages parser
if (typeof distroPackagesParser !== 'undefined') {
    SCC_RULES.distroPackages = distroPackagesParser;
}

// From parsers/unix.js
if (typeof basicEnvironmentParser !== 'undefined') {
    SCC_RULES.basicEnvironment = basicEnvironmentParser;
}
if (typeof osReleaseParser !== 'undefined') {
    SCC_RULES.osRelease = osReleaseParser;
}
if (typeof fstabParser !== 'undefined') {
    SCC_RULES.fstab = fstabParser;
}
if (typeof inspectDiskResultsParser !== 'undefined') {
    SCC_RULES.inspectDiskResults = inspectDiskResultsParser;
}
if (typeof kernelTuningParser !== 'undefined') {
    SCC_RULES.kernelTuning = kernelTuningParser;
}
if (typeof hugePagesParser !== 'undefined') {
    SCC_RULES.hugePages = hugePagesParser;
}
if (typeof timeSyncParser !== 'undefined') {
    SCC_RULES.timeSync = timeSyncParser;
}
if (typeof ptpClockSourceParser !== 'undefined') {
    SCC_RULES.ptpClockSource = ptpClockSourceParser;
}
if (typeof timeSyncServiceParser !== 'undefined') {
    SCC_RULES.timeSyncService = timeSyncServiceParser;
}
if (typeof timedatectlParser !== 'undefined') {
    SCC_RULES.timedatectl = timedatectlParser;
}
if (typeof ptpDeviceParser !== 'undefined') {
    SCC_RULES.ptpDevice = ptpDeviceParser;
}
if (typeof chronyTrackingParser !== 'undefined') {
    SCC_RULES.chronyTracking = chronyTrackingParser;
}
if (typeof chronyMakestepParser !== 'undefined') {
    SCC_RULES.chronyMakestep = chronyMakestepParser;
}

// From parsers/services.js
if (typeof sshServiceParser !== 'undefined') {
    SCC_RULES.sshService = sshServiceParser;
}
if (typeof dlmServiceParser !== 'undefined') {
    SCC_RULES.dlmService = dlmServiceParser;
}
if (typeof azureSiteRecoveryParser !== 'undefined') {
    SCC_RULES.azureSiteRecovery = azureSiteRecoveryParser;
}
if (typeof guardicoreAgentParser !== 'undefined') {
    SCC_RULES.guardicoreAgent = guardicoreAgentParser;
}
if (typeof puppetAgentParser !== 'undefined') {
    SCC_RULES.puppetAgent = puppetAgentParser;
}
if (typeof chefClientParser !== 'undefined') {
    SCC_RULES.chefClient = chefClientParser;
}
if (typeof illumioParser !== 'undefined') {
    SCC_RULES.illumio = illumioParser;
}
if (typeof trendMicroParser !== 'undefined') {
    SCC_RULES.trendMicro = trendMicroParser;
}
if (typeof falconSensorParser !== 'undefined') {
    SCC_RULES.falconSensor = falconSensorParser;
}
if (typeof falconSensorConfigParser !== 'undefined') {
    SCC_RULES.falconSensorConfig = falconSensorConfigParser;
}
if (typeof msDefenderParser !== 'undefined') {
    SCC_RULES.msDefender = msDefenderParser;
}
if (typeof msDefenderConfigParser !== 'undefined') {
    SCC_RULES.msDefenderConfig = msDefenderConfigParser;
}
if (typeof involfltVersionParser !== 'undefined') {
    SCC_RULES.involfltVersion = involfltVersionParser;
}
if (typeof involfltKernelVersionParser !== 'undefined') {
    SCC_RULES.involfltKernelVersion = involfltKernelVersionParser;
}
if (typeof azureExtensionsParser !== 'undefined') {
    SCC_RULES.azureExtensions = azureExtensionsParser;
}
if (typeof fstrimParser !== 'undefined') {
    SCC_RULES.fstrim = fstrimParser;
}

// From parsers/events.js  
if (typeof emergencyModeParser !== 'undefined') {
    SCC_RULES.emergencyMode = emergencyModeParser;
}
if (typeof kernelRebootsParser !== 'undefined') {
    SCC_RULES.kernelReboots = kernelRebootsParser;
}
if (typeof oomKillerParser !== 'undefined') {
    SCC_RULES.oomKiller = oomKillerParser;
}
if (typeof xfsErrorsParser !== 'undefined') {
    SCC_RULES.xfsErrors = xfsErrorsParser;
}

// From parsers/azure.js
if (typeof azureVMPropertiesParser !== 'undefined') {
    SCC_RULES.azureVMProperties = azureVMPropertiesParser;
}
if (typeof suseCloudRegisterParser !== 'undefined') {
    SCC_RULES.suseCloudRegister = suseCloudRegisterParser;
}
if (typeof waagentConfigParser !== 'undefined') {
    SCC_RULES.waagentConfig = waagentConfigParser;
}
if (typeof waagentLogParser !== 'undefined') {
    SCC_RULES.waagentLog = waagentLogParser;
}
if (typeof secureBootParser !== 'undefined') {
    SCC_RULES.secureBoot = secureBootParser;
}

// From parsers/cluster.js
// Initialize cluster parsers
if (typeof createClusterParsers !== 'undefined') {
    const clusterParsers = createClusterParsers();
    SCC_RULES.clusterNodes = clusterParsers.clusterNodes;
    SCC_RULES.hostsFile = clusterParsers.hostsFile;
    SCC_RULES.corosyncConfig = clusterParsers.corosyncConfig;
    SCC_RULES.pacemakerResources = clusterParsers.pacemakerResources;
    SCC_RULES.corosyncStatus = clusterParsers.corosyncStatus;
    SCC_RULES.clusterStatus = clusterParsers.clusterStatus;
    SCC_RULES.clusterDaemonStatus = clusterParsers.clusterDaemonStatus;
    SCC_RULES.azureScheduledEvents = clusterParsers.azureScheduledEvents;
    SCC_RULES.fencingConfig = clusterParsers.fencingConfig;
    SCC_RULES.clusterEvents = clusterParsers.clusterEvents;
    SCC_RULES.liveMigration = clusterParsers.liveMigration;
    SCC_RULES.sapInstanceConfig = clusterParsers.sapInstanceConfig;
    SCC_RULES.sapInstanceErrors = clusterParsers.sapInstanceErrors;
    SCC_RULES.clusterMaintenanceMode = clusterParsers.clusterMaintenanceMode;
    SCC_RULES.sbdConfig = clusterParsers.sbdConfig;
    SCC_RULES.azureFenceAuth = clusterParsers.azureFenceAuth;
    SCC_RULES.iscsiConfig = clusterParsers.iscsiConfig;
}

// From parsers/storage.js
if (typeof lvmConfigParser !== 'undefined') {
    SCC_RULES.lvmConfig = lvmConfigParser;
}
if (typeof raidConfigParser !== 'undefined') {
    SCC_RULES.raidConfig = raidConfigParser;
}
if (typeof btrfsConfigParser !== 'undefined') {
    SCC_RULES.btrfsConfig = btrfsConfigParser;
}
if (typeof blockDevicesParser !== 'undefined') {
    SCC_RULES.blockDevices = blockDevicesParser;
}
if (typeof fstabAnalysisParser !== 'undefined') {
    SCC_RULES.fstabAnalysis = fstabAnalysisParser;
}
if (typeof dfOutputParser !== 'undefined') {
    SCC_RULES.dfOutput = dfOutputParser;
}
if (typeof mtabAnalysisParser !== 'undefined') {
    SCC_RULES.mtabAnalysis = mtabAnalysisParser;
}
if (typeof nvmeListParser !== 'undefined') {
    SCC_RULES.nvmeList = nvmeListParser;
}
if (typeof nfsMountsParser !== 'undefined') {
    SCC_RULES.nfsMounts = nfsMountsParser;
}

// From parsers/hana.js
if (typeof hanaSavepointsParser !== 'undefined') {
    SCC_RULES.hanaSavepoints = hanaSavepointsParser;
}
if (typeof hanaDeadlocksParser !== 'undefined') {
    SCC_RULES.hanaDeadlocks = hanaDeadlocksParser;
}
if (typeof hanaOomParser !== 'undefined') {
    SCC_RULES.hanaOom = hanaOomParser;
}
if (typeof hanaMergeErrorsParser !== 'undefined') {
    SCC_RULES.hanaMergeErrors = hanaMergeErrorsParser;
}

// From parsers/unix.js - RHUI/EUS parsers
if (typeof rhuiConfigParser !== 'undefined') {
    SCC_RULES.rhuiConfig = rhuiConfigParser;
}
if (typeof eusVersionLockParser !== 'undefined') {
    SCC_RULES.eusVersionLock = eusVersionLockParser;
}
if (typeof rhelRhuiCheckParser !== 'undefined') {
    SCC_RULES.rhelRhuiCheck = rhelRhuiCheckParser;
}
if (typeof cryptoPoliciesParser !== 'undefined') {
    SCC_RULES.cryptoPolicies = cryptoPoliciesParser;
}
if (typeof fipsModeSetupParser !== 'undefined') {
    SCC_RULES.fipsModeSetup = fipsModeSetupParser;
}
if (typeof tunedProfileParser !== 'undefined') {
    SCC_RULES.tunedProfile = tunedProfileParser;
}
if (typeof selinuxParser !== 'undefined') {
    SCC_RULES.selinux = selinuxParser;
}
if (typeof swapSpaceParser !== 'undefined') {
    SCC_RULES.swapSpace = swapSpaceParser;
}
if (typeof kernelCmdlineParser !== 'undefined') {
    SCC_RULES.kernelCmdline = kernelCmdlineParser;
}
if (typeof rhuiErrorsParser !== 'undefined') {
    SCC_RULES.rhuiErrors = rhuiErrorsParser;
}
if (typeof leappReportParser !== 'undefined') {
    SCC_RULES.leappReport = leappReportParser;
}
if (typeof leappLogParser !== 'undefined') {
    SCC_RULES.leappLog = leappLogParser;
}

// From parsers/networking.js
if (typeof firewallRulesParser !== 'undefined') {
    SCC_RULES.firewallRules = firewallRulesParser;
    debugLog('[Worker] firewallRulesParser registered successfully, filePattern:', firewallRulesParser.filePattern);
} else {
    console.warn('[Worker] firewallRulesParser is NOT defined - networking.js may have failed to load');
}
if (typeof packetLossParser !== 'undefined') {
    SCC_RULES.packetLoss = packetLossParser;
}
if (typeof ringBufferParser !== 'undefined') {
    SCC_RULES.ringBuffer = ringBufferParser;
}
if (typeof networkSysctlParser !== 'undefined') {
    SCC_RULES.networkSysctl = networkSysctlParser;
}

// From parsers/network-interfaces.js
if (typeof networkInterfacesParser !== 'undefined') {
    SCC_RULES.networkInterfaces = networkInterfacesParser;
    debugLog('[Worker] networkInterfacesParser registered successfully, filePattern:', networkInterfacesParser.filePattern);
} else {
    console.warn('[Worker] networkInterfacesParser is NOT defined - network-interfaces.js may have failed to load');
}

// From parsers/vmcore.js
if (typeof vmcoreParser !== 'undefined') {
    SCC_RULES.vmcore = vmcoreParser;
    debugLog('[Worker] vmcoreParser registered successfully, filePattern:', vmcoreParser.filePattern);
} else {
    console.warn('[Worker] vmcoreParser is NOT defined - vmcore.js may have failed to load');
}

// From parsers/debugfs.js
if (typeof hvBalloonParser !== 'undefined') {
    SCC_RULES.hvBalloon = hvBalloonParser;
    debugLog('[Worker] hvBalloonParser registered successfully, filePattern:', hvBalloonParser.filePattern);
} else {
    console.warn('[Worker] hvBalloonParser is NOT defined - debugfs.js may have failed to load');
}
if (typeof extfragParser !== 'undefined') {
    SCC_RULES.extfrag = extfragParser;
    debugLog('[Worker] extfragParser registered successfully, filePattern:', extfragParser.filePattern);
} else {
    console.warn('[Worker] extfragParser is NOT defined - debugfs.js may have failed to load');
}
// ============================================================================

// Load the Rust streaming WASM module.
//
// The build step renames the LZMA module's top-level global from
// `wasm_bindgen` to `lzma_bindgen` so it can co-exist with the
// supportfile_wasm module (also target=no-modules) without redeclaring
// the same identifier.
importScripts(versionedAsset('./lzma-stream-wasm/lzma_stream_wasm.js'));
const rustLzmaInit = lzma_bindgen;
const rustLzmaModule = lzma_bindgen;

let moduleReady = false;
let LzmaModule = null;
let Module = {};

(async () => {
    try {
        debugLog('[XZ Streaming Worker] Initializing Rust LZMA wasm...');
        await rustLzmaInit(
            versionedAsset('./lzma-stream-wasm/lzma_stream_wasm_bg.wasm'));
        LzmaModule = rustLzmaModule;
        if (typeof LzmaModule.xzStreamInit !== 'function' ||
            typeof LzmaModule.xzStreamProcess !== 'function' ||
            typeof LzmaModule.xzStreamError !== 'function' ||
            typeof LzmaModule.xzStreamFree !== 'function') {
            throw new Error('Rust XZ wasm module is missing expected exports');
        }

        moduleReady = true;
        debugLog('[XZ Streaming Worker] Rust LZMA module initialized successfully');

        if (typeof wasm_bindgen === 'function') {
            await wasm_bindgen(
                versionedAsset('supportfile-wasm/supportfile_wasm_bg.wasm'));
            self.SUPPORTFILE_WASM_READY = true;
            debugLog('[Worker] supportfile WASM initialized');
        } else {
            self.SUPPORTFILE_WASM_READY = false;
            console.warn('[Worker] supportfile wasm-bindgen init was not available');
        }

        self.postMessage({ ready: true });
        debugLog('[XZ Streaming Worker] Ready message sent to main thread');
    } catch (err) {
        console.error('[XZ Streaming Worker] Module initialization failed:', err);
        self.postMessage({ error: 'WASM module initialization failed: ' + err.message });
    }
})();

// Parse TAR headers incrementally as data arrives
class IncrementalTARParser {
    constructor() {
        this.buffer = new Uint8Array(0);
        this.pendingChunks = [];   // Chunks waiting to be merged into buffer
        this.pendingLength = 0;    // Total bytes in pendingChunks
        // When the previous entry was a non-matching file whose data section
        // exceeded what was already buffered at parse time, this holds the
        // number of bytes that should be discarded from incoming chunks
        // before any further data is queued. Keeps worker memory bounded
        // even when the archive contains very large files we don't parse.
        this.pendingSkip = 0;
        this.files = [];
        // Cap the file inventory to bound worker memory on archives with
        // hundreds of thousands of entries. getAnalysis() only returns the
        // first 50 anyway; we still maintain an accurate `fileCount` via
        // `totalFileCount` which is incremented for every file regardless of
        // whether it's stored.
        this.MAX_FILES_RETAINED = 5000;
        this.totalFileCount = 0;
        this.directories = new Set();
        this.MAX_DIRECTORIES_RETAINED = 5000;
        this.fileTypes = {};
        this.offset = 0;
        this.totalParsed = 0;
        this.foundEndMarker = false;
        
        // SCC report analysis state
        this.isSCCReport = false;
        this.isHanaLog = false;
        this.sccReportName = null;
        this.analysisResults = {}; // Stores parsed results by rule name (no raw file content)
        this.perfTracker = null; // Lazy-init when performance debug is enabled
        this.nextLongFilename = null; // For GNU TAR long filename extension
        this.paxExtendedHeaders = {};  // For PAX extended attributes
        this.usedPaxFormat = false;  // Track if PAX extended headers were used
        this.processedLogFiles = {}; // Track processed log files to limit rotations (performance optimization)
        
        // Current file being processed (for progress reporting)
        this.currentFile = '';
        
        // Nested compression statistics
        this.nestedGzipTotalCount = 0; // Total .gz files found in archive
        this.nestedGzipTotalCompressedBytes = 0; // Total compressed size of all .gz files
        this.nestedGzipCount = 0; // .gz files actually decompressed
        this.nestedGzipCompressedBytes = 0; // Compressed size of decompressed files
        this.nestedGzipDecompressedBytes = 0; // Decompressed size
    }

    /**
     * Bounded inventory append. We always count every file (so fileCount and
     * the file-type histogram stay accurate), but only retain the first
     * MAX_FILES_RETAINED entries in the `files` array. The UI shows at most
     * the first 50, so retaining more would just waste memory on archives
     * with hundreds of thousands of entries.
     */
    recordFile(filename, size, typeflag) {
        this.totalFileCount++;
        if (this.files.length < this.MAX_FILES_RETAINED) {
            this.files.push({
                name: filename,
                size: size,
                type: typeflag === 53 ? 'dir' : 'file'
            });
        }
    }

    /**
     * Bounded directory tracking. Same rationale as recordFile: directory
     * sets in deeply-nested archives can grow unbounded.
     */
    addDirectory(path) {
        if (this.directories.size < this.MAX_DIRECTORIES_RETAINED) {
            this.directories.add(path);
        }
    }

    // Add decompressed chunk to buffer and parse what we can
    addChunk(chunk) {
        // Memory-efficiency: when the previous entry was a non-matching file
        // larger than what was buffered at parse time, we mark its remaining
        // data bytes for discard. Consume that many bytes from the front of
        // this chunk before queueing anything. This prevents multi-GB archives
        // from being held in worker memory just to be ignored later.
        if (this.pendingSkip > 0) {
            if (chunk.length <= this.pendingSkip) {
                this.pendingSkip -= chunk.length;
                return;
            }
            chunk = chunk.subarray(this.pendingSkip);
            this.pendingSkip = 0;
        }

        // Defer buffer concatenation: just queue the chunk
        this.pendingChunks.push(chunk);
        this.pendingLength += chunk.length;

        // Only flatten when we might have a complete TAR entry to process.
        // A TAR header is 512 bytes; we need at least header + data to proceed.
        // Flatten when total available data (buffer remainder + pending) could
        // contain a new entry or when pending data exceeds 4 MB (avoid unbounded queue).
        const available = (this.buffer.length - this.offset) + this.pendingLength;
        if (available >= 512 || this.pendingLength >= 4 * 1024 * 1024) {
            this.flushPendingChunks();
        }

        // Parse complete TAR entries
        this.parseAvailableEntries();
    }

    // Merge pending chunks into the main buffer in one copy.
    //
    // Memory-efficiency: when a single TAR entry is large (e.g. a multi-100 MB
    // log), naive growth (allocate exactly remaining + pending each call) is
    // O(N²) total bytes copied because every flush re-copies the whole prefix.
    // We grow geometrically (at least double the previous capacity) so the
    // total work is O(N) and peak memory stays close to 2× the entry size.
    flushPendingChunks() {
        if (this.pendingChunks.length === 0) return;

        const remaining = this.buffer.length - this.offset;
        const newDataLen = remaining + this.pendingLength;

        // Reuse the existing backing buffer's tail capacity if there's room
        // beyond the current view. We append at `byteOffset + length`, so the
        // available room is measured from there — NOT from `offset`, which
        // would over-count the bytes we have already consumed and lead to a
        // RangeError ("Invalid typed array length") when the new view is
        // constructed past the backing buffer's end.
        const backing = this.buffer.buffer;
        const tailStart = this.buffer.byteOffset + this.buffer.length;
        const tailRoom = backing.byteLength - tailStart;
        if (tailRoom >= this.pendingLength) {
            // Append in place — no allocation, no copy of the prefix.
            const view = new Uint8Array(backing, tailStart, this.pendingLength);
            let pos = 0;
            for (const c of this.pendingChunks) {
                view.set(c, pos);
                pos += c.length;
            }
            // Extend logical view to include the new data.
            this.buffer = new Uint8Array(
                backing,
                this.buffer.byteOffset,
                this.buffer.length + this.pendingLength
            );
            this.pendingChunks = [];
            this.pendingLength = 0;
            return;
        }

        // Need to reallocate. Grow geometrically to avoid quadratic copy.
        const capacity = Math.max(newDataLen, this.buffer.length * 2, 64 * 1024);
        const mergedBacking = new ArrayBuffer(capacity);
        const merged = new Uint8Array(mergedBacking, 0, newDataLen);

        // Copy unprocessed portion of old buffer
        if (remaining > 0) {
            merged.set(this.buffer.subarray(this.offset), 0);
        }

        // Append all pending chunks
        let pos = remaining;
        for (const c of this.pendingChunks) {
            merged.set(c, pos);
            pos += c.length;
        }

        this.buffer = merged;
        this.offset = 0;
        this.pendingChunks = [];
        this.pendingLength = 0;
    }

    parseAvailableEntries() {
        while (true) {
            // Ensure pending data is merged before checking available bytes
            const available = (this.buffer.length - this.offset) + this.pendingLength;
            if (available < 512) break;

            // Flush pending chunks if buffer doesn't have enough for header check
            if (this.buffer.length - this.offset < 512 && this.pendingLength > 0) {
                this.flushPendingChunks();
            }

            // Check for end marker (two consecutive zero blocks)
            if (this.isEndMarker(this.offset)) {
                this.foundEndMarker = true;
                debugLog('[TAR Parser] Found TAR end marker');
                break;
            }

            // Need full header + potential data
            const header = this.parseHeader(this.offset);
            if (!header) {
                break; // Invalid or incomplete header
            }

            const entrySize = 512 + Math.ceil(header.size / 512) * 512;

            // Memory-efficiency prefilter: if no parser will read the data
            // section of this entry, advance past the header + data without
            // ever buffering the data. We still record the file's metadata
            // (filename, size, type) for the inventory.
            if (!this.entryNeedsContent(header)) {
                // Record lightweight metadata; never touch the (possibly huge)
                // data section.
                this.recordEntryMetadataOnly(header);

                // Advance over the header (which IS in the buffer).
                this.offset += 512;

                // Discard data bytes that are already in the buffer …
                const dataInBuffer = Math.min(
                    this.buffer.length - this.offset,
                    entrySize - 512
                );
                if (dataInBuffer > 0) {
                    this.offset += dataInBuffer;
                }

                // … and discard the rest from incoming chunks via pendingSkip.
                const dataNotYetSeen = (entrySize - 512) - dataInBuffer;
                if (dataNotYetSeen > 0) {
                    this.pendingSkip = dataNotYetSeen;
                }

                this.totalParsed++;

                // Trim and continue. If we set pendingSkip we may not have
                // any more parseable data right now; loop will exit.
                if (this.offset > 512 * 1024) {
                    this.buffer = this.buffer.subarray(this.offset);
                    this.offset = 0;
                }
                if (this.pendingSkip > 0) break;
                continue;
            }

            // Check if we have the complete entry (including pending data)
            const buffered = this.buffer.length - this.offset;
            if (buffered < entrySize) {
                if (buffered + this.pendingLength >= entrySize) {
                    // We have enough in pending chunks — flush and retry
                    this.flushPendingChunks();
                } else {
                    break; // Wait for more data
                }
            }

            // Process entry
            this.processEntry(header);

            // Move to next entry
            this.offset += entrySize;
            this.totalParsed++;
        }

        // Trim processed data from buffer to keep memory low
        if (this.offset > 512 * 1024) {
            this.buffer = this.buffer.subarray(this.offset);
            this.offset = 0;
        }
    }

    /**
     * Decide whether the data section of a TAR entry must be buffered.
     *
     * Returns true for:
     *   - GNU long-name and PAX extended-header entries (their data IS the
     *     metadata for the next entry)
     *   - A file whose name triggers SCC-report detection
     *   - Any file whose name matches a parser's filePattern (when we already
     *     know we are in an SCC report)
     *
     * Returns false for everything else (directories, empty files, files in
     * `/proc/`, `/sys/`, large binaries, etc.). Their bytes are dropped on the
     * floor — never copied into worker memory.
     */
    entryNeedsContent(header) {
        const { filename, size, typeflag } = header;

        // GNU long filename and PAX extended-header entries: the data section
        // contains metadata for the *next* entry, so we must read it.
        if (
            typeflag === 76 || typeflag === 'L'.charCodeAt(0) ||
            typeflag === 120 || typeflag === 103 ||
            typeflag === 'x'.charCodeAt(0) || typeflag === 'g'.charCodeAt(0)
        ) {
            return true;
        }

        // Empty entries and directories carry no parseable content.
        if (size === 0) return false;
        if (typeflag === 53 || typeflag === '5'.charCodeAt(0)) return false;

        // SCC detection runs on filename only — but we'll need to extract
        // content immediately on the very first detection file as well.
        if (!this.isSCCReport && SCC_RULES.detection.isSCCReport(filename)) {
            return true;
        }

        // HANA trace files may appear in a standalone (non-SCC) log archive.
        if (SCC_RULES.detection.isHanaLog(filename)) {
            return true;
        }

        // Files outside an SCC report are inventoried but never parsed.
        if (!this.isSCCReport) return false;

        // Inside an SCC report, only files matching at least one parser
        // pattern are worth buffering.
        for (const ruleName in SCC_RULES) {
            const rule = SCC_RULES[ruleName];
            if (ruleName === 'detection' || !rule || !rule.filePattern) continue;
            if (rule.filePattern.test(filename)) return true;
        }

        return false;
    }

    /**
     * Lightweight bookkeeping for entries whose data was discarded.
     * Mirrors the bookkeeping side of processEntry() without touching the
     * (already-discarded) data bytes.
     */
    recordEntryMetadataOnly(header) {
        const { filename, size, typeflag } = header;

        // Track current file for progress reporting
        this.currentFile = filename;

        // Clear PAX headers after a regular file (matches processEntry behavior)
        if (typeflag === 48 || typeflag === 0 || typeflag === '0'.charCodeAt(0)) {
            this.paxExtendedHeaders = {};
        }

        // Track directories
        if (filename.includes('/')) {
            const parts = filename.split('/');
            let path = '';
            for (let i = 0; i < parts.length - 1; i++) {
                path += parts[i] + '/';
                this.addDirectory(path);
            }
        }

        // Track file-type histogram
        const ext = filename.includes('.') ? filename.split('.').pop().toLowerCase() : 'none';
        this.fileTypes[ext] = (this.fileTypes[ext] || 0) + 1;

        // Inventory the file (bounded; counts all, retains first N)
        this.recordFile(filename, size, typeflag);

        // Track *all* .gz entries (not just the ones we actually decompress)
        if (filename.toLowerCase().endsWith('.gz') &&
            (typeflag === 48 || typeflag === 0 || typeflag === '0'.charCodeAt(0))) {
            this.nestedGzipTotalCount++;
            this.nestedGzipTotalCompressedBytes += size;
        }
    }

    isEndMarker(offset) {
        if (this.buffer.length - offset < 1024) return false;
        for (let i = 0; i < 1024; i++) {
            if (this.buffer[offset + i] !== 0) return false;
        }
        return true;
    }

    parseHeader(offset) {
        if (this.buffer.length - offset < 512) return null;

        // Read type flag first (offset 156)
        const typeflag = this.buffer[offset + 156];

        // Read filename (null-terminated, first 100 bytes)
        let filename = '';
        for (let i = 0; i < 100; i++) {
            if (this.buffer[offset + i] === 0) break;
            filename += String.fromCharCode(this.buffer[offset + i]);
        }

        // Read prefix field (offset 345, 155 bytes) for POSIX ustar format
        let prefix = '';
        for (let i = 345; i < 500; i++) {
            if (this.buffer[offset + i] === 0) break;
            prefix += String.fromCharCode(this.buffer[offset + i]);
        }

        // Combine prefix and filename if prefix exists
        if (prefix) {
            filename = prefix + '/' + filename;
        }

        // Use long filename from previous GNU extension if available
        if (this.nextLongFilename) {
            filename = this.nextLongFilename;
            this.nextLongFilename = null;
        }

        // Use path from PAX extended headers if available
        if (this.paxExtendedHeaders.path) {
            filename = this.paxExtendedHeaders.path;
        }

        if (!filename) return null;

        // Read size (octal string at offset 124, 12 bytes)
        let sizeStr = '';
        for (let i = 124; i < 136; i++) {
            const c = this.buffer[offset + i];
            if (c === 0 || c === 32) break;
            sizeStr += String.fromCharCode(c);
        }

        const size = parseInt(sizeStr.trim(), 8) || 0;

        // Debug: Log when parsing headers for key files
        if (filename.includes('dpkg') || filename.includes('usr/lib/os-release')) {
            debugLog(`[TAR Parser] parseHeader:`, filename, `size=${size}, prefix='${prefix}', name_len=${filename.length}, typeflag=${typeflag}`);
        }

        return { filename, size, typeflag, offset };
    }

    processEntry(header) {
        const { filename, size, typeflag, offset } = header;
        
        // Track current file for progress reporting
        this.currentFile = filename;

        // Handle GNU TAR long filename extension (typeflag='L' or 76)
        if (typeflag === 76 || typeflag === 'L'.charCodeAt(0)) {
            // This entry contains a long filename for the NEXT entry
            // Extract the long filename from the data section
            const dataOffset = offset + 512;
            let longName = '';
            const maxRead = Math.min(size, this.buffer.length - dataOffset);
            for (let i = 0; i < maxRead; i++) {
                const c = this.buffer[dataOffset + i];
                if (c === 0) break;
                longName += String.fromCharCode(c);
            }
            this.nextLongFilename = longName;
            debugLog(`[TAR Parser] Found long filename:`, longName);
            return; // Don't process this as a regular file
        }

        // Handle PAX extended headers (typeflag='x' (120) or 'g' (103))
        if (typeflag === 120 || typeflag === 103 || typeflag === 'x'.charCodeAt(0) || typeflag === 'g'.charCodeAt(0)) {
            this.usedPaxFormat = true;  // Mark that this archive uses PAX format
            const dataOffset = offset + 512;
            let paxData = '';
            const maxRead = Math.min(size, this.buffer.length - dataOffset);
            for (let i = 0; i < maxRead; i++) {
                const c = this.buffer[dataOffset + i];
                if (c === 0) break;
                paxData += String.fromCharCode(c);
            }
            
            // Parse PAX extended headers (format: "length key=value\n")
            const lines = paxData.split('\n');
            for (const line of lines) {
                if (!line.trim()) continue;
                // PAX format: "111 path=sosreport-..." or "111 path = sosreport-..."
                const match = line.match(/^\d+\s+(\S+)\s*=\s*(.*)$/);
                if (match) {
                    const key = match[1];
                    const value = match[2];
                    this.paxExtendedHeaders[key] = value;
                    if (key === 'path' || key === 'linkpath') {
                        debugLog(`[TAR Parser] Found PAX ${key}:`, value);
                    }
                }
            }
            return; // Don't process PAX headers as regular files
        }

        // Debug: Log when we see key files
        if (filename.endsWith('dpkg_-l') || filename.endsWith('os-release')) {
            debugLog(`[TAR Parser] processEntry:`, filename, `size=${size}, typeflag=${typeflag}`);
        }

        // Detect SCC report using rules
        if (!this.isSCCReport && SCC_RULES.detection.isSCCReport(filename)) {
            this.isSCCReport = true;
            this.sccReportName = filename.split('/')[0];
            debugLog('[TAR Parser] Detected SCC report:', this.sccReportName);
        }

        // Detect standalone HANA log archive (no SCC wrapper).
        if (!this.isHanaLog && SCC_RULES.detection.isHanaLog(filename)) {
            this.isHanaLog = true;
            debugLog('[TAR Parser] Detected HANA trace file:', filename);
        }

        // Process SCC rules if this is an SCC report
        if ((this.isSCCReport || this.isHanaLog) && size > 0) {
            this.processSCCRules(filename, size, offset);
        }

        // Clear PAX headers after processing regular file (typeflag '0' or 48)
        if (typeflag === 48 || typeflag === 0 || typeflag === '0'.charCodeAt(0)) {
            this.paxExtendedHeaders = {};
        }

        // Track directories
        if (filename.includes('/')) {
            const parts = filename.split('/');
            let path = '';
            for (let i = 0; i < parts.length - 1; i++) {
                path += parts[i] + '/';
                this.addDirectory(path);
            }
        }

        // Track file types
        const ext = filename.includes('.') ? filename.split('.').pop().toLowerCase() : 'none';
        this.fileTypes[ext] = (this.fileTypes[ext] || 0) + 1;

        // Store file entry (bounded; counts all, retains first N)
        this.recordFile(filename, size, typeflag);
        
        // Track ALL .gz files in the archive (not just the ones we decompress)
        if (filename.toLowerCase().endsWith('.gz') && (typeflag === 48 || typeflag === 0 || typeflag === '0'.charCodeAt(0))) {
            this.nestedGzipTotalCount++;
            this.nestedGzipTotalCompressedBytes += size;
        }
    }

    // Process all SCC rules against current file
    processSCCRules(filename, size, offset) {
        // Skip PaxHeaders - they are TAR extended headers, not actual file content
        if (filename.includes('/PaxHeaders/') || filename.endsWith('/PaxHeaders')) {
            return;
        }
        
        // Normalize sos_strings tailed file paths back to their original paths
        // sosreport stores large log files in sos_strings/<plugin>/var.log.<path>.<file>.tailed
        // and creates symlinks from the original paths (which appear as 0-byte entries in tar)
        // Example: sos_strings/pacemaker/var.log.pacemaker.pacemaker.log.tailed -> var/log/pacemaker/pacemaker.log
        // Example: sos_strings/logs/var.log.messages.tailed -> var/log/messages
        // Example: sos_strings/logs/var.log.secure-20260125.tailed -> var/log/secure-20260125
        const tailedMatch = filename.match(/sos_strings\/[^\/]+\/(.+)\.tailed$/);
        if (tailedMatch) {
            // The dotted path encodes the original filesystem path with dots as separators
            // We need to reconstruct: var.log.pacemaker.pacemaker.log -> var/log/pacemaker/pacemaker.log
            // Strategy: known log file extensions (.log, .conf) mark where filename starts
            const dottedPath = tailedMatch[1];
            let originalPath;
            
            // Match known file extensions to find filename boundary
            // e.g., "var.log.pacemaker.pacemaker.log" -> split at last known ext keeping it as extension
            const extMatch = dottedPath.match(/^(.+)\.((log|conf|txt|xml)(?:[.-].+)?)$/);
            if (extMatch) {
                // extMatch[1] = "var.log.pacemaker.pacemaker", extMatch[2] = "log" or "log-20260127"
                const pathPart = extMatch[1];
                const filePart = extMatch[2];
                // Find the last dot-separated segment before the extension as the filename base
                const segments = pathPart.split('.');
                const fileBase = segments.pop();
                const dirPath = segments.join('/');
                originalPath = dirPath + '/' + fileBase + '.' + filePart;
            } else {
                // No known extension (e.g., "var.log.messages", "var.log.secure-20260125")
                const segments = dottedPath.split('.');
                const fileName = segments.pop();
                const dirPath = segments.join('/');
                originalPath = dirPath + '/' + fileName;
            }
            
            // Reconstruct full path with the report prefix
            const reportPrefix = filename.substring(0, filename.indexOf('sos_strings'));
            filename = reportPrefix + originalPath;
            debugLog('[TAR Parser] Normalized sos_strings tailed path to:', filename);
        }
        
        // Performance optimization: Limit processing of compressed rotated log files
        // Track which base log files we've seen and limit compressed rotations to 3 most recent
        // Uncompressed rotated logs are processed without limit
        if (!this.processedLogFiles) {
            this.processedLogFiles = {}; // Track: baseFileName -> [rotation numbers for compressed files]
        }
        
        // Check if this is a compressed rotated log file (messages.1.gz, messages-20241215.bz2, etc.)
        const compressedRotationMatch = filename.match(/\/(messages|localmessages|journalctl[^/]*|pacemaker\.log|corosync\.log)([.-]\d+)?(?:\.gz|\.bz2|\.xz)$/);
        if (compressedRotationMatch) {
            const baseFile = compressedRotationMatch[1];
            const rotation = compressedRotationMatch[2] || '.current';
            
            if (!this.processedLogFiles[baseFile]) {
                this.processedLogFiles[baseFile] = [];
            }
            
            // Check if any rule needs all rotations for this file
            const needsAllRotations = Object.values(SCC_RULES).some(rule => 
                rule.processAllRotations && rule.filePattern && rule.filePattern.test(filename)
            );
            
            if (!needsAllRotations) {
                // Limit to 3 versions of compressed log files (current + 2 rotations)
                // This prevents processing dozens of old compressed rotated logs
                if (this.processedLogFiles[baseFile].length >= 3) {
                    debugLog(`[TAR Parser] Skipping compressed rotated log (limit reached):`, filename);
                    return;
                }
            }
            
            this.processedLogFiles[baseFile].push(rotation);
            const limitInfo = needsAllRotations ? 'no limit' : `${this.processedLogFiles[baseFile].length}/3`;
            debugLog(`[TAR Parser] Processing compressed log file ${baseFile} rotation ${rotation} (${limitInfo})`);
        }
        
        // Debug: Log when we see key files
        if (filename.endsWith('dpkg_-l') || filename.endsWith('os-release')) {
            debugLog(`[TAR Parser] Processing file:`, filename, `size=${size}`);
        }
        
        // Iterate through all rules (except detection)
        // Performance: extract file content ONCE and reuse across all matching parsers
        // instead of re-slicing and re-decoding the buffer for each parser
        const dataOffset = offset + 512;
        let cachedContent = null;          // Full content (decoded once, reused)
        let cachedLines = null;            // Pre-split lines (shared across all parsers for same file)
        let cachedContentSmall = null;     // Truncated content for suseCloudRegister

        // Lazy-init performance tracker on first file if performance debug is on
        const perfMode = DEBUG_CONFIG.performance;
        if (perfMode && !this.perfTracker && typeof PerformanceTracker !== 'undefined') {
            this.perfTracker = new PerformanceTracker();
        }
        const pt = this.perfTracker;
        let fileParserCount = 0;
        
        for (const [ruleName, rule] of Object.entries(SCC_RULES)) {
            if (ruleName === 'detection' || !rule.filePattern) continue;
            
            // Debug: Log pattern testing for key files
            if (filename.includes('os-release') || filename.includes('dpkg') || filename.includes('installed-rpms') || filename.includes('package-data') || filename.includes('dnf.log') || filename.includes('/block/') || filename.includes('/fstab') || filename.includes('fs-iscsi') || filename.includes('iscsi')) {
                debugLog(`[TAR Parser] Testing rule '${ruleName}' pattern ${rule.filePattern} against:`, filename);
            }
            // Check if filename matches rule pattern
            if (rule.filePattern.test(filename)) {
                debugLog(`[TAR Parser] Matched rule '${ruleName}' for file:`, filename);

                // Start per-file timing on first matching rule
                if (pt && fileParserCount === 0) {
                    pt.startFile();
                }
                fileParserCount++;
                
                // Special case: cloudregister.txt can be huge (1GB+), only extract first 100KB
                let content;
                if (ruleName === 'suseCloudRegister') {
                    const maxSize = 100 * 1024; // 100 KB
                    const extractSize = Math.min(size, maxSize);
                    debugLog(`[TAR Parser] cloudregister.txt size ${size} bytes, extracting first ${extractSize} bytes`);
                    if (this.buffer.length >= dataOffset + extractSize) {
                        if (!cachedContentSmall) {
                            cachedContentSmall = this.extractFileContent(dataOffset, extractSize, filename);
                        }
                        content = cachedContentSmall;
                    }
                } else {
                    if (this.buffer.length >= dataOffset + size) {
                        if (!cachedContent) {
                            cachedContent = this.extractFileContent(dataOffset, size, filename);
                        }
                        content = cachedContent;
                    }
                }
                
                if (content) {
                        // Split lines ONCE and share across all matching parsers
                        // Avoids each parser re-splitting the same content (e.g. 10 parsers × 44MB = 10 redundant splits)
                        if (!cachedLines) {
                            cachedLines = content.split('\n');
                        }
                        
                        // For rules that process multiple files (like liveMigration, kernelReboots, oomKiller, xfsErrors, emergencyMode, sshService, automation, clusterEvents, rhuiErrors, blockDevices, sapInstanceErrors, firewallRules, azureExtensions, and kernelTuning)
                        // we need to accumulate results instead of replacing
                        const isMultiFileRule = ruleName === 'liveMigration' || ruleName === 'kernelReboots' || ruleName === 'oomKiller' || ruleName === 'xfsErrors' || ruleName === 'emergencyMode' || ruleName === 'sshService' || ruleName === 'automation' || ruleName === 'clusterEvents' || ruleName === 'rhuiErrors' || ruleName === 'blockDevices' || ruleName === 'sapInstanceErrors' || ruleName === 'firewallRules' || ruleName === 'networkInterfaces' || ruleName === 'vmcore' || ruleName === 'azureExtensions' || ruleName === 'lvmConfig' || ruleName === 'kernelTuning' || ruleName === 'nfsMounts' || ruleName === 'hanaSavepoints' || ruleName === 'hanaDeadlocks' || ruleName === 'hanaOom' || ruleName === 'hanaMergeErrors';
                        
                        // NOTE: We don't store file content in extractedFiles anymore to save memory
                        // Content is parsed immediately and discarded
                        
                        // Parse using rule's parse function (pass filename for format detection)
                        try {
                            const parseStart = pt ? performance.now() : 0;
                            const result = rule.parse(content, filename, cachedLines);
                            if (pt) {
                                pt.recordParser(filename, ruleName, performance.now() - parseStart, result, this.analysisResults[ruleName]);
                            }
                            
                            if (isMultiFileRule) {
                                // Accumulate results for multi-file rules
                                // rhuiErrors, blockDevices, sapInstanceErrors, firewallRules, lvmConfig, and kernelTuning have different structures, so initialize separately
                                if (!this.analysisResults[ruleName] && ruleName !== 'rhuiErrors' && ruleName !== 'blockDevices' && ruleName !== 'sapInstanceErrors' && ruleName !== 'firewallRules' && ruleName !== 'networkInterfaces' && ruleName !== 'vmcore' && ruleName !== 'lvmConfig' && ruleName !== 'kernelTuning' && ruleName !== 'nfsMounts' && ruleName !== 'hanaSavepoints' && ruleName !== 'hanaDeadlocks' && ruleName !== 'hanaOom' && ruleName !== 'hanaMergeErrors') {
                                    this.analysisResults[ruleName] = {
                                        count: 0,
                                        events: []
                                    };
                                }
                                
                                // Handle kernelTuning accumulation - merges sysctl parameters across sysctl.conf + sysctl.d/*.conf files
                                if (ruleName === 'kernelTuning') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = { found: false, parameters: {}, warnings: [], hasWarnings: false, azureNetworkWarnings: [], hasAzureNetworkWarnings: false, optionalNetworkInfo: [], hasOptionalNetworkInfo: false };
                                    }
                                    kernelTuningParser.mergeResults(this.analysisResults[ruleName], result);
                                    debugLog(`[TAR Parser] Rule 'kernelTuning' accumulated from ${filename} (parameters: ${Object.keys(this.analysisResults[ruleName].parameters).length})`);
                                }
                                // Handle lvmConfig accumulation - merges PVs, VGs, LVs across separate files
                                else if (ruleName === 'lvmConfig') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = { found: false, pvs: [], vgs: [], lvs: [], warnings: [], rawOutput: {} };
                                    }
                                    lvmConfigParser.mergeResults(this.analysisResults[ruleName], result);
                                    debugLog(`[TAR Parser] Rule 'lvmConfig' accumulated from ${filename} (pvs: ${this.analysisResults[ruleName].pvs.length}, vgs: ${this.analysisResults[ruleName].vgs.length}, lvs: ${this.analysisResults[ruleName].lvs.length})`);
                                }
                                // Handle nfsMounts accumulation - merges NFS mounts and warnings across fstab + mount sources
                                else if (ruleName === 'nfsMounts') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = result;
                                    } else {
                                        this.analysisResults[ruleName] = nfsMountsParser.mergeResults(this.analysisResults[ruleName], result);
                                    }
                                    debugLog(`[TAR Parser] Rule 'nfsMounts' accumulated from ${filename} (mounts: ${(this.analysisResults[ruleName].mounts || []).length}, warnings: ${(this.analysisResults[ruleName].warnings || []).length})`);
                                }
                                // Handle hanaSavepoints accumulation - merges HANA savepoint events and warnings across trace files
                                else if (ruleName === 'hanaSavepoints') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = result;
                                    } else {
                                        this.analysisResults[ruleName] = hanaSavepointsParser.mergeResults(this.analysisResults[ruleName], result);
                                    }
                                    debugLog(`[TAR Parser] Rule 'hanaSavepoints' accumulated from ${filename} (savepoints: ${(this.analysisResults[ruleName].savepoints || []).length}, warnings: ${(this.analysisResults[ruleName].warnings || []).length})`);
                                }
                                // Handle hanaDeadlocks accumulation - merges HANA deadlock events across trace files
                                else if (ruleName === 'hanaDeadlocks') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = result;
                                    } else {
                                        this.analysisResults[ruleName] = hanaDeadlocksParser.mergeResults(this.analysisResults[ruleName], result);
                                    }
                                    debugLog(`[TAR Parser] Rule 'hanaDeadlocks' accumulated from ${filename} (deadlocks: ${(this.analysisResults[ruleName].deadlocks || []).length}, warnings: ${(this.analysisResults[ruleName].warnings || []).length})`);
                                }
                                // Handle hanaOom accumulation - merges HANA out-of-memory events across trace files
                                else if (ruleName === 'hanaOom') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = result;
                                    } else {
                                        this.analysisResults[ruleName] = hanaOomParser.mergeResults(this.analysisResults[ruleName], result);
                                    }
                                    debugLog(`[TAR Parser] Rule 'hanaOom' accumulated from ${filename} (events: ${(this.analysisResults[ruleName].events || []).length}, warnings: ${(this.analysisResults[ruleName].warnings || []).length})`);
                                }
                                // Handle hanaMergeErrors accumulation - merges HANA delta-merge/compression errors across trace files
                                else if (ruleName === 'hanaMergeErrors') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = result;
                                    } else {
                                        this.analysisResults[ruleName] = hanaMergeErrorsParser.mergeResults(this.analysisResults[ruleName], result);
                                    }
                                    debugLog(`[TAR Parser] Rule 'hanaMergeErrors' accumulated from ${filename} (errors: ${(this.analysisResults[ruleName].errors || []).length}, warnings: ${(this.analysisResults[ruleName].warnings || []).length})`);
                                }
                                // Handle blockDevices accumulation - merges disks, partitions, and UUID maps
                                else if (ruleName === 'blockDevices') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = result;
                                    } else {
                                        // Merge result into existing
                                        this.mergeBlockDevicesResult(this.analysisResults[ruleName], result);
                                    }
                                    debugLog(`[TAR Parser] Rule 'blockDevices' accumulated from ${filename} (disks: ${this.analysisResults[ruleName].disks?.length || 0}, partitions: ${this.analysisResults[ruleName].partitions?.length || 0})`);
                                }
                                // Handle vmcore accumulation - merges crash dumps, kdump config/status
                                else if (ruleName === 'vmcore') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = {
                                            found: false,
                                            crashes: [],
                                            kdumpStatus: null,
                                            crashListing: null,
                                            kdumpConf: null
                                        };
                                    }
                                    vmcoreParser.mergeResults(this.analysisResults[ruleName], result);
                                    debugLog(`[TAR Parser] Rule 'vmcore' accumulated from ${filename} (crashes: ${this.analysisResults[ruleName].crashes.length})`);
                                }
                                // For kernelReboots, xfsErrors, emergencyMode, sshService, automation, clusterEvents, rhuiErrors, sapInstanceErrors, firewallRules, networkInterfaces, and azureExtensions, deduplicate events based on timestamp and relevant fields
                                else if (ruleName === 'kernelReboots' || ruleName === 'xfsErrors' || ruleName === 'emergencyMode' || ruleName === 'sshService' || ruleName === 'automation' || ruleName === 'clusterEvents' || ruleName === 'rhuiErrors' || ruleName === 'sapInstanceErrors' || ruleName === 'firewallRules' || ruleName === 'networkInterfaces' || ruleName === 'azureExtensions') {
                                    // Define comparison fields for each rule type
                                    const comparisonFields = ruleName === 'kernelReboots' 
                                        ? ['timestamp', 'type', 'kernelVersion']
                                        : ruleName === 'xfsErrors'
                                        ? ['timestamp', 'device', 'message']
                                        : ruleName === 'emergencyMode'
                                        ? ['timestamp', 'lineNumber']
                                        : ruleName === 'sshService'
                                        ? ['timestamp', 'issueType', 'message']
                                        : ruleName === 'automation'
                                        ? ['timestamp', 'toolType', 'command']
                                        : ruleName === 'azureExtensions'
                                        ? ['name']
                                        : null; // clusterEvents handled separately below
                                    
                                    if (ruleName === 'clusterEvents') {
                                        // clusterEvents has two arrays: resourceMigrations and fencingEvents
                                        if (!this.analysisResults[ruleName].resourceMigrations) {
                                            this.analysisResults[ruleName].resourceMigrations = [];
                                        }
                                        if (!this.analysisResults[ruleName].fencingEvents) {
                                            this.analysisResults[ruleName].fencingEvents = [];
                                        }
                                        // Initialize total counters (track all events even if arrays are capped)
                                        if (this.analysisResults[ruleName].totalResourceMigrations === undefined) {
                                            this.analysisResults[ruleName].totalResourceMigrations = 0;
                                        }
                                        if (this.analysisResults[ruleName].totalFencingEvents === undefined) {
                                            this.analysisResults[ruleName].totalFencingEvents = 0;
                                        }
                                        
                                        // Cap stored events to prevent OOM while keeping accurate counts
                                        const MAX_STORED_EVENTS = 5000;
                                        
                                        // Deduplicate resource migrations
                                        const migrationFields = ['timestamp', 'resource', 'fromNode', 'toNode', 'action'];
                                        const migrationResult = SCC_RULES.deduplicateEvents(
                                            this.analysisResults[ruleName].resourceMigrations,
                                            result.resourceMigrations || [],
                                            migrationFields
                                        );
                                        // Count all unique events
                                        this.analysisResults[ruleName].totalResourceMigrations += migrationResult.addedEvents.length;
                                        // Only store up to the cap
                                        const migrationRoom = MAX_STORED_EVENTS - this.analysisResults[ruleName].resourceMigrations.length;
                                        if (migrationRoom > 0) {
                                            this.analysisResults[ruleName].resourceMigrations.push(
                                                ...migrationResult.addedEvents.slice(0, migrationRoom)
                                            );
                                        }
                                        
                                        // Deduplicate fencing events
                                        const fencingFields = ['timestamp', 'targetNode', 'action', 'status'];
                                        const fencingResult = SCC_RULES.deduplicateEvents(
                                            this.analysisResults[ruleName].fencingEvents,
                                            result.fencingEvents || [],
                                            fencingFields
                                        );
                                        // Count all unique events
                                        this.analysisResults[ruleName].totalFencingEvents += fencingResult.addedEvents.length;
                                        // Only store up to the cap
                                        const fencingRoom = MAX_STORED_EVENTS - this.analysisResults[ruleName].fencingEvents.length;
                                        if (fencingRoom > 0) {
                                            this.analysisResults[ruleName].fencingEvents.push(
                                                ...fencingResult.addedEvents.slice(0, fencingRoom)
                                            );
                                        }
                                        
                                        this.analysisResults[ruleName].count = this.analysisResults[ruleName].totalResourceMigrations + this.analysisResults[ruleName].totalFencingEvents;
                                        
                                        debugLog(`[TAR Parser] Rule 'clusterEvents' accumulated ${migrationResult.addedEvents.length} migrations, ${fencingResult.addedEvents.length} fencing events (${migrationResult.duplicateCount + fencingResult.duplicateCount} duplicates skipped, total: ${this.analysisResults[ruleName].count}, stored: ${this.analysisResults[ruleName].resourceMigrations.length}+${this.analysisResults[ruleName].fencingEvents.length})`);
                                    } else if (ruleName === 'rhuiErrors') {
                                        // RHUI errors rule has special structure - merge boolean flags and arrays
                                        if (!this.analysisResults[ruleName]) {
                                            this.analysisResults[ruleName] = {
                                                found: false,
                                                hasCertExpiration: false,
                                                hasHttp403: false,
                                                hasHttp400: false,
                                                hasConnectionError: false,
                                                errors: [],
                                                affectedRepos: [],
                                                warnings: [],
                                                recommendations: []
                                            };
                                        }
                                        
                                        // Merge boolean flags (OR them together)
                                        this.analysisResults[ruleName].found = this.analysisResults[ruleName].found || result.found;
                                        this.analysisResults[ruleName].hasCertExpiration = this.analysisResults[ruleName].hasCertExpiration || result.hasCertExpiration;
                                        this.analysisResults[ruleName].hasHttp403 = this.analysisResults[ruleName].hasHttp403 || result.hasHttp403;
                                        this.analysisResults[ruleName].hasHttp400 = this.analysisResults[ruleName].hasHttp400 || result.hasHttp400;
                                        this.analysisResults[ruleName].hasConnectionError = this.analysisResults[ruleName].hasConnectionError || result.hasConnectionError;
                                        
                                        // Add errors (with source file)
                                        result.errors.forEach(err => {
                                            this.analysisResults[ruleName].errors.push({
                                                ...err,
                                                sourceFile: filename
                                            });
                                        });
                                        
                                        // Add unique affected repos
                                        result.affectedRepos.forEach(repo => {
                                            if (!this.analysisResults[ruleName].affectedRepos.includes(repo)) {
                                                this.analysisResults[ruleName].affectedRepos.push(repo);
                                            }
                                        });
                                        
                                        // Add unique warnings (by type)
                                        result.warnings.forEach(warning => {
                                            if (!this.analysisResults[ruleName].warnings.find(w => w.type === warning.type)) {
                                                this.analysisResults[ruleName].warnings.push(warning);
                                            }
                                        });
                                        
                                        debugLog(`[TAR Parser] Rule 'rhuiErrors' accumulated from ${filename} (found: ${result.found}, errors: ${result.errors.length}, total errors: ${this.analysisResults[ruleName].errors.length})`);
                                    } else if (ruleName === 'sapInstanceErrors') {
                                        // sapInstanceErrors: merge errors from multiple log files (analysis.txt, cluster-log.txt, messages)
                                        if (!this.analysisResults[ruleName]) {
                                            this.analysisResults[ruleName] = {
                                                found: false,
                                                errors: [],
                                                startProfileErrors: [],
                                                grayStatusErrors: [],
                                                filesystemErrors: []
                                            };
                                        }
                                        
                                        // Only process if errors were found in this file
                                        if (result.found && result.errors && result.errors.length > 0) {
                                            // Merge found flag
                                            this.analysisResults[ruleName].found = true;
                                            
                                            // Add errors with deduplication (by type, resourceName, message)
                                            result.errors.forEach(err => {
                                                const key = `${err.type}:${err.resourceName}:${err.message}`;
                                                const exists = this.analysisResults[ruleName].errors.some(e => 
                                                    `${e.type}:${e.resourceName}:${e.message}` === key
                                                );
                                                if (!exists) {
                                                    this.analysisResults[ruleName].errors.push({
                                                        ...err,
                                                        sourceFile: filename
                                                    });
                                                }
                                            });
                                            
                                            // Update categorized arrays
                                            this.analysisResults[ruleName].startProfileErrors = this.analysisResults[ruleName].errors.filter(e => e.type === 'start_profile_not_found');
                                            this.analysisResults[ruleName].grayStatusErrors = this.analysisResults[ruleName].errors.filter(e => e.type === 'sap_service_gray_status');
                                            this.analysisResults[ruleName].filesystemErrors = this.analysisResults[ruleName].errors.filter(e => e.type === 'filesystem_unmount_error');
                                            
                                            debugLog(`[TAR Parser] Rule 'sapInstanceErrors' accumulated from ${filename} (errors: ${result.errors.length}, total errors: ${this.analysisResults[ruleName].errors.length})`);
                                        }
                                    } else if (ruleName === 'firewallRules') {
                                        // firewallRules: merge results from multiple files (SOS has many)
                                        if (!this.analysisResults[ruleName]) {
                                            this.analysisResults[ruleName] = result;
                                        } else {
                                            const existing = this.analysisResults[ruleName];
                                            existing.found = existing.found || result.found;
                                            // Merge firewalld
                                            existing.firewalld.detected = existing.firewalld.detected || result.firewalld.detected;
                                            existing.firewalld.running = existing.firewalld.running || result.firewalld.running;
                                            if (result.firewalld.config) existing.firewalld.config = result.firewalld.config;
                                            if (result.firewalld.zones) existing.firewalld.zones = result.firewalld.zones;
                                            if (result.firewalld.directRules) existing.firewalld.directRules = (existing.firewalld.directRules || '') + result.firewalld.directRules;
                                            if (result.firewalld.passthroughs) existing.firewalld.passthroughs = (existing.firewalld.passthroughs || '') + result.firewalld.passthroughs;
                                            if (result.firewalld.chains) existing.firewalld.chains = (existing.firewalld.chains || '') + result.firewalld.chains;
                                            if (result.firewalld.logDenied) existing.firewalld.logDenied = result.firewalld.logDenied;
                                            if (result.firewalld.backend) existing.firewalld.backend = result.firewalld.backend;
                                            // Merge iptables / ip6tables
                                            existing.iptables.detected = existing.iptables.detected || result.iptables.detected;
                                            existing.iptables.rules.push(...result.iptables.rules);
                                            existing.iptables.modules.push(...result.iptables.modules);
                                            existing.ip6tables.detected = existing.ip6tables.detected || result.ip6tables.detected;
                                            existing.ip6tables.rules.push(...result.ip6tables.rules);
                                            existing.ip6tables.modules.push(...result.ip6tables.modules);
                                            // Merge ebtables
                                            existing.ebtables.detected = existing.ebtables.detected || result.ebtables.detected;
                                            if (result.ebtables.config) existing.ebtables.config = result.ebtables.config;
                                            // Merge nftables
                                            existing.nftables.detected = existing.nftables.detected || result.nftables.detected;
                                            if (result.nftables.ruleset) existing.nftables.ruleset = result.nftables.ruleset;
                                            if (result.nftables.tables) existing.nftables.tables = result.nftables.tables;
                                            // Merge warnings and raw sections
                                            existing.warnings.push(...result.warnings.filter(w => {
                                                const key = typeof w === 'string' ? w : JSON.stringify(w);
                                                return !existing.warnings.some(e => (typeof e === 'string' ? e : JSON.stringify(e)) === key);
                                            }));
                                            if (!existing.rawSections) existing.rawSections = {};
                                            if (result.rawSections) Object.assign(existing.rawSections, result.rawSections);
                                            // Re-determine active firewall
                                            existing.activeFirewall = firewallRulesParser.determineActiveFirewall(existing);
                                        }
                                        debugLog(`[TAR Parser] Rule 'firewallRules' accumulated from ${filename} (active: ${this.analysisResults[ruleName].activeFirewall})`);
                                    } else if (ruleName === 'networkInterfaces') {
                                        // networkInterfaces: merge results from multiple files (SOS has many)
                                        if (!this.analysisResults[ruleName]) {
                                            this.analysisResults[ruleName] = result;
                                        } else {
                                            networkInterfacesParser.mergeResults(this.analysisResults[ruleName], result);
                                        }
                                        const ifaceCount = Object.keys(this.analysisResults[ruleName].interfaces || {}).length;
                                        debugLog(`[TAR Parser] Rule 'networkInterfaces' accumulated from ${filename} (interfaces: ${ifaceCount})`);
                                    } else {
                                        // Add sourceFile to new events
                                        const newEventsWithSource = result.events.map(event => ({
                                            ...event,
                                            sourceFile: filename
                                        }));
                                        
                                        // Use utility function for deduplication
                                        const dedupeResult = SCC_RULES.deduplicateEvents(
                                            this.analysisResults[ruleName].events,
                                            newEventsWithSource,
                                            comparisonFields
                                        );
                                        
                                        // Add non-duplicate events
                                        this.analysisResults[ruleName].events.push(...dedupeResult.addedEvents);
                                        this.analysisResults[ruleName].count = this.analysisResults[ruleName].events.length;
                                        
                                        debugLog(`[TAR Parser] Rule '${ruleName}' accumulated ${dedupeResult.addedEvents.length} new events (${dedupeResult.duplicateCount} duplicates skipped, total: ${this.analysisResults[ruleName].count})`);
                                    }
                                } else {
                                    // Merge results without deduplication for other multi-file rules
                                    this.analysisResults[ruleName].count += result.count;
                                    this.analysisResults[ruleName].events.push(...result.events.map(e => ({
                                        ...e,
                                        sourceFile: filename
                                    })));
                                    
                                    debugLog(`[TAR Parser] Rule '${ruleName}' accumulated ${result.count} new events (total: ${this.analysisResults[ruleName].count})`);
                                }
                            } else {
                                // Single file rule - for fencingConfig and pacemakerResources, merge/keep best result
                                if (ruleName === 'fencingConfig') {
                                    // Keep the result with the most information
                                    const existing = this.analysisResults[ruleName];
                                    
                                    // If no existing result, use this one
                                    if (!existing) {
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (first):`, result);
                                    } else {
                                        // Merge: prefer explicit stonithEnabled over null, accumulate devices
                                        const merged = {
                                            found: existing.found || result.found,
                                            stonithEnabled: result.stonithEnabled !== null ? result.stonithEnabled : existing.stonithEnabled,
                                            stonithSourceFile: result.stonithEnabled !== null ? result.stonithSourceFile : existing.stonithSourceFile,
                                            stonithSourcePattern: result.stonithEnabled !== null ? result.stonithSourcePattern : existing.stonithSourcePattern,
                                            fencingDevices: [...existing.fencingDevices],
                                            count: existing.count
                                        };
                                        
                                        // Add new devices that don't already exist
                                        result.fencingDevices.forEach(newDevice => {
                                            if (!merged.fencingDevices.find(d => d.name === newDevice.name)) {
                                                merged.fencingDevices.push(newDevice);
                                                merged.count++;
                                            }
                                        });
                                        
                                        this.analysisResults[ruleName] = merged;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged with existing (${merged.count} devices, stonith: ${merged.stonithEnabled})`);
                                    }
                                } else if (ruleName === 'pacemakerResources') {
                                    // Keep the result with resources, or merge resources
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.found) {
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (first):`, result);
                                    } else if (result.found) {
                                        // Merge resources and enrich with node information
                                        let newResourcesAdded = 0;
                                        let enrichedResources = 0;
                                        
                                        result.resources.forEach(newRes => {
                                            const existingRes = existing.resources.find(r => r.name === newRes.name);
                                            if (existingRes) {
                                                // Enrich existing resource with new data (especially node info from crm_mon)
                                                let wasEnriched = false;
                                                if (newRes.node && !existingRes.node) {
                                                    existingRes.node = newRes.node;
                                                    existingRes.status = newRes.status;
                                                    wasEnriched = true;
                                                }
                                                if (newRes.status && !existingRes.status) {
                                                    existingRes.status = newRes.status;
                                                    wasEnriched = true;
                                                }
                                                if (wasEnriched) {
                                                    enrichedResources++;
                                                    debugLog(`[TAR Parser] Enriched resource '${newRes.name}' with node/status info`);
                                                }
                                            } else {
                                                // Add new resource only if it's truly new
                                                existing.resources.push(newRes);
                                                newResourcesAdded++;
                                                debugLog(`[TAR Parser] Added new resource '${newRes.name}'`);
                                            }
                                        });
                                        existing.count = existing.resources.length;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged: ${newResourcesAdded} new resources added, ${enrichedResources} enriched, ${result.resources.length - newResourcesAdded - enrichedResources} duplicates skipped (${existing.count} total)`);
                                    }
                                } else if (ruleName === 'clusterNodes') {
                                    // Merge and deduplicate cluster nodes from multiple files
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.nodes || existing.nodes.length === 0) {
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (first): ${result.nodes.length} nodes`);
                                    } else {
                                        // Merge node lists and deduplicate
                                        const nodeSet = new Set([...existing.nodes, ...result.nodes]);
                                        // Merge node-to-IP mappings
                                        const mergedMap = {...existing.nodeToIpMap, ...result.nodeToIpMap};
                                        this.analysisResults[ruleName] = {
                                            nodes: Array.from(nodeSet).sort(),
                                            nodeToIpMap: mergedMap
                                        };
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged (${this.analysisResults[ruleName].nodes.length} unique nodes, ${Object.keys(mergedMap).length} mappings)`);
                                    }
                                } else if (ruleName === 'distroPackages') {
                                    // distroPackages: prefer raw format over Azure validation format
                                    const existing = this.analysisResults[ruleName];
                                    
                                    // Priority: raw content (isRpmRaw or isDpkg) > Azure validation (packages/warnings)
                                    const isRawFormat = result.isRpmRaw || result.isDpkg;
                                    const existingIsRaw = existing && (existing.isRpmRaw || existing.isDpkg);
                                    
                                    if (!existing || isRawFormat && !existingIsRaw) {
                                        // No existing result, or this is raw and existing is validation
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (${isRawFormat ? 'raw format' : 'validation format'}):`, result);
                                    } else if (!isRawFormat && existingIsRaw) {
                                        // This is validation but existing is raw - keep existing
                                        debugLog(`[TAR Parser] Rule '${ruleName}' skipping validation format (already have raw format)`);
                                    } else {
                                        // Both same type, use newer
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' replaced with newer result`);
                                    }
                                } else if (ruleName === 'involfltKernelVersion') {
                                    // involfltKernelVersion: preserve positive result (found: true) once found
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.found) {
                                        // No existing result or existing is negative - update if we have a result
                                        if (result) {
                                            this.analysisResults[ruleName] = result;
                                            debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully:`, result);
                                        }
                                    } else {
                                        // Already have a positive result - keep it
                                        debugLog(`[TAR Parser] Rule '${ruleName}' already found, keeping existing result`);
                                    }
                                } else if (ruleName === 'azureScheduledEvents') {
                                    // azureScheduledEvents: merge results from multiple files (pcs_status, crm_mon, cib.xml)
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.found) {
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (first):`, result);
                                    } else if (result.found) {
                                        // Merge results: accumulate nodes, resources, and warnings
                                        // Keep healthAzureConfigured if either found it
                                        existing.healthAzureConfigured = existing.healthAzureConfigured || result.healthAzureConfigured;
                                        
                                        // Keep healthAzureResource if either found it
                                        if (result.healthAzureResource && !existing.healthAzureResource) {
                                            existing.healthAzureResource = result.healthAzureResource;
                                        }
                                        
                                        // Keep nodeHealthStrategy if either found it
                                        if (result.nodeHealthStrategy && !existing.nodeHealthStrategy) {
                                            existing.nodeHealthStrategy = result.nodeHealthStrategy;
                                        }
                                        
                                        // Merge nodesWithHealthAzure (dedupe by node name)
                                        result.nodesWithHealthAzure.forEach(newNode => {
                                            if (!existing.nodesWithHealthAzure.find(n => n.node === newNode.node)) {
                                                existing.nodesWithHealthAzure.push(newNode);
                                            }
                                        });
                                        
                                        // Merge onlineNodes (dedupe)
                                        result.onlineNodes.forEach(node => {
                                            if (!existing.onlineNodes.includes(node)) {
                                                existing.onlineNodes.push(node);
                                            }
                                        });
                                        
                                        // Merge stoppedResources (dedupe)
                                        result.stoppedResources.forEach(res => {
                                            if (!existing.stoppedResources.includes(res)) {
                                                existing.stoppedResources.push(res);
                                            }
                                        });
                                        
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged (onlineNodes: ${existing.onlineNodes.length}, stoppedResources: ${existing.stoppedResources.length})`);
                                    }
                                } else if (ruleName === 'iscsiConfig') {
                                    // iscsiConfig: merge results from multiple files (fs-iscsi.txt, ha.txt)
                                    // Don't overwrite a found result with not-found
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.found) {
                                        // No existing result or existing is not found - use new result
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed (first or replacing not-found):`, result.found);
                                    } else if (result.found) {
                                        // Both found - merge by keeping all sessions and targets
                                        // Merge sessions (dedupe by ip:port:iqn)
                                        result.sessions.forEach(newSession => {
                                            const key = `${newSession.ip}:${newSession.port}:${newSession.iqn}`;
                                            const exists = existing.sessions.find(s => `${s.ip}:${s.port}:${s.iqn}` === key);
                                            if (!exists) {
                                                existing.sessions.push(newSession);
                                            }
                                        });
                                        
                                        // Merge discoveryServers (dedupe by ip:port)
                                        result.discoveryServers.forEach(newServer => {
                                            const key = `${newServer.ip}:${newServer.port}`;
                                            const exists = existing.discoveryServers.find(s => `${s.ip}:${s.port}` === key);
                                            if (!exists) {
                                                existing.discoveryServers.push(newServer);
                                            }
                                        });
                                        
                                        // Merge targets (dedupe by iqn)
                                        result.targets.forEach(newTarget => {
                                            const exists = existing.targets.find(t => t.iqn === newTarget.iqn);
                                            if (!exists) {
                                                existing.targets.push(newTarget);
                                            }
                                        });
                                        
                                        // Keep warnings from both
                                        result.warnings.forEach(w => {
                                            if (!existing.warnings.find(ew => ew.type === w.type && ew.message === w.message)) {
                                                existing.warnings.push(w);
                                            }
                                        });
                                        
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged results (sessions: ${existing.sessions.length})`);
                                    } else {
                                        // New result is not found but existing is - keep existing
                                        debugLog(`[TAR Parser] Rule '${ruleName}' keeping existing found result, ignoring not-found from ${filename}`);
                                    }
                                } else {
                                    // Other single file rules - replace result
                                    this.analysisResults[ruleName] = result;
                                    debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully:`, result);
                                }
                            }
                        } catch (e) {
                            debugLog(`[TAR Parser] Rule '${ruleName}' parse failed:`, e);
                        }
                    }
                }
            }

            // End per-file timing if any parsers matched
            if (pt && fileParserCount > 0) {
                const contentLen = cachedContent ? cachedContent.length : (cachedContentSmall ? cachedContentSmall.length : 0);
                pt.endFile(filename, contentLen, fileParserCount);
            }
        }

    /**
     * Process a pre-extracted file (e.g. from a ZIP archive) through all SCC parsers.
     * This reuses the same parser matching and result accumulation logic as processSCCRules
     * but accepts already-decoded string content instead of reading from the TAR buffer.
     * @param {string} filename - The file path within the archive
     * @param {Uint8Array} contentBytes - Raw file bytes
     */
    processExtractedFile(filename, contentBytes) {
        // Track current file for progress reporting
        this.currentFile = filename;

        const size = contentBytes.length;

        // Detect SCC report
        if (!this.isSCCReport && SCC_RULES.detection.isSCCReport(filename)) {
            this.isSCCReport = true;
            this.sccReportName = filename.split('/')[0];
            debugLog('[ZIP Parser] Detected SCC report:', this.sccReportName);
        }

        // Detect standalone HANA log archive (no SCC wrapper).
        if (!this.isHanaLog && SCC_RULES.detection.isHanaLog(filename)) {
            this.isHanaLog = true;
            debugLog('[ZIP Parser] Detected HANA trace file:', filename);
        }

        // Track directories
        if (filename.includes('/')) {
            const parts = filename.split('/');
            let path = '';
            for (let i = 0; i < parts.length - 1; i++) {
                path += parts[i] + '/';
                this.addDirectory(path);
            }
        }

        // Track file types
        const ext = filename.includes('.') ? filename.split('.').pop().toLowerCase() : 'none';
        this.fileTypes[ext] = (this.fileTypes[ext] || 0) + 1;

        // Store file entry (bounded; counts all, retains first N)
        this.recordFile(filename, size, filename.endsWith('/') ? 53 : 48);

        // Skip directories and empty files
        if (size === 0 || filename.endsWith('/')) return;

        // Only process if this is an SCC/sosreport or a standalone HANA log
        if (!this.isSCCReport && !this.isHanaLog) return;

        // Normalize sos_strings tailed file paths (same logic as processSCCRules)
        let matchFilename = filename;
        const tailedMatch = filename.match(/sos_strings\/[^\/]+\/(.+)\.tailed$/);
        if (tailedMatch) {
            const dottedPath = tailedMatch[1];
            let originalPath;
            const extMatch = dottedPath.match(/^(.+)\.((log|conf|txt|xml)(?:[.-].+)?)$/);
            if (extMatch) {
                const segments = extMatch[1].split('.');
                const fileBase = segments.pop();
                const dirPath = segments.join('/');
                originalPath = dirPath + '/' + fileBase + '.' + extMatch[2];
            } else {
                const segments = dottedPath.split('.');
                const fileName = segments.pop();
                const dirPath = segments.join('/');
                originalPath = dirPath + '/' + fileName;
            }
            const reportPrefix = filename.substring(0, filename.indexOf('sos_strings'));
            matchFilename = reportPrefix + originalPath;
            debugLog('[ZIP Parser] Normalized sos_strings tailed path to:', matchFilename);
        }

        // Compressed log rotation limiter (same logic as processSCCRules)
        if (!this.processedLogFiles) {
            this.processedLogFiles = {};
        }
        const compressedRotationMatch = matchFilename.match(/\/(messages|localmessages|journalctl[^/]*|pacemaker\.log|corosync\.log)([.-]\d+)?(?:\.gz|\.bz2|\.xz)$/);
        if (compressedRotationMatch) {
            const baseFile = compressedRotationMatch[1];
            const rotation = compressedRotationMatch[2] || '.current';
            if (!this.processedLogFiles[baseFile]) this.processedLogFiles[baseFile] = [];
            const needsAllRotations = Object.values(SCC_RULES).some(rule =>
                rule.processAllRotations && rule.filePattern && rule.filePattern.test(matchFilename)
            );
            if (!needsAllRotations && this.processedLogFiles[baseFile].length >= 3) {
                debugLog('[ZIP Parser] Skipping compressed rotated log (limit reached):', matchFilename);
                return;
            }
            this.processedLogFiles[baseFile].push(rotation);
        }

        // Track .gz files
        if (matchFilename.toLowerCase().endsWith('.gz')) {
            this.nestedGzipTotalCount++;
            this.nestedGzipTotalCompressedBytes += size;
        }

        // Decode content - handle nested gzip if applicable
        let content;
        const isGzipped = contentBytes.length >= 2 && contentBytes[0] === 0x1f && contentBytes[1] === 0x8b;
        if (isGzipped && typeof pako !== 'undefined') {
            try {
                const decompressed = pako.ungzip(contentBytes);
                content = new TextDecoder('utf-8').decode(decompressed);
                this.nestedGzipCount++;
                this.nestedGzipCompressedBytes += size;
                this.nestedGzipDecompressedBytes += decompressed.length;
                debugLog('[ZIP Parser] Decompressed nested .gz file:', matchFilename, size, '->', decompressed.length);
            } catch (e) {
                debugLog('[ZIP Parser] Failed to decompress .gz file:', matchFilename, e);
                try { content = new TextDecoder('utf-8').decode(contentBytes); } catch (e2) { return; }
            }
        } else {
            try {
                content = new TextDecoder('utf-8').decode(contentBytes);
            } catch (e) {
                debugLog('[ZIP Parser] Failed to decode file:', matchFilename, e);
                return;
            }
        }

        if (!content) return;

        // Performance tracking
        const perfMode = DEBUG_CONFIG.performance;
        if (perfMode && !this.perfTracker && typeof PerformanceTracker !== 'undefined') {
            this.perfTracker = new PerformanceTracker();
        }
        const pt = this.perfTracker;
        let fileParserCount = 0;
        let cachedLines = null;

        // Run all matching parsers (same accumulation logic as processSCCRules)
        for (const [ruleName, rule] of Object.entries(SCC_RULES)) {
            if (ruleName === 'detection' || !rule.filePattern) continue;
            if (!rule.filePattern.test(matchFilename)) continue;

            debugLog('[ZIP Parser] Matched rule', ruleName, 'for file:', matchFilename);

            if (pt && fileParserCount === 0) pt.startFile();
            fileParserCount++;

            let fileContent = content;
            // Special case: cloudregister.txt truncation
            if (ruleName === 'suseCloudRegister') {
                const maxSize = 100 * 1024;
                if (content.length > maxSize) fileContent = content.substring(0, maxSize);
            }

            if (!cachedLines) cachedLines = content.split('\n');

            const isMultiFileRule = ruleName === 'liveMigration' || ruleName === 'kernelReboots' || ruleName === 'oomKiller' || ruleName === 'xfsErrors' || ruleName === 'emergencyMode' || ruleName === 'sshService' || ruleName === 'automation' || ruleName === 'clusterEvents' || ruleName === 'rhuiErrors' || ruleName === 'blockDevices' || ruleName === 'sapInstanceErrors' || ruleName === 'firewallRules' || ruleName === 'networkInterfaces' || ruleName === 'vmcore' || ruleName === 'azureExtensions' || ruleName === 'lvmConfig' || ruleName === 'kernelTuning' || ruleName === 'nfsMounts' || ruleName === 'hanaSavepoints' || ruleName === 'hanaDeadlocks' || ruleName === 'hanaOom' || ruleName === 'hanaMergeErrors';

            try {
                const parseStart = pt ? performance.now() : 0;
                const result = rule.parse(fileContent, matchFilename, cachedLines);
                if (pt) pt.recordParser(matchFilename, ruleName, performance.now() - parseStart, result, this.analysisResults[ruleName]);

                if (isMultiFileRule) {
                    if (!this.analysisResults[ruleName] && ruleName !== 'rhuiErrors' && ruleName !== 'blockDevices' && ruleName !== 'sapInstanceErrors' && ruleName !== 'firewallRules' && ruleName !== 'networkInterfaces' && ruleName !== 'vmcore' && ruleName !== 'lvmConfig' && ruleName !== 'kernelTuning' && ruleName !== 'nfsMounts' && ruleName !== 'hanaSavepoints' && ruleName !== 'hanaDeadlocks' && ruleName !== 'hanaOom' && ruleName !== 'hanaMergeErrors') {
                        this.analysisResults[ruleName] = { count: 0, events: [] };
                    }

                    if (ruleName === 'kernelTuning') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = { found: false, parameters: {}, warnings: [], hasWarnings: false, azureNetworkWarnings: [], hasAzureNetworkWarnings: false, optionalNetworkInfo: [], hasOptionalNetworkInfo: false };
                        }
                        kernelTuningParser.mergeResults(this.analysisResults[ruleName], result);
                    } else if (ruleName === 'lvmConfig') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = { found: false, pvs: [], vgs: [], lvs: [], warnings: [], rawOutput: {} };
                        }
                        lvmConfigParser.mergeResults(this.analysisResults[ruleName], result);
                    } else if (ruleName === 'nfsMounts') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else {
                            this.analysisResults[ruleName] = nfsMountsParser.mergeResults(this.analysisResults[ruleName], result);
                        }
                        debugLog(`[ZIP Parser] Rule 'nfsMounts' accumulated from ${matchFilename} (mounts: ${(this.analysisResults[ruleName].mounts || []).length})`);
                    } else if (ruleName === 'hanaSavepoints') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else {
                            this.analysisResults[ruleName] = hanaSavepointsParser.mergeResults(this.analysisResults[ruleName], result);
                        }
                        debugLog(`[ZIP Parser] Rule 'hanaSavepoints' accumulated from ${matchFilename} (savepoints: ${(this.analysisResults[ruleName].savepoints || []).length})`);
                    } else if (ruleName === 'hanaDeadlocks') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else {
                            this.analysisResults[ruleName] = hanaDeadlocksParser.mergeResults(this.analysisResults[ruleName], result);
                        }
                        debugLog(`[ZIP Parser] Rule 'hanaDeadlocks' accumulated from ${matchFilename} (deadlocks: ${(this.analysisResults[ruleName].deadlocks || []).length})`);
                    } else if (ruleName === 'hanaOom') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else {
                            this.analysisResults[ruleName] = hanaOomParser.mergeResults(this.analysisResults[ruleName], result);
                        }
                        debugLog(`[ZIP Parser] Rule 'hanaOom' accumulated from ${matchFilename} (events: ${(this.analysisResults[ruleName].events || []).length})`);
                    } else if (ruleName === 'hanaMergeErrors') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else {
                            this.analysisResults[ruleName] = hanaMergeErrorsParser.mergeResults(this.analysisResults[ruleName], result);
                        }
                        debugLog(`[ZIP Parser] Rule 'hanaMergeErrors' accumulated from ${matchFilename} (errors: ${(this.analysisResults[ruleName].errors || []).length})`);
                    } else if (ruleName === 'blockDevices') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else {
                            this.mergeBlockDevicesResult(this.analysisResults[ruleName], result);
                        }
                    } else if (ruleName === 'vmcore') {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = { found: false, crashes: [], kdumpStatus: null, crashListing: null, kdumpConf: null };
                        }
                        vmcoreParser.mergeResults(this.analysisResults[ruleName], result);
                    } else if (ruleName === 'clusterEvents') {
                        if (!this.analysisResults[ruleName].resourceMigrations) this.analysisResults[ruleName].resourceMigrations = [];
                        if (!this.analysisResults[ruleName].fencingEvents) this.analysisResults[ruleName].fencingEvents = [];
                        if (result && result.resourceMigrations) {
                            const dedup = SCC_RULES.deduplicateEvents(this.analysisResults[ruleName].resourceMigrations, result.resourceMigrations, ['timestamp', 'resource', 'action']);
                            this.analysisResults[ruleName].resourceMigrations.push(...dedup.addedEvents);
                        }
                        if (result && result.fencingEvents) {
                            const dedup = SCC_RULES.deduplicateEvents(this.analysisResults[ruleName].fencingEvents, result.fencingEvents, ['timestamp', 'node', 'action']);
                            this.analysisResults[ruleName].fencingEvents.push(...dedup.addedEvents);
                        }
                        this.analysisResults[ruleName].count = (this.analysisResults[ruleName].resourceMigrations?.length || 0) + (this.analysisResults[ruleName].fencingEvents?.length || 0);
                    } else if (ruleName === 'networkInterfaces') {
                        // networkInterfaces: merge interfaces/raw using parser's mergeResults (same as TAR path)
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else {
                            networkInterfacesParser.mergeResults(this.analysisResults[ruleName], result);
                        }
                        debugLog(`[ZIP Parser] Rule 'networkInterfaces' accumulated from ${matchFilename} (interfaces: ${Object.keys(this.analysisResults[ruleName].interfaces || {}).length})`);
                    } else if (ruleName === 'firewallRules') {
                        // firewallRules: merge firewall config using same logic as TAR path
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else {
                            const existing = this.analysisResults[ruleName];
                            existing.found = existing.found || result.found;
                            existing.firewalld.detected = existing.firewalld.detected || result.firewalld.detected;
                            existing.firewalld.running = existing.firewalld.running || result.firewalld.running;
                            if (result.firewalld.config) existing.firewalld.config = result.firewalld.config;
                            if (result.firewalld.zones) existing.firewalld.zones = result.firewalld.zones;
                            if (result.firewalld.directRules) existing.firewalld.directRules = (existing.firewalld.directRules || '') + result.firewalld.directRules;
                            if (result.firewalld.passthroughs) existing.firewalld.passthroughs = (existing.firewalld.passthroughs || '') + result.firewalld.passthroughs;
                            if (result.firewalld.chains) existing.firewalld.chains = (existing.firewalld.chains || '') + result.firewalld.chains;
                            if (result.firewalld.logDenied) existing.firewalld.logDenied = result.firewalld.logDenied;
                            if (result.firewalld.backend) existing.firewalld.backend = result.firewalld.backend;
                            existing.iptables.detected = existing.iptables.detected || result.iptables.detected;
                            existing.iptables.rules.push(...result.iptables.rules);
                            existing.iptables.modules.push(...result.iptables.modules);
                            existing.ip6tables.detected = existing.ip6tables.detected || result.ip6tables.detected;
                            existing.ip6tables.rules.push(...result.ip6tables.rules);
                            existing.ip6tables.modules.push(...result.ip6tables.modules);
                            existing.ebtables.detected = existing.ebtables.detected || result.ebtables.detected;
                            if (result.ebtables.config) existing.ebtables.config = result.ebtables.config;
                            existing.nftables.detected = existing.nftables.detected || result.nftables.detected;
                            if (result.nftables.ruleset) existing.nftables.ruleset = result.nftables.ruleset;
                            if (result.nftables.tables) existing.nftables.tables = result.nftables.tables;
                            existing.warnings.push(...result.warnings.filter(w => {
                                const key = typeof w === 'string' ? w : JSON.stringify(w);
                                return !existing.warnings.some(e => (typeof e === 'string' ? e : JSON.stringify(e)) === key);
                            }));
                            if (!existing.rawSections) existing.rawSections = {};
                            if (result.rawSections) Object.assign(existing.rawSections, result.rawSections);
                            existing.activeFirewall = firewallRulesParser.determineActiveFirewall(existing);
                        }
                        debugLog(`[ZIP Parser] Rule 'firewallRules' accumulated from ${matchFilename} (active: ${this.analysisResults[ruleName].activeFirewall})`);
                    } else if (['rhuiErrors', 'sapInstanceErrors'].includes(ruleName)) {
                        if (!this.analysisResults[ruleName]) {
                            this.analysisResults[ruleName] = result;
                        } else if (result && result.found !== false) {
                            // Merge events/data from result into existing
                            if (result.events && Array.isArray(result.events)) {
                                if (!this.analysisResults[ruleName].events) this.analysisResults[ruleName].events = [];
                                const compFields = ['timestamp', 'message'];
                                const dedup = SCC_RULES.deduplicateEvents(this.analysisResults[ruleName].events, result.events, compFields);
                                this.analysisResults[ruleName].events.push(...dedup.addedEvents);
                            }
                            this.analysisResults[ruleName].found = this.analysisResults[ruleName].found || result.found;
                            this.analysisResults[ruleName].count = this.analysisResults[ruleName].events?.length || 0;
                        }
                    } else {
                        // Standard event accumulation (liveMigration, kernelReboots, oomKiller, etc.)
                        if (result && result.events && Array.isArray(result.events) && result.events.length > 0) {
                            const compFields = ruleName === 'kernelReboots' ? ['timestamp', 'type', 'kernelVersion']
                                : ruleName === 'xfsErrors' ? ['timestamp', 'device', 'message']
                                : ruleName === 'emergencyMode' ? ['timestamp', 'lineNumber']
                                : ruleName === 'sshService' ? ['timestamp', 'issueType', 'message']
                                : ruleName === 'automation' ? ['timestamp', 'toolType', 'command']
                                : ruleName === 'azureExtensions' ? ['name']
                                : ['timestamp', 'message'];
                            const dedup = SCC_RULES.deduplicateEvents(this.analysisResults[ruleName].events, result.events, compFields);
                            this.analysisResults[ruleName].events.push(...dedup.addedEvents);
                            this.analysisResults[ruleName].count = this.analysisResults[ruleName].events.length;
                            if (result.found) this.analysisResults[ruleName].found = true;
                        }
                    }
                } else if (ruleName === 'iscsiConfig') {
                    const existing = this.analysisResults[ruleName];
                    if (!existing || !existing.found) {
                        this.analysisResults[ruleName] = result;
                    } else if (result.found) {
                        result.sessions.forEach(ns => {
                            const key = `${ns.ip}:${ns.port}:${ns.iqn}`;
                            if (!existing.sessions.find(s => `${s.ip}:${s.port}:${s.iqn}` === key)) existing.sessions.push(ns);
                        });
                        result.discoveryServers.forEach(ns => {
                            const key = `${ns.ip}:${ns.port}`;
                            if (!existing.discoveryServers.find(s => `${s.ip}:${s.port}` === key)) existing.discoveryServers.push(ns);
                        });
                        result.targets.forEach(nt => { if (!existing.targets.find(t => t.iqn === nt.iqn)) existing.targets.push(nt); });
                        result.warnings.forEach(w => { if (!existing.warnings.find(ew => ew.type === w.type && ew.message === w.message)) existing.warnings.push(w); });
                    }
                } else {
                    this.analysisResults[ruleName] = result;
                    debugLog('[ZIP Parser] Rule', ruleName, 'parsed successfully');
                }
            } catch (e) {
                debugLog('[ZIP Parser] Rule', ruleName, 'parse failed:', e);
            }
        }

        if (pt && fileParserCount > 0) {
            pt.endFile(matchFilename, content.length, fileParserCount);
        }
    }

    extractFileContent(offset, size, filename) {
        const contentBytes = this.buffer.slice(offset, offset + size);
        
        // Check if content is gzipped (magic bytes: 0x1f 0x8b)
        const isGzipped = contentBytes.length >= 2 && contentBytes[0] === 0x1f && contentBytes[1] === 0x8b;
        
        if (isGzipped) {
            debugLog(`[TAR Parser] Detected gzipped file: ${filename} (${size} bytes)`);
            try {
                debugLog(`[TAR Parser] Decompressing nested .gz file: ${filename} (${size} bytes compressed)`);
                
                // Send progress update for nested decompression
                debugLog(`[TAR Parser] Sending nested decompression progress message for: ${filename}`);
                self.postMessage({
                    progress: true,
                    message: `Decompressing nested file: ${filename.split('/').pop()}`
                });
                
                // Use native browser DecompressionStream if available (modern browsers)
                if (typeof DecompressionStream !== 'undefined') {
                    // DecompressionStream is async, we need to handle it differently
                    // For now, fall back to synchronous pako-style decompression
                    debugLog('[TAR Parser] DecompressionStream API available but async - using alternative method');
                }
                
                // Use pako library for gzip decompression (synchronous)
                // pako.inflate returns Uint8Array
                if (typeof pako !== 'undefined' && pako.inflate) {
                    debugLog(`[TAR Parser] Using pako to decompress ${filename}`);
                    const decompressed = pako.inflate(contentBytes);
                    const decodedText = new TextDecoder('utf-8').decode(decompressed);
                    
                    // Track nested decompression statistics
                    this.nestedGzipCount++;
                    this.nestedGzipCompressedBytes += size;
                    this.nestedGzipDecompressedBytes += decompressed.length;
                    
                    debugLog(`[TAR Parser] Successfully decompressed ${filename}: ${size} → ${decompressed.length} bytes`);
                    return decodedText;
                } else {
                    debugLog('[TAR Parser] pako library not available, cannot decompress .gz file:', filename);
                    debugLog('[TAR Parser] Attempting to decode as-is (will likely fail)');
                    // Fall through to regular decoding
                }
            } catch (e) {
                debugLog('[TAR Parser] Failed to decompress gzipped file:', filename, e);
                debugLog('[TAR Parser] Attempting to decode as-is (will likely fail)');
                // Fall through to regular decoding attempt
            }
        }
        
        try {
            return new TextDecoder('utf-8').decode(contentBytes);
        } catch (e) {
            debugLog('[TAR Parser] Failed to decode file content:', filename, e);
            return null;
        }
    }
    
    mergeAzureVMProperties() {
        const azureVMProps = this.analysisResults.azureVMProperties;
        const suseCloudReg = this.analysisResults.suseCloudRegister;
        
        // If no Azure VM properties found, return null
        if (!azureVMProps) {
            // If we have SUSE cloud registration, create a minimal Azure VM properties object
            if (suseCloudReg && suseCloudReg.found) {
                return {
                    billingModel: suseCloudReg.billingModel,
                    detectionMethod: suseCloudReg.detectionMethod + ' (SUSE only)',
                    registrationServer: suseCloudReg.registrationServer,
                    registrationType: suseCloudReg.registrationType
                };
            }
            return null;
        }
        
        // If no SUSE cloud registration or it didn't find anything, return Azure VM properties as-is
        if (!suseCloudReg || !suseCloudReg.found) {
            return azureVMProps;
        }
        
        // Both sources available - merge intelligently
        const merged = { ...azureVMProps };
        
        // If azureVMProperties doesn't have billing model, use SUSE cloud registration
        if (!merged.billingModel && suseCloudReg.billingModel) {
            merged.billingModel = suseCloudReg.billingModel;
            merged.detectionMethod = suseCloudReg.detectionMethod;
            merged.registrationServer = suseCloudReg.registrationServer;
            merged.registrationType = suseCloudReg.registrationType;
            debugLog('[mergeAzureVMProperties] Using SUSE cloud registration for billing model');
        }
        // If both have billing models, prefer SUSE cloud registration for SUSE VMs
        // (it's more reliable and specific to SUSE)
        else if (merged.billingModel && suseCloudReg.billingModel) {
            // Add SUSE registration as additional information
            merged.suseRegistrationServer = suseCloudReg.registrationServer;
            merged.suseRegistrationType = suseCloudReg.registrationType;
            merged.suseDetectionMethod = suseCloudReg.detectionMethod;
            
            // If they disagree, log a warning and prefer SUSE cloud registration for SUSE systems
            if (merged.billingModel !== suseCloudReg.billingModel) {
                debugLog(`[mergeAzureVMProperties] Billing model mismatch: Azure metadata says ${merged.billingModel}, SUSE registration says ${suseCloudReg.billingModel}`);
                // For SUSE systems, prefer the SUSE cloud registration (it's more accurate)
                if (merged.publisher && merged.publisher.toLowerCase() === 'suse') {
                    merged.billingModel = suseCloudReg.billingModel;
                    merged.detectionMethod = suseCloudReg.detectionMethod + ' (preferred over Azure metadata)';
                    debugLog('[mergeAzureVMProperties] Using SUSE cloud registration for SUSE VM');
                } else {
                    // For non-SUSE, add SUSE data as secondary source
                    merged.alternativeBillingModel = suseCloudReg.billingModel;
                    merged.alternativeDetectionMethod = suseCloudReg.detectionMethod;
                }
            } else {
                debugLog('[mergeAzureVMProperties] Both sources agree on billing model:', merged.billingModel);
            }
        }
        
        return merged;
    }

    /**
     * Merge results from blockDevices parser (multi-file parser)
     * Accumulates disk, partition, and UUID data across multiple files
     */
    mergeBlockDevicesResult(existing, newResult) {
        // Merge found flag
        existing.found = existing.found || newResult.found;
        
        // Merge arrays (disks, partitions, warnings) avoiding duplicates
        for (const key of ['disks', 'partitions', 'warnings']) {
            if (Array.isArray(newResult[key])) {
                if (!existing[key]) existing[key] = [];
                for (const item of newResult[key]) {
                    // Avoid duplicates by checking for unique identifier
                    const isDupe = existing[key].some(e => 
                        (e.name && e.name === item.name) || 
                        (e.device && e.device === item.device)
                    );
                    if (!isDupe) {
                        existing[key].push(item);
                    }
                }
            }
        }
        
        // Merge maps (uuidMap, deviceMap, mountPoints)
        for (const key of ['uuidMap', 'deviceMap', 'mountPoints']) {
            if (newResult[key] && typeof newResult[key] === 'object') {
                if (!existing[key]) existing[key] = {};
                Object.assign(existing[key], newResult[key]);
            }
        }
        
        // Merge raw output
        if (newResult.rawOutput && typeof newResult.rawOutput === 'object') {
            if (!existing.rawOutput) existing.rawOutput = {};
            Object.assign(existing.rawOutput, newResult.rawOutput);
        }
    }

    /**
     * Compare mtab entries with fstab to find mounts not defined in fstab.
     * These are typically hand-mounted filesystems or cluster-managed resources.
     * Returns the mtab analysis enriched with extraMounts data.
     */
    compareMtabWithFstab() {
        const mtab = this.analysisResults.mtabAnalysis;
        if (!mtab?.found) {
            debugLog('[Storage] No mtab data available for comparison');
            return mtab || null;
        }

        const fstab = this.analysisResults.fstabAnalysis;

        // Build a set of fstab mountpoints for fast lookup
        const fstabMountpoints = new Set();
        if (fstab?.found && fstab.entries) {
            for (const entry of fstab.entries) {
                fstabMountpoints.add(entry.mountpoint);
            }
        }

        // Count real vs virtual mounts and build type breakdown
        let realMounts = 0;
        let virtualMounts = 0;
        const typeBreakdown = {};
        for (const entry of mtab.entries) {
            if (entry.isVirtualFs) {
                virtualMounts++;
            } else {
                realMounts++;
            }
            typeBreakdown[entry.fstype] = (typeBreakdown[entry.fstype] || 0) + 1;
        }

        // Find mounts in mtab that are NOT in fstab (excluding virtual filesystems)
        const extraMounts = [];
        for (const entry of mtab.entries) {
            if (entry.isVirtualFs) continue;
            if (!fstabMountpoints.has(entry.mountpoint)) {
                extraMounts.push({
                    source: entry.source,
                    mountpoint: entry.mountpoint,
                    fstype: entry.fstype,
                    options: entry.options,
                    sourceType: entry.sourceType,
                    reason: 'Not found in /etc/fstab - possibly hand-mounted or cluster-managed'
                });
            }
        }

        // Collect autofs entries separately for visibility
        const autofsMounts = mtab.entries.filter(e => e.fstype === 'autofs');

        debugLog('[Storage] mtab vs fstab: found', extraMounts.length, 'extra mounts,', realMounts, 'real,', virtualMounts, 'virtual,', autofsMounts.length, 'autofs');

        return {
            found: mtab.found,
            entries: mtab.entries,
            realMounts: realMounts,
            virtualMounts: virtualMounts,
            typeBreakdown: typeBreakdown,
            extraMounts: extraMounts,
            autofsMounts: autofsMounts,
            rawContent: mtab.rawContent
        };
    }

    /**
     * Correlate fstab entries with block device information
     * Detects UUID mismatches, missing UUIDs, and filesystem type mismatches
     */
    correlateFstabWithBlockDevices() {
        const fstab = this.analysisResults.fstabAnalysis;
        const blockDevices = this.analysisResults.blockDevices;
        
        if (!fstab?.found || !blockDevices?.found) {
            debugLog('[Storage] Cannot correlate: fstab or blockDevices not found');
            return null;
        }
        
        // Create a storage correlation result
        const correlation = {
            found: true,
            mountedVolumes: [],
            warnings: [],
            errors: []
        };
        
        for (const entry of (fstab.entries || [])) {
            const mountInfo = {
                mountpoint: entry.mountpoint,
                source: entry.source,
                fstabFstype: entry.fstype,
                actualDevice: null,
                actualUuid: null,
                actualFstype: null,
                status: 'unknown',
                issues: []
            };
            
            if (entry.sourceType === 'uuid' && entry.uuid) {
                // Look up UUID in block devices
                const device = blockDevices.uuidMap?.[entry.uuid] || 
                              blockDevices.uuidMap?.[entry.uuid.toLowerCase()] ||
                              blockDevices.uuidMap?.[entry.uuid.toUpperCase()];
                
                if (device) {
                    const deviceInfo = blockDevices.deviceMap?.[device];
                    mountInfo.actualDevice = device;
                    mountInfo.actualUuid = deviceInfo?.uuid;
                    mountInfo.actualFstype = deviceInfo?.fstype;
                    mountInfo.status = 'found';
                    
                    // Check for filesystem type mismatch
                    if (entry.fstype !== 'auto' && deviceInfo?.fstype && 
                        entry.fstype.toLowerCase() !== deviceInfo.fstype.toLowerCase()) {
                        mountInfo.status = 'warning';
                        mountInfo.issues.push({
                            type: 'fstype_mismatch',
                            message: `Filesystem type mismatch: fstab expects '${entry.fstype}' but device has '${deviceInfo.fstype}'`,
                            severity: 'warning'
                        });
                        correlation.warnings.push({
                            mountpoint: entry.mountpoint,
                            message: `Filesystem type mismatch for ${entry.mountpoint}: fstab='${entry.fstype}', actual='${deviceInfo.fstype}'`
                        });
                    }
                } else {
                    // UUID not found - this is a problem
                    mountInfo.status = 'error';
                    mountInfo.issues.push({
                        type: 'uuid_not_found',
                        message: `UUID '${entry.uuid}' referenced in fstab not found on any block device`,
                        severity: 'error'
                    });
                    correlation.errors.push({
                        mountpoint: entry.mountpoint,
                        uuid: entry.uuid,
                        message: `UUID ${entry.uuid} for ${entry.mountpoint} not found on any device. The disk may have been replaced or reformatted.`
                    });
                }
            } else if (entry.sourceType === 'device' && entry.device) {
                // Direct device reference
                const deviceInfo = blockDevices.deviceMap?.[entry.device];
                if (deviceInfo) {
                    mountInfo.actualDevice = entry.device;
                    mountInfo.actualUuid = deviceInfo.uuid;
                    mountInfo.actualFstype = deviceInfo.fstype;
                    mountInfo.status = 'found';
                } else {
                    // Might be a symlink path
                    mountInfo.status = 'symlink';
                }
            }
            
            correlation.mountedVolumes.push(mountInfo);
        }
        
        // Add summary
        correlation.summary = {
            totalEntries: fstab.entries?.length || 0,
            foundDevices: correlation.mountedVolumes.filter(m => m.status === 'found').length,
            warnings: correlation.warnings.length,
            errors: correlation.errors.length
        };
        
        debugLog('[Storage] Correlation complete:', correlation.summary);
        return correlation;
    }

    getAnalysis() {
        // Full analysis mode (always enabled)
        // Get raw cluster nodes (may be IPs or hostnames)
        const clusterNodesData = this.analysisResults.clusterNodes || { nodes: [], nodeToIpMap: {} };
        let clusterNodes = clusterNodesData.nodes || [];
        const nodeToIpMap = clusterNodesData.nodeToIpMap || {};
        const hostsData = this.analysisResults.hostsFile || null;
        const liveMigrationData = this.analysisResults.liveMigration || null;
        const kernelRebootsData = this.analysisResults.kernelReboots || null;
        const oomKillerData = this.analysisResults.oomKiller || null;
        const xfsErrorsData = this.analysisResults.xfsErrors || null;
        const corosyncData = this.analysisResults.corosyncConfig || null;
        const distroPackagesData = this.analysisResults.distroPackages || null;
        const pacemakerResourcesData = this.analysisResults.pacemakerResources || null;
        const fencingConfigData = this.analysisResults.fencingConfig || null;
        const clusterEventsData = this.analysisResults.clusterEvents || null;
        
        if (clusterEventsData && clusterEventsData.count > 0) {
            debugLog('[Analysis] Cluster Events:', clusterEventsData.count, 'total -', (clusterEventsData.resourceMigrations || []).length, 'resource events,', (clusterEventsData.fencingEvents || []).length, 'fencing events');
        }
        
        // Get OS information to filter distribution-specific checks
        const osReleaseData = this.analysisResults.osRelease || this.analysisResults.sysinfo || this.analysisResults.basicEnvironment || null;
        const isSUSE = osReleaseData && osReleaseData.name && 
                      (osReleaseData.name.toLowerCase().includes('suse') || 
                       (osReleaseData.prettyName && osReleaseData.prettyName.toLowerCase().includes('suse')));
        const isRHEL = osReleaseData && osReleaseData.name &&
                      (osReleaseData.name.toLowerCase().includes('red hat') ||
                       osReleaseData.name.toLowerCase().includes('rhel') ||
                       (osReleaseData.prettyName && (osReleaseData.prettyName.toLowerCase().includes('red hat') || osReleaseData.prettyName.toLowerCase().includes('rhel'))));
        const distroFamily = isSUSE ? 'sles' : (isRHEL ? 'rhel' : 'unknown');
        
        // Add distro family to corosync data for distro-aware rendering
        if (corosyncData) {
            corosyncData.distroFamily = distroFamily;
        }
        
        // Filter corosync warnings based on distro family
        if (corosyncData && corosyncData.warnings) {
            if (isRHEL) {
                // RHEL guide recommends the same totem values as SUSE, except transport should be 'knet' instead of 'udpu'
                // Reference: https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker
                
                // Remove the SUSE-specific transport warning (which expects 'udpu')
                corosyncData.warnings = corosyncData.warnings.filter(warning => 
                    warning.parameter !== 'totem.transport'
                );
                
                // Add RHEL-specific transport check: should be 'knet' for RHEL 8+
                if (corosyncData.totemTransport !== null && corosyncData.totemTransport !== 'knet') {
                    corosyncData.warnings.push({
                        parameter: 'totem.transport',
                        expected: 'knet',
                        actual: corosyncData.totemTransport,
                        severity: 'warning',
                        message: `Totem transport value is '${corosyncData.totemTransport}', but should be 'knet' for RHEL 8+ Azure environments`,
                        documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker'
                    });
                }
                
                // Update documentation URLs to RHEL guide for remaining warnings
                corosyncData.warnings.forEach(warning => {
                    warning.documentationUrl = 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker';
                });
                
                debugLog('[TAR Parser] Applied RHEL-specific corosync validation (transport: knet)');
            } else if (!isSUSE) {
                // For unknown distros, only remove transport warning
                corosyncData.warnings = corosyncData.warnings.filter(warning => 
                    warning.parameter !== 'totem.transport'
                );
                debugLog('[TAR Parser] Filtered totem.transport warning for non-SUSE distribution');
            }
        }
        
        // Antivirus detection results
        const falconSensorData = this.analysisResults.falconSensor || { found: false };
        const falconConfigData = this.analysisResults.falconSensorConfig || { found: false };
        const msDefenderData = this.analysisResults.msDefender || { found: false };
        const msDefenderConfigData = this.analysisResults.msDefenderConfig || { found: false };
        const illumioData = this.analysisResults.illumio || { found: false };
        const trendMicroData = this.analysisResults.trendMicro || { found: false };
        const azureSiteRecoveryData = this.analysisResults.azureSiteRecovery || { found: false };
        const guardicoreAgentData = this.analysisResults.guardicoreAgent || { found: false };
        const puppetAgentData = this.analysisResults.puppetAgent || { found: false };
        const chefClientData = this.analysisResults.chefClient || { found: false };
        
        // Combine antivirus and Azure services results
        const antivirusResults = {
            falconSensor: {
                detected: falconSensorData.found,
                version: falconSensorData.version,
                runningProcess: falconSensorData.runningProcess,
                sapExceptions: falconConfigData.hasExclusions || false,
                exclusionPaths: falconConfigData.exclusions || [],
                message: falconSensorData.message
            },
            msDefender: {
                detected: msDefenderData.found,
                version: msDefenderData.version,
                runningProcess: msDefenderData.runningProcess,
                sapExceptions: msDefenderConfigData.hasExclusions || false,
                exclusionPaths: msDefenderConfigData.exclusions || [],
                message: msDefenderData.message
            },
            illumio: {
                detected: illumioData.found,
                message: illumioData.message
            },
            trendMicro: {
                detected: trendMicroData.found,
                message: trendMicroData.message
            },
            guardicoreAgent: {
                detected: guardicoreAgentData.found,
                enabled: guardicoreAgentData.enabled || false,
                severity: guardicoreAgentData.severity,
                message: guardicoreAgentData.message,
                detectionFile: guardicoreAgentData.detectionFile,
                detectionLine: guardicoreAgentData.detectionLine,
                detectionContent: guardicoreAgentData.detectionContent
            },
            puppetAgent: {
                detected: puppetAgentData.found,
                enabled: puppetAgentData.enabled || false,
                severity: puppetAgentData.severity,
                message: puppetAgentData.message,
                detectionFile: puppetAgentData.detectionFile,
                detectionLine: puppetAgentData.detectionLine,
                detectionContent: puppetAgentData.detectionContent
            },
            chefClient: {
                detected: chefClientData.found,
                enabled: chefClientData.enabled || false,
                severity: chefClientData.severity,
                message: chefClientData.message,
                detectionFile: chefClientData.detectionFile,
                detectionLine: chefClientData.detectionLine,
                detectionContent: chefClientData.detectionContent
            },
            azureSiteRecovery: {
                detected: azureSiteRecoveryData.found,
                enabled: azureSiteRecoveryData.enabled || false,
                severity: azureSiteRecoveryData.severity,
                message: azureSiteRecoveryData.message,
                detectionFile: azureSiteRecoveryData.detectionFile,
                detectionLine: azureSiteRecoveryData.detectionLine,
                detectionContent: azureSiteRecoveryData.detectionContent
            },
            // Overall status
            anyDetected: falconSensorData.found || msDefenderData.found || illumioData.found || trendMicroData.found || azureSiteRecoveryData.found || guardicoreAgentData.found || puppetAgentData.found || chefClientData.found,
            allHaveExceptions: (falconSensorData.found ? (falconConfigData.hasExclusions || false) : true) && 
                              (msDefenderData.found ? (msDefenderConfigData.hasExclusions || false) : true)
        };
        
        // Cluster services results (separate from antivirus and Azure services)
        const dlmServiceData = this.analysisResults.dlmService || { found: false };
        const clusterServicesResults = {
            dlmService: {
                detected: dlmServiceData.found,
                enabled: dlmServiceData.enabled || false,
                severity: dlmServiceData.severity,
                message: dlmServiceData.message,
                documentationUrl: dlmServiceData.documentationUrl,
                detectionFile: dlmServiceData.detectionFile,
                detectionLine: dlmServiceData.detectionLine,
                detectionContent: dlmServiceData.detectionContent
            }
        };
        
        debugLog('[TAR Parser] getAnalysis() called');
        debugLog('[TAR Parser] analysisResults:', this.analysisResults);
        
        // Resolve cluster nodes using multiple strategies:
        // 1. If we have nodeToIpMap (from corosync.conf), use it to resolve IPs back to hostnames
        // 2. Then use hosts file to resolve any remaining IPs to hostnames
        // 3. Remove duplicates (IPs that have corresponding hostnames in the same list)
        if (clusterNodes.length > 0) {
            const resolvedNodes = [];
            const ipToHostnameMap = {}; // Reverse mapping: IP -> hostname
            
            // Build reverse map from nodeToIpMap
            for (const [hostname, ip] of Object.entries(nodeToIpMap)) {
                ipToHostnameMap[ip] = hostname;
            }
            
            clusterNodes.forEach(node => {
                // Check if it's an IP address
                if (node.match(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) {
                    // First, check if we have a hostname mapping from corosync.conf
                    if (ipToHostnameMap[node]) {
                        const hostname = ipToHostnameMap[node];
                        resolvedNodes.push(hostname);
                    }
                    // If not, try to resolve using hosts file
                    else if (hostsData) {
                        const hostEntry = hostsData.entries.find(entry => entry.ip === node);
                        if (hostEntry && hostEntry.hostnames.length > 0) {
                            // Use the first hostname
                            const hostname = hostEntry.hostnames[0];
                            resolvedNodes.push(hostname);
                        } else {
                            // Keep the IP if we can't resolve it
                            resolvedNodes.push(node);
                        }
                    } else {
                        resolvedNodes.push(node);
                    }
                } else {
                    // It's a hostname - check if we have an IP mapping for validation
                    resolvedNodes.push(node);
                }
            });
            
            // Deduplicate resolved nodes (in case same hostname was added multiple times)
            clusterNodes = Array.from(new Set(resolvedNodes)).sort();
        }
        
        let nodesInHosts = [];
        let nodesMissingFromHosts = [];
        
        if (hostsData && clusterNodes.length > 0) {
            const hostsSet = new Set(hostsData.allHostnames);
            const hostsIpSet = new Set(hostsData.entries.map(e => e.ip));
            
            clusterNodes.forEach(node => {
                let foundInHosts = false;
                
                // Check if the node (hostname) is directly in hosts file
                if (hostsSet.has(node)) {
                    foundInHosts = true;
                    debugLog(`[TAR Parser] Node ${node} found directly in hosts file`);
                }
                // Check if we have an IP mapping for this hostname and that IP is in hosts file
                else if (nodeToIpMap[node] && hostsIpSet.has(nodeToIpMap[node])) {
                    foundInHosts = true;
                    debugLog(`[TAR Parser] Node ${node} found in hosts file via IP ${nodeToIpMap[node]}`);
                }
                
                if (foundInHosts) {
                    nodesInHosts.push(node);
                } else {
                    nodesMissingFromHosts.push(node);
                }
            });
            
            debugLog('[TAR Parser] Nodes found in hosts file:', nodesInHosts);
            debugLog('[TAR Parser] Nodes missing from hosts file:', nodesMissingFromHosts);
        }
        
        const analysisData = {
            fileCount: this.totalFileCount || this.files.length,
            directories: Array.from(this.directories).sort(),
            fileTypes: this.fileTypes,
            files: this.files.slice(0, 50), // Return first 50 files
            totalParsed: this.totalParsed,
            // Nested compression statistics
            nestedGzipTotalCount: this.nestedGzipTotalCount,
            nestedGzipTotalCompressedBytes: this.nestedGzipTotalCompressedBytes,
            nestedGzipCount: this.nestedGzipCount,
            nestedGzipCompressedBytes: this.nestedGzipCompressedBytes,
            nestedGzipDecompressedBytes: this.nestedGzipDecompressedBytes,
            // SCC report information
            isSCCReport: this.isSCCReport,
            sccReportName: this.sccReportName,
            // Rule-based analysis results
            azureVMProperties: this.mergeAzureVMProperties(),
            osRelease: this.analysisResults.osRelease || this.analysisResults.sysinfo || this.analysisResults.basicEnvironment || null,
            clusterNodes: clusterNodes,
            nodeToIpMap: nodeToIpMap,
            hostsFile: hostsData,
            liveMigration: liveMigrationData,
            kernelReboots: kernelRebootsData,
            oomKiller: oomKillerData,
            xfsErrors: xfsErrorsData,
            corosyncConfig: corosyncData,
            corosyncStatus: this.analysisResults.corosyncStatus || null,
            clusterStatus: this.analysisResults.clusterStatus || null,
            clusterDaemonStatus: this.analysisResults.clusterDaemonStatus || null,
            azureScheduledEvents: this.analysisResults.azureScheduledEvents || null,
            distroPackages: distroPackagesData,
            pacemakerResources: pacemakerResourcesData,
            fencingConfig: fencingConfigData,
            clusterEvents: clusterEventsData,
            antivirus: antivirusResults,
            clusterServices: clusterServicesResults,
            kernelTuning: this.analysisResults.kernelTuning || null,
            hugePages: this.analysisResults.hugePages || null,
            timeSync: this.analysisResults.timeSync || null,
            ptpClockSource: this.analysisResults.ptpClockSource || null,
            timeSyncService: this.analysisResults.timeSyncService || null,
            timedatectl: this.analysisResults.timedatectl || null,
            ptpDevice: this.analysisResults.ptpDevice || null,
            chronyTracking: this.analysisResults.chronyTracking || null,
            chronyMakestep: this.analysisResults.chronyMakestep || null,
            lvmConfig: this.analysisResults.lvmConfig || null,
            raidConfig: this.analysisResults.raidConfig || null,
            btrfsConfig: this.analysisResults.btrfsConfig || null,
            fstab: this.analysisResults.fstab || null,
            blockDevices: this.analysisResults.blockDevices || null,
            fstabAnalysis: this.analysisResults.fstabAnalysis || null,
            inspectDiskResults: this.analysisResults.inspectDiskResults || null,
            dfOutput: this.analysisResults.dfOutput || null,
            mtabAnalysis: this.compareMtabWithFstab(),
            storageCorrelation: this.correlateFstabWithBlockDevices(),
            nvmeList: this.analysisResults.nvmeList || null,
            nfsMounts: this.analysisResults.nfsMounts || null,
            hanaSavepoints: this.analysisResults.hanaSavepoints || null,
            hanaDeadlocks: this.analysisResults.hanaDeadlocks || null,
            hanaOom: this.analysisResults.hanaOom || null,
            hanaMergeErrors: this.analysisResults.hanaMergeErrors || null,
            involfltVersion: this.analysisResults.involfltVersion || null,
            involfltKernelVersion: this.analysisResults.involfltKernelVersion || null,
            azureExtensions: this.analysisResults.azureExtensions || null,
            emergencyMode: this.analysisResults.emergencyMode || null,
            sshService: this.analysisResults.sshService || null,
            automation: this.analysisResults.automation || null,
            rhuiConfig: this.analysisResults.rhuiConfig || null,
            eusVersionLock: this.analysisResults.eusVersionLock || null,
            rhelRhuiCheck: this.analysisResults.rhelRhuiCheck || null,
            cryptoPolicies: this.analysisResults.cryptoPolicies || null,
            fipsModeSetup: this.analysisResults.fipsModeSetup || null,
            tunedProfile: this.analysisResults.tunedProfile || null,
            selinux: this.analysisResults.selinux || null,
            swapSpace: this.analysisResults.swapSpace || null,
            fstrim: this.analysisResults.fstrim || null,
            kernelCmdline: this.analysisResults.kernelCmdline || null,
            rhuiErrors: this.analysisResults.rhuiErrors || null,
            leappReport: this.analysisResults.leappReport || null,
            leappLog: this.analysisResults.leappLog || null,
            sapInstanceConfig: this.analysisResults.sapInstanceConfig || null,
            sapInstanceErrors: this.analysisResults.sapInstanceErrors || null,
            clusterMaintenanceMode: this.analysisResults.clusterMaintenanceMode || null,
            sbdConfig: this.analysisResults.sbdConfig || null,
            azureFenceAuth: this.analysisResults.azureFenceAuth || null,
            iscsiConfig: this.analysisResults.iscsiConfig || null,
            firewallRules: this.analysisResults.firewallRules || null,
            networkInterfaces: this.analysisResults.networkInterfaces || null,
            packetLoss: this.analysisResults.packetLoss || null,
            ringBuffer: this.analysisResults.ringBuffer || null,
            networkSysctl: this.analysisResults.networkSysctl || null,
            vmcore: this.analysisResults.vmcore || null,
            waagentConfig: this.analysisResults.waagentConfig || null,
            waagentLog: this.analysisResults.waagentLog || null,
            secureBoot: this.analysisResults.secureBoot || null,
            hvBalloon: this.analysisResults.hvBalloon || null,
            extfrag: this.analysisResults.extfrag || null,
            usedPaxFormat: this.usedPaxFormat || false,  // Flag if PAX format was detected
            // Cross-validation results
            nodesInHosts: nodesInHosts,
            nodesMissingFromHosts: nodesMissingFromHosts
        };
        
        // Enrich huge pages data with sysctl parameters from kernelTuning if available
        // This avoids duplicate parsing of sysctl output
        if (analysisData.hugePages && analysisData.kernelTuning && analysisData.kernelTuning.parameters) {
            const params = analysisData.kernelTuning.parameters;
            const hp = analysisData.hugePages;
            // Extract huge pages sysctl parameters from already-parsed kernel tuning data
            if (params['vm.nr_hugepages'] !== undefined && hp.sysctlParams.nr_hugepages === undefined) {
                hp.sysctlParams.nr_hugepages = parseInt(params['vm.nr_hugepages'], 10);
                hp.found = true;
            }
            if (params['vm.nr_overcommit_hugepages'] !== undefined && hp.sysctlParams.nr_overcommit_hugepages === undefined) {
                hp.sysctlParams.nr_overcommit_hugepages = parseInt(params['vm.nr_overcommit_hugepages'], 10);
                hp.found = true;
            }
            if (params['vm.hugetlb_shm_group'] !== undefined && hp.sysctlParams.hugetlb_shm_group === undefined) {
                hp.sysctlParams.hugetlb_shm_group = parseInt(params['vm.hugetlb_shm_group'], 10);
                hp.found = true;
            }
        }
        // Add SAP HANA huge pages recommendation if huge pages are not configured
        if (analysisData.hugePages && analysisData.hugePages.found) {
            const hp = analysisData.hugePages;
            // Check if static huge pages are configured (from sysctl or meminfo)
            const nrHugepages = hp.sysctlParams.nr_hugepages !== undefined ? hp.sysctlParams.nr_hugepages : 
                               (hp.staticHugePages.total !== undefined ? hp.staticHugePages.total : 0);
            // For SAP HANA workloads, check if huge pages are configured
            if (nrHugepages === 0 && !hp.recommendations.some(r => r.type === 'sap_hugepages')) {
                hp.recommendations.push({
                    type: 'sap_hugepages',
                    message: 'No static huge pages configured. For SAP HANA workloads, huge pages should be configured to improve performance and prevent memory fragmentation.',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/dbms-guide-general#linux-kernel-settings'
                });
                hp.hasRecommendations = true;
            }
        }
        
        // Post-processing: Regenerate azureScheduledEvents warnings after merging data from multiple files
        if (analysisData.azureScheduledEvents && analysisData.azureScheduledEvents.found) {
            const ase = analysisData.azureScheduledEvents;
            // Clear existing warnings and regenerate based on merged data
            ase.warnings = [];
            
            // Case 1: Resources are stopped while nodes are online AND health-azure is not configured
            if (ase.stoppedResources.length > 0 && ase.onlineNodes.length > 0) {
                if (!ase.healthAzureConfigured && !ase.healthAzureResource) {
                    ase.warnings.push({
                        severity: 'error',
                        type: 'health_azure_not_configured',
                        message: `${ase.stoppedResources.length} cluster resource(s) are stopped while ${ase.onlineNodes.length} node(s) are online. Azure Scheduled Events (health-azure) is NOT configured.`,
                        recommendation: 'Configure Azure Scheduled Events by creating the health-azure-events resource and setting #health-azure attribute on all nodes. See: https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker#configure-pacemaker-for-azure-scheduled-events',
                        stoppedResources: ase.stoppedResources,
                        onlineNodes: ase.onlineNodes
                    });
                }
                
                // Case 2: node-health-strategy is set to custom but health-azure attribute is missing
                if (ase.nodeHealthStrategy === 'custom' && !ase.healthAzureConfigured) {
                    ase.warnings.push({
                        severity: 'error',
                        type: 'health_azure_attribute_missing',
                        message: 'node-health-strategy is set to "custom" but #health-azure attribute is not configured on nodes. Resources cannot be scheduled.',
                        recommendation: 'Initialize the #health-azure attribute on all nodes: sudo crm_attribute --node <node-name> --name \'#health-azure\' --update 0',
                        onlineNodes: ase.onlineNodes
                    });
                }
            }
            
            // Case 3: Some nodes have health-azure configured but not all
            if (ase.nodesWithHealthAzure && ase.nodesWithHealthAzure.length > 0 && ase.onlineNodes.length > ase.nodesWithHealthAzure.length) {
                const nodesWithAttr = ase.nodesWithHealthAzure.map(n => n.node);
                const nodesMissing = ase.onlineNodes.filter(n => !nodesWithAttr.includes(n));
                if (nodesMissing.length > 0) {
                    ase.nodesWithoutHealthAzure = nodesMissing;
                    ase.warnings.push({
                        severity: 'warning',
                        type: 'health_azure_partial',
                        message: `#health-azure attribute is configured on some nodes but missing on: ${nodesMissing.join(', ')}`,
                        recommendation: 'Set the #health-azure attribute on all cluster nodes for consistent behavior.',
                        nodesMissing: nodesMissing
                    });
                }
            }
            
            debugLog('[TAR Parser] azureScheduledEvents post-processing: warnings regenerated:', ase.warnings.length);
        }
        
        return analysisData;
    }

    finish() {
        // Parse any remaining complete entries
        this.parseAvailableEntries();

        // End-of-stream end-marker detection.
        //
        // The strict isEndMarker() requires 1024 contiguous zero bytes in the
        // buffer. Once the underlying decompressor stops feeding chunks we may
        // legitimately have <1024 bytes left (the trailing zero block(s) of the
        // archive plus any padding). At that point we know no more data is
        // coming, so any remaining zero-only tail of >= 512 bytes can safely be
        // treated as the TAR end marker.
        if (!this.foundEndMarker) {
            // Drain any still-pending chunks into the buffer for inspection.
            if (this.pendingLength > 0) {
                this.flushPendingChunks();
            }
            const tailLen = this.buffer.length - this.offset;
            if (tailLen >= 512) {
                let allZero = true;
                for (let i = this.offset; i < this.buffer.length; i++) {
                    if (this.buffer[i] !== 0) { allZero = false; break; }
                }
                if (allZero) {
                    this.foundEndMarker = true;
                    debugLog(`[TAR Parser] Treating ${tailLen}-byte zero tail as end marker`);
                }
            } else if (tailLen === 0 && this.pendingSkip === 0 && this.totalParsed > 0) {
                // Stream ended cleanly on an entry boundary with nothing left
                // over: the archive's last entry padding effectively *is* the
                // end marker for our purposes.
                this.foundEndMarker = true;
                debugLog('[TAR Parser] Stream ended on clean entry boundary; treating as end marker');
            }
        }

        const analysis = this.getAnalysis();

        // Output performance report once at the end
        if (this.perfTracker && DEBUG_CONFIG.performance) {
            const report = this.perfTracker.getReport();
            // Get memory info if available (Chrome/Edge only)
            let memoryMB = null;
            if (typeof performance !== 'undefined' && performance.memory) {
                memoryMB = performance.memory.usedJSHeapSize / (1024 * 1024);
            }
            const text = formatPerformanceReport(report, memoryMB);
            console.log(text);
        }

        return analysis;
    }
}

// Handle messages from main thread
self.onmessage = async function(e) {
    // Handle debug mode setting
    if (e.data.command === 'set_debug') {
        const mode = e.data.enabled;
        // First disable all debug flags
        Object.keys(DEBUG_CONFIG).forEach(key => DEBUG_CONFIG[key] = false);
        
        if (mode === true || mode === 'on' || mode === 'all') {
            // Enable all debug flags
            Object.keys(DEBUG_CONFIG).forEach(key => DEBUG_CONFIG[key] = true);
            console.log('[Worker] All debug modes enabled');
        } else if (mode && mode !== 'off' && mode !== false) {
            // Accept comma-separated parser names: ?debug=cluster,worker
            const names = String(mode).split(',').map(s => s.trim().toLowerCase());
            names.forEach(name => {
                if (name in DEBUG_CONFIG) {
                    DEBUG_CONFIG[name] = true;
                }
            });
            // Always enable worker debug when any parser debug is on
            if (names.some(n => n !== 'worker' && DEBUG_CONFIG[n])) {
                DEBUG_CONFIG.worker = true;
            }
            console.log('[Worker] Debug enabled for:', names.filter(n => DEBUG_CONFIG[n]).join(', '));
        }
        return;
    }
    
    // Handle plain text console log analysis (no TAR, no compression)
    if (e.data.cmd === 'analyze_plaintext') {
        debugLog('[Worker] Received analyze_plaintext command');
        try {
            const { textData, filename } = e.data;
            debugLog(`[Worker] Starting plain text analysis: ${filename}, ${textData.byteLength} bytes`);
            
            // Convert to text
            debugLog('[Worker] Converting to text...');
            const decoder = new TextDecoder('utf-8');
            const textContent = decoder.decode(new Uint8Array(textData));
            debugLog('[Worker] Text decoded, length:', textContent.length);
            
            // Create a synthetic analysis structure matching TAR analysis format
            debugLog('[Worker] Creating analysis structure...');
            const analysis = {
                reportType: 'console-log',
                reportName: filename,
                fileCount: 1,
                totalSize: textData.byteLength,
                // Add empty arrays for formatter compatibility
                directories: [],
                files: [filename],
                fileTypes: { 'log': 1 },
                // Initialize event arrays to avoid undefined errors in formatter
                oomKiller: { found: false, events: [] },
                kernelReboots: { found: false, events: [] },
                liveMigration: { found: false, events: [] },
                xfsErrors: { found: false, events: [] },
                emergencyMode: { found: false, events: [] },
                sshService: { found: false, events: [] },
                automation: { found: false, events: [] }
            };
            debugLog('[Worker] Analysis structure created');
            
            // Run event detection parsers that work on kernel logs
            debugLog('[Worker] Preparing event parsers...');
            const eventParsers = {
                oomKiller: SCC_RULES.oomKiller,
                kernelReboots: SCC_RULES.kernelReboots,
                liveMigration: SCC_RULES.liveMigration,
                xfsErrors: SCC_RULES.xfsErrors,
                emergencyMode: SCC_RULES.emergencyMode,
                sshService: SCC_RULES.sshService,
                automation: SCC_RULES.automation
            };
            debugLog('[Worker] Event parsers ready, starting analysis...');
            
            let eventsFound = 0;
            
            for (const [parserName, parser] of Object.entries(eventParsers)) {
                debugLog(`[Worker] Checking parser: ${parserName}`);
                if (parser && parser.parse) {
                    debugLog(`[Worker] Running parser: ${parserName}`);
                    const result = parser.parse(textContent, filename);
                    debugLog(`[Worker] Parser ${parserName} completed`);
                    
                    if (result) {
                        // Ensure event provenance is set for plain-text logs.
                        if (result.events && Array.isArray(result.events)) {
                            result.events.forEach(event => {
                                if (!event.sourcePath && !event.sourceFile) {
                                    event.sourcePath = filename;
                                }
                            });
                        }
                        
                        // Always store the result, even if found=false
                        analysis[parserName] = result;
                        
                        if (result.found && result.events) {
                            eventsFound += result.events.length;
                            debugLog(`[Worker] ${parserName}: found ${result.events.length} events`);
                        }
                    }
                }
            }
            
            debugLog(`[Worker] Plain text analysis complete: ${eventsFound} total events`);
            
            // Validate analysis object before sending
            debugLog(`[Worker] Analysis object keys:`, Object.keys(analysis));
            
            try {
                // Test if the analysis object can be serialized
                JSON.stringify(analysis);
                debugLog(`[Worker] Analysis object successfully serialized`);
            } catch (serErr) {
                console.error('[Worker] Analysis serialization error:', serErr);
                self.postMessage({ error: 'Failed to serialize analysis: ' + serErr.message });
                return;
            }
            
            self.postMessage({
                success: true,
                analysis: analysis,
                progress: 100
            });
            
        } catch (err) {
            console.error('[Worker] Plain text analysis error:', err);
            console.error('[Worker] Error stack:', err.stack);
            self.postMessage({ error: 'Plain text analysis failed: ' + err.message + '\nStack: ' + err.stack });
        }
        return;
    }
    
    // Handle ZIP archive analysis
    if (e.data.cmd === 'analyze_zip') {
        try {
            const { zipData } = e.data;
            debugLog(`[Worker] Starting ZIP analysis: ${zipData.byteLength} bytes`);

            if (typeof fflate === 'undefined' || !fflate.unzipSync) {
                self.postMessage({ error: 'fflate library not loaded - ZIP support unavailable' });
                return;
            }

            // Extract all files from the ZIP archive
            const zipBytes = new Uint8Array(zipData);
            let extracted;
            try {
                extracted = fflate.unzipSync(zipBytes);
            } catch (unzipErr) {
                self.postMessage({ error: 'Failed to extract ZIP archive: ' + unzipErr.message });
                return;
            }

            const filenames = Object.keys(extracted);
            debugLog(`[Worker] ZIP extracted ${filenames.length} entries`);

            // Use IncrementalTARParser for its analysis infrastructure
            // (parser matching, result accumulation, getAnalysis)
            const parser = new IncrementalTARParser();
            // Mark the end marker as found since ZIP doesn't have one
            parser.foundEndMarker = true;

            // Pre-scan filenames to detect report type before processing.
            // This is necessary because ZIP entries are unordered - detection
            // entries (e.g. device_0/...) may appear after parseable top-level
            // files (e.g. results.txt) that would otherwise be skipped.
            for (const fname of filenames) {
                if (SCC_RULES.detection.isSCCReport(fname)) {
                    parser.isSCCReport = true;
                    parser.sccReportName = fname.split('/')[0];
                    debugLog('[Worker] ZIP pre-scan detected report type:', parser.sccReportName);
                    break;
                }
            }

            let processedCount = 0;
            for (const fname of filenames) {
                const data = extracted[fname];
                parser.processExtractedFile(fname, data);
                processedCount++;

                // Send progress updates every 50 files
                if (processedCount % 50 === 0) {
                    self.postMessage({
                        progress: Math.floor((processedCount / filenames.length) * 100),
                        currentFile: fname,
                        analysis: { fileCount: processedCount }
                    });
                }
            }

            // Build final analysis using the same getAnalysis() logic
            const analysis = parser.getAnalysis();
            debugLog(`[Worker] ZIP analysis complete: ${analysis.fileCount} files`);

            try {
                self.postMessage({
                    success: true,
                    analysis: analysis,
                    progress: 100
                });
            } catch (postErr) {
                console.error('[Worker] postMessage failed for ZIP analysis:', postErr.message);
                // Trim large arrays and retry
                if (analysis.clusterEvents) {
                    const ce = analysis.clusterEvents;
                    if (ce.resourceMigrations && ce.resourceMigrations.length > 1000) {
                        ce.resourceMigrations = ce.resourceMigrations.slice(0, 1000);
                        ce.resourceMigrationsTrimmed = true;
                    }
                    if (ce.fencingEvents && ce.fencingEvents.length > 1000) {
                        ce.fencingEvents = ce.fencingEvents.slice(0, 1000);
                        ce.fencingEventsTrimmed = true;
                    }
                }
                self.postMessage({
                    success: true,
                    analysis: analysis,
                    progress: 100
                });
            }

            return;
        } catch (err) {
            console.error('[Worker] ZIP analysis error:', err);
            self.postMessage({ error: 'ZIP analysis failed: ' + err.message });
            return;
        }
    }

    // Handle TAR-only analysis (for already decompressed data like from gzip)
    if (e.data.cmd === 'analyze_tar') {
        try {
            const { tarData } = e.data;
            debugLog(`[Worker] Starting TAR analysis: ${tarData.byteLength} bytes`);
            
            // Initialize TAR parser
            const tarParser = new IncrementalTARParser();
            
            // Process the TAR data
            const tarBytes = new Uint8Array(tarData);
            tarParser.addChunk(tarBytes);
            
            // Get analysis results
            const analysis = tarParser.getAnalysis();
            
            debugLog(`[Worker] TAR analysis complete: ${analysis.fileCount} files`);
            
            try {
                self.postMessage({
                    success: true,
                    analysis: analysis,
                    progress: 100
                });
                debugLog('[Worker] Success message sent to main thread');
            } catch (err) {
                console.error('[Worker] Error sending message:', err);
                self.postMessage({ error: 'Failed to send results: ' + err.message });
            }
            
            return;
        } catch (err) {
            console.error('[Worker] TAR analysis error:', err);
            self.postMessage({ error: 'TAR analysis failed: ' + err.message });
            return;
        }
    }
    
    // Handle streaming XZ decompression (existing code)
    if (e.data.cmd === 'decompress_streaming') {
        if (!moduleReady || !LzmaModule) {
            self.postMessage({ error: 'WASM module not properly initialized' });
            return;
        }

        // Declare outside try so catch block can access for partial results
        let tarParser = null;
        let inputOffset = 0;
        let totalDecompressed = 0;
        let chunkCount = 0;
        let inputSize = 0;

        try {
            const { compressedData, chunkSize } = e.data;
            inputSize = compressedData.byteLength;
            const effectiveChunkSize = chunkSize || (256 * 1024); // 256KB default

            debugLog(`[XZ Streaming Worker] Starting streaming decompression: ${inputSize} bytes input`);

            const handle = LzmaModule.xzStreamInit();
            if (!handle) {
                throw new Error('Failed to initialize Rust XZ stream');
            }

            debugLog('[XZ Streaming Worker] Stream initialized');

            // Initialize TAR parser
            tarParser = new IncrementalTARParser();

            // Process input in chunks
            let streamComplete = false;
            let lastStatus = 0;
            // Throttle progress messages so the main thread is not flooded.
            // For multi-GB archives the per-chunk loop produces tens of
            // thousands of postMessage calls; the UI re-render cost on the
            // main thread becomes the bottleneck and the tab eventually
            // shows "page isn't responding". Cap to ~20 updates/sec.
            let lastProgressPostMs = 0;
            const PROGRESS_MIN_INTERVAL_MS = 50;

            while (inputOffset < inputSize) {
                // Get next chunk of input
                const remainingInput = inputSize - inputOffset;
                const currentChunkSize = Math.min(effectiveChunkSize, remainingInput);
                const isLastChunk = (inputOffset + currentChunkSize >= inputSize);

                const chunk = new Uint8Array(compressedData, inputOffset, currentChunkSize);
                const result = LzmaModule.xzStreamProcess(handle, chunk);
                const status = result.status;
                const outputData = result.output;
                const outLen = outputData ? outputData.length : 0;
                lastStatus = status;

                debugLog(`[XZ Streaming Worker] Chunk ${chunkCount}: input=${currentChunkSize}, output=${outLen}, status=${status}, isLast=${isLastChunk}`);

                if (outLen > 0) {
                    // Feed to TAR parser
                    tarParser.addChunk(outputData);
                    totalDecompressed += outLen;

                    // Send lightweight progress update (avoid cloning full analysis).
                    // Throttled: at most one message every PROGRESS_MIN_INTERVAL_MS
                    // to keep the main thread responsive for very large archives.
                    const nowMs = Date.now();
                    if (nowMs - lastProgressPostMs >= PROGRESS_MIN_INTERVAL_MS) {
                        lastProgressPostMs = nowMs;
                        const progress = Math.floor((inputOffset / inputSize) * 100);
                        self.postMessage({
                            progress,
                            decompressed: totalDecompressed,
                            currentFile: tarParser.currentFile,
                            analysis: { fileCount: tarParser.totalFileCount || tarParser.files.length }
                        });
                    }
                    
                }

                // Check status
                if (status < 0) {
                    const errMsg = LzmaModule.xzStreamError(handle);
                    LzmaModule.xzStreamFree(handle);
                    throw new Error(`Decompression error: ${errMsg} (status=${status})`);
                }

                if (status === 1) {
                    // Stream finished
                    streamComplete = true;
                    debugLog('[XZ Streaming Worker] Stream finished');
                    break;
                }

                // Move to next chunk
                inputOffset += currentChunkSize;
                chunkCount++;

                // Yield to prevent blocking and allow GC
                if (chunkCount % 10 === 0) {
                    await new Promise(resolve => setTimeout(resolve, 0));
                }
                
                // More aggressive GC hint every 50 chunks (helps browser reclaim memory)
                if (chunkCount % 50 === 0) {
                    await new Promise(resolve => setTimeout(resolve, 10));
                }
            }

            // Final finish flush: the Rust stream validates the footer once it
            // receives an empty input chunk signaling end-of-stream.
            if (!streamComplete && lastStatus >= 0) {
                const emptyChunk = new Uint8Array(0);
                for (let i = 0; i < 16; i++) {
                    const flushResult = LzmaModule.xzStreamProcess(handle, emptyChunk);
                    const flushStatus = flushResult.status;
                    const flushData = flushResult.output;
                    const flushOutLen = flushData ? flushData.length : 0;
                    if (flushOutLen > 0) {
                        tarParser.addChunk(flushData);
                        totalDecompressed += flushOutLen;
                    }
                    lastStatus = flushStatus;
                    if (flushStatus === 1) {
                        streamComplete = true;
                        debugLog('[XZ Streaming Worker] Stream finished during flush');
                        break;
                    }
                    if (flushStatus < 0) {
                        debugLog(`[XZ Streaming Worker] Flush returned error status=${flushStatus}`);
                        break;
                    }
                    // status==0 means the decoder still wants more input but
                    // none is available — bail after the bounded retries to
                    // avoid livelock on a genuinely truncated stream.
                }
            }

            LzmaModule.xzStreamFree(handle);

            // Final analysis
            const finalAnalysis = tarParser.finish();

            // Check if TAR archive is complete (has end marker)
            //
            // We only flag "truncated" when XZ itself signaled corruption
            // (throws a Decompression error above) OR when the consumer fed
            // less than the full input. Reaching this code means every byte
            // of the .txz was decompressed without error, so the *file* is
            // intact. A missing TAR end marker at this point is a parse
            // glitch (e.g. a non-standard PAX size attribute or a corrupt
            // entry header in the inner tar) — not a download truncation —
            // so we surface a successful analysis instead of misleading the
            // user with a "truncated" warning.
            const inputFullyConsumed = (inputOffset >= inputSize);
            // The XZ stream itself is incomplete when liblzma never returned
            // status==1 (LZMA_STREAM_END) before we ran out of input.  Treat
            // that as a corrupt/truncated archive and surface progress so the
            // UI can render a useful partial-analysis warning.
            if (!streamComplete) {
                debugLog('[XZ Streaming Worker] WARNING: XZ stream did not reach end marker - file may be truncated');
                self.postMessage({
                    success: true,
                    partialSuccess: true,
                    totalDecompressed,
                    analysis: {
                        ...finalAnalysis,
                        corruptionDetected: true,
                        corruptionMessage: `XZ stream is incomplete (no end marker) — processed ${chunkCount} block(s), ${totalDecompressed} byte(s) decompressed before input was exhausted.`,
                        xzBlocksProcessed: chunkCount,
                        bytesProcessed: inputOffset,
                        totalInputBytes: inputSize,
                        percentProcessed: Math.floor((inputOffset / Math.max(inputSize, 1)) * 100)
                    }
                });
                return;
            }
            if (!tarParser.foundEndMarker && finalAnalysis.fileCount > 0 && !inputFullyConsumed) {
                debugLog('[XZ Streaming Worker] WARNING: TAR archive missing end marker - file may be truncated');
                
                self.postMessage({
                    success: true,
                    partialSuccess: true,
                    totalDecompressed,
                    analysis: {
                        ...finalAnalysis,
                        corruptionDetected: true,
                        corruptionMessage: 'TAR archive is incomplete - file appears to be truncated or corrupted',
                        xzBlocksProcessed: chunkCount,
                        bytesProcessed: inputOffset,
                        totalInputBytes: inputSize,
                        percentProcessed: Math.floor((inputOffset / inputSize) * 100)
                    }
                });
                return;
            }

            debugLog(`[XZ Streaming Worker] Complete: ${totalDecompressed} bytes decompressed, ${finalAnalysis.fileCount} files`);

            try {
                self.postMessage({
                    success: true,
                    totalDecompressed,
                    analysis: finalAnalysis
                });
            } catch (postErr) {
                console.error('[XZ Streaming Worker] postMessage failed (analysis too large), retrying with trimmed data:', postErr.message);
                // Trim large event arrays to fit in structured clone
                if (finalAnalysis.clusterEvents) {
                    const ce = finalAnalysis.clusterEvents;
                    if (ce.resourceMigrations && ce.resourceMigrations.length > 1000) {
                        ce.resourceMigrations = ce.resourceMigrations.slice(0, 1000);
                        ce.resourceMigrationsTrimmed = true;
                    }
                    if (ce.fencingEvents && ce.fencingEvents.length > 1000) {
                        ce.fencingEvents = ce.fencingEvents.slice(0, 1000);
                        ce.fencingEventsTrimmed = true;
                    }
                }
                self.postMessage({
                    success: true,
                    totalDecompressed,
                    analysis: finalAnalysis
                });
            }

        } catch (error) {
            console.error('[XZ Streaming Worker] Error:', error);
            
            // Check if we got partial data before the error
            let partialAnalysis = null;
            try {
                partialAnalysis = tarParser ? tarParser.getAnalysis() : null;
            } catch (analysisErr) {
                console.error('[XZ Streaming Worker] Failed to get partial analysis:', analysisErr.message);
            }
            
            if (partialAnalysis && partialAnalysis.fileCount > 0) {
                // We have partial data - report it along with the error
                debugLog(`[XZ Streaming Worker] Partial success: ${totalDecompressed} bytes decompressed, ${partialAnalysis.fileCount} files before error`);
                
                // Trim large arrays to prevent OOM on postMessage
                if (partialAnalysis.clusterEvents) {
                    const ce = partialAnalysis.clusterEvents;
                    if (ce.resourceMigrations && ce.resourceMigrations.length > 1000) {
                        ce.resourceMigrations = ce.resourceMigrations.slice(0, 1000);
                        ce.resourceMigrationsTrimmed = true;
                    }
                    if (ce.fencingEvents && ce.fencingEvents.length > 1000) {
                        ce.fencingEvents = ce.fencingEvents.slice(0, 1000);
                        ce.fencingEventsTrimmed = true;
                    }
                }
                
                try {
                    self.postMessage({
                        success: true,
                        partialSuccess: true,
                        totalDecompressed,
                        analysis: {
                            ...partialAnalysis,
                            corruptionDetected: true,
                            corruptionMessage: error.message || 'File appears to be corrupted or truncated',
                            xzBlocksProcessed: chunkCount,
                            bytesProcessed: inputOffset,
                            totalInputBytes: inputSize
                        }
                    });
                } catch (postErr) {
                    console.error('[XZ Streaming Worker] Failed to send partial results:', postErr.message);
                    self.postMessage({
                        error: 'Analysis completed but results too large to transfer: ' + error.message
                    });
                }
            } else {
                // Complete failure — surface the partial progress (XZ blocks
                // processed and bytes decompressed before the corruption was
                // detected) so the UI can show the user *something* useful
                // instead of a bare "Decompression error" line.  The
                // ui.spec.js corruption test asserts that the rendered error
                // contains at least one of "block", "byte" or "decompressed".
                const progressSummary = `Processed ${chunkCount} XZ block(s) and ${totalDecompressed} byte(s) decompressed before failure.`;
                self.postMessage({
                    error: `${error.message || 'Unknown streaming decompression error'} — ${progressSummary}`
                });
            }
        }
    }
};

debugLog('[XZ Streaming Worker] Worker initialized, waiting for module...');
