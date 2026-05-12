/**
 * @module parsers/services
 * @description WASM-shim parsers for distro/cluster service detection.
 * All 13 parsers delegate to `supportfile_core::parsers::services`.
 *
 * Per-parser field aliases bring the WASM result back in line with the
 * legacy schema the Leptos sections consume:
 *   - `sourcePath` → `sourceFile` (event records)
 *   - `sourcePath` → `detectionFile` (systemd-service detections)
 *   - `issueType` (already snake→camelCase'd, no further alias needed)
 *
 * For systemd-service detections the legacy JS helper also surfaced a
 * `detectionContent` snippet (the matched line text).  The Rust port
 * stores `source_line` only; the shim resolves the snippet by indexing
 * the raw content with that line number.
 */

function debugLog() {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.services) {
        console.log.apply(console, ['[services.js]'].concat(Array.from(arguments)));
    }
}

function emptyEvents() { return { found: false, count: 0, events: [] }; }
function emptyDetect() { return { found: false }; }

function lineSnippet(content, lineNo) {
    if (!content || !lineNo || typeof lineNo !== 'number') return null;
    const lines = content.split('\n');
    if (lineNo < 1 || lineNo > lines.length) return null;
    return lines[lineNo - 1].trim();
}

function callServiceEvents(fnName, content, filename) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return emptyEvents();
    let r;
    try { r = WASM_BRIDGE.parseJson(fnName, content, filename || ''); }
    catch (err) { console.error('[services.js]', fnName, err); return emptyEvents(); }
    if (r == null) return emptyEvents();
    WASM_BRIDGE.aliasKeys(r, { sourcePath: 'sourceFile' });
    return r;
}

/**
 * Wrap a systemd-service detection result so legacy consumers see
 * `enabled`, `detectionFile`, `detectionLine`, `detectionContent`.
 */
function decorateDetection(rawResult, content, filename, opts) {
    if (!rawResult || !rawResult.found) return { found: false };
    const out = {
        found: true,
        enabled: true,
        severity: rawResult.severity,
        message: rawResult.message,
        detectionFile: filename,
        detectionLine: rawResult.sourceLine || null,
        detectionContent: lineSnippet(content, rawResult.sourceLine)
    };
    if (rawResult.documentationUrl) out.documentationUrl = rawResult.documentationUrl;
    if (opts && opts.documentationUrl && !out.documentationUrl) {
        out.documentationUrl = opts.documentationUrl;
    }
    return out;
}

function callDetection(fnName, content, filename, opts) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return emptyDetect();
    let r;
    try { r = WASM_BRIDGE.parseJson(fnName, content, filename || ''); }
    catch (err) { console.error('[services.js]', fnName, err); return emptyDetect(); }
    return decorateDetection(r, content, filename, opts);
}

function callSecurityDetection(fnName, content) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return emptyDetect();
    let r;
    try { r = WASM_BRIDGE.parseJson(fnName, content, ''); }
    catch (err) { console.error('[services.js]', fnName, err); return emptyDetect(); }
    if (!r || !r.found) return { found: false };
    return { found: true, message: r.message };
}

function callConfigCheck(fnName, content) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return emptyDetect();
    let r;
    try { r = WASM_BRIDGE.parseJson(fnName, content, ''); }
    catch (err) { console.error('[services.js]', fnName, err); return emptyDetect(); }
    if (!r) return emptyDetect();
    return r;
}

const sshServiceParser = {
    filePattern: /\/(messages|localmessages|syslog|journalctl[^\/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$/,
    parse: function(content, filename, _lines) {
        return callServiceEvents('parseSshServiceIssues', content, filename);
    }
};

const dlmServiceParser = {
    filePattern: /sos_commands\/systemd\/systemctl_list-unit-files$/,
    parse: function(content, filename, _lines) {
        return callDetection('parseDlmService', content, filename,
            { documentationUrl: 'https://access.redhat.com/solutions/878023' });
    }
};

const azureSiteRecoveryParser = {
    filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
    parse: function(content, filename, _lines) {
        return callDetection('parseAzureSiteRecovery', content, filename);
    }
};

const guardicoreAgentParser = {
    filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
    parse: function(content, filename, _lines) {
        return callDetection('parseGuardicoreAgent', content, filename);
    }
};

const illumioParser = {
    filePattern: /sos_commands\/systemd\/systemctl_list-units_--all$/,
    parse: function(content, _filename, _lines) {
        return callSecurityDetection('parseIllumio', content);
    }
};

const trendMicroParser = {
    filePattern: /sos_commands\/systemd\/systemctl_list-units_--all$/,
    parse: function(content, _filename, _lines) {
        return callSecurityDetection('parseTrendMicro', content);
    }
};

const falconSensorParser = {
    filePattern: /\/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$/,
    parse: function(content, _filename, _lines) {
        return callSecurityDetection('parseFalconSensor', content);
    }
};

const falconSensorConfigParser = {
    filePattern: /\/(falconctl|CrowdStrike.*config|falcon.*conf)$/i,
    parse: function(content, _filename, _lines) {
        return callConfigCheck('parseFalconSensorConfig', content);
    }
};

const msDefenderParser = {
    filePattern: /\/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$/,
    parse: function(content, _filename, _lines) {
        return callSecurityDetection('parseMsDefender', content);
    }
};

const msDefenderConfigParser = {
    filePattern: /\/(mdatp.*|defender.*config)$/i,
    parse: function(content, _filename, _lines) {
        return callConfigCheck('parseMsDefenderConfig', content);
    }
};

const involfltVersionParser = {
    filePattern: /modules\.txt$/,
    parse: function(content, filename, _lines) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return { found: false };
        let r;
        try { r = WASM_BRIDGE.parseJson('parseInvolfltVersion', content, filename || ''); }
        catch (err) { console.error('[services.js] parseInvolfltVersion', err); return { found: false }; }
        if (!r || !r.found) return { found: false };
        return r;
    }
};

const involfltKernelVersionParser = {
    filePattern: /\/(messages|boot)(?:[.-]\d+)?(?:\.txt)?$/,
    parse: function(content, filename, _lines) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return null;
        let r;
        try { r = WASM_BRIDGE.parseJson('parseInvolfltKernelVersion', content, filename || ''); }
        catch (err) { console.error('[services.js] parseInvolfltKernelVersion', err); return null; }
        if (!r || !r.found) return null;
        // Legacy field name
        if (!r.detectionFile) r.detectionFile = filename;
        return r;
    }
};

const azureExtensionsParser = {
    filePattern: /var\/lib\/waagent\/[^\/]+\/config\/HandlerStatus$/,
    parse: function(content, filename, _lines) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return null;
        let r;
        try { r = WASM_BRIDGE.parseJson('parseAzureExtensions', content, filename || ''); }
        catch (err) { console.error('[services.js] parseAzureExtensions', err); return null; }
        if (!r || !r.found) return null;
        WASM_BRIDGE.aliasKeys(r, { sourcePath: 'sourceFile' });
        return r;
    }
};
