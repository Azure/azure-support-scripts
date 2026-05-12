/**
 * @module parsers/events
 * @description Kernel and system event parsers (emergency-mode, kernel
 * reboots, OOM-killer, XFS errors).  All four are WASM-backed shims
 * delegating to `supportfile_core::parsers::events`.
 *
 * Field aliases applied after `WASM_BRIDGE.parseJson(...)` so the
 * Leptos UI components keep using their legacy schema:
 *   - Rust `event_type` → JS `type` (already snake→camelCase'd to
 *     `eventType`, then aliased)
 *   - Rust `total_vm`  → JS `totalVM` (uppercase `VM`)
 *   - Each event gets `sourceFile` mirrored from `sourcePath`
 */

function debugLog() {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.events) {
        console.log.apply(console, ['[events.js]'].concat(Array.from(arguments)));
    }
}

const EVENTS_ALIASES = {
    eventType: 'type',
    totalVm: 'totalVM',
    sourcePath: 'sourceFile',
};

function emptyEventsResult() {
    return { found: false, count: 0, events: [] };
}

function callWasmEvents(fnName, content, filename) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
        debugLog('WASM not ready --', fnName, 'returning empty for', filename);
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
    WASM_BRIDGE.aliasKeys(result, EVENTS_ALIASES);
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
