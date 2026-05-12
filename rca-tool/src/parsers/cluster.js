/**
 * @module parsers/cluster
 * @description Thin shims for cluster (Pacemaker / Corosync / SAP HA / SBD /
 * iSCSI / Azure fence agent) parsers. The real implementation lives in
 * `rca-tool/lib/supportfile_core/src/parsers/cluster.rs` and is exposed via
 * `wasm_bindgen.parse*` exports (see `supportfile_wasm/src/lib.rs`).
 *
 * Each shim:
 *   1. Calls `WASM_BRIDGE.parseJson(...)` (which JSON-parses the Rust output
 *      and recursively snake_case → camelCase transforms keys).
 *   2. Optionally projects/aliases fields where the JS bridge would corrupt
 *      a value or where the original JS shape used keys that contain dots,
 *      mixed case, or other characters that the camelCase transform mangles.
 *
 * Special projections:
 *   - `iscsiConfig`: `iscsidConfig` is emitted as `[{name, value}]` from Rust
 *     to dodge the bridge's mangling of dotted keys; this shim rebuilds the
 *     legacy `{ "node.startup": "manual", ... }` object shape.
 *   - `clusterNodes`: `nodeToIpMap` is emitted as `[{host, ip}]` for the same
 *     reason; this shim rebuilds the legacy `{ "node1": "10.0.0.1", ... }`
 *     hostname → IP object.
 *
 * The factory `createClusterParsers(SCC_RULES, debugLog, parseXMLSimple,
 * querySelectorAll)` is preserved for binary compatibility with worker.js
 * (line 902). The legacy `parseXMLSimple` / `querySelectorAll` arguments are
 * accepted but unused — Rust handles XML extraction internally.
 *
 * Fallback: if WASM is not loaded, every parser returns `{ found: false }`.
 *
 * @see {@link module:worker} for registration in SCC_RULES.
 */

function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.cluster) {
        console.log('[cluster.js]', ...args);
    }
}

function _wasmCall(fnName, content, filename, fallback) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
        debugLog('WASM not ready -- returning empty result for', fnName, filename);
        return fallback;
    }
    try {
        return WASM_BRIDGE.parseJson(fnName, content, filename || '');
    } catch (err) {
        console.error('[cluster.js]', fnName, 'WASM call failed:', err);
        return fallback;
    }
}

// ---------------------------------------------------------------------------
// Core cluster
// ---------------------------------------------------------------------------

const corosyncConfigParser = {
    filePattern: /\/(ha\.txt|corosync\.conf)$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseCorosyncConfig', content, filename, { found: false, warnings: [] });
    }
};

const clusterNodesParser = {
    filePattern: /\/(ha\.txt|pacemaker\.log|corosync\.conf|cib\.xml|crm_mon.*\.txt)$/,
    parse: function(content, filename, _lines) {
        const result = _wasmCall('parseClusterNodes', content, filename,
            { nodes: [], nodeToIpMap: {} });
        // Rust emits nodeToIpMap as [{host, ip}, ...] to dodge bridge key mangling.
        // Project back to legacy { hostname: ip } object shape.
        if (result && Array.isArray(result.nodeToIpMap)) {
            const obj = {};
            for (const entry of result.nodeToIpMap) {
                if (entry && entry.host) obj[entry.host] = entry.ip;
            }
            result.nodeToIpMap = obj;
        }
        return result;
    }
};

const hostsFileParser = {
    filePattern: /\/(network\.txt|etc\/hosts|etc_hosts)$|\/[^\/]+\/(hosts)$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseHostsFile', content, filename, { found: false });
    }
};

const corosyncStatusParser = {
    filePattern: /corosync-cfgtool.*-s$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseCorosyncStatus', content, filename, { found: false });
    }
};

const clusterStatusParser = {
    filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/crm_mon.*\.xml$|\/ha\.txt$|\/pcs_status/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseClusterStatus', content, filename, { found: false });
    }
};

const clusterDaemonStatusParser = {
    filePattern: /\/pcs_status|\/ha\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseClusterDaemonStatus', content, filename, { found: false });
    }
};

