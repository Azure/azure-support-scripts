/**
 * @module parsers/network-interfaces
 * @description Network Interfaces Parser for RCA Tool
 *
 * Provides the `networkInterfacesParser`, a multi-file parser that builds a
 * unified view of every network interface on the system by correlating data
 * from IP commands, driver metadata, and configuration files.
 *
 * ### Capabilities
 *
 * | Capability | Source Commands / Files |
 * |------------|------------------------|
 * | Interface inventory (name, state, MAC, MTU) | `ip addr`, `ip -s -d link`, `wicked ifstatus` |
 * | IPv4 / IPv6 addresses with scope | `ip addr`, `ip -o addr`, `ifcfg-*`, `netplan` |
 * | DHCP vs Static detection | `ifcfg-*` (BOOTPROTO), `nmcli con show` (ipv4.method), `wicked ifstatus` (leases), `netplan` (dhcp4) |
 * | Accelerated Networking | `ethtool -i` driver field matched against `ACCELNET_DRIVERS` map |
 * | Bond/bridge membership | `master` field from `ip addr` / `ip -s -d link` |
 * | Driver and firmware details | `ethtool -i` (driver, firmware-version, bus-info) |
 *
 * ### Accelerated Networking Drivers
 *
 * The constant `ACCELNET_DRIVERS` maps kernel driver names to Azure
 * Accelerated Networking status:
 *
 * | Driver | Label | AccelNet |
 * |--------|-------|---------|
 * | `mlx4_core` / `mlx4_en` | Mellanox ConnectX-3 | Yes |
 * | `mlx5_core` | Mellanox ConnectX-4/5/6 | Yes |
 * | `mana` | Microsoft Azure Network Adapter | Yes |
 * | `hv_netvsc` | Hyper-V NetVSC (synthetic) | No |
 *
 * ### Source File Layouts
 *
 * | Report Type | Files Consumed |
 * |-------------|---------------|
 * | SCC         | `network.txt` -- sections: `ip addr`, `ethtool -i <iface>`, `ifcfg-<iface>`, `wicked ifstatus` |
 * | SOS         | `sos_commands/networking/ip_-o_addr` |
 * | SOS         | `sos_commands/networking/ip_-s_-d_link` |
 * | SOS         | `sos_commands/networking/ethtool_-i_<iface>` |
 * | SOS / SCC   | `etc/sysconfig/network-scripts/ifcfg-<iface>` (RHEL) |
 * | SOS / SCC   | `etc/sysconfig/network/ifcfg-<iface>` (SUSE) |
 * | InspectIaaSDisk | `etc/sysconfig/network/network/ifcfg-<iface>` (SUSE, doubled path) |
 * | SOS / SCC   | `etc/netplan/*.yaml` (Ubuntu) |
 * | SOS         | `sos_commands/networkmanager/nmcli_con_show_id_*` |
 * | InspectIaaSDisk / SCC | `var/log/messages`, `var/log/cloud-init-output.log` (cloud-init ci-info) |
 *
 * ### Return Shape (per-file call, merged via `mergeResults`)
 *
 * ```
 * {
 *   found:       Boolean,
 *   interfaces:  { [name]: InterfaceInfo },   // keyed by interface name
 *   raw:         { [label]: String }           // raw command outputs
 * }
 * ```
 *
 * Each `InterfaceInfo` object:
 * ```
 * {
 *   name, state, mac, mtu, ipv4[], ipv6[],
 *   driver, driverInfo, accelNet,
 *   bootproto,         // 'dhcp' | 'static' | 'none' | null
 *   master,            // bonding / bridge master interface
 *   type               // 'ethernet' | 'loopback' | 'bond' | 'linked'
 * }
 * ```
 *
 * ### Key Internal Methods
 *
 * | Method | Purpose |
 * |--------|---------|
 * | `parseSCCNetworkTxt` | Walks SCC `network.txt` sections; delegates to `parseIpAddrFull`, `parseEthtoolI`, `parseIfcfg`, `parseWickedIfstatus` |
 * | `parseIpAddrFull` | Parses multi-line `ip addr` output; extracts state, MAC, MTU, IPs, master, type |
 * | `parseIpOAddr` | Parses one-line-per-address `ip -o addr` output |
 * | `parseIpSdLink` | Parses `ip -s -d link` output; extracts state, MAC, MTU, SLAVE flag |
 * | `parseEthtoolI` | Reads `ethtool -i` output; sets driver, firmware, bus-info, AccelNet flag |
 * | `parseIfcfg` | Parses RHEL/SUSE `ifcfg-*` files; extracts BOOTPROTO, IPADDR, PREFIX |
 * | `parseNmcliConShow` | Parses `nmcli con show` key-value output; maps `ipv4.method` to bootproto |
 * | `parseWickedIfstatus` | Parses SUSE wicked output; extracts state and lease type (dhcp/static) |
 * | `parseNetplan` | Simple YAML parser for Ubuntu netplan; reads `dhcp4` and interface names |
 * | `parseCloudInitCiInfo` | Parses cloud-init `ci-info` net device tables from log files; extracts IPs, MACs, state |
 * | `mergeResults` | Combines two result objects, deduplicating IPs and preferring non-null field values |
 * | `hasAcceleratedNetworking` | Returns true if any interface has `accelNet === true` |
 * | `getAccelNetLinked` | Finds the AccelNet-capable interface linked to a given master |
 */

