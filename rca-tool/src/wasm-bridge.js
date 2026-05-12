/**
 * @module assets/supportfile-wasm/wasm-bridge
 * @description Helper utilities for parser .js shims that delegate to the
 * supportfile WASM module.  Loaded by `worker.js` after `importScripts` of
 * `supportfile_wasm.js` and before any parser .js files.
 *
 * Exposed globals:
 *   - `WASM_BRIDGE.snakeToCamel(obj)`  — recursive key transformer
 *   - `WASM_BRIDGE.parseJson(name, content, sourcePath)` — invoke a
 *     `parse*` export on `wasm_bindgen`, JSON.parse + snake→camel transform.
 *   - `WASM_BRIDGE.isReady()` — true after worker init resolves the
 *     supportfile WASM promise (mirrors `self.SUPPORTFILE_WASM_READY`).
 *
 * Each individual parser shim layers its own field-rename / alias logic on
 * top of `parseJson`.  The legacy JS parsers used camelCase keys with some
 * non-1:1 names (e.g. event `sourceFile` vs. Rust `source_path`); shims
 * patch those over the generic transform.
 */
(function (root) {
    'use strict';

    function snakeToCamelKey(key) {
        if (typeof key !== 'string' || key.indexOf('_') === -1) return key;
        return key.replace(/_([a-z0-9])/g, function (_, ch) {
            return ch.toUpperCase();
        });
    }

    function transform(value) {
        if (Array.isArray(value)) {
            return value.map(transform);
        }
        if (value !== null && typeof value === 'object') {
            const out = {};
            for (const k of Object.keys(value)) {
                out[snakeToCamelKey(k)] = transform(value[k]);
            }
            return out;
        }
        return value;
    }

    function isReady() {
        // `wasm_bindgen` from the wasm-pack `target=no-modules` bundle is a
        // top-level `let` binding, which lives in the script-global lexical
        // environment but is NOT a property of `self`/`globalThis`.  We must
        // reference it lexically here rather than via `root.wasm_bindgen`.
        return Boolean(root.SUPPORTFILE_WASM_READY)
            && typeof wasm_bindgen !== 'undefined';
    }

    function parseJson(fnName, content, sourcePath) {
        if (!isReady()) {
            throw new Error(
                '[wasm-bridge] supportfile WASM not initialized yet (calling ' +
                fnName + ')'
            );
        }
        const fn = wasm_bindgen[fnName];
        if (typeof fn !== 'function') {
            throw new Error(
                '[wasm-bridge] wasm_bindgen.' + fnName + ' is not a function'
            );
        }
        const json = fn(content || '', sourcePath || '');
        return transform(JSON.parse(json));
    }

    /**
     * Recursively rename keys in `obj` according to `aliases` (a plain
     * object whose keys are the OLD field name and values are the NEW
     * name).  Mutates `obj` in place and returns it for chaining.
     *
     * Example: `aliasKeys(result, { eventType: 'type', totalVm: 'totalVM' })`
     * will copy the value at each old key to the new key (preserving the
     * old key as well, so consumers that read either name still work).
     */
    function aliasKeys(obj, aliases) {
        if (Array.isArray(obj)) {
            for (const item of obj) aliasKeys(item, aliases);
            return obj;
        }
        if (obj !== null && typeof obj === 'object') {
            for (const oldName of Object.keys(aliases)) {
                if (Object.prototype.hasOwnProperty.call(obj, oldName)
                    && !Object.prototype.hasOwnProperty.call(obj, aliases[oldName])) {
                    obj[aliases[oldName]] = obj[oldName];
                }
            }
            for (const k of Object.keys(obj)) aliasKeys(obj[k], aliases);
        }
        return obj;
    }

    root.WASM_BRIDGE = {
        snakeToCamel: transform,
        parseJson: parseJson,
        aliasKeys: aliasKeys,
        isReady: isReady,
    };
})(typeof self !== 'undefined' ? self : globalThis);