const clusterMaintenanceModeParser = {
    filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/ha\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseClusterMaintenanceMode', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// Resources and constraints
// ---------------------------------------------------------------------------

const pacemakerResourcesParser = {
    filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/crm.*config$|pacemaker\.log$|\/ha\.txt$|\/pcs_config$|\/pcs_status/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parsePacemakerResources', content, filename, { found: false });
    }
};

const azureScheduledEventsParser = {
    filePattern: /\/pcs_status.*|\/crm_mon.*|cib\.xml$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseAzureScheduledEvents', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// Fencing and SBD
// ---------------------------------------------------------------------------

const fencingConfigParser = {
    filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/crm.*config$|stonith|\/ha\.txt$|\/pcs_config$|\/pcs_property/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseFencingConfig', content, filename, { found: false });
    }
};

const sbdConfigParser = {
    filePattern: /\/sbd$|\/sysconfig\/sbd|\/ha\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseSbdConfig', content, filename, { found: false });
    }
};

const azureFenceAuthParser = {
    filePattern: /cib\.xml$|\/ha\.txt$|\/crm.*config$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseAzureFenceAuth', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// Events and live migration
// ---------------------------------------------------------------------------

const clusterEventsParser = {
    multiFile: true,
    processAllRotations: true,
    filePattern: /\/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?(?:\.gz)?$|\/ha\.txt$/,
    parse: function(content, filename, _lines) {
        const result = _wasmCall('parseClusterEvents', content, filename, { found: false });
        if (result && typeof WASM_BRIDGE !== 'undefined' && WASM_BRIDGE.aliasKeys) {
            WASM_BRIDGE.aliasKeys(result, { sourcePath: 'sourceFile' });
        }
        return result;
    }
};

const liveMigrationParser = {
    filePattern: /\/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|localmessages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseLiveMigration', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// SAP
// ---------------------------------------------------------------------------

const sapInstanceConfigParser = {
    filePattern: /\/pcs_config|\/cib\.xml$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseSapInstanceConfig', content, filename, { found: false });
    }
};

const sapInstanceErrorsParser = {
    filePattern: /\/analysis\.txt$|\/cluster-log\.txt$|\/messages|\/var\/log\/messages/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseSapInstanceErrors', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// iSCSI
// ---------------------------------------------------------------------------

const iscsiConfigParser = {
    filePattern: /fs-iscsi\.txt$|\/iscsi\/|\/iscsiadm|\/ha\.txt$|initiatorname\.iscsi$/,
    parse: function(content, filename, _lines) {
        const result = _wasmCall('parseIscsiConfig', content, filename, { found: false });
        // Rust emits iscsidConfig as [{name, value}, ...] to dodge bridge key
        // mangling of dotted/underscored setting names like
        // "node.session.timeo.replacement_timeout". Project to legacy object.
        if (result && Array.isArray(result.iscsidConfig)) {
            const obj = {};
            for (const setting of result.iscsidConfig) {
                if (setting && setting.name) obj[setting.name] = setting.value;
            }
            result.iscsidConfig = obj;
        }
        return result;
    }
};

// ---------------------------------------------------------------------------
// Factory: preserved signature for worker.js binary compatibility.
// The legacy parseXMLSimple / querySelectorAll args are accepted but unused;
// Rust handles XML attribute extraction inline.
// ---------------------------------------------------------------------------

// eslint-disable-next-line no-unused-vars
const createClusterParsers = function(SCC_RULES, debugLog, parseXMLSimple, querySelectorAll) {
    return {
        corosyncConfig: corosyncConfigParser,
        clusterNodes: clusterNodesParser,
        hostsFile: hostsFileParser,
        pacemakerResources: pacemakerResourcesParser,
        corosyncStatus: corosyncStatusParser,
        clusterStatus: clusterStatusParser,
        clusterDaemonStatus: clusterDaemonStatusParser,
        azureScheduledEvents: azureScheduledEventsParser,
        fencingConfig: fencingConfigParser,
        clusterEvents: clusterEventsParser,
        liveMigration: liveMigrationParser,
        sapInstanceConfig: sapInstanceConfigParser,
        sapInstanceErrors: sapInstanceErrorsParser,
        clusterMaintenanceMode: clusterMaintenanceModeParser,
        sbdConfig: sbdConfigParser,
        azureFenceAuth: azureFenceAuthParser,
        iscsiConfig: iscsiConfigParser
    };
};