// Debug logging – checks global DEBUG_CONFIG from worker.js
function netIfDebugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.networking) {
        console.log('[network-interfaces.js]', ...args);
    }
}

// ============================================================================
// Helper: extract all SCC sections between #==[ … ]===# markers that match
// a heading filter.  Returns an array of { heading, body } objects.
// ============================================================================
function extractSCCSectionsForNetIf(content, headingFilter) {
    const sections = [];
    const lines = content.split('\n');
    let currentHeading = null;
    let currentBody = [];

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        if (/^#==\[/.test(line)) {
            if (currentHeading !== null) {
                sections.push({ heading: currentHeading, body: currentBody.join('\n') });
            }
            currentHeading = null;
            currentBody = [];
            continue;
        }

        if (currentHeading === null && /^#\s+/.test(line)) {
            currentHeading = line.replace(/^#\s+/, '').trim();
            continue;
        }

        if (currentHeading !== null) {
            currentBody.push(line);
        }
    }
    if (currentHeading !== null) {
        sections.push({ heading: currentHeading, body: currentBody.join('\n') });
    }

    return sections.filter(s => headingFilter(s.heading));
}

// ============================================================================
// Accelerated Networking driver detection
// ============================================================================
const ACCELNET_DRIVERS = {
    'mlx4_core': { label: 'Mellanox ConnectX-3 (mlx4)', accelNet: true },
    'mlx4_en':   { label: 'Mellanox ConnectX-3 (mlx4)', accelNet: true },
    'mlx5_core': { label: 'Mellanox ConnectX-4/5/6 (mlx5)', accelNet: true },
    'mana':      { label: 'Microsoft Azure Network Adapter (MANA)', accelNet: true },
    'hv_netvsc': { label: 'Hyper-V NetVSC (synthetic)', accelNet: false },
};

function classifyDriver(driverName) {
    if (!driverName) return { label: 'unknown', accelNet: false };
    const info = ACCELNET_DRIVERS[driverName.trim()];
    if (info) return info;
    return { label: driverName.trim(), accelNet: false };
}

