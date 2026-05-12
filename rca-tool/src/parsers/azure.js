/**
 * @module parsers/azure
 * @description Thin shims for Azure-related parsers. The real implementation
 * lives in `rca-tool/lib/supportfile_core/src/parsers/azure.rs` and is
 * exposed via `wasm_bindgen.parseAzureVmProperties / parseSuseCloudRegister
 * / parseWaagentConfig / parseWaagentLog`.
 *
 * Each shim:
 *   1. Calls `WASM_BRIDGE.parseJson(...)` (which JSON-parses the Rust
 *      output and recursively snake_case→camelCase transforms keys).
 *   2. Patches a small set of fields whose mechanical camelCase form does
 *      not match the legacy JS schema that Leptos consumes (i.e. fields
 *      that contain all-caps acronyms like FIPS, GAFamily, MB, GB).
 *
 * Note: `azureExtensionsParser` and `azureSiteRecoveryParser` already live
 * in `parsers/services.js` as thin shims and are NOT re-defined here.
 *
 * Fallback: if WASM is not loaded, every parser returns `{ found: false }`.
 *
 * @see {@link module:worker} for registration in SCC_RULES (azureVMProperties,
 *      suseCloudRegister, waagentConfig, waagentLog).
 */

function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.azure) {
        console.log('[azure.js]', ...args);
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
        console.error('[azure.js]', fnName, 'WASM call failed:', err);
        return fallback;
    }
}

// ---------------------------------------------------------------------------
// azureVMProperties
// ---------------------------------------------------------------------------
//
// Patches: dataDisks[].diskSizeGb -> diskSizeGB (Azure uses the all-caps
// "GB" form; mechanical conversion produces "Gb" which Leptos already
// tolerates as a fallback but the canonical name is the all-caps one).

const azureVMPropertiesParser = {
    filePattern: /(?:instance_metadata\.json|public_cloud\/metadata\.txt)$/,

    parse: function(content, filename, _lines) {
        const result = _wasmCall('parseAzureVmProperties', content, filename, { found: false });
        if (result && Array.isArray(result.dataDisks)) {
            for (const disk of result.dataDisks) {
                if (disk && disk.diskSizeGb != null && disk.diskSizeGB == null) {
                    disk.diskSizeGB = disk.diskSizeGb;
                }
            }
        }
        debugLog('azureVMProperties result for', filename, '-> found =', result && result.found);
        return result;
    }
};

// ---------------------------------------------------------------------------
// suseCloudRegister
// ---------------------------------------------------------------------------
//
// No alias patching needed — every Rust field maps cleanly to the legacy
// camelCase shape (registrationServer, registrationType, billingModel,
// detectionMethod).

const suseCloudRegisterParser = {
    filePattern: /public_cloud\/cloudregister\.txt$/,

    parse: function(content, filename, _lines) {
        const result = _wasmCall('parseSuseCloudRegister', content, filename, { found: false });
        debugLog('suseCloudRegister result for', filename, '-> found =', result && result.found);
        return result;
    }
};

// ---------------------------------------------------------------------------
// waagentConfig
// ---------------------------------------------------------------------------
//
// Patches in `summary`:
//   enable_fips             -> enableFIPS              (acronym)
//   auto_update_ga_family   -> autoUpdateGAFamily      (acronym)
//   resource_disk_swap_size_mb -> resourceDiskSwapSizeMB  (acronym)

const WAAGENT_CONFIG_SUMMARY_ALIASES = {
    enableFips: 'enableFIPS',
    autoUpdateGaFamily: 'autoUpdateGAFamily',
    resourceDiskSwapSizeMb: 'resourceDiskSwapSizeMB',
};

const waagentConfigParser = {
    filePattern: /\/etc\/waagent\.conf$/,

    parse: function(content, filename, _lines) {
        const result = _wasmCall('parseWaagentConfig', content, filename, { found: false });
        if (result && result.summary) {
            for (const oldKey of Object.keys(WAAGENT_CONFIG_SUMMARY_ALIASES)) {
                const newKey = WAAGENT_CONFIG_SUMMARY_ALIASES[oldKey];
                if (result.summary[oldKey] !== undefined && result.summary[newKey] === undefined) {
                    result.summary[newKey] = result.summary[oldKey];
                }
            }
        }
        debugLog('waagentConfig result for', filename, '-> found =', result && result.found,
            'warnings =', (result && result.warnings && result.warnings.length) || 0);
        return result;
    }
};

// ---------------------------------------------------------------------------
// waagentLog
// ---------------------------------------------------------------------------
//
// No alias patching: extensionStatusSummary, imdsErrors, goalStateErrors,
// resourceDiskErrors, agentVersionHistory, etc. all map cleanly via
// mechanical snake→camel.

const waagentLogParser = {
    filePattern: /\/waagent\.log$/,

    parse: function(content, filename, _lines) {
        const result = _wasmCall('parseWaagentLog', content, filename, { found: false });
        debugLog('waagentLog result for', filename, '-> found =', result && result.found,
            'errors =', (result && result.totalErrors) || 0);
        return result;
    }
};
