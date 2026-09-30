/**
 * @module parsers/vmcore
 * @description Multi-file kernel-crash-dump parser — WASM shim
 * delegating to `supportfile_core::parsers::vmcore`.  Each call
 * dispatches to one of `parseVmcoreDmesg`, `parseKdumpStatus`,
 * `parseCrashListing`, or `parseKdumpConf` based on the filename, and
 * the worker's `mergeResults` accumulator merges the per-file results
 * into the final consolidated view (same shape as the legacy parser).
 */

function emptyResult() {
    return { found: false, type: null, crash: null, kdumpStatus: null, crashListing: null, kdumpConf: null };
}

function callWasm(fnName, content, filename) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
        return null;
    }
    try {
        return WASM_BRIDGE.parseJson(fnName, content, filename || '');
    } catch (err) {
        console.error('[vmcore.js]', fnName, 'WASM call failed:', err);
        return null;
    }
}

var vmcoreParser = {
    filePattern: /(?:var\/crash\/[^/]+\/vmcore-dmesg\.txt|sos_commands\/kdump\/kdumpctl_status|sos_commands\/kdump\/ls_-alZR_\.var\.crash|etc\/kdump\.conf)$/,

    parse: function(content, filename, _lines) {
        const result = emptyResult();

        if (filename.indexOf('vmcore-dmesg.txt') !== -1) {
            const crash = callWasm('parseVmcoreDmesg', content, filename);
            if (crash) {
                result.type = 'vmcore-dmesg';
                result.crash = crash;
                result.found = true;
            }
        } else if (filename.indexOf('kdumpctl_status') !== -1) {
            const status = callWasm('parseKdumpStatus', content, filename);
            // Rust returns Option<KdumpStatus>: null becomes JSON null.
            if (status) {
                result.type = 'kdump-status';
                result.kdumpStatus = status;
                result.found = true;
            }
        } else if (filename.indexOf('ls_-alZR_') !== -1) {
            const listing = callWasm('parseCrashListing', content, filename);
            if (listing) {
                result.type = 'crash-listing';
                result.crashListing = listing;
                result.found = true;
            }
        } else if (filename.indexOf('kdump.conf') !== -1) {
            const conf = callWasm('parseKdumpConf', content, filename);
            if (conf) {
                result.type = 'kdump-conf';
                result.kdumpConf = conf;
                result.found = true;
            }
        }

        return result;
    },

    mergeResults: function(existing, newResult) {
        existing.found = existing.found || newResult.found;

        if (newResult.crash) {
            if (!Array.isArray(existing.crashes)) existing.crashes = [];
            existing.crashes.push(newResult.crash);
            existing.crashes.sort(function(a, b) {
                if (!a.date) return 1;
                if (!b.date) return -1;
                return b.date.localeCompare(a.date);
            });
        }

        if (newResult.kdumpStatus) existing.kdumpStatus = newResult.kdumpStatus;
        if (newResult.crashListing) existing.crashListing = newResult.crashListing;
        if (newResult.kdumpConf) existing.kdumpConf = newResult.kdumpConf;
    }
};
