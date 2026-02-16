/**
 * @module parsers/networking
 * @description Networking and Firewall Parsers for RCA Tool
 *
 * Provides the `firewallRulesParser`, a multi-file parser that detects and
 * extracts firewall configuration from both SCC (supportconfig) and SOS
 * (sosreport) archives.  It classifies the active firewall technology and
 * surfaces individual rule sets for display in the web UI.
 *
 * ### Firewall Technologies Detected
 *
 * | Technology | Detection Method | Data Collected |
 * |------------|-----------------|----------------|
 * | firewalld  | systemctl status, `firewall-cmd --state` | Zones, direct rules, passthroughs, chains, log-denied policy, backend (iptables/nftables) |
 * | nftables   | `nft list ruleset`, `nft list tables` | Full ruleset, table list |
 * | iptables   | `iptables -L` sections in SCC | Rule chains, module load status |
 * | ip6tables  | `ip6tables -L` sections in SCC | Rule chains, module load status |
 * | ebtables   | `/etc/sysconfig/ebtables-config` | Sysconfig content |
 *
 * ### Source File Layouts
 *
 * | Report Type | Files Consumed |
 * |-------------|---------------|
 * | SCC         | `network.txt` (aggregated, section-delimited with `#==[ Command ]===`) |
 * | SOS         | `sos_commands/firewalld/*` (firewall-cmd outputs) |
 * | SOS         | `sos_commands/firewall_tables/*` (nft list ruleset, modinfo) |
 * | SOS / SCC   | `etc/sysconfig/iptables-config`, `ebtables-config`, `nftables.conf` |
 * | SOS / SCC   | `etc/firewalld/firewalld.conf` |
 *
 * ### Active Firewall Resolution
 *
 * `determineActiveFirewall()` returns one of `firewalld`, `nftables`,
 * `iptables`, `ip6tables`, or `none`, using this priority order:
 * 1. firewalld running
 * 2. nftables with a non-empty ruleset
 * 3. iptables with parsed rules
 * 4. ip6tables with parsed rules
 *
 * ### Return Shape (per-file call, merged by worker.js)
 *
 * ```
 * {
 *   found:           Boolean,
 *   firewalld:       { detected, running, config, zones, directRules, passthroughs, chains, logDenied, backend },
 *   iptables:        { detected, rules[], modules[] },
 *   ip6tables:       { detected, rules[], modules[] },
 *   ebtables:        { detected, config },
 *   nftables:        { detected, ruleset, tables },
 *   activeFirewall:  String,
 *   warnings:        String[],
 *   rawSections:     Object          // keyed by human-readable section name
 * }
 * ```
 *
 * ### Key Internal Methods
 *
 * | Method | Purpose |
 * |--------|---------|
 * | `parseSCCNetwork` | Walks the aggregated `network.txt` file, extracting firewalld status, iptables/ip6tables chains, and nftables rulesets |
 * | `parseFirewalldState` | Reads `firewall-cmd --state` output; sets `running` flag |
 * | `parseFirewalldZones` | Reads `--list-all-zones` output for runtime or permanent scope |
 * | `parseFirewalldDirect` | Reads `--direct --get-all-{rules,chains,passthroughs}` for both scopes |
 * | `parseFirewalldLogDenied` | Reads `--get-log-denied` policy value |
 * | `parseNftRuleset` | Reads `nft -a list ruleset` output |
 * | `parseFirewalldConf` | Parses `/etc/firewalld/firewalld.conf` key-value pairs; extracts `FirewallBackend` |
 * | `determineActiveFirewall` | Priority-based resolution of the active firewall technology |
 *
 * Helper function `extractSCCSections(content, headingFilter)` splits an SCC
 * aggregated file into `{ heading, body }` objects filtered by a predicate.
 */

// Debug logging – checks global DEBUG_CONFIG from worker.js
function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.networking) {
        console.log('[networking.js]', ...args);
    }
}

