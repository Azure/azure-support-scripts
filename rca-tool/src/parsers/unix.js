/**
 * @module parsers/unix
 * @description Thin shims for Unix system parsers. The real implementation
 * lives in `rca-tool/lib/supportfile_core/src/parsers/unix.rs` and is
 * exposed via `wasm_bindgen.parse*` exports (see `supportfile_wasm/src/lib.rs`).
 *
 * Each shim:
 *   1. Calls `WASM_BRIDGE.parseJson(...)` (which JSON-parses the Rust output
 *      and recursively snake_case → camelCase transforms keys).
 *   2. Returns the result unchanged. A Leptos audit confirmed every consumer
 *      reads the mechanical camelCase form for these 22 parsers — no
 *      acronym-aware aliasing is required.
 *
 * Special cases:
 *   - `kernelTuningParser` keeps its `mergeResults` method because worker.js
 *     accumulates `parameters{}` across multiple sysctl files and recomputes
 *     warnings/Azure-network/optional-network info from the merged set.
 *
 * Fallback: if WASM is not loaded, every parser returns `{ found: false }`.
 *
 * @see {@link module:worker} for registration in SCC_RULES.
 */

function _wasmCall(fnName, content, filename, fallback) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
        return fallback;
    }
    try {
        return WASM_BRIDGE.parseJson(fnName, content, filename || '');
    } catch (err) {
        console.error('[unix.js]', fnName, 'WASM call failed:', err);
        return fallback;
    }
}

// ---------------------------------------------------------------------------
// OS Identity
// ---------------------------------------------------------------------------

const basicEnvironmentParser = {
    filePattern: /basic-environment\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseBasicEnvironment', content, filename, { found: false });
    }
};

