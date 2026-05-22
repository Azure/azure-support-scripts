/**
 * @module parsers/networking
 * @description WASM-shim firewall-rules parser delegating to
 * `supportfile_core::parsers::networking::parse_firewall_rules`.
 *
 * The worker invokes this parser once per matching file and uses its
 * own merge logic (see `worker.js`'s `firewallRules` branch) to fold
 * results across many files.  After merging, the worker calls
 * `firewallRulesParser.determineActiveFirewall(existing)` — so we keep
 * that helper here on the parser object.
 */

function emptyFirewallResult() {
    return {
        found: false,
        firewalld: { detected: false, running: false, config: null, zones: null, directRules: null, passthroughs: null, chains: null, logDenied: null, backend: null },
        iptables: { detected: false, rules: [], modules: [] },
        ip6tables: { detected: false, rules: [], modules: [] },
        ebtables: { detected: false, config: null },
        nftables: { detected: false, ruleset: null, tables: null },
        activeFirewall: 'none',
        warnings: [],
        rawSections: {}
    };
}

const firewallRulesParser = {
    filePattern: /(?:network\.txt$|sos_commands\/firewalld\/|sos_commands\/firewall_tables\/|etc\/sysconfig\/(?:iptables-config|ebtables-config|nftables\.conf|firewalld)$|etc\/firewalld\/firewalld\.conf$)/,
    multiFile: true,

    parse: function(content, filename, _lines) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
            return emptyFirewallResult();
        }
        let result;
        try {
            result = WASM_BRIDGE.parseJson('parseFirewallRules', content, filename || '');
        } catch (err) {
            console.error('[networking.js] parseFirewallRules WASM call failed:', err);
            return emptyFirewallResult();
        }
        if (result == null) return emptyFirewallResult();
        if (!result.rawSections) result.rawSections = {};
        return result;
    },

    /**
     * Re-run the active-firewall priority check after the worker has
     * merged contributions from multiple files.  Mirrors the priority
     * order in the Rust parser: firewalld(running) > nftables(non-empty)
     * > iptables > ip6tables > none.
     */
    determineActiveFirewall: function(result) {
        if (result.firewalld && result.firewalld.running) return 'firewalld';
        if (result.nftables && result.nftables.ruleset
            && result.nftables.ruleset !== '(empty)'
            && result.nftables.ruleset.trim() !== '') return 'nftables';
        if (result.iptables && result.iptables.rules && result.iptables.rules.length > 0) return 'iptables';
        if (result.ip6tables && result.ip6tables.rules && result.ip6tables.rules.length > 0) return 'ip6tables';
        return 'none';
    }
};

/**
 * Packet-loss / RX-TX counter parser. Delegates to
 * `supportfile_core::parsers::networking::parse_packet_loss` which
 * reads `ip -stats link` output from SCC `network.txt` (or SOS
 * `sos_commands/networking/ip_-s_-d_link`).
 */
function emptyPacketLossResult() {
    return { found: false, interfaces: [], warnings: [], sourcePath: '' };
}
const packetLossParser = {
    filePattern: /(?:network\.txt$|sos_commands\/networking\/ip_-s_-d_link$|sos_commands\/networking\/ip_-s_link$)/,
    multiFile: false,
    parse: function(content, filename) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return emptyPacketLossResult();
        try {
            return WASM_BRIDGE.parseJson('parsePacketLoss', content, filename || '') || emptyPacketLossResult();
        } catch (err) {
            console.error('[networking.js] parsePacketLoss WASM call failed:', err);
            return emptyPacketLossResult();
        }
    }
};

/**
 * NIC ring-buffer parser (ethtool -g). Delegates to
 * `supportfile_core::parsers::networking::parse_ring_buffer`.
 */
function emptyRingBufferResult() {
    return { found: false, entries: [], warnings: [], sourcePath: '' };
}
const ringBufferParser = {
    filePattern: /(?:network\.txt$|sos_commands\/networking\/ethtool_-g_\w+)/,
    multiFile: false,
    parse: function(content, filename) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return emptyRingBufferResult();
        try {
            return WASM_BRIDGE.parseJson('parseRingBuffer', content, filename || '') || emptyRingBufferResult();
        } catch (err) {
            console.error('[networking.js] parseRingBuffer WASM call failed:', err);
            return emptyRingBufferResult();
        }
    }
};

/**
 * Network-tuning sysctl parser. Currently surfaces
 * `net.ipv4.conf.*.rp_filter` values; warns on non-zero settings
 * because they cause asymmetric-routing drops on multi-NIC Azure VMs.
 */
function emptyNetworkSysctlResult() {
    return { found: false, rpFilter: [], warnings: [], sourcePath: '' };
}
const networkSysctlParser = {
    filePattern: /(?:\/env\.txt$|\/sysctl\.conf$|sos_commands\/kernel\/sysctl_-a$|etc\/sysctl\.d\/)/,
    multiFile: false,
    parse: function(content, filename) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) return emptyNetworkSysctlResult();
        try {
            return WASM_BRIDGE.parseJson('parseNetworkSysctl', content, filename || '') || emptyNetworkSysctlResult();
        } catch (err) {
            console.error('[networking.js] parseNetworkSysctl WASM call failed:', err);
            return emptyNetworkSysctlResult();
        }
    }
};
