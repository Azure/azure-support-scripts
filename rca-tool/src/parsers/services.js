/**
 * @module parsers/services
 * @description WASM-shim parsers for distro/cluster service detection.
 * All parsers delegate to `supportfile_core::parsers::services`.
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

function emptyEvents() { return { found: false, count: 0, events: [] }; }
function emptyDetect() { return { found: false }; }

function callServicesWasm(fnName, content, filename, fallback) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return fallback;
    try {
        const result = WASM_BRIDGE.parseJson(fnName, content, filename || '');
        return result == null ? fallback : result;
    } catch (err) {
        console.error('[services.js]', fnName, err);
        return fallback;
    }
}

function lineSnippet(content, lineNo) {
    if (!content || !lineNo || typeof lineNo !== 'number') return null;
    const lines = content.split('\n');
    if (lineNo < 1 || lineNo > lines.length) return null;
    return lines[lineNo - 1].trim();
}

function callServiceEvents(fnName, content, filename) {
    return callServicesWasm(fnName, content, filename, emptyEvents());
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
    const r = callServicesWasm(fnName, content, filename, emptyDetect());
    return decorateDetection(r, content, filename, opts);
}

function callSecurityDetection(fnName, content) {
    const r = callServicesWasm(fnName, content, '', emptyDetect());
    if (!r || !r.found) return { found: false };
    return { found: true, message: r.message };
}

function callConfigCheck(fnName, content) {
    return callServicesWasm(fnName, content, '', emptyDetect());
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

const puppetAgentParser = {
    filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
    parse: function(content, filename, _lines) {
        return callDetection('parsePuppetAgent', content, filename);
    }
};

const chefClientParser = {
    filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
    parse: function(content, filename, _lines) {
        return callDetection('parseChefClient', content, filename);
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
        const r = callServicesWasm('parseInvolfltVersion', content, filename, emptyDetect());
        if (!r || !r.found) return { found: false };
        return r;
    }
};

const involfltKernelVersionParser = {
    filePattern: /\/(messages|boot)(?:[.-]\d+)?(?:\.txt)?$/,
    parse: function(content, filename, _lines) {
        const r = callServicesWasm('parseInvolfltKernelVersion', content, filename, null);
        if (!r || !r.found) return null;
        return r;
    }
};

const azureExtensionsParser = {
    filePattern: /var\/lib\/waagent\/[^\/]+\/config\/HandlerStatus$/,
    parse: function(content, filename, _lines) {
        const r = callServicesWasm('parseAzureExtensions', content, filename, null);
        if (!r || !r.found) return null;
        return r;
    }
};

const fstrimParser = {
    filePattern: /sos_commands\/systemd\/systemctl_list-unit-files$|\/systemd-status\.txt$|sos_commands\/.*fstrim.*$/,
    parse: function(content, filename, _lines) {
        const r = callServicesWasm('parseFstrim', content, filename, null);
        if (!r || !r.found) return null;
        return r;
    }
};
