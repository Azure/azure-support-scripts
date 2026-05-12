/**
 * @module parsers/automation
 * @description Automation tool detection (Ansible / Puppet / Chef) parser.
 *
 * **WASM-backed shim.**  The Rust implementation lives in
 * `rca-tool/lib/supportfile_core/src/parsers/automation.rs` and is exposed
 * via `wasm_bindgen.parseAutomationEvents(content, sourcePath)`.  This file
 * is now a thin adapter that calls into the WASM module and renames a few
 * keys (`source_path` -> `sourceFile` on each event) to preserve the legacy
 * JS schema that downstream Leptos components consume.
 *
 * **Behavioral diff vs. the old JS parser:**
 *   - Chef events: the previous JS implementation aggregated up to 5
 *     subsequent `chef-*[PID]:` lines into `event.command` joined with
 *     ` | `.  The Rust port does NOT do this aggregation today and
 *     populates `command` with only the first matched message.  Tracked
 *     as a follow-up under the provenance/parity migration.
 *
 * **Fallback path.** If `wasm_bindgen` is not loaded (e.g. WASM init
 * failed at startup), the shim returns `{ found: false, count: 0,
 * events: [] }` -- equivalent to a no-op parser.
 */

function debugLog() {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.automation) {
        console.log.apply(console, ['[automation parser]'].concat(Array.from(arguments)));
    }
}

const createAutomationParser = function(SCC_RULES) {
    return {
        filePattern: /\/(messages|localmessages|syslog|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,

        parse: function(content, filename, _lines) {
            if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
                debugLog('WASM not ready -- returning empty result for', filename);
                return { found: false, count: 0, events: [] };
            }

            let result;
            try {
                result = WASM_BRIDGE.parseJson('parseAutomationEvents', content, filename || '');
            } catch (err) {
                console.error('[automation parser] WASM call failed:', err);
                return { found: false, count: 0, events: [] };
            }

            if (result && Array.isArray(result.events)) {
                for (const ev of result.events) {
                    if (ev && ev.sourcePath != null && ev.sourceFile == null) {
                        ev.sourceFile = ev.sourcePath;
                    }
                }
            }

            debugLog('Found', (result && result.count) || 0, 'automation events via WASM');
            return result;
        }
    };
};
