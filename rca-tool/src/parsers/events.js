/**
 * @module parsers/events
 * @description Kernel and system event parsers (emergency-mode, kernel
 * reboots, OOM-killer, XFS errors).  All four are WASM-backed shims
 * delegating to `supportfile_core::parsers::events`.
 *
 * Rust-native field names are now consumed directly by the Leptos UI
 * helper fallbacks, so this shim only delegates to WASM.
 */

function emptyEventsResult() {
    return { found: false, count: 0, events: [] };
}

function callWasmEvents(fnName, content, filename) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
        return emptyEventsResult();
    }
    let result;
    try {
        result = WASM_BRIDGE.parseJson(fnName, content, filename || '');
    } catch (err) {
        console.error('[events.js]', fnName, 'WASM call failed:', err);
        return emptyEventsResult();
    }
    if (result == null) return emptyEventsResult();
    if (typeof result.found === 'undefined') {
        result.found = (result.count || (result.events && result.events.length) || 0) > 0;
    }
    return result;
}

const emergencyModeParser = {
    filePattern: /\/(messages|localmessages|journalctl[^\/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$/,
    parse: function(content, filename, _lines) {
        return callWasmEvents('parseEmergencyMode', content, filename);
    }
};

const kernelRebootsParser = {
    filePattern: /\/(messages|localmessages|ha-log|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
    parse: function(content, filename, _lines) {
        return callWasmEvents('parseKernelReboots', content, filename);
    }
};

const oomKillerParser = {
    filePattern: /\/(messages|localmessages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
    parse: function(content, filename, _lines) {
        return callWasmEvents('parseOomKiller', content, filename);
    }
};

const xfsErrorsParser = {
    filePattern: /\/(messages|localmessages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
    parse: function(content, filename, _lines) {
        return callWasmEvents('parseXfsErrors', content, filename);
    }
};
