/**
 * @module parsers/packages
 * @description Distro package parser — WASM-shim delegating to
 * `supportfile_core::parsers::packages::parse_distro_packages`.
 */

function debugLog() {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.packages) {
        console.log.apply(console, ['[packages.js]'].concat(Array.from(arguments)));
    }
}

const PACKAGES_ALIASES = {
    sourcePath: 'sourceFile',
    sourceLine: 'lineNumber',
};

function emptyPackagesResult() {
    return {
        found: false,
        packages: {},
        warnings: [],
        fipsPackages: [],
        hasDracutFips: false,
    };
}

const distroPackagesParser = {
    filePattern: /\/(rpm\.txt|installed-rpms|package-data|dpkg_-l|dnf[_-]list[_-]installed|yum[_-]list[_-]installed|var\/log\/zypp\/history|var\/log\/(?:dnf|yum)\.log)$/,

    parse: function(content, filename, _lines) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
            debugLog('WASM not ready, returning empty for', filename);
            return emptyPackagesResult();
        }
        let result;
        try {
            result = WASM_BRIDGE.parseJson('parseDistroPackages', content, filename || '');
        } catch (err) {
            console.error('[packages.js] parseDistroPackages WASM call failed:', err);
            return emptyPackagesResult();
        }
        if (result == null) return emptyPackagesResult();
        WASM_BRIDGE.aliasKeys(result, PACKAGES_ALIASES);
        // Mirror filename for legacy display blocks.
        if (result.isDpkg || result.isRpmRaw || result.isZypperHistory || result.isDnfYumLog) {
            result.filename = filename;
        }
        return result;
    }
};
