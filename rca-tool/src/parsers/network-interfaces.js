/**
 * @module parsers/network-interfaces
 * @description WASM-shim parser delegating to
 * `supportfile_core::parsers::network_interfaces::parse_network_interfaces`.
 *
 * Per-file dispatch is handled inside the Rust port (it auto-detects
 * `ip addr`, `ifcfg`, `nmcli`, `wicked`, `netplan` formats from the
 * file content).  This shim invokes the Rust parser once per matching
 * file and exposes a `mergeResults` helper for the worker to fold
 * results across many files (see worker.js's `networkInterfaces`
 * branch).  The legacy field name `iface_type` (Rust) becomes
 * `ifaceType` after snake→camel; we alias it to `type` to keep
 * existing consumers happy.
 */

function netIfDebugLog() {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.networkInterfaces) {
        console.log.apply(console, ['[network-interfaces.js]'].concat(Array.from(arguments)));
    }
}

function emptyNetIfResult() {
    return { found: false, interfaces: {}, raw: {} };
}

const NETIF_ALIASES = { ifaceType: 'type' };

const networkInterfacesParser = {
    filePattern: /(?:network\.txt$|sos_commands\/networking\/ip_-o_addr$|sos_commands\/networking\/ip_-s_-d_link$|sos_commands\/networking\/ethtool_-i_\w+|sos_commands\/networkmanager\/nmcli_con_show_id_|etc\/sysconfig\/network-scripts\/ifcfg-|etc\/sysconfig\/network\/(?:network\/)?ifcfg-|etc\/netplan\/|var\/log\/cloud-init-output\.log$|(?:^|\/)messages$)/,
    multiFile: true,

    parse: function(content, filename, _lines) {
        if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
            return emptyNetIfResult();
        }
        let result;
        try {
            result = WASM_BRIDGE.parseJson('parseNetworkInterfaces', content, filename || '');
        } catch (err) {
            console.error('[network-interfaces.js] parseNetworkInterfaces WASM call failed:', err);
            return emptyNetIfResult();
        }
        if (result == null) return emptyNetIfResult();
        WASM_BRIDGE.aliasKeys(result, NETIF_ALIASES);
        if (!result.raw) result.raw = {};
        netIfDebugLog('Parsed', filename, '→ interfaces:', Object.keys(result.interfaces || {}).length);
        return result;
    },

    /**
     * Helper used by the cluster section to find the accelerated-network
     * "linked" interface bound to a primary master interface.
     */
    getAccelNetLinked: function(result, masterName) {
        if (!result || !result.interfaces) return undefined;
        return Object.values(result.interfaces).find(
            i => i.master === masterName && i.accelNet
        );
    },

    /**
     * Merge two single-file results.  Mirrors the original JS merge:
     * keep first non-null scalar fields per interface and dedupe IP
     * lists by address.
     */
    mergeResults: function(existing, incoming) {
        if (!existing || !incoming) return;
        existing.found = existing.found || incoming.found;
        if (!existing.interfaces) existing.interfaces = {};

        for (const name of Object.keys(incoming.interfaces || {})) {
            const iface = incoming.interfaces[name];
            if (!existing.interfaces[name]) {
                existing.interfaces[name] = iface;
                continue;
            }
            const e = existing.interfaces[name];
            if (iface.state && !e.state) e.state = iface.state;
            if (iface.mac && !e.mac) e.mac = iface.mac;
            if (iface.mtu && !e.mtu) e.mtu = iface.mtu;
            if (iface.driver && !e.driver) e.driver = iface.driver;
            if (iface.driverInfo && !e.driverInfo) e.driverInfo = iface.driverInfo;
            if (iface.accelNet) e.accelNet = true;
            if (iface.bootproto && !e.bootproto) e.bootproto = iface.bootproto;
            if (iface.master && !e.master) e.master = iface.master;
            if (iface.type && !e.type) e.type = iface.type;
            if (iface.firmwareVersion && !e.firmwareVersion) e.firmwareVersion = iface.firmwareVersion;
            if (iface.busInfo && !e.busInfo) e.busInfo = iface.busInfo;
            if (Array.isArray(iface.ipv4)) {
                if (!Array.isArray(e.ipv4)) e.ipv4 = [];
                for (const ip of iface.ipv4) {
                    if (!e.ipv4.some(a => a.address === ip.address)) e.ipv4.push(ip);
                }
            }
            if (Array.isArray(iface.ipv6)) {
                if (!Array.isArray(e.ipv6)) e.ipv6 = [];
                for (const ip of iface.ipv6) {
                    if (!e.ipv6.some(a => a.address === ip.address)) e.ipv6.push(ip);
                }
            }
        }

        if (incoming.raw) {
            if (!existing.raw) existing.raw = {};
            Object.assign(existing.raw, incoming.raw);
        }
    }
};