// ============================================================================
// networkInterfacesParser
// ============================================================================
const networkInterfacesParser = {
    // Match the relevant files from SCC and SOS reports
    filePattern: /(?:network\.txt$|sos_commands\/networking\/ip_-o_addr$|sos_commands\/networking\/ip_-s_-d_link$|sos_commands\/networking\/ethtool_-i_\w+|sos_commands\/networkmanager\/nmcli_con_show_id_|etc\/sysconfig\/network-scripts\/ifcfg-|etc\/sysconfig\/network\/(?:network\/)?ifcfg-|etc\/netplan\/|var\/log\/cloud-init-output\.log$|(?:^|\/)messages$)/,
    multiFile: true,

    parse: function(content, filename, _lines) {
        netIfDebugLog('[networkInterfaces] Analyzing:', filename, '(', content.length, 'bytes)');

        const result = {
            found: false,
            interfaces: {},     // keyed by interface name
            raw: {}             // raw output sections for display
        };

        // ----- Dispatch based on filename pattern -----

        if (/network\.txt$/.test(filename)) {
            this.parseSCCNetworkTxt(content, result);
        } else if (/ip_-o_addr$/.test(filename)) {
            this.parseIpOAddr(content, result);
        } else if (/ip_-s_-d_link$/.test(filename)) {
            this.parseIpSdLink(content, result);
        } else if (/ethtool_-i_(\w+)$/.test(filename)) {
            const ifaceMatch = filename.match(/ethtool_-i_(\w+)$/);
            if (ifaceMatch) {
                this.parseEthtoolI(content, result, ifaceMatch[1]);
            }
        } else if (/ifcfg-(\S+)$/.test(filename)) {
            const ifaceMatch = filename.match(/ifcfg-(\S+)$/);
            if (ifaceMatch) {
                this.parseIfcfg(content, result, ifaceMatch[1]);
            }
        } else if (/nmcli_con_show_id_(.+)$/.test(filename)) {
            const connMatch = filename.match(/nmcli_con_show_id_(.+)$/);
            if (connMatch) {
                this.parseNmcliConShow(content, result, connMatch[1]);
            }
        } else if (/etc\/netplan\//.test(filename)) {
            this.parseNetplan(content, result, filename);
        } else if (/cloud-init-output\.log$|messages$/.test(filename)) {
            // Only parse if the file actually contains cloud-init ci-info data
            if (/ci-info:.*Net device info/i.test(content)) {
                this.parseCloudInitCiInfo(content, result, filename);
            }
        }

        netIfDebugLog('[networkInterfaces] Result found:', result.found, 'interfaces:', Object.keys(result.interfaces).length);
        return result;
    },

    // Ensure interface entry exists
    _ensureIface: function(result, name) {
        if (!result.interfaces[name]) {
            result.interfaces[name] = {
                name: name,
                state: null,
                mac: null,
                mtu: null,
                ipv4: [],
                ipv6: [],
                driver: null,
                driverInfo: null,
                accelNet: false,
                bootproto: null,     // 'dhcp' | 'static' | 'none' | null
                master: null,        // bonding/bridge master
                type: null           // 'ethernet', 'loopback', 'bond', etc.
            };
        }
        return result.interfaces[name];
    },

    // =====================================================================
    // SCC network.txt – aggregated file with section markers
    // =====================================================================
    parseSCCNetworkTxt: function(content, result) {
        netIfDebugLog('[networkInterfaces] Parsing SCC network.txt');

        // --- ip addr ---
        const ipAddrSections = extractSCCSectionsForNetIf(content, h =>
            /\bip\s+addr\b/.test(h) && !/ip\s+addr\s+show\s+type/.test(h)
        );
        for (const sec of ipAddrSections) {
            if (sec.body.trim()) {
                result.raw['ip addr'] = sec.body.trim();
                this.parseIpAddrFull(sec.body, result);
            }
        }

        // --- ethtool -i ---
        const ethtoolSections = extractSCCSectionsForNetIf(content, h =>
            /ethtool\s+-i\s+/.test(h)
        );
        for (const sec of ethtoolSections) {
            const ifaceMatch = sec.heading.match(/ethtool\s+-i\s+(\w+)/);
            if (ifaceMatch && sec.body.trim() && !/Cannot get driver|not supported/i.test(sec.body)) {
                this.parseEthtoolI(sec.body, result, ifaceMatch[1]);
            }
        }

        // --- ifcfg ---
        const ifcfgSections = extractSCCSectionsForNetIf(content, h =>
            /ifcfg-\w/.test(h)
        );
        for (const sec of ifcfgSections) {
            const ifaceMatch = sec.heading.match(/ifcfg-(\S+)/);
            if (ifaceMatch && sec.body.trim()) {
                this.parseIfcfg(sec.body, result, ifaceMatch[1]);
            }
        }

        // --- wicked ifstatus (SUSE) ---
        const wickedSections = extractSCCSectionsForNetIf(content, h =>
            /wicked\s+ifstatus/.test(h)
        );
        for (const sec of wickedSections) {
            if (sec.body.trim()) {
                result.raw['wicked ifstatus'] = sec.body.trim();
                this.parseWickedIfstatus(sec.body, result);
            }
        }
    },

    // =====================================================================
    // Parse "ip addr" full output (non -o format)
    // =====================================================================
    parseIpAddrFull: function(content, result) {
        const lines = content.split('\n');
        let currentIface = null;

        for (const line of lines) {
            // Interface line: "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ..."
            const ifaceMatch = line.match(/^\d+:\s+(\S+?):\s+<([^>]*)>\s*(.*)/);
            if (ifaceMatch) {
                const name = ifaceMatch[1].replace(/@.*/, '');  // strip e.g. eth1@if2
                const flags = ifaceMatch[2];
                const rest = ifaceMatch[3];
                currentIface = this._ensureIface(result, name);
                result.found = true;

                currentIface.state = flags.includes('UP') ? 'UP' : 'DOWN';
                const mtuMatch = rest.match(/mtu\s+(\d+)/);
                if (mtuMatch) currentIface.mtu = parseInt(mtuMatch[1]);
                const stateMatch = rest.match(/state\s+(\S+)/);
                if (stateMatch) currentIface.state = stateMatch[1];

                if (flags.includes('LOOPBACK')) currentIface.type = 'loopback';
                else currentIface.type = 'ethernet';

                const masterMatch = rest.match(/master\s+(\S+)/);
                if (masterMatch) currentIface.master = masterMatch[1];
                continue;
            }

            if (!currentIface) continue;

            // MAC line: "    link/ether 60:45:bd:03:42:7e brd ..."
            const macMatch = line.match(/link\/ether\s+([0-9a-f:]+)/i);
            if (macMatch) {
                currentIface.mac = macMatch[1];
                continue;
            }

            // IPv4: "    inet 10.112.212.152/28 brd ... scope global eth0"
            const inetMatch = line.match(/inet\s+(\S+)\s+(?:brd\s+\S+\s+)?scope\s+(\S+)/);
            if (inetMatch) {
                currentIface.ipv4.push({ address: inetMatch[1], scope: inetMatch[2] });
                continue;
            }

            // IPv6: "    inet6 fe80::6245:bdff:fe03:427e/64 scope link"
            const inet6Match = line.match(/inet6\s+(\S+)\s+scope\s+(\S+)/);
            if (inet6Match) {
                currentIface.ipv6.push({ address: inet6Match[1], scope: inet6Match[2] });
            }
        }
    },

    // =====================================================================
    // Parse "ip -o addr" (one line per address)
    // =====================================================================
    parseIpOAddr: function(content, result) {
        result.raw['ip -o addr'] = content.trim();
        const lines = content.trim().split('\n');

        for (const line of lines) {
            // "2: eth0    inet 10.112.212.152/28 brd 10.112.212.159 scope global noprefixroute eth0\ ..."
            const match = line.match(/^\d+:\s+(\S+)\s+(inet6?)\s+(\S+)/);
            if (match) {
                const name = match[1];
                const iface = this._ensureIface(result, name);
                result.found = true;

                const scopeMatch = line.match(/scope\s+(\S+)/);
                const scope = scopeMatch ? scopeMatch[1] : 'unknown';

                if (match[2] === 'inet') {
                    iface.ipv4.push({ address: match[3], scope });
                } else {
                    iface.ipv6.push({ address: match[3], scope });
                }
            }
        }
    },

    // =====================================================================
    // Parse "ip -s -d link" (detailed link info)
    // =====================================================================
    parseIpSdLink: function(content, result) {
        result.raw['ip -s -d link'] = content.trim();
        const lines = content.split('\n');
        let currentIface = null;

        for (const line of lines) {
            const ifaceMatch = line.match(/^\d+:\s+(\S+?):\s+<([^>]*)>\s*(.*)/);
            if (ifaceMatch) {
                const name = ifaceMatch[1].replace(/@.*/, '');
                const flags = ifaceMatch[2];
                const rest = ifaceMatch[3];
                currentIface = this._ensureIface(result, name);
                result.found = true;

                currentIface.state = flags.includes('UP') ? 'UP' : 'DOWN';
                const mtuMatch = rest.match(/mtu\s+(\d+)/);
                if (mtuMatch) currentIface.mtu = parseInt(mtuMatch[1]);
                const stateMatch = rest.match(/state\s+(\S+)/);
                if (stateMatch) currentIface.state = stateMatch[1];
                if (flags.includes('LOOPBACK')) currentIface.type = 'loopback';
                else currentIface.type = 'ethernet';
                if (flags.includes('SLAVE')) currentIface.type = 'linked';

                const masterMatch = rest.match(/master\s+(\S+)/);
                if (masterMatch) currentIface.master = masterMatch[1];
                continue;
            }

            if (!currentIface) continue;

            const macMatch = line.match(/link\/ether\s+([0-9a-f:]+)/i);
            if (macMatch) {
                currentIface.mac = macMatch[1];
            }
        }
    },

    // =====================================================================
    // Parse ethtool -i output (driver info)
    // =====================================================================
    parseEthtoolI: function(content, result, ifaceName) {
        const iface = this._ensureIface(result, ifaceName);
        const body = content.trim();

        if (/Cannot get driver|not supported/i.test(body)) return;

        result.found = true;
        const driverMatch = body.match(/^driver:\s*(\S+)/m);
        if (driverMatch) {
            iface.driver = driverMatch[1];
            const info = classifyDriver(driverMatch[1]);
            iface.driverInfo = info.label;
            iface.accelNet = info.accelNet;
        }

        const fwMatch = body.match(/^firmware-version:\s*(.+)/m);
        if (fwMatch && fwMatch[1].trim() !== 'N/A' && fwMatch[1].trim()) {
            iface.firmwareVersion = fwMatch[1].trim();
        }

        const busMatch = body.match(/^bus-info:\s*(\S+)/m);
        if (busMatch && busMatch[1].trim()) {
            iface.busInfo = busMatch[1].trim();
        }

        result.raw['ethtool -i ' + ifaceName] = body;
    },

    // =====================================================================
    // Parse ifcfg-<iface> files (RHEL/SUSE style)
    // =====================================================================
    parseIfcfg: function(content, result, ifaceName) {
        if (ifaceName === 'lo' || ifaceName === 'template') return;

        const iface = this._ensureIface(result, ifaceName);
        result.found = true;

        // Clean SCC header lines
        const body = content.replace(/^#==\[.*?\]===.*$/gm, '').replace(/^#\s+\/etc\/.*$/gm, '').trim();

        const getVal = (key) => {
            const m = body.match(new RegExp('^' + key + "\\s*=\\s*['\"]?([^'\"\\n]*)", 'm'));
            return m ? m[1].trim() : null;
        };

        const bootproto = getVal('BOOTPROTO');
        if (bootproto) {
            iface.bootproto = bootproto.toLowerCase();
        }

        const ipaddr = getVal('IPADDR');
        if (ipaddr && iface.bootproto !== 'dhcp') {
            const prefix = getVal('PREFIX') || getVal('PREFIXLEN');
            const netmask = getVal('NETMASK');
            let addr = ipaddr;
            if (prefix) addr += '/' + prefix;
            else if (netmask) addr += ' netmask ' + netmask;
            // Only add if not already present from ip addr
            if (!iface.ipv4.some(a => a.address.startsWith(ipaddr))) {
                iface.ipv4.push({ address: addr, scope: 'global', source: 'ifcfg' });
            }
        }

        const device = getVal('DEVICE');
        if (device && device !== ifaceName) {
            // ifcfg file for a different device name
            iface.configDevice = device;
        }

        result.raw['ifcfg-' + ifaceName] = body;
    },

    // =====================================================================
    // Parse nmcli con show id <connection> output
    // =====================================================================
    parseNmcliConShow: function(content, result, connName) {
        const body = content.trim();
        if (!body) return;

        // Find the interface name
        const ifNameMatch = body.match(/^connection\.interface-name:\s+(\S+)/m);
        if (!ifNameMatch) return;

        const ifaceName = ifNameMatch[1];
        const iface = this._ensureIface(result, ifaceName);
        result.found = true;

        // Check for DHCP vs manual (static)
        const methodMatch = body.match(/^ipv4\.method:\s+(\S+)/m);
        if (methodMatch) {
            const method = methodMatch[1].toLowerCase();
            if (method === 'auto') iface.bootproto = 'dhcp';
            else if (method === 'manual') iface.bootproto = 'static';
            else iface.bootproto = method;
        }

        result.raw['nmcli con show ' + connName] = body;
    },

    // =====================================================================
    // Parse wicked ifstatus output (SUSE)
    // =====================================================================
    parseWickedIfstatus: function(content, result) {
        const lines = content.split('\n');
        let currentIface = null;

        for (const line of lines) {
            // Interface header: "eth0              up"
            const ifaceMatch = line.match(/^(\S+)\s+(up|down|setup-in-progress|enslaved)/);
            if (ifaceMatch && !line.startsWith(' ')) {
                const name = ifaceMatch[1];
                if (name === 'lo') { currentIface = null; continue; }
                currentIface = this._ensureIface(result, name);
                result.found = true;
                currentIface.state = ifaceMatch[2] === 'up' ? 'UP' : ifaceMatch[2].toUpperCase();
                continue;
            }

            if (!currentIface) continue;

            // Leases line: "      leases:   ipv4 dhcp granted"
            const leaseMatch = line.match(/leases:\s+ipv4\s+(\S+)/);
            if (leaseMatch) {
                const leaseType = leaseMatch[1].toLowerCase();
                if (leaseType === 'dhcp') currentIface.bootproto = 'dhcp';
                else if (leaseType === 'static') currentIface.bootproto = 'static';
            }
        }
    },

    // =====================================================================
    // Parse netplan YAML (Ubuntu)
    // =====================================================================
    parseNetplan: function(content, result, filename) {
        result.raw['netplan: ' + filename.split('/').pop()] = content.trim();

        // Simple YAML parsing for dhcp4/addresses
        const lines = content.split('\n');
        let currentIface = null;
        let inEthernets = false;

        for (const line of lines) {
            if (/^\s*ethernets:/.test(line)) { inEthernets = true; continue; }
            if (inEthernets && /^\s{4}(\w+):/.test(line)) {
                const m = line.match(/^\s{4}(\w+):/);
                if (m) {
                    currentIface = this._ensureIface(result, m[1]);
                    result.found = true;
                }
                continue;
            }
            if (!currentIface) continue;
            if (/^\s*dhcp4:\s*(true|yes)/i.test(line)) { currentIface.bootproto = 'dhcp'; }
            if (/^\s*dhcp4:\s*(false|no)/i.test(line)) { currentIface.bootproto = 'static'; }
            // Reset if we've left the section
            if (/^\S/.test(line) && !/^#/.test(line)) { inEthernets = false; currentIface = null; }
        }
    },

    // =====================================================================
    // Parse cloud-init ci-info net device tables from log files
    // Supports both syslog format (messages) and plain format (cloud-init-output.log)
    // If multiple boot cycles exist, only the LAST ci-info block is used.
    // =====================================================================
    parseCloudInitCiInfo: function(content, result, filename) {
        netIfDebugLog('[networkInterfaces] Parsing cloud-init ci-info from:', filename);

        // Find all "Net device info" blocks – take the last one
        // Each block entry stores { text, lineNumber } for provenance tracking
        const blocks = [];
        const lines = content.split('\n');
        let inBlock = false;
        let currentBlock = [];

        for (let lineIdx = 0; lineIdx < lines.length; lineIdx++) {
            const line = lines[lineIdx];
            if (/ci-info:.*Net device info/i.test(line)) {
                inBlock = true;
                currentBlock = [];
                continue;
            }
            if (inBlock) {
                if (/ci-info:.*\|/.test(line)) {
                    currentBlock.push({ text: line, lineNumber: lineIdx + 1 });
                } else if (/ci-info:.*Route\s+(IPv[46])\s+info/i.test(line)) {
                    // Route table follows device table – stop collecting device rows
                    if (currentBlock.length > 0) blocks.push([...currentBlock]);
                    inBlock = false;
                } else if (/ci-info:.*\+[-+]+\+/.test(line)) {
                    // Separator line (e.g. +--------+------+--...) – skip but stay in block
                    continue;
                } else {
                    // Non-ci-info line or end of block
                    if (currentBlock.length > 0) blocks.push([...currentBlock]);
                    inBlock = false;
                }
            }
        }
        // Capture last block if still in progress
        if (inBlock && currentBlock.length > 0) blocks.push(currentBlock);

        if (blocks.length === 0) return;

        // Use the last block (latest boot cycle)
        const lastBlock = blocks[blocks.length - 1];
        netIfDebugLog('[networkInterfaces] Found', blocks.length, 'cloud-init ci-info blocks, using the last one with', lastBlock.length, 'rows');

        // Parse header row to find column indices
        const headerEntry = lastBlock.find(e => /Device/.test(e.text));
        if (!headerEntry) return;

        // Extract the ci-info table portion after the ci-info: prefix
        const extractRow = (line) => {
            const m = line.match(/ci-info:\s*\|(.+)\|/);
            if (!m) return null;
            return m[1].split('|').map(c => c.trim());
        };

        const headerCols = extractRow(headerEntry.text);
        if (!headerCols) return;

        const colIdx = {};
        headerCols.forEach((col, i) => {
            const lc = col.toLowerCase().replace(/[-_\s]+/g, '');
            if (lc === 'device') colIdx.device = i;
            else if (lc === 'up') colIdx.up = i;
            else if (lc === 'address') colIdx.address = i;
            else if (lc === 'mask') colIdx.mask = i;
            else if (lc === 'scope') colIdx.scope = i;
            else if (lc === 'hwaddress') colIdx.hwaddress = i;
        });

        if (colIdx.device === undefined || colIdx.address === undefined) return;

        // Parse data rows (skip header row)
        for (const entry of lastBlock) {
            if (/Device/.test(entry.text)) continue;  // skip header
            const cols = extractRow(entry.text);
            if (!cols) continue;

            const device = cols[colIdx.device];
            if (!device || device === '.' || device === 'lo') continue;

            const address = cols[colIdx.address] || '.';
            const mask = colIdx.mask !== undefined ? (cols[colIdx.mask] || '.') : '.';
            const scope = colIdx.scope !== undefined ? (cols[colIdx.scope] || '.') : '.';
            const hwAddr = colIdx.hwaddress !== undefined ? (cols[colIdx.hwaddress] || '.') : '.';

            // Skip rows with no useful address
            if (address === '.' || address === '') continue;

            const iface = this._ensureIface(result, device);
            result.found = true;

            // Set MAC if available
            if (hwAddr && hwAddr !== '.' && !iface.mac) {
                iface.mac = hwAddr;
            }

            // Set state to UP
            if (colIdx.up !== undefined) {
                const up = cols[colIdx.up];
                if (up && up.toLowerCase() === 'true') iface.state = 'UP';
            }

            // Source provenance for this IP entry
            const ipSource = {
                source: 'cloud-init',
                sourceFile: filename,
                lineNumber: entry.lineNumber
            };

            // Classify and add address
            const isIPv6 = address.includes(':') && !address.startsWith('127.');
            if (isIPv6) {
                const addr = address.includes('/') ? address : address;
                if (!iface.ipv6.some(a => a.address === addr)) {
                    iface.ipv6.push({ address: addr, scope: scope !== '.' ? scope : 'link', ...ipSource });
                }
            } else {
                // IPv4 — combine with mask
                let addr = address;
                if (mask && mask !== '.') {
                    // Convert dotted mask to CIDR prefix if possible
                    const cidr = mask.split('.').reduce((acc, octet) => acc + (parseInt(octet) >>> 0).toString(2).replace(/0/g, '').length, 0);
                    addr = address + '/' + cidr;
                }
                if (!iface.ipv4.some(a => a.address.startsWith(address))) {
                    iface.ipv4.push({ address: addr, scope: scope !== '.' ? scope : 'global', ...ipSource });
                }
            }
        }
    },

    // =====================================================================
    // Determine if any interface has accelerated networking
    // =====================================================================
    hasAcceleratedNetworking: function(result) {
        return Object.values(result.interfaces).some(i => i.accelNet);
    },

    // =====================================================================
    // Get the accelerated networking linked interface for a primary
    // =====================================================================
    getAccelNetLinked: function(result, masterName) {
        return Object.values(result.interfaces).find(
            i => i.master === masterName && i.accelNet
        );
    },

    // =====================================================================
    // Merge two result objects (for multi-file handling)
    // =====================================================================
    mergeResults: function(existing, incoming) {
        existing.found = existing.found || incoming.found;

        for (const [name, iface] of Object.entries(incoming.interfaces)) {
            if (!existing.interfaces[name]) {
                existing.interfaces[name] = iface;
            } else {
                const e = existing.interfaces[name];
                // Merge fields: keep non-null values
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
                // Merge IPs (deduplicate by address)
                for (const ip of iface.ipv4) {
                    if (!e.ipv4.some(a => a.address === ip.address)) e.ipv4.push(ip);
                }
                for (const ip of iface.ipv6) {
                    if (!e.ipv6.some(a => a.address === ip.address)) e.ipv6.push(ip);
                }
            }
        }

        Object.assign(existing.raw, incoming.raw);
    }
};