const osReleaseParser = {
    // Match os-release files from various report types:
    // - /usr/lib/os-release (sosreport - real file, not the /etc symlink)
    // - /etc/os-release (crm_report)
    // - sysinfo.txt (supportconfig SUSE - older format)
    // - basic-environment.txt (supportconfig SUSE - newer format)
    // - /etc/redhat-release, /etc/centos-release, /etc/SuSE-release, /etc/system-release
    filePattern: /\/usr\/lib\/os-release$|\/etc\/os-release$|\/sysinfo\.txt$|\/basic-environment\.txt$|\/etc\/(redhat|centos|SuSE|system)-release$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseOsRelease', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// Filesystem
// ---------------------------------------------------------------------------

const fstabParser = {
    filePattern: /\/etc\/fstab$|\/fs-diskio\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseFstab', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// InspectIaaSDisk
// ---------------------------------------------------------------------------

const inspectDiskResultsParser = {
    filePattern: /^results\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseInspectDiskResults', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// Kernel Tuning
// ---------------------------------------------------------------------------

const kernelTuningParser = {
    filePattern: /sos_commands\/kernel\/sysctl_-a$|\/env\.txt$|\/etc\/sysctl\.conf$|\/sysctl\.d\/[^\/]*\.conf$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseKernelTuning', content, filename, { found: false });
    },

    /**
     * Merge a per-file kernelTuning result into the accumulated state.
     * Worker invokes this for every matching sysctl file so we accumulate
     * `parameters{}` across env.txt + sysctl.conf + sysctl.d/*.conf, then
     * recompute SAP-HANA / Azure-network / optional-network warnings from
     * the merged set (the per-file warnings from Rust are discarded).
     */
    mergeResults: function(accumulated, newResult) {
        if (!newResult || !newResult.found) return;
        accumulated.found = true;

        // Merge parameters — later values override earlier ones
        Object.assign(accumulated.parameters, newResult.parameters || {});

        const parameters = accumulated.parameters;

        // SAP HANA / high-performance warnings
        const expectedValues = {
            'vm.dirty_bytes': '629145600',
            'vm.dirty_background_bytes': '314572800',
            'vm.swappiness': '10'
        };
        const documentation = {
            'vm.dirty_bytes': 'https://learn.microsoft.com/en-us/azure/sap/workloads/sap-hana-high-availability',
            'vm.dirty_background_bytes': 'https://learn.microsoft.com/en-us/azure/sap/workloads/sap-hana-high-availability',
            'vm.swappiness': 'https://learn.microsoft.com/en-us/azure/sap/workloads/sap-hana-high-availability'
        };
        const warnings = [];
        for (const [param, expectedValue] of Object.entries(expectedValues)) {
            if (parameters[param] && parameters[param] !== expectedValue) {
                warnings.push({ parameter: param, expected: expectedValue, actual: parameters[param], documentationUrl: documentation[param] });
            }
        }

        // Azure Network optimization warnings
        const azureNetworkParams = {
            'net.ipv4.tcp_mem': '4096\t87380\t67108864',
            'net.ipv4.udp_mem': '4096\t87380\t33554432',
            'net.ipv4.tcp_rmem': '4096\t87380\t67108864',
            'net.ipv4.tcp_wmem': '4096\t65536\t67108864',
            'net.core.rmem_default': '33554432',
            'net.core.wmem_default': '33554432',
            'net.ipv4.udp_wmem_min': '16384',
            'net.ipv4.udp_rmem_min': '16384',
            'net.core.wmem_max': '134217728',
            'net.core.rmem_max': '134217728',
            'net.core.busy_poll': '50',
            'net.core.busy_read': '50',
            'net.ipv4.tcp_congestion_control': 'bbr'
        };
        const azureNetworkDocUrl = 'https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-optimize-network-bandwidth#linux-virtual-machines';
        const azureNetworkWarnings = [];
        for (const [param, expectedValue] of Object.entries(azureNetworkParams)) {
            if (parameters[param]) {
                const normalizedActual = parameters[param].replace(/\s+/g, '\t');
                const normalizedExpected = expectedValue.replace(/\s+/g, '\t');
                if (normalizedActual !== normalizedExpected) {
                    azureNetworkWarnings.push({ parameter: param, expected: expectedValue, actual: parameters[param], documentationUrl: azureNetworkDocUrl });
                }
            }
        }

        accumulated.warnings = warnings;
        accumulated.hasWarnings = warnings.length > 0;
        accumulated.azureNetworkWarnings = azureNetworkWarnings;
        accumulated.hasAzureNetworkWarnings = azureNetworkWarnings.length > 0;
        accumulated.azureNetworkTuned = azureNetworkWarnings.length === 0 && Object.keys(azureNetworkParams).every(p => parameters[p]);

        // Optional network parameters (informational)
        const optionalNetworkParams = {
            'net.ipv4.tcp_timestamps': '1',
            'net.ipv4.tcp_tw_reuse': '1',
            'net.ipv4.ip_local_port_range': '1024\t65535',
            'net.core.netdev_budget': '1000',
            'net.core.optmem_max': '65535',
            'net.ipv4.tcp_frto': '0',
            'net.core.somaxconn': '32768',
            'net.core.netdev_max_backlog': '32768',
            'net.core.dev_weight': '64',
            'net.core.default_qdisc': 'fq'
        };
        const optionalNetworkInfo = [];
        for (const [param, expectedValue] of Object.entries(optionalNetworkParams)) {
            if (parameters[param]) {
                const normalizedActual = parameters[param].replace(/\s+/g, '\t');
                const normalizedExpected = expectedValue.replace(/\s+/g, '\t');
                optionalNetworkInfo.push({
                    parameter: param,
                    expected: expectedValue,
                    actual: parameters[param],
                    matches: normalizedActual === normalizedExpected,
                    documentationUrl: azureNetworkDocUrl
                });
            }
        }
        accumulated.optionalNetworkInfo = optionalNetworkInfo;
        accumulated.hasOptionalNetworkInfo = optionalNetworkInfo.length > 0;

        // Recompute FIPS detection from merged parameters
        accumulated.fipsEnabled = parameters['crypto.fips_enabled'] === '1';

    }
};

const hugePagesParser = {
    filePattern: /\/proc\/meminfo$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseHugePages', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// Time Synchronisation (Azure PTP)
// ---------------------------------------------------------------------------

const timeSyncParser = {
    filePattern: /sos_commands\/kernel\/lsmod$|\/modules\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseTimeSync', content, filename, { found: false });
    }
};

const ptpClockSourceParser = {
    filePattern: /sos_commands\/chrony\/chronyc_sources$|\/etc\/chrony\.conf$|\/etc\/chrony\/chrony\.conf$|\/ntp\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parsePtpClockSource', content, filename, { found: false });
    }
};

const timeSyncServiceParser = {
    filePattern: /sos_commands\/systemd\/systemctl_list-unit-files$|\/systemd-status\.txt$|\/ntp\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseTimeSyncService', content, filename, { found: false });
    }
};