// ============================================================================
// Helper: extract all SCC sections between #==[ … ]===# markers that match
// a heading filter.  Returns an array of { heading, body } objects.
// ============================================================================
function extractSCCSections(content, headingFilter) {
    const sections = [];
    const lines = content.split('\n');
    let currentHeading = null;
    let currentBody = [];

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // Detect a new section header: #==[ Command ]===# or # /usr/sbin/nft …
        if (/^#==\[/.test(line)) {
            // Flush previous section
            if (currentHeading !== null) {
                sections.push({ heading: currentHeading, body: currentBody.join('\n') });
            }
            currentHeading = null;
            currentBody = [];
            continue;
        }

        // The line immediately after a #==[ header is the "# command" line
        if (currentHeading === null && /^#\s+/.test(line)) {
            currentHeading = line.replace(/^#\s+/, '').trim();
            continue;
        }

        if (currentHeading !== null) {
            currentBody.push(line);
        }
    }
    // Flush last section
    if (currentHeading !== null) {
        sections.push({ heading: currentHeading, body: currentBody.join('\n') });
    }

    // Filter by the caller's predicate
    return sections.filter(s => headingFilter(s.heading));
}

// ============================================================================
// firewallRulesParser
// ============================================================================
const firewallRulesParser = {
    // Match SCC network.txt, SOS firewalld/firewall_tables command outputs,
    // and relevant /etc/sysconfig or /etc/firewalld config files.
    filePattern: /(?:network\.txt$|sos_commands\/firewalld\/|sos_commands\/firewall_tables\/|etc\/sysconfig\/(?:iptables-config|ebtables-config|nftables\.conf|firewalld)$|etc\/firewalld\/firewalld\.conf$)/,
    multiFile: true,

    parse: function(content, filename) {
        debugLog('[firewallRules parser] Analyzing:', filename, '(', content.length, 'bytes)');

        // Accumulator – each call contributes; worker.js merges across files.
        const result = {
            found: false,
            // Per-firewall-type buckets
            firewalld: { detected: false, running: false, config: null, zones: null, directRules: null, passthroughs: null, chains: null, logDenied: null, backend: null },
            iptables: { detected: false, rules: [], modules: [] },
            ip6tables: { detected: false, rules: [], modules: [] },
            ebtables: { detected: false, config: null },
            nftables: { detected: false, ruleset: null, tables: null },
            // Summary helpers
            activeFirewall: 'none',
            warnings: [],
            rawSections: {}
        };

        // ----- Dispatch based on filename pattern -----

        if (/network\.txt$/.test(filename)) {
            this.parseSCCNetwork(content, result);
        } else if (/firewall-cmd_--state$/.test(filename)) {
            this.parseFirewalldState(content, result);
        } else if (/firewall-cmd_--list-all-zones$/.test(filename)) {
            this.parseFirewalldZones(content, result, 'runtime');
        } else if (/firewall-cmd_--permanent_--list-all-zones$/.test(filename)) {
            this.parseFirewalldZones(content, result, 'permanent');
        } else if (/firewall-cmd_--direct_--get-all-rules$/.test(filename)) {
            this.parseFirewalldDirect(content, result, 'rules', 'runtime');
        } else if (/firewall-cmd_--permanent_--direct_--get-all-rules$/.test(filename)) {
            this.parseFirewalldDirect(content, result, 'rules', 'permanent');
        } else if (/firewall-cmd_--direct_--get-all-chains$/.test(filename)) {
            this.parseFirewalldDirect(content, result, 'chains', 'runtime');
        } else if (/firewall-cmd_--permanent_--direct_--get-all-chains$/.test(filename)) {
            this.parseFirewalldDirect(content, result, 'chains', 'permanent');
        } else if (/firewall-cmd_--direct_--get-all-passthroughs$/.test(filename)) {
            this.parseFirewalldDirect(content, result, 'passthroughs', 'runtime');
        } else if (/firewall-cmd_--permanent_--direct_--get-all-passthroughs$/.test(filename)) {
            this.parseFirewalldDirect(content, result, 'passthroughs', 'permanent');
        } else if (/firewall-cmd_--get-log-denied$/.test(filename)) {
            this.parseFirewalldLogDenied(content, result);
        } else if (/nft_-a_list_ruleset$/.test(filename)) {
            this.parseNftRuleset(content, result);
        } else if (/etc\/sysconfig\/iptables-config$/.test(filename)) {
            result.iptables.detected = true;
            result.iptables.config = content.trim();
            result.rawSections['iptables-config'] = content.trim();
            result.found = true;
        } else if (/etc\/sysconfig\/ebtables-config$/.test(filename)) {
            result.ebtables.detected = true;
            result.ebtables.config = content.trim();
            result.rawSections['ebtables-config'] = content.trim();
            result.found = true;
        } else if (/etc\/sysconfig\/nftables\.conf$/.test(filename)) {
            result.nftables.detected = true;
            result.rawSections['nftables-sysconfig'] = content.trim();
            result.found = true;
        } else if (/etc\/firewalld\/firewalld\.conf$/.test(filename)) {
            this.parseFirewalldConf(content, result);
        } else if (/etc\/sysconfig\/firewalld$/.test(filename)) {
            result.firewalld.detected = true;
            result.rawSections['sysconfig-firewalld'] = content.trim();
            result.found = true;
        }

        // Determine the active firewall type
        result.activeFirewall = this.determineActiveFirewall(result);

        debugLog('[firewallRules parser] Result found:', result.found, 'active:', result.activeFirewall);
        return result;
    },

    // =====================================================================
    // SCC network.txt – aggregated file with section markers
    // =====================================================================
    parseSCCNetwork: function(content, result) {
        debugLog('[firewallRules parser] Parsing SCC network.txt');

        // --- firewalld status ---
        const fwSections = extractSCCSections(content, h =>
            /firewalld\.service/.test(h) || /firewall-cmd/.test(h)
        );
        for (const sec of fwSections) {
            result.firewalld.detected = true;
            result.found = true;

            if (/systemctl status firewalld/.test(sec.heading)) {
                const running = /Active:\s+active\s+\(running\)/.test(sec.body);
                const inactive = /Active:\s+inactive/.test(sec.body);
                result.firewalld.running = running;
                result.rawSections['firewalld-status'] = sec.body.trim();
                if (inactive) {
                    result.warnings.push('firewalld is installed but inactive (dead)');
                }
            }
            if (/firewall-cmd\s+--list-all/.test(sec.heading)) {
                if (/FirewallD is not running/i.test(sec.body)) {
                    result.firewalld.running = false;
                } else {
                    result.firewalld.running = true;
                    result.firewalld.zones = sec.body.trim();
                }
                result.rawSections['firewall-cmd --list-all'] = sec.body.trim();
            }
        }

        // --- iptables / ip6tables ---
        const iptSections = extractSCCSections(content, h =>
            /^iptables\b/.test(h) || /^ip6tables\b/.test(h)
        );
        for (const sec of iptSections) {
            const isV6 = /^ip6tables/.test(sec.heading);
            const bucket = isV6 ? result.ip6tables : result.iptables;
            bucket.detected = true;
            result.found = true;

            const body = sec.body.trim();
            if (/module is not loaded/i.test(body)) {
                // Module not loaded – record the note
                const modMatch = body.match(/The\s+(\S+)\s+module is not loaded/i);
                bucket.modules.push({
                    module: modMatch ? modMatch[1] : 'unknown',
                    loaded: false,
                    note: body
                });
            } else if (body.length > 0) {
                // Actual rules output
                bucket.rules.push({ heading: sec.heading, raw: body });
            }
            result.rawSections[sec.heading] = body;
        }

        // --- nftables ---
        const nftSections = extractSCCSections(content, h =>
            /nft\b/.test(h) || /nftables/.test(h)
        );
        for (const sec of nftSections) {
            result.nftables.detected = true;
            result.found = true;
            const body = sec.body.trim();
            if (/nft list tables/.test(sec.heading)) {
                result.nftables.tables = body || '(empty)';
            }
            if (/nft.*list ruleset/.test(sec.heading)) {
                result.nftables.ruleset = body || '(empty)';
            }
            result.rawSections[sec.heading] = body;
        }
    },

    // =====================================================================
    // SOS: firewall-cmd --state
    // =====================================================================
    parseFirewalldState: function(content, result) {
        result.firewalld.detected = true;
        result.found = true;
        const trimmed = content.trim();
        result.firewalld.running = /^running$/im.test(trimmed);
        result.rawSections['firewall-cmd --state'] = trimmed;
        if (!result.firewalld.running) {
            result.warnings.push('firewalld is not running');
        }
    },

    // =====================================================================
    // SOS: firewall-cmd --list-all-zones (runtime or permanent)
    // =====================================================================
    parseFirewalldZones: function(content, result, scope) {
        result.firewalld.detected = true;
        result.found = true;
        const trimmed = content.trim();
        if (/FirewallD is not running/i.test(trimmed)) {
            result.firewalld.running = false;
        } else if (trimmed.length > 0) {
            if (scope === 'runtime') {
                result.firewalld.zones = trimmed;
            }
            // We store both for raw display
            result.rawSections[`firewall-cmd --${scope === 'permanent' ? 'permanent --' : ''}list-all-zones`] = trimmed;
        }
    },

    // =====================================================================
    // SOS: firewall-cmd --direct --get-all-{rules|chains|passthroughs}
    // =====================================================================
    parseFirewalldDirect: function(content, result, type, scope) {
        result.firewalld.detected = true;
        result.found = true;
        const trimmed = content.trim();
        const key = `firewall-cmd --${scope === 'permanent' ? 'permanent --' : ''}direct --get-all-${type}`;
        result.rawSections[key] = trimmed;

        if (/FirewallD is not running/i.test(trimmed)) {
            result.firewalld.running = false;
            return;
        }
        if (trimmed.length > 0) {
            if (type === 'rules') result.firewalld.directRules = (result.firewalld.directRules || '') + '\n[' + scope + '] ' + trimmed;
            if (type === 'chains') result.firewalld.chains = (result.firewalld.chains || '') + '\n[' + scope + '] ' + trimmed;
            if (type === 'passthroughs') result.firewalld.passthroughs = (result.firewalld.passthroughs || '') + '\n[' + scope + '] ' + trimmed;
        }
    },

    // =====================================================================
    // SOS: firewall-cmd --get-log-denied
    // =====================================================================
    parseFirewalldLogDenied: function(content, result) {
        result.firewalld.detected = true;
        result.found = true;
        const trimmed = content.trim();
        result.rawSections['firewall-cmd --get-log-denied'] = trimmed;
        if (!/FirewallD is not running/i.test(trimmed)) {
            result.firewalld.logDenied = trimmed;
        }
    },

    // =====================================================================
    // SOS: nft -a list ruleset
    // =====================================================================
    parseNftRuleset: function(content, result) {
        result.nftables.detected = true;
        result.found = true;
        const trimmed = content.trim();
        result.nftables.ruleset = trimmed || '(empty)';
        result.rawSections['nft -a list ruleset'] = trimmed;
    },

    // =====================================================================
    // /etc/firewalld/firewalld.conf
    // =====================================================================
    parseFirewalldConf: function(content, result) {
        result.firewalld.detected = true;
        result.found = true;
        result.rawSections['firewalld.conf'] = content.trim();

        // Extract key settings
        const config = {};
        const lines = content.split('\n');
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            const match = trimmed.match(/^(\w+)\s*=\s*(.+)$/);
            if (match) {
                config[match[1]] = match[2].trim();
            }
        }
        result.firewalld.config = config;
        result.firewalld.backend = config.FirewallBackend || null;
    },

    // =====================================================================
    // Determine the "active" firewall type
    // =====================================================================
    determineActiveFirewall: function(result) {
        // Priority: firewalld running > nftables with rules > iptables with rules > none
        if (result.firewalld.running) return 'firewalld';

        const nftHasRules = result.nftables.ruleset &&
            result.nftables.ruleset !== '(empty)' &&
            result.nftables.ruleset.length > 10;
        if (nftHasRules) return 'nftables';

        const iptHasRules = result.iptables.rules.length > 0;
        if (iptHasRules) return 'iptables';

        const ip6tHasRules = result.ip6tables.rules.length > 0;
        if (ip6tHasRules) return 'ip6tables';

        return 'none';
    }
};
