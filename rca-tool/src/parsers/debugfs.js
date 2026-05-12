/**
 * @module parsers/debugfs
 * @description WASM-shim parsers for `/sys/kernel/debug/` files —
 * Hyper-V balloon driver (`hv_balloon`) and external/unusable
 * fragmentation indices (`extfrag/extfrag_index`,
 * `extfrag/unusable_index`).
 *
 * Both parsers delegate to `supportfile_core::parsers::debugfs`.  The
 * extfrag parser is multi-file: it accumulates the raw text of each
 * file it sees with the labelled separator the Rust parser
 * understands (`=== extfrag_index ===` / `=== unusable_index ===`)
 * and re-invokes the Rust parser on the combined buffer each call.
 * That mirrors the original JS accumulator semantics without needing
 * an end-of-batch hook.
 */

function debugLog() {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.debugfs) {
        console.log.apply(console, ['[debugfs.js]'].concat(Array.from(arguments)));
    }
}

function emptyHvBalloon() {
    return {
        found: false, warnings: [], rawContent: '',
        hostVersion: null, capabilities: null, state: null, stateText: null,
        pageSize: 4096, pagesAdded: 0, pagesOnlined: 0, pagesBallooned: 0,
        totalPagesCommitted: 0, maxDynamicPageCount: 0,
        committedMemoryGB: 0, maxDynamicMemoryGB: 0, balloonedMemoryMB: 0
    };
}

function emptyExtfrag() {
    return { found: false, zones: [], warnings: [], rawContent: '' };
}

const hvBalloonParser = {
    filePattern: /sys\/kernel\/debug\/hv[-_]balloon$/,
    parse: function(content, filename, _lines) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
            return emptyHvBalloon();
        }
        try {
            return WASM_BRIDGE.parseJson('parseHvBalloon', content, filename || '');
        } catch (err) {
            console.error('[debugfs.js] parseHvBalloon WASM call failed:', err);
            return emptyHvBalloon();
        }
    }
};

const extfragParser = {
    filePattern: /sys\/kernel\/debug\/extfrag\/(extfrag_index|unusable_index)$/,
    multiFile: true,

    parse: function(content, filename) {
        if (!this._buffer) this._buffer = '';
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
            return emptyExtfrag();
        }
        if (!content || typeof content !== 'string') return emptyExtfrag();
        var trimmed = content.trim();
        if (!trimmed) return emptyExtfrag();

        var label = (filename && filename.indexOf('extfrag_index') !== -1) ? 'extfrag_index'
                   : (filename && filename.indexOf('unusable_index') !== -1) ? 'unusable_index'
                   : null;
        if (!label) return emptyExtfrag();

        if (this._buffer) this._buffer += '\n\n';
        this._buffer += '=== ' + label + ' ===\n' + trimmed;

        try {
            return WASM_BRIDGE.parseJson('parseExtfrag', this._buffer, filename || '');
        } catch (err) {
            console.error('[debugfs.js] parseExtfrag WASM call failed:', err);
            return emptyExtfrag();
        }
    }
};