const timedatectlParser = {
    filePattern: /sos_commands\/systemd\/timedatectl$|\/ntp\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseTimedatectl', content, filename, { found: false });
    }
};

const ptpDeviceParser = {
    filePattern: /sos_commands\/block\/ls_-lanR_\.dev$|\/udev\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parsePtpDevice', content, filename, { found: false });
    }
};

const chronyTrackingParser = {
    filePattern: /sos_commands\/chrony\/chronyc_tracking$|\/ntp\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseChronyTracking', content, filename, { found: false });
    }
};

const chronyMakestepParser = {
    filePattern: /\/etc\/chrony\.conf$|\/etc\/chrony\/chrony\.conf$|\/ntp\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseChronyMakestep', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// RHUI (Red Hat Update Infrastructure)
// ---------------------------------------------------------------------------

const rhuiConfigParser = {
    filePattern: /\/(rh-cloud.*\.repo|rhui-.*\.repo|yum\.repos\.d\.txt|dnf\.repos\.d\.txt|yum\.repos\.d\/.*\.repo)$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseRhuiConfig', content, filename, { found: false });
    }
};

const eusVersionLockParser = {
    filePattern: /\/(releasever|yum-vars\.txt|dnf-vars\.txt|etc\/yum\/vars|etc\/dnf\/vars|dnf\/vars\/releasever|yum\/vars\/releasever)$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseEusVersionLock', content, filename, { found: false });
    }
};

const rhelRhuiCheckParser = {
    filePattern: /\/(installed-rpms|rpm-qa\.txt|rpm_-qa|package-data)$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseRhelRhuiCheck', content, filename, { found: false });
    }
};

const rhuiErrorsParser = {
    filePattern: /\/(dnf\.log|yum\.log|rhsm\.log)(\.\d+)?$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseRhuiErrors', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// Security
// ---------------------------------------------------------------------------

const cryptoPoliciesParser = {
    filePattern: /\/crypto-policies\/(config|state\/current)$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseCryptoPolicies', content, filename, { found: false });
    }
};

const fipsModeSetupParser = {
    filePattern: /sos_commands\/crypto\/fips-mode-setup/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseFipsModeSetup', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// OS tuning (SAP-on-Azure QualityCheck ports)
// ---------------------------------------------------------------------------

const tunedProfileParser = {
    filePattern: /sos_commands\/tuned\/tuned-adm_active$|\/tuned-adm.*\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseTunedProfile', content, filename, { found: false });
    }
};

const selinuxParser = {
    filePattern: /\/etc\/selinux\/config$|sos_commands\/selinux\/sestatus$|\/selinux\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseSelinux', content, filename, { found: false });
    }
};

const swapSpaceParser = {
    filePattern: /\/proc\/meminfo$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseSwapSpace', content, filename, { found: false });
    }
};

const kernelCmdlineParser = {
    filePattern: /\/proc\/cmdline$|\/boot\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseKernelCmdline', content, filename, { found: false });
    }
};

// ---------------------------------------------------------------------------
// Leapp In-Place Upgrade
// ---------------------------------------------------------------------------

const leappReportParser = {
    filePattern: /var\/log\/leapp\/leapp-report\.txt$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseLeappReport', content, filename, { found: false });
    }
};

const leappLogParser = {
    filePattern: /var\/log\/leapp\/leapp-(preupgrade|upgrade)\.log$/,
    parse: function(content, filename, _lines) {
        return _wasmCall('parseLeappLog', content, filename, { found: false });
    }
};
