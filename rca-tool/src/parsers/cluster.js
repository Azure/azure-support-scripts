/**
 * @module parsers/cluster
 * @description Cluster Parsers for RCA Tool
 *
 * Provides 17 parsers for analysing Linux HA cluster configurations
 * collected in SCC (supportconfig) and SOS (sosreport) archives.
 * Coverage spans Corosync transport and quorum, Pacemaker resources and
 * constraints, STONITH/SBD fencing, iSCSI targets, SAP Instance resources,
 * Azure fence agent authentication, and cluster event timelines.
 *
 * ### Parser Inventory
 *
 * #### Core Cluster
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `corosyncConfigParser` | `ha.txt`, `corosync.conf` | Validates totem token/transport and quorum settings (two_node, expected_votes) |
 * | `clusterNodesParser` | `ha.txt`, `pacemaker.log`, `corosync.conf`, `cib.xml`, `crm_mon*.txt` | Discovers node names and node-to-IP mappings from CIB, corosync nodelist, or crm_mon |
 * | `hostsFileParser` | `network.txt`, `etc/hosts` | Extracts IP-to-hostname mappings from `/etc/hosts` |
 * | `corosyncStatusParser` | `corosync-cfgtool*-s` | Parses runtime ring/link health, local node ID, and transport type |
 * | `clusterStatusParser` | `cib.xml`, `crm_mon*.txt`, `ha.txt`, `pcs_status` | DC node, quorum, node count, per-node online/offline status |
 * | `clusterDaemonStatusParser` | `pcs_status`, `ha.txt` | Checks corosync, pacemaker, pcsd daemon active/enabled status |
 * | `clusterMaintenanceModeParser` | `cib.xml`, `crm_mon*.txt`, `ha.txt` | Detects cluster-wide or per-resource maintenance mode |
 *
 * #### Resources and Constraints
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `pacemakerResourcesParser` | `cib.xml`, `crm_mon*.txt`, `crm*config`, `pcs_config`, `pcs_status`, `ha.txt` | Resource definitions, clone/group membership, location/colocation/order constraints |
 * | `azureScheduledEventsParser` | `pcs_status`, `crm_mon*`, `cib.xml` | Detects `health-azure` resource and per-node health monitoring attribute |
 *
 * #### Fencing and SBD
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `fencingConfigParser` | `cib.xml`, `crm_mon*.txt`, `crm*config`, `stonith`, `ha.txt`, `pcs_config`, `pcs_property` | STONITH device list, fence agent parameters, stonith-enabled property |
 * | `sbdConfigParser` | `sbd`, `sysconfig/sbd`, `ha.txt` | SBD device paths, watchdog settings, pacemaker integration, timeout action |
 * | `azureFenceAuthParser` | `cib.xml`, `ha.txt`, `crm*config` | `fence_azure_arm` auth method (MSI vs service principal), subscription/tenant, pcmk delays |
 *
 * #### Events and Live Migration
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `clusterEventsParser` | `pacemaker.log`, `corosync.log`, `messages`, `journalctl*` | **Multi-file**: accumulates node join/leave, resource failover, fencing actions across rotated logs |
 * | `liveMigrationParser` | `pacemaker.log`, `corosync.log`, `messages`, `localmessages` | Detects Hyper-V Live Migration by matching hv_utils/hv_balloon/hv_netvsc sequence within 100 lines |
 *
 * #### SAP
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `sapInstanceConfigParser` | `pcs_config`, `cib.xml` | SAP Instance resource definitions: instance name, start profile, ERS flag, auto-recover |
 * | `sapInstanceErrorsParser` | `analysis.txt`, `cluster-log.txt`, `messages` | START_PROFILE failures, gray/undefined resource states, filesystem errors |
 *
 * #### iSCSI
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `iscsiConfigParser` | `fs-iscsi.txt`, `iscsi/`, `iscsiadm`, `ha.txt`, `initiatorname.iscsi` | Initiator name, targets, sessions, hosts, startup mode, iscsid.conf settings |
 *
 * ### Multi-File Handling
 *
 * Only `clusterEventsParser` sets `multiFile: true` with `processAllRotations`
 * to accumulate events across rotated log files. All other parsers process
 * individual files independently.
 *
 * ### Common Dependencies
 *
 * Most parsers rely on `SCC_RULES.extractSection(content, filename, marker,
 * fallbackFilename)` from worker.js to locate command output sections within
 * aggregated SCC files like `ha.txt`.
 */

// Debug logging - checks global DEBUG_CONFIG from worker.js
function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.cluster) {
        console.log('[cluster.js]', ...args);
    }
}

// Export individual parser objects
const corosyncConfigParser = {
    // Target file path patterns
    // supportconfig: */ha.txt (contains embedded corosync.conf)
    // sosreport: */etc/corosync/corosync.conf
    filePattern: /\/(ha\.txt|corosync\.conf)$/,
    
    // Parse function receives file content as string
    // Handles two formats:
    // 1. supportconfig: ha.txt with embedded corosync.conf section
    // 2. sosreport: direct corosync.conf file
    // Extracts corosync.conf section and validates totem token parameter
    // Returns object with configuration and validation warnings
    parse: function(content, filename) {
        const warnings = [];
        let corosyncConf = null;
        let totemToken = null;
        let totemRetransmits = null;
        let totemJoin = null;
        let totemConsensus = null;
        let totemMaxMessages = null;
        let totemTransport = null;
        let quorumProvider = null;
        let quorumExpectedVotes = null;
        let quorumTwoNode = null;
        
        debugLog('[corosyncConfig parser] Analyzing for corosync.conf');
        
        // Extract the corosync.conf section
        const section = SCC_RULES.extractSection(content, filename, '# /etc/corosync/corosync.conf', 'corosync.conf');
        
        if (!section.found) {
            debugLog('[corosyncConfig parser] No corosync.conf found');
            return {
                found: false,
                warnings: []
            };
        }
        
        debugLog('[corosyncConfig parser] Extracted', section.lines.length, 'lines from corosync.conf');
        corosyncConf = section.content;
        const corosyncLines = section.lines;
        
        // Parse both totem and quorum blocks in a single pass
        let inTotemBlock = false;
        let inQuorumBlock = false;
        let totemBraceDepth = 0;
        let quorumBraceDepth = 0;
        
        for (let i = 0; i < corosyncLines.length; i++) {
            const line = corosyncLines[i].trim();
            
            // Detect totem block start
            if (!inTotemBlock && line.startsWith('totem')) {
                inTotemBlock = true;
                debugLog('[corosyncConfig parser] Found totem block at line', i + 1);
            }
            
            // Detect quorum block start
            if (!inQuorumBlock && line.startsWith('quorum')) {
                inQuorumBlock = true;
                debugLog('[corosyncConfig parser] *** Found quorum block at line', i + 1, 'line content:', line);
            }
            
            // Parse totem block
            if (inTotemBlock) {
                // Track brace depth
                totemBraceDepth += (line.match(/{/g) || []).length;
                totemBraceDepth -= (line.match(/}/g) || []).length;
                
                // Look for token parameter
                const tokenMatch = line.match(/^\s*token\s*:\s*(\d+)/);
                if (tokenMatch) {
                    totemToken = parseInt(tokenMatch[1], 10);
                    debugLog('[corosyncConfig parser] Found token value:', totemToken);
                }
                
                // Look for token_retransmits_before_loss_const parameter
                const retransmitsMatch = line.match(/^\s*token_retransmits_before_loss_const\s*:\s*(\d+)/);
                if (retransmitsMatch) {
                    totemRetransmits = parseInt(retransmitsMatch[1], 10);
                    debugLog('[corosyncConfig parser] Found token_retransmits_before_loss_const value:', totemRetransmits);
                }
                
                // Look for join parameter
                const joinMatch = line.match(/^\s*join\s*:\s*(\d+)/);
                if (joinMatch) {
                    totemJoin = parseInt(joinMatch[1], 10);
                    debugLog('[corosyncConfig parser] Found join value:', totemJoin);
                }
                
                // Look for consensus parameter
                const consensusMatch = line.match(/^\s*consensus\s*:\s*(\d+)/);
                if (consensusMatch) {
                    totemConsensus = parseInt(consensusMatch[1], 10);
                    debugLog('[corosyncConfig parser] Found consensus value:', totemConsensus);
                }
                
                // Look for max_messages parameter
                const maxMessagesMatch = line.match(/^\s*max_messages\s*:\s*(\d+)/);
                if (maxMessagesMatch) {
                    totemMaxMessages = parseInt(maxMessagesMatch[1], 10);
                    debugLog('[corosyncConfig parser] Found max_messages value:', totemMaxMessages);
                }
                
                // Look for transport parameter (string value)
                const transportMatch = line.match(/^\s*transport\s*:\s*(\w+)/);
                if (transportMatch) {
                    totemTransport = transportMatch[1];
                    debugLog('[corosyncConfig parser] Found transport value:', totemTransport);
                }
                
                // Exit totem block when braces balance
                if (totemBraceDepth === 0 && line.includes('}')) {
                    inTotemBlock = false;
                    debugLog('[corosyncConfig parser] Exited totem block at line', i + 1);
                }
            }
            
            // Parse quorum block
            if (inQuorumBlock) {
                // Track brace depth
                quorumBraceDepth += (line.match(/{/g) || []).length;
                quorumBraceDepth -= (line.match(/}/g) || []).length;
                
                debugLog('[corosyncConfig parser] Quorum line', i + 1, ':', line, 'depth:', quorumBraceDepth);
                
                // Look for provider parameter
                const providerMatch = line.match(/^\s*provider\s*:\s*(\w+)/);
                if (providerMatch) {
                    quorumProvider = providerMatch[1];
                    debugLog('[corosyncConfig parser] Found provider value:', quorumProvider);
                }
                
                // Look for expected_votes parameter
                const expectedVotesMatch = line.match(/^\s*expected_votes\s*:\s*(\d+)/);
                if (expectedVotesMatch) {
                    quorumExpectedVotes = parseInt(expectedVotesMatch[1], 10);
                    debugLog('[corosyncConfig parser] Found expected_votes value:', quorumExpectedVotes);
                }
                
                // Look for two_node parameter
                const twoNodeMatch = line.match(/^\s*two_node\s*:\s*(\d+)/);
                if (twoNodeMatch) {
                    quorumTwoNode = parseInt(twoNodeMatch[1], 10);
                    debugLog('[corosyncConfig parser] Found two_node value:', quorumTwoNode);
                }
                
                // Exit quorum block when braces balance
                if (quorumBraceDepth === 0 && line.includes('}')) {
                    inQuorumBlock = false;
                    debugLog('[corosyncConfig parser] Exited quorum block at line', i + 1);
                }
            }
        }
        
        // Log summary of parsed values
        debugLog('[corosyncConfig parser] === PARSING SUMMARY ===');
        debugLog('[corosyncConfig parser] Totem values:', {
            token: totemToken,
            retransmits: totemRetransmits,
            join: totemJoin,
            consensus: totemConsensus,
            maxMessages: totemMaxMessages,
            transport: totemTransport
        });
        debugLog('[corosyncConfig parser] Quorum values:', {
            provider: quorumProvider,
            expectedVotes: quorumExpectedVotes,
            twoNode: quorumTwoNode
        });
        
        // Validate token parameter
        if (totemToken !== null) {
            if (totemToken !== 30000) {
                warnings.push({
                    parameter: 'totem.token',
                    expected: 30000,
                    actual: totemToken,
                    severity: 'warning',
                    message: `Totem token value is ${totemToken}, but should be 30000 for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: token value is', totemToken, 'instead of 30000');
            }
        } else {
            debugLog('[corosyncConfig parser] No token value found in totem block');
        }
        
        // Validate token_retransmits_before_loss_const value
        if (totemRetransmits !== null) {
            if (totemRetransmits !== 10) {
                warnings.push({
                    parameter: 'totem.token_retransmits_before_loss_const',
                    expected: 10,
                    actual: totemRetransmits,
                    severity: 'warning',
                    message: `Totem token_retransmits_before_loss_const value is ${totemRetransmits}, but should be 10 for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: token_retransmits_before_loss_const value is', totemRetransmits, 'instead of 10');
            }
        } else {
            debugLog('[corosyncConfig parser] No token_retransmits_before_loss_const value found in totem block');
        }
        
        // Validate join value
        if (totemJoin !== null) {
            if (totemJoin !== 60) {
                warnings.push({
                    parameter: 'totem.join',
                    expected: 60,
                    actual: totemJoin,
                    severity: 'warning',
                    message: `Totem join value is ${totemJoin}, but should be 60 for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: join value is', totemJoin, 'instead of 60');
            }
        } else {
            debugLog('[corosyncConfig parser] No join value found in totem block');
        }
        
        // Validate consensus value
        if (totemConsensus !== null) {
            if (totemConsensus !== 36000) {
                warnings.push({
                    parameter: 'totem.consensus',
                    expected: 36000,
                    actual: totemConsensus,
                    severity: 'warning',
                    message: `Totem consensus value is ${totemConsensus}, but should be 36000 for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: consensus value is', totemConsensus, 'instead of 36000');
            }
        } else {
            debugLog('[corosyncConfig parser] No consensus value found in totem block');
        }
        
        // Validate max_messages value
        if (totemMaxMessages !== null) {
            if (totemMaxMessages !== 20) {
                warnings.push({
                    parameter: 'totem.max_messages',
                    expected: 20,
                    actual: totemMaxMessages,
                    severity: 'warning',
                    message: `Totem max_messages value is ${totemMaxMessages}, but should be 20 for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: max_messages value is', totemMaxMessages, 'instead of 20');
            }
        } else {
            debugLog('[corosyncConfig parser] No max_messages value found in totem block');
        }
        
        // Validate transport value
        if (totemTransport !== null) {
            if (totemTransport !== 'udpu') {
                warnings.push({
                    parameter: 'totem.transport',
                    expected: 'udpu',
                    actual: totemTransport,
                    severity: 'warning',
                    message: `Totem transport value is '${totemTransport}', but should be 'udpu' for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: transport value is', totemTransport, 'instead of udpu');
            }
        } else {
            debugLog('[corosyncConfig parser] No transport value found in totem block');
        }
        
        // Validate quorum provider value
        if (quorumProvider !== null) {
            if (quorumProvider !== 'corosync_votequorum') {
                warnings.push({
                    parameter: 'quorum.provider',
                    expected: 'corosync_votequorum',
                    actual: quorumProvider,
                    severity: 'warning',
                    message: `Quorum provider value is '${quorumProvider}', but should be 'corosync_votequorum' for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: provider value is', quorumProvider, 'instead of corosync_votequorum');
            }
        } else {
            debugLog('[corosyncConfig parser] No provider value found in quorum block');
        }
        
        // Validate quorum expected_votes value
        if (quorumExpectedVotes !== null) {
            if (quorumExpectedVotes !== 2) {
                warnings.push({
                    parameter: 'quorum.expected_votes',
                    expected: 2,
                    actual: quorumExpectedVotes,
                    severity: 'warning',
                    message: `Quorum expected_votes value is ${quorumExpectedVotes}, but should be 2 for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: expected_votes value is', quorumExpectedVotes, 'instead of 2');
            }
        } else {
            debugLog('[corosyncConfig parser] No expected_votes value found in quorum block');
        }
        
        // Validate quorum two_node value
        if (quorumTwoNode !== null) {
            if (quorumTwoNode !== 1) {
                warnings.push({
                    parameter: 'quorum.two_node',
                    expected: 1,
                    actual: quorumTwoNode,
                    severity: 'warning',
                    message: `Quorum two_node value is ${quorumTwoNode}, but should be 1 for Azure environments`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                debugLog('[corosyncConfig parser] WARNING: two_node value is', quorumTwoNode, 'instead of 1');
            }
        } else {
            debugLog('[corosyncConfig parser] No two_node value found in quorum block');
        }
        
        return {
            found: true,
            totemToken: totemToken,
            totemRetransmits: totemRetransmits,
            totemJoin: totemJoin,
            totemConsensus: totemConsensus,
            totemMaxMessages: totemMaxMessages,
            totemTransport: totemTransport,
            quorumProvider: quorumProvider,
            quorumExpectedVotes: quorumExpectedVotes,
            quorumTwoNode: quorumTwoNode,
            warnings: warnings,
            configLength: corosyncLines.length
        };
    }
};

const clusterNodesParser = {
        // Target file path patterns
        // supportconfig: */ha.txt
        // sosreport: */pacemaker.log or */corosync.conf
        // hb_report/crm_report: */corosync.conf or */cib.xml or */crm_mon*.txt
        filePattern: /\/(ha\.txt|pacemaker\.log|corosync\.conf|cib\.xml|crm_mon.*\.txt)$/,
        
        // Parse function receives file content as string
        // Returns array of cluster node names and node-to-IP mapping
        parse: function(content) {
            const lines = content.split('\n');
            const nodeSet = new Set();
            const nodeToIpMap = {}; // Maps hostname to IP from corosync.conf
            
            // If content contains XML (CIB format), use XML parser for node extraction
            if (content.includes('<node') && (content.includes('<cib') || content.includes('uname='))) {
                debugLog('[clusterNodes parser] Detected XML format, using custom XML parser');
                const elements = parseXMLSimple(content);
                const nodes = querySelectorAll(elements, 'node');
                
                nodes.forEach(node => {
                    const attrs = node.attributes;
                    // Prioritize uname over id (uname is the actual hostname, id can be numeric)
                    if (attrs.uname) {
                        nodeSet.add(attrs.uname);
                    } else if (attrs.id && !attrs.id.match(/^\d+$/)) {
                        nodeSet.add(attrs.id);
                    }
                });
            }
            
            // Track if we're inside a nodelist block
            let inNodelist = false;
            let inNode = false;
            let depth = 0;
            let currentNodeName = null;
            let currentNodeRing0 = null;
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                const trimmed = line.trim();
                
                // Track nodelist block in corosync.conf
                if (trimmed.match(/^nodelist\s*\{/i)) {
                    inNodelist = true;
                    depth = 1;
                    debugLog('[clusterNodes parser] Entered nodelist block at line', i);
                    continue;
                }
                
                // Inside nodelist, track node blocks
                if (inNodelist) {
                    // Entering a node block
                    if (trimmed.match(/^node\s*\{/i)) {
                        inNode = true;
                        currentNodeName = null;
                        currentNodeRing0 = null;
                        debugLog('[clusterNodes parser] Entered node block at line', i);
                        depth++;
                        continue;
                    }
                    
                    // Inside a node block, look for name or ring0_addr
                    if (inNode) {
                        debugLog('[clusterNodes parser] Checking node line:', trimmed, 'depth:', depth);
                        
                        const nameMatch = trimmed.match(/^name:\s*([a-zA-Z][a-zA-Z0-9_\-\.]+)/i);
                        if (nameMatch) {
                            currentNodeName = nameMatch[1];
                            debugLog('[clusterNodes parser] Found node name:', currentNodeName);
                        }
                        
                        // Match ring0_addr - can be hostname or IP
                        const ring0Match = trimmed.match(/^ring0_addr:\s*(.+)$/i);
                        if (ring0Match) {
                            const addr = ring0Match[1].trim();
                            // Check if it's an IP address
                            if (addr.match(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) {
                                // It's an IP, store it for later lookup in hosts file
                                currentNodeRing0 = addr;
                                debugLog('[clusterNodes parser] Found node ring0_addr (IP):', currentNodeRing0);
                            } else if (addr.match(/^[a-zA-Z][a-zA-Z0-9_\-\.]+$/)) {
                                // It's a hostname
                                currentNodeRing0 = addr;
                                debugLog('[clusterNodes parser] Found node ring0_addr (hostname):', currentNodeRing0);
                            }
                        }
                        
                        // Exiting node block - check BEFORE decrementing depth
                        if (trimmed === '}') {
                            inNode = false;
                            depth--;
                            // Store the name-to-IP mapping if we have both
                            if (currentNodeName && currentNodeRing0 && currentNodeRing0.match(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) {
                                nodeToIpMap[currentNodeName] = currentNodeRing0;
                                debugLog('[clusterNodes parser] Mapped hostname to IP:', currentNodeName, '->', currentNodeRing0);
                            }
                            // For corosync.conf: always prefer name, and don't add IPs
                            // IPs will be added only from other sources (cib.xml, crm_mon) where we can get the actual node names
                            if (currentNodeName) {
                                nodeSet.add(currentNodeName);
                                debugLog('[clusterNodes parser] Added node from name:', currentNodeName);
                            }
                            // Note: We intentionally don't add ring0_addr (IP) here anymore
                            // The IP mapping is preserved in nodeToIpMap for validation purposes
                            continue;
                        }
                    }
                    
                    // Check for other braces (not node blocks)
                    if (trimmed === '}') {
                        depth--;
                    } else if (trimmed.endsWith('{')) {
                        depth++;
                    }
                    
                    // Exiting nodelist block
                    if (depth === 0) {
                        inNodelist = false;
                        debugLog('[clusterNodes parser] Exited nodelist block at line', i);
                    }
                    continue;
                }
                
                // Pattern 1: "node X" or "node: X" in cluster configuration
                const nodeMatch = trimmed.match(/^node[:\s]+([a-zA-Z][a-zA-Z0-9_\-\.]+)/i);
                if (nodeMatch) {
                    nodeSet.add(nodeMatch[1]);
                    continue;
                }
                
                // Pattern 2: crm_mon style "Node hostname: online" or "* Node hostname (id):"
                const crmNodeMatch = trimmed.match(/(?:\*\s+)?Node\s+([a-zA-Z0-9][a-zA-Z0-9_\-\.]+)(?:\s+\(|:)/i);
                if (crmNodeMatch) {
                    nodeSet.add(crmNodeMatch[1]);
                    continue;
                }
                
                // Pattern 3: Simple "name: hostname" (not inside nodelist)
                if (trimmed.match(/^\s*name:/i)) {
                    const nameMatch = trimmed.match(/name:\s*([a-zA-Z0-9][a-zA-Z0-9_\-\.]+)/i);
                    if (nameMatch && !nameMatch[1].match(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/)) {
                        nodeSet.add(nameMatch[1]);
                    }
                }
            }
            
            // Filter out common false positives
            const excluded = [
                'online', 'offline', 'standby', 'maintenance', 'pending', 'unclean',
                'node', 'nodes', 'cluster', 'member', 'members', 'list', 'attributes',
                'stonith', 'fencing', 'resource', 'resources', 'status'
            ];
            
            const filteredNodes = Array.from(nodeSet).filter(n => {
                // Allow IP addresses
                if (n.match(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) return true;
                // Must start with letter for hostnames
                if (!n.match(/^[a-zA-Z]/)) return false;
                // Must be at least 3 characters
                if (n.length < 3) return false;
                // Exclude keywords
                if (excluded.includes(n.toLowerCase())) return false;
                // Valid hostname characters only
                if (!n.match(/^[a-zA-Z0-9_\-\.]+$/)) return false;
                return true;
            }).sort();
            
            debugLog('[clusterNodes parser] Found', filteredNodes.length, 'nodes');
            debugLog('[clusterNodes parser] Node-to-IP mappings:', nodeToIpMap);
            
            return {
                nodes: filteredNodes,
                nodeToIpMap: nodeToIpMap
            };
        }
};

const hostsFileParser = {
        // Target file path patterns
        // supportconfig: */network.txt (contains embedded /etc/hosts)
        // sosreport/crm_report/hb_report: */etc/hosts or *etc_hosts
        // hb_report may have: */hostname/hosts or */hostname.hosts
        filePattern: /\/(network\.txt|etc\/hosts|etc_hosts)$|\/[^\/]+\/(hosts)$/,
        
        // Parse function receives file content as string
        // Handles two formats:
        // 1. supportconfig: network.txt with embedded /etc/hosts section
        // 2. sosreport: direct /etc/hosts file
        // Returns object with hosts entries and validation info
        parse: function(content, filename) {
            // Extract the /etc/hosts section
            const section = SCC_RULES.extractSection(content, filename, '# /etc/hosts', '/etc/hosts');
            
            if (!section.found) {
                return { entries: [], allHostnames: [] };
            }
            
            const hosts = [];
            const hostnames = new Set();
            
            for (const line of section.lines) {
                const trimmed = line.trim();
                
                // Skip empty lines and comment lines
                if (!trimmed || trimmed.startsWith('#')) continue;
                
                // Parse host entry: IP followed by one or more hostnames
                // Format: 192.168.1.10 hostname1 hostname2 hostname3
                const parts = trimmed.split(/\s+/);
                if (parts.length < 2) continue;
                
                const ip = parts[0];
                const names = parts.slice(1);
                
                // Store entry
                hosts.push({
                    ip: ip,
                    hostnames: names
                });
                
                // Track all hostnames
                names.forEach(name => hostnames.add(name));
            }
            
            debugLog('[hostsFile parser] Extracted', hosts.length, 'host entries with', hostnames.size, 'unique hostnames');
            
            return {
                entries: hosts,
                allHostnames: Array.from(hostnames).sort()
            };
        }
};

const pacemakerResourcesParser = {
        // Target file patterns - pacemaker CIB (Cluster Information Base) or crm config
        // supportconfig: */ha.txt (contains embedded crm_mon or cib.xml sections)
        // sosreport/crm_report: */cib.xml, */crm_mon*.txt, */crm*config, */pcs_config, */pcs_status*, */pacemaker.log
        filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/crm.*config$|pacemaker\.log$|\/ha\.txt$|\/pcs_config$|\/pcs_status/,
        
        parse: function(content, filename) {
            debugLog('[pacemakerResources parser] Analyzing pacemaker configuration in:', filename);
            
            const resources = [];
            const constraints = [];
            const lines = content.split('\n');
            
            // Pattern 1: CIB XML format - <primitive id="resource-name" class="..." type="...">
            // Pattern 2: crm config format - primitive resource-name type:provider
            // Pattern 3: crm_mon output format - resource-name (type::provider)
            
            // For ha.txt files, we need to extract relevant sections to avoid false matches
            let relevantContent = content;
            const isHaTxt = filename.includes('ha.txt');
            let crmMonSections = []; // Declare outside the if block so it's accessible in debug code
            
            if (isHaTxt) {
                // For ha.txt, we want to extract BOTH CIB XML and crm_mon sections
                // First pass: get resources from CIB XML
                // Second pass: enrich with node info from crm_mon
                const cibStart = content.indexOf('<cib');
                const cibEnd = content.indexOf('</cib>');
                
                // Look for crm_mon sections - we want ALL of them, not just one
                // Different flags show different info:
                // -r shows resources
                // -n shows node names
                // -A shows attributes
                // Split content by command section markers
                const sectionParts = content.split(/^#==\[ Command \]====/m);
                
                let crmStatusSection = null;
                
                debugLog('[pacemakerResources parser] Split into', sectionParts.length, 'parts');
                
                for (let i = 1; i < sectionParts.length; i++) {  // Skip first part (before first marker)
                    const part = sectionParts[i];
                    
                    // Debug: show first 200 chars of each part
                    if (i <= 3) {
                        debugLog(`[pacemakerResources parser] Part ${i} preview:`, part.substring(0, 200).replace(/\n/g, '\\n'));
                    }
                    
                // Extract command line
                // After split, each part starts with the rest of the marker line (====#)
                // Then newline, then # command
                // Pattern: skip any ='s and whitespace, find line starting with #
                const commandLineMatch = part.match(/^[=\s]*#\s*([^\n]+)/);
                if (!commandLineMatch) {
                    debugLog(`[pacemakerResources parser] Part ${i}: No command line match found`);
                    debugLog(`[pacemakerResources parser] Part ${i} first 100 chars:`, JSON.stringify(part.substring(0, 100)));
                    continue;
                }                    const commandLine = commandLineMatch[1].trim();
                    // Extract content (everything after the command line)
                    const contentStart = part.indexOf('\n', commandLineMatch[0].length);
                    const sectionContent = contentStart >= 0 ? part.substring(contentStart + 1) : '';
                    
                    debugLog('[pacemakerResources parser] Found command section:', commandLine.substring(0, 100));
                    
                    // Check if this is crm_mon command (not rpm -qa with crm packages)
                    if (commandLine.includes('crm_mon') && !commandLine.includes('rpm') && !commandLine.includes('egrep')) {
                        crmMonSections.push(sectionContent);
                        debugLog('[pacemakerResources parser] Matched crm_mon section:', commandLine);
                        debugLog('[pacemakerResources parser] Section content length:', sectionContent.length, 'chars');
                        debugLog('[pacemakerResources parser] First 500 chars:', sectionContent.substring(0, 500));
                    } else if (commandLine.match(/^crm\s+status/) && !commandLine.includes('rpm')) {
                        crmStatusSection = sectionContent;
                        debugLog('[pacemakerResources parser] Matched crm status section');
                    }
                }
                
                // Combine all relevant sections
                let sections = [];
                
                if (cibStart !== -1 && cibEnd !== -1) {
                    sections.push(content.substring(cibStart, cibEnd + 6));
                    debugLog('[pacemakerResources parser] Found CIB XML section in ha.txt');
                }
                
                if (crmMonSections.length > 0) {
                    // Add ALL crm_mon sections - each might have different information
                    sections.push(...crmMonSections);
                    debugLog('[pacemakerResources parser] Found', crmMonSections.length, 'crm_mon section(s) in ha.txt');
                    debugLog('[pacemakerResources parser] First crm_mon section preview (first 500 chars):', crmMonSections[0].substring(0, 500));
                }
                
                if (crmStatusSection) {
                    sections.push(crmStatusSection);
                    debugLog('[pacemakerResources parser] Found crm status section in ha.txt');
                }
                
                // If we found multiple sections, combine them
                if (sections.length > 0) {
                    relevantContent = sections.join('\n\n');
                    debugLog('[pacemakerResources parser] Combined', sections.length, 'sections from ha.txt');
                } else {
                    // Try crm configure show as last resort
                    const crmConfigSection = content.match(/^#==\[ Command \]====.*?crm configure show.*?(?=^#==\[|$)/ms);
                    if (crmConfigSection) {
                        relevantContent = crmConfigSection[0];
                        debugLog('[pacemakerResources parser] Found crm configure section in ha.txt');
                    } else {
                        debugLog('[pacemakerResources parser] No recognized cluster sections found in ha.txt');
                        return { found: false };
                    }
                }
            }
            
            const contentLines = relevantContent.split('\n');
            const groupData = [];  // Initialize groups array at function scope
            const groupMemberIds = new Set();  // Track which primitives are group members
            
            debugLog('[pacemakerResources parser] Processing', contentLines.length, 'lines from', isHaTxt ? 'ha.txt sections' : filename);
            
            // Debug: Show actual content of each crm_mon section
            if (isHaTxt && crmMonSections.length > 0) {
                debugLog('[pacemakerResources parser] Showing content of', crmMonSections.length, 'crm_mon sections:');
                crmMonSections.forEach((section, idx) => {
                    const lines = section.split('\n').filter(l => l.trim() && !l.includes('#==[ Command ]===='));
                    debugLog(`  crm_mon section ${idx + 1}: ${lines.length} non-empty lines`);
                    lines.slice(0, 30).forEach((l, i) => debugLog(`    [${i}]:`, l.substring(0, 200)));
                });
                
                // Look for lines that match crm_mon output format (not XML)
                const crmMonLines = contentLines.filter(l => {
                    const trimmed = l.trim();
                    // Look for lines with * or indentation followed by resource name and parentheses
                    return (trimmed.startsWith('*') || /^\s+\*/.test(l)) && 
                           (trimmed.includes('(ocf::') || trimmed.includes('(stonith:'));
                });
                
                debugLog('[pacemakerResources parser] Lines matching crm_mon format:', crmMonLines.length, 'found');
                crmMonLines.slice(0, 20).forEach((l, i) => debugLog(`  crm_mon[${i}]:`, l));
            }
            
            // Parse XML content using simple XML parser (works in Web Workers)
            if (relevantContent.includes('<cib') || relevantContent.includes('<primitive')) {
                debugLog('[pacemakerResources parser] Parsing XML with custom XML parser');
                
                // Parse XML into elements
                const elements = parseXMLSimple(relevantContent);
                
                // Find all group elements first
                const groups = querySelectorAll(elements, 'group').filter(g => 
                    g.attributes.id && !g.attributes['crm-debug-origin']
                );
                
                debugLog('[pacemakerResources parser] Found', groups.length, 'group elements');
                groups.forEach(group => {
                    const groupAttrs = group.attributes;
                    const groupId = groupAttrs.id;
                    
                    if (groupId) {
                        const groupInfo = {
                            name: groupId,
                            type: 'group',
                            members: [],
                            node: null,
                            status: null
                        };
                        
                        // Find primitives that belong to this group
                        // In CIB XML, primitives inside groups don't have special markers,
                        // so we'll mark them during primitive parsing
                        groupData.push(groupInfo);
                        debugLog('[pacemakerResources parser] Found group (XML):', groupId);
                    }
                });
                
                // Find all primitive elements
                const primitives = querySelectorAll(elements, 'primitive');
                debugLog('[pacemakerResources parser] Found', primitives.length, 'primitive elements');
                
                primitives.forEach(primitive => {
                    const attrs = primitive.attributes;
                    const id = attrs.id;
                    const type = attrs.type;
                    const provider = attrs.provider || 'unknown';
                    const cls = attrs.class || 'ocf';
                    
                    if (id && type) {
                        resources.push({
                            name: id,
                            type: type,
                            provider: provider,
                            class: cls,
                            format: 'xml',
                            node: null,  // Node info not in XML, will be enriched from crm_mon
                            groupMember: false  // Will be updated if it belongs to a group
                        });
                        debugLog('[pacemakerResources parser] Found resource (XML):', id, type);
                    }
                });
                
                // Extract location constraints (preferred node assignments)
                const locations = querySelectorAll(elements, 'rsc_location');
                debugLog('[pacemakerResources parser] Found', locations.length, 'rsc_location constraints');
                
                locations.forEach(loc => {
                    const attrs = loc.attributes;
                    const id = attrs.id;
                    const rscName = attrs.rsc;
                    const node = attrs.node;
                    const role = attrs.role || 'Started';
                    const score = attrs.score;
                    
                    // Add to constraints list
                    if (id && rscName) {
                        constraints.push({
                            id: id,
                            type: 'location',
                            resource: rscName,
                            node: node || null,
                            role: role,
                            score: score || null
                        });
                        debugLog('[pacemakerResources parser] Found location constraint:', id, rscName, 'on', node || 'rule-based', 'score:', score);
                    }
                    
                    // Enrich resource with node info if available
                    if (rscName && node) {
                        const resource = resources.find(r => r.name === rscName);
                        if (resource && !resource.node) {
                            resource.node = node;
                            resource.status = role;
                            resource.locationScore = score;
                            debugLog('[pacemakerResources parser] Enriched from XML constraint:', rscName, 'on', node, 'role:', role, 'score:', score);
                        }
                    }
                });
                
                // Extract colocation constraints (resources that should/shouldn't run together)
                const colocations = querySelectorAll(elements, 'rsc_colocation');
                debugLog('[pacemakerResources parser] Found', colocations.length, 'rsc_colocation constraints');
                
                colocations.forEach(coloc => {
                    const attrs = coloc.attributes;
                    const id = attrs.id;
                    const rsc = attrs.rsc;
                    const withRsc = attrs['with-rsc'];
                    const score = attrs.score;
                    
                    if (id && rsc && withRsc) {
                        constraints.push({
                            id: id,
                            type: 'colocation',
                            resource: rsc,
                            withResource: withRsc,
                            score: score || null
                        });
                        debugLog('[pacemakerResources parser] Found colocation constraint:', id, rsc, 'with', withRsc, 'score:', score);
                    }
                });
                
                // Extract order constraints (start/stop ordering dependencies)
                const orders = querySelectorAll(elements, 'rsc_order');
                debugLog('[pacemakerResources parser] Found', orders.length, 'rsc_order constraints');
                
                orders.forEach(order => {
                    const attrs = order.attributes;
                    const id = attrs.id;
                    const first = attrs.first;
                    const then = attrs.then;
                    const firstAction = attrs['first-action'] || 'start';
                    const thenAction = attrs['then-action'] || 'start';
                    const kind = attrs.kind || 'Mandatory';
                    const symmetrical = attrs.symmetrical;
                    
                    if (id && first && then) {
                        constraints.push({
                            id: id,
                            type: 'order',
                            firstResource: first,
                            firstAction: firstAction,
                            thenResource: then,
                            thenAction: thenAction,
                            kind: kind,
                            symmetrical: symmetrical
                        });
                        debugLog('[pacemakerResources parser] Found order constraint:', id, first, firstAction, '->', then, thenAction);
                    }
                });
                
                debugLog('[pacemakerResources parser] XML parsing complete, found', resources.length, 'resources and', constraints.length, 'constraints');
            }
            
            let currentGroup = null;  // Track current group when parsing crm_mon output
            let currentClone = null;  // Track current clone/master-slave set
            let inPcsResourcesSection = false;  // Track if we're in pcs_config Resources section
            let inPcsConstraintsSection = false;  // Track if we're in Constraints section
            
            for (const line of contentLines) {
                const trimmed = line.trim();
                
                // Detect pcs_config/pcs_status sections
                if (trimmed === 'Resources:' || trimmed === 'Full List of Resources:') {
                    inPcsResourcesSection = true;
                    inPcsConstraintsSection = false;
                    debugLog('[pacemakerResources parser] Entered pcs Resources section');
                    continue;
                }
                
                if (trimmed.match(/^(Stonith Devices|Location Constraints|Ordering Constraints|Colocation Constraints|Ticket Constraints|Fencing Levels|Node Attributes|Migration Summary|Tickets|PCSD Status|Daemon Status):/)) {
                    inPcsResourcesSection = false;
                    if (trimmed.match(/Constraints:/)) {
                        inPcsConstraintsSection = true;
                        debugLog('[pacemakerResources parser] Entered pcs Constraints section');
                    }
                    continue;
                }
                
                // Parse pcs_config resource format: "  Resource: name (class=ocf provider=heartbeat type=IPaddr2)"
                if (inPcsResourcesSection && trimmed.match(/^Resource:/)) {
                    const pcsResourceMatch = trimmed.match(/^Resource:\s+(\S+)\s+\(class=(\S+)(?:\s+provider=(\S+))?\s+type=([^)]+)\)/);
                    if (pcsResourceMatch) {
                        const [, name, cls, provider, type] = pcsResourceMatch;
                        const newResource = {
                            name: name,
                            type: type,
                            provider: provider || 'heartbeat',
                            class: cls,
                            format: 'pcs_config',
                            node: null,
                            groupMember: currentGroup ? true : false,
                            groupName: currentGroup || null,
                            cloneMember: currentClone ? true : false,
                            cloneName: currentClone || null
                        };
                        resources.push(newResource);
                        
                        if (currentGroup) {
                            const group = groupData.find(g => g.name === currentGroup);
                            if (group && !group.members.includes(name)) {
                                group.members.push(name);
                            }
                        } else if (currentClone) {
                            const clone = groupData.find(g => g.name === currentClone);
                            if (clone && !clone.members.includes(name)) {
                                clone.members.push(name);
                            }
                        }
                        
                        debugLog('[pacemakerResources parser] Found resource (pcs_config):', name, type);
                        continue;
                    }
                }
                
                // Parse pcs_config group format: "  Group: g_ipnc_db2pjr_PJR"
                if (inPcsResourcesSection && trimmed.match(/^Group:/)) {
                    const pcsGroupMatch = trimmed.match(/^Group:\s+(\S+)/);
                    if (pcsGroupMatch) {
                        const groupName = pcsGroupMatch[1];
                        currentGroup = groupName;
                        currentClone = null;
                        
                        let group = groupData.find(g => g.name === groupName);
                        if (!group) {
                            group = {
                                name: groupName,
                                type: 'group',
                                members: [],
                                node: null
                            };
                            groupData.push(group);
                        }
                        debugLog('[pacemakerResources parser] Found Group (pcs_config):', groupName);
                        continue;
                    }
                }
                
                // Parse pcs_config clone format: "  Clone: Db2_HADR_PJR-master"
                if (inPcsResourcesSection && trimmed.match(/^Clone:/)) {
                    const pcsCloneMatch = trimmed.match(/^Clone:\s+(\S+)/);
                    if (pcsCloneMatch) {
                        const cloneName = pcsCloneMatch[1];
                        currentClone = cloneName;
                        currentGroup = null;
                        
                        let clone = groupData.find(g => g.name === cloneName);
                        if (!clone) {
                            clone = {
                                name: cloneName,
                                type: 'clone',
                                members: [],
                                node: null
                            };
                            groupData.push(clone);
                        }
                        debugLog('[pacemakerResources parser] Found Clone (pcs_config):', cloneName);
                        continue;
                    }
                }
                
                // Parse pcs_status resource format: "  * rsc_st_azure        (stonith:fence_azure_arm):       Started pjrw4100-db"
                if (trimmed.match(/^\*\s+\S+\s+\([\w:]+\):\s+(Started|Stopped|Master|Slave)/)) {
                    const pcsStatusMatch = trimmed.match(/^\*\s+(\S+)\s+\(([\w:]+)\):\s+(\w+)(?:\s+(\S+))?/);
                    if (pcsStatusMatch) {
                        const [, name, typeString, status, node] = pcsStatusMatch;
                        
                        // Parse type string (could be "stonith:fence_azure_arm" or "ocf::heartbeat:IPaddr2")
                        let cls, provider, type;
                        if (typeString.includes('::')) {
                            [cls, provider, type] = typeString.split('::');
                            provider = provider.replace(':', '');
                        } else if (typeString.includes(':')) {
                            [cls, type] = typeString.split(':');
                            provider = 'heartbeat';
                        } else {
                            cls = 'ocf';
                            provider = 'heartbeat';
                            type = typeString;
                        }
                        
                        // Check if resource already exists
                        const existing = resources.find(r => r.name === name);
                        if (existing) {
                            existing.node = node || null;
                            existing.status = status;
                            debugLog('[pacemakerResources parser] Enriched resource (pcs_status):', name, 'on', node);
                        } else {
                            resources.push({
                                name: name,
                                type: type,
                                provider: provider,
                                class: cls,
                                format: 'pcs_status',
                                node: node || null,
                                status: status,
                                groupMember: currentGroup ? true : false,
                                groupName: currentGroup || null
                            });
                            debugLog('[pacemakerResources parser] Found resource (pcs_status):', name, type, 'on', node);
                        }
                        continue;
                    }
                }
                
                // Parse pcs_config constraints: "  promote Db2_HADR_PJR-master then start g_ipnc_db2pjr_PJR (kind:Mandatory)"
                if (inPcsConstraintsSection) {
                    const pcsOrderMatch = trimmed.match(/^(\w+)\s+(\S+)\s+then\s+(\w+)\s+(\S+)\s+\(kind:(\w+)\)(?:\s+\(id:([^)]+)\))?/);
                    if (pcsOrderMatch) {
                        const [, firstAction, firstResource, thenAction, thenResource, kind, id] = pcsOrderMatch;
                        constraints.push({
                            id: id || `order-${firstResource}-${thenResource}`,
                            type: 'order',
                            firstResource: firstResource,
                            firstAction: firstAction,
                            thenResource: thenResource,
                            thenAction: thenAction,
                            kind: kind
                        });
                        debugLog('[pacemakerResources parser] Found order constraint (pcs_config):', firstResource, firstAction, '->', thenResource, thenAction);
                        continue;
                    }
                    
                    // Parse colocation: "  g_ipnc_db2pjr_PJR with Db2_HADR_PJR-master (score:INFINITY)"
                    const pcsColocMatch = trimmed.match(/^(\S+)\s+with\s+(\S+)\s+\(score:(\S+)\)/);
                    if (pcsColocMatch) {
                        const [, resource, withResource, score] = pcsColocMatch;
                        constraints.push({
                            id: `colocation-${resource}-${withResource}`,
                            type: 'colocation',
                            resource: resource,
                            withResource: withResource,
                            score: score
                        });
                        debugLog('[pacemakerResources parser] Found colocation constraint (pcs_config):', resource, 'with', withResource);
                        continue;
                    }
                }
                
                // Detect Clone Set or Primary/Secondary Set lines
                // * Clone Set: cln_azure-events [rsc_azure-events] (maintenance):
                // * Clone Set: msl_SAPHana_CPH_HDB01 [rsc_SAPHana_CPH_HDB01] (promotable, maintenance):
                const cloneMatch = trimmed.match(/^\*?\s*(?:Clone Set|Master\/Slave Set|Primary\/Secondary Set):\s+(\S+)\s+\[(\S+)\](?:\s+\(([^)]+)\))?/i);
                if (cloneMatch) {
                    const cloneName = cloneMatch[1];
                    const resourceName = cloneMatch[2];
                    const attributes = cloneMatch[3] || '';
                    const isMaintenance = attributes.includes('maintenance');
                    
                    currentClone = cloneName;
                    
                    // Find or create clone/primary-secondary set in groupData
                    let clone = groupData.find(g => g.name === cloneName);
                    if (!clone) {
                        clone = {
                            name: cloneName,
                            type: trimmed.toLowerCase().includes('master') ? 'master-slave' : 'clone',
                            members: [],
                            node: null,
                            status: isMaintenance ? 'maintenance' : null,
                            maintenance: isMaintenance
                        };
                        groupData.push(clone);
                    }
                    
                    debugLog('[pacemakerResources parser] Found Clone/Primary-Secondary Set:', cloneName, 'maintenance:', isMaintenance);
                    continue;
                }
                
                // Detect Resource Group lines: "* Resource Group: g-NAP_ASCS:"
                // * Resource Group: GRP_IP_CPH_HDB01 (maintenance):
                const groupMatch = trimmed.match(/^\*?\s*Resource Group:\s+(\S+):?\s*(?:\(([^)]+)\))?/i);
                if (groupMatch) {
                    const groupName = groupMatch[1].replace(/:$/, '');  // Remove trailing colon
                    const attributes = groupMatch[2] || '';
                    const isMaintenance = attributes.includes('maintenance');
                    
                    currentGroup = groupName;
                    currentClone = null;  // Reset clone tracking when entering group
                    
                    // Find or create group in groupData
                    let group = groupData.find(g => g.name === groupName);
                    if (!group) {
                        group = {
                            name: groupName,
                            type: 'group',
                            members: [],
                            node: null,
                            status: isMaintenance ? 'maintenance' : null,
                            maintenance: isMaintenance
                        };
                        groupData.push(group);
                    }
                    
                    debugLog('[pacemakerResources parser] Found Resource Group:', groupName, 'maintenance:', isMaintenance);
                    continue;
                }
                
                // Reset current group if we hit a non-indented resource (standalone resource)
                if (trimmed.match(/^\*\s+\S+/) && !trimmed.match(/Resource Group|Clone Set|Master\/Slave Set/i)) {
                    // Check if this is a deeply indented line (group member) vs. top-level
                    if (!line.match(/^\s{2,}/)) {  // Top-level resources have less indentation
                        currentGroup = null;
                        currentClone = null;
                    }
                }
                
                // crm config format: primitive rsc_ip ocf:heartbeat:IPaddr2
                const crmMatch = trimmed.match(/^primitive\s+(\S+)\s+(\S+):(\S+):(\S+)/);
                if (crmMatch) {
                    const [, name, cls, provider, type] = crmMatch;
                    resources.push({
                        name: name,
                        type: type,
                        provider: provider,
                        class: cls,
                        format: 'crm',
                        node: null,  // Node info not in crm config, will be enriched from crm_mon
                        groupMember: false,
                        maintenance: false
                    });
                    debugLog('[pacemakerResources parser] Found resource (crm):', name, type);
                    continue;
                }
                
                // crm_mon format variations:
                // * rsc_ip_ABC (ocf::heartbeat:IPaddr2): Started node1
                // * rsc_ip_ABC (ocf::heartbeat:IPaddr2): Started node1 (maintenance)
                // * rsc_SAPHana_CPH_HDB01 (ocf::suse:SAPHana): Master csscp2d10 (maintenance)
                // * rsc_SAPHana_CPH_HDB01 (ocf::suse:SAPHana): Slave csscp2d20 (maintenance)
                // Indented format (within Resource Group):
                //   * fs_NAP_ASCS       (ocf::heartbeat:Filesystem):     Started ccecccsprd01
                // Also captures: Stopped, Master, Slave, etc.
                
                // Debug: log lines that might be crm_mon output
                if (trimmed.includes('(ocf::') || trimmed.includes('(stonith:')) {
                    debugLog('[pacemakerResources parser] Checking crm_mon line:', trimmed.substring(0, 100));
                }
                
                // Updated regex to capture maintenance status
                const monMatch = trimmed.match(/^\*?\s*(\S+)\s+\((\S+)::(\S+):(\S+)\):\s+(\w+)(?:\s+(\S+))?(?:\s+\(([^)]+)\))?/);
                if (monMatch) {
                    const [, name, cls, provider, type, status, node, attributes] = monMatch;
                    const isMaintenance = attributes ? attributes.includes('maintenance') : false;
                    
                    // Check if resource already exists (from XML or crm config)
                    const existing = resources.find(r => r.name === name);
                    if (existing) {
                        // Enrich existing resource with node info
                        existing.node = node || null;
                        existing.status = status;
                        existing.maintenance = isMaintenance;
                        
                        // Mark as group or clone member if we're currently parsing one
                        if (currentGroup) {
                            existing.groupMember = true;
                            existing.groupName = currentGroup;
                            
                            // Add to group's members list
                            const group = groupData.find(g => g.name === currentGroup);
                            if (group && !group.members.includes(name)) {
                                group.members.push(name);
                                // Inherit node from first member
                                if (!group.node) group.node = node;
                            }
                        } else if (currentClone) {
                            existing.cloneMember = true;
                            existing.cloneName = currentClone;
                            
                            // Add to clone's members list
                            const clone = groupData.find(g => g.name === currentClone);
                            if (clone && !clone.members.includes(name)) {
                                clone.members.push(name);
                            }
                        }
                        
                        debugLog('[pacemakerResources parser] Enriched resource with node info:', name, 'on', node || 'unknown', 'status:', status, 'maintenance:', isMaintenance);
                    } else {
                        // Add new resource
                        const newResource = {
                            name: name,
                            type: type,
                            provider: provider,
                            class: cls,
                            format: 'crm_mon',
                            node: node || null,
                            status: status,
                            maintenance: isMaintenance,
                            groupMember: currentGroup ? true : false,
                            groupName: currentGroup || null,
                            cloneMember: currentClone ? true : false,
                            cloneName: currentClone || null
                        };
                        resources.push(newResource);
                        
                        // Add to group's or clone's members list
                        if (currentGroup) {
                            const group = groupData.find(g => g.name === currentGroup);
                            if (group && !group.members.includes(name)) {
                                group.members.push(name);
                                if (!group.node) group.node = node;
                            }
                        } else if (currentClone) {
                            const clone = groupData.find(g => g.name === currentClone);
                            if (clone && !clone.members.includes(name)) {
                                clone.members.push(name);
                            }
                        }
                        
                        debugLog('[pacemakerResources parser] Found resource (crm_mon):', name, type, 'on', node || 'unknown', 'status:', status, 'maintenance:', isMaintenance);
                    }
                    continue;
                }
                
                // Pattern for lines without parentheses but with colon separator
                // Example:   * stonith-sbd (stonith:external/sbd):  Started cceccerprd02 (maintenance)
                // Format: name (type:provider/agent): Status node (attributes)
                const stonithMatch = trimmed.match(/^\*?\s*(\S+)\s+\((\S+):(\S+)\/(\S+)\):\s+(\w+)(?:\s+(\S+))?(?:\s+\(([^)]+)\))?/);
                if (stonithMatch) {
                    const [, name, type, provider, agent, status, node, attributes] = stonithMatch;
                    const isMaintenance = attributes ? attributes.includes('maintenance') : false;
                    
                    const existing = resources.find(r => r.name === name);
                    if (existing) {
                        existing.node = node || null;
                        existing.status = status;
                        existing.maintenance = isMaintenance;
                        
                        // Mark as group or clone member if we're currently parsing one
                        if (currentGroup) {
                            existing.groupMember = true;
                            existing.groupName = currentGroup;
                            
                            const group = groupData.find(g => g.name === currentGroup);
                            if (group && !group.members.includes(name)) {
                                group.members.push(name);
                                if (!group.node) group.node = node;
                            }
                        } else if (currentClone) {
                            existing.cloneMember = true;
                            existing.cloneName = currentClone;
                            
                            const clone = groupData.find(g => g.name === currentClone);
                            if (clone && !clone.members.includes(name)) {
                                clone.members.push(name);
                            }
                        }
                        
                        debugLog('[pacemakerResources parser] Enriched resource (stonith):', name, 'on', node || 'unknown', 'maintenance:', isMaintenance);
                    } else {
                        const newResource = {
                            name: name,
                            type: agent,
                            provider: provider,
                            class: type,
                            format: 'crm_mon_stonith',
                            node: node || null,
                            status: status,
                            maintenance: isMaintenance,
                            groupMember: currentGroup ? true : false,
                            groupName: currentGroup || null,
                            cloneMember: currentClone ? true : false,
                            cloneName: currentClone || null
                        };
                        resources.push(newResource);
                        
                        if (currentGroup) {
                            const group = groupData.find(g => g.name === currentGroup);
                            if (group && !group.members.includes(name)) {
                                group.members.push(name);
                                if (!group.node) group.node = node;
                            }
                        } else if (currentClone) {
                            const clone = groupData.find(g => g.name === currentClone);
                            if (clone && !clone.members.includes(name)) {
                                clone.members.push(name);
                            }
                        }
                        
                        debugLog('[pacemakerResources parser] Found resource (stonith format):', name, agent, 'on', node || 'unknown', 'maintenance:', isMaintenance);
                    }
                    continue;
                }
                
                // Additional pattern for "crm status" or alternate crm_mon format
                // Full line: resource-name    (class:provider:type):    Status    node-name
                const statusMatch = trimmed.match(/^(\S+)\s+\((\S+):(\S+):(\S+)\):\s+(\w+)\s+(\S+)/);
                if (statusMatch) {
                    const [, name, cls, provider, type, status, node] = statusMatch;
                    
                    const existing = resources.find(r => r.name === name);
                    if (existing) {
                        existing.node = node || null;
                        existing.status = status;
                        debugLog('[pacemakerResources parser] Enriched resource (alt format):', name, 'on', node);
                    } else {
                        resources.push({
                            name: name,
                            type: type,
                            provider: provider,
                            class: cls,
                            format: 'status',
                            node: node || null,
                            status: status
                        });
                        debugLog('[pacemakerResources parser] Found resource (status format):', name, type, 'on', node);
                    }
                    continue;
                }
            }
            
            if (resources.length === 0) {
                debugLog('[pacemakerResources parser] No resources found');
                return { found: false };
            }
            
            debugLog('[pacemakerResources parser] Found', resources.length, 'resources');
            debugLog('[pacemakerResources parser] Resources with node info:', 
                resources.filter(r => r.node).map(r => `${r.name} on ${r.node} (${r.status || 'unknown'})`));
            
            // Parse Failed Resource Actions section
            const failedActions = [];
            let inFailedSection = false;
            for (const line of contentLines) {
                const trimmed = line.trim();
                
                // Detect section start
                if (trimmed === 'Failed Resource Actions:' || trimmed === 'Failed Actions:') {
                    inFailedSection = true;
                    debugLog('[pacemakerResources parser] Found Failed Resource Actions section');
                    continue;
                }
                
                // Detect section end (empty line or next section)
                if (inFailedSection && (trimmed === '' || trimmed.match(/^[A-Z]/))) {
                    if (trimmed.match(/^(Node Attributes|Migration Summary|Tickets):/)) {
                        inFailedSection = false;
                    }
                    continue;
                }
                
                // Parse failed action lines
                // Format: * resource_name_monitor_10000 on node 'not running' (7): call=123, status=complete, exitreason='...', last-rc-change='timestamp', queued=0ms, exec=0ms
                if (inFailedSection && trimmed.startsWith('*')) {
                    const failMatch = trimmed.match(/^\*\s+(\S+)\s+on\s+(\S+)\s+'([^']+)'\s+\((\d+)\):\s+(.+)/);
                    if (failMatch) {
                        const [, action, node, state, code, details] = failMatch;
                        failedActions.push({
                            action: action,
                            node: node,
                            state: state,
                            returnCode: code,
                            details: details
                        });
                        debugLog('[pacemakerResources parser] Found failed action:', action, 'on', node);
                    }
                }
            }
            
            debugLog('[pacemakerResources parser] Found', failedActions.length, 'failed actions');
            debugLog('[pacemakerResources parser] Found', groupData.length, 'groups');
            
            return {
                found: true,
                resources: resources,
                count: resources.length,
                groups: groupData,
                groupsCount: groupData.length,
                constraints: constraints,
                constraintsCount: constraints.length,
                failedActions: failedActions,
                failedActionsCount: failedActions.length
            };
        }
};

const corosyncStatusParser = {
        filePattern: /corosync-cfgtool.*-s$/,
        
        parse: function(content, filename) {
            debugLog('[corosyncStatus parser] Analyzing corosync runtime status in:', filename);
            
            const lines = content.split('\n');
            let isValid = true;
            let errorMessage = null;
            let localNodeId = null;
            let transport = null;
            const nodes = [];
            
            for (const line of lines) {
                const trimmed = line.trim();
                
                // Check for configuration error
                if (trimmed.match(/Could not initialize corosync configuration/i)) {
                    isValid = false;
                    errorMessage = trimmed;
                    debugLog('[corosyncStatus parser] Corosync configuration error detected:', trimmed);
                    break;
                }
                
                // Parse local node ID and transport
                const localNodeMatch = trimmed.match(/Local node ID\s+(\d+).*transport\s+(\w+)/i);
                if (localNodeMatch) {
                    localNodeId = localNodeMatch[1];
                    transport = localNodeMatch[2];
                    debugLog('[corosyncStatus parser] Local node ID:', localNodeId, 'Transport:', transport);
                }
                
                // Parse node status lines (format: "nodeid: 1: localhost" or "nodeid: 2: connected")
                const nodeMatch = trimmed.match(/nodeid:\s*(\d+):\s*(\w+)/i);
                if (nodeMatch) {
                    const nodeId = nodeMatch[1];
                    const status = nodeMatch[2];
                    nodes.push({ nodeId: nodeId, status: status });
                    debugLog('[corosyncStatus parser] Node', nodeId, 'status:', status);
                }
            }
            
            if (!isValid) {
                return {
                    found: true,
                    valid: false,
                    error: errorMessage || 'Could not initialize corosync configuration'
                };
            }
            
            return {
                found: true,
                valid: true,
                localNodeId: localNodeId,
                transport: transport,
                nodes: nodes
            };
        }
};

const clusterStatusParser = {
        // Target file patterns - crm_mon XML output, cib.xml, or pcs_status
        filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/crm_mon.*\.xml$|\/ha\.txt$|\/pcs_status/,
        
        parse: function(content, filename) {
            debugLog('[clusterStatus parser] Analyzing cluster status in:', filename);
            
            let clusterName = null;
            let dcNode = null;
            let nodesConfigured = null;
            let resourcesConfigured = null;
            let lastUpdated = null;
            const nodeStatuses = [];
            let quorumStatus = null;
            
            // Check if content contains XML
            if (content.includes('<crm_mon') || content.includes('<cib')) {
                debugLog('[clusterStatus parser] Detected XML format, using custom XML parser');
                
                // Extract only the CIB XML section if this is ha.txt with embedded content
                let xmlContent = content;
                if (filename.includes('ha.txt')) {
                    // Try to extract the cibadmin -Q section
                    const cibSection = extractSection(content, filename, '# /usr/sbin/cibadmin -Q', 'cib.xml', debugLog);
                    if (cibSection.found) {
                        xmlContent = cibSection.content;
                        debugLog('[clusterStatus parser] Extracted CIB section from ha.txt:', cibSection.lines.length, 'lines');
                    }
                }
                
                const elements = parseXMLSimple(xmlContent);
                
                // Parse crm_mon root element for summary info
                const crmMonElements = querySelectorAll(elements, 'crm_mon');
                if (crmMonElements.length > 0) {
                    const attrs = crmMonElements[0].attributes;
                    lastUpdated = attrs.version || null;
                }
                
                // Parse CIB root element for cluster info
                const cibElements = querySelectorAll(elements, 'cib');
                if (cibElements.length > 0) {
                    const attrs = cibElements[0].attributes;
                    lastUpdated = attrs['cib-last-written'] || lastUpdated;
                    dcNode = attrs['dc-uuid'] || dcNode;
                    quorumStatus = attrs['have-quorum'] === '1' ? 'with quorum' : 'without quorum';
                }
                
                // Parse cluster_property_set for cluster-name and stonith settings
                const nvpairs = querySelectorAll(elements, 'nvpair');
                nvpairs.forEach(nvpair => {
                    const attrs = nvpair.attributes;
                    if (attrs.name === 'cluster-name') {
                        clusterName = attrs.value;
                    } else if (attrs.name === 'cluster-infrastructure') {
                        if (!clusterName) clusterName = attrs.value;
                    }
                });
                
                // Parse summary element (crm_mon format)
                const summaryElements = querySelectorAll(elements, 'summary');
                if (summaryElements.length > 0) {
                    const summary = summaryElements[0].attributes;
                    
                    // Extract stack info
                    const stackElements = querySelectorAll(elements, 'stack');
                    if (stackElements.length > 0) {
                        const stackAttrs = stackElements[0].attributes;
                        clusterName = stackAttrs.type || clusterName || 'corosync';
                    }
                    
                    // Extract current DC
                    const currentDcElements = querySelectorAll(elements, 'current_dc');
                    if (currentDcElements.length > 0) {
                        const dcAttrs = currentDcElements[0].attributes;
                        dcNode = dcAttrs.name || dcAttrs.uname || dcNode;
                        quorumStatus = dcAttrs.with_quorum === 'true' ? 'with quorum' : quorumStatus;
                    }
                    
                    // Extract nodes and resources count
                    const nodesConfiguredElements = querySelectorAll(elements, 'nodes_configured');
                    if (nodesConfiguredElements.length > 0) {
                        nodesConfigured = parseInt(nodesConfiguredElements[0].attributes.number) || null;
                    }
                    
                    const resourcesConfiguredElements = querySelectorAll(elements, 'resources_configured');
                    if (resourcesConfiguredElements.length > 0) {
                        resourcesConfigured = parseInt(resourcesConfiguredElements[0].attributes.number) || null;
                    }
                    
                    // Parse last update timestamp
                    const lastUpdateElements = querySelectorAll(elements, 'last_update');
                    if (lastUpdateElements.length > 0) {
                        lastUpdated = lastUpdateElements[0].attributes.time || lastUpdated;
                    }
                }
                
                // Parse node_state elements from CIB (runtime status)
                const nodeStateElements = querySelectorAll(elements, 'node_state');
                if (nodeStateElements.length > 0) {
                    debugLog('[clusterStatus parser] Found', nodeStateElements.length, 'node_state elements in CIB');
                    nodeStateElements.forEach(nodeState => {
                        const attrs = nodeState.attributes;
                        const nodeName = attrs.uname || attrs.name;
                        const nodeId = attrs.id;
                        
                        // in_ccm and crmd can be timestamps (Unix epoch) or boolean strings
                        // A node is in cluster membership if in_ccm is present and non-zero
                        // A node has crmd running if crmd is present and non-zero
                        const in_ccm_value = attrs.in_ccm || attrs['in_ccm'];
                        const crmd_value = attrs.crmd;
                        const in_ccm = in_ccm_value && in_ccm_value !== '0' && in_ccm_value !== 'false';
                        const crmd_running = crmd_value && crmd_value !== '0' && crmd_value !== 'false';
                        const join = attrs.join;
                        const expected = attrs.expected;
                        
                        // Node is online if it's in CCM, has crmd running, and is a member
                        const online = in_ccm && crmd_running && (join === 'member' || expected === 'member');
                        
                        // Check if this is the DC node
                        const is_dc = (nodeId === dcNode || nodeName === dcNode);
                        
                        // Determine status
                        let status = 'unknown';
                        if (attrs.standby === 'true' || attrs.standby === 'on') {
                            status = 'standby';
                        } else if (attrs.maintenance === 'true') {
                            status = 'maintenance';
                        } else if (online) {
                            status = 'online';
                        } else if (!crmd_running) {
                            status = 'offline';
                        } else {
                            status = 'pending';
                        }
                        
                        if (nodeName && !nodeStatuses.find(n => n.name === nodeName)) {
                            nodeStatuses.push({
                                name: nodeName,
                                status: status,
                                online: online,
                                isDC: is_dc,
                                resourcesRunning: 0,  // CIB doesn't have this, would need to count resources
                                type: 'member',
                                sourceFile: filename,
                                sourceLine: 0,
                                sourcePattern: '<node_state> (CIB XML)'
                            });
                            
                            debugLog('[clusterStatus parser] Found node_state:', nodeName, status, 
                                    is_dc ? '(DC)' : '', `crmd=${attrs.crmd}, in_ccm=${in_ccm}, join=${join}`);
                        }
                    });
                }
                
                // Parse node elements from crm_mon format (these have online attribute)
                const nodeElements = querySelectorAll(elements, 'node');
                nodeElements.forEach(node => {
                    const attrs = node.attributes;
                    const nodeName = attrs.name || attrs.uname;
                    const online = attrs.online === 'true';
                    const standby = attrs.standby === 'true' || attrs.standby === 'on';
                    const maintenance = attrs.maintenance === 'true';
                    const pending = attrs.pending === 'true';
                    const unclean = attrs.unclean === 'true';
                    const shutdown = attrs.shutdown === 'true';
                    const expected_up = attrs.expected_up === 'true';
                    const is_dc = attrs.is_dc === 'true';
                    const resources_running = parseInt(attrs.resources_running) || 0;
                    const type = attrs.type || 'member';
                    
                    // Only process if this node has online status attribute (crm_mon format)
                    // Skip CIB configuration nodes that don't have status
                    if (nodeName && attrs.online !== undefined && !nodeStatuses.find(n => n.name === nodeName)) {
                        let status = 'unknown';
                        if (unclean) status = 'UNCLEAN';
                        else if (shutdown) status = 'shutdown';
                        else if (pending) status = 'pending';
                        else if (maintenance) status = 'maintenance';
                        else if (standby) status = 'standby';
                        else if (online) status = 'online';
                        else status = 'offline';
                        
                        nodeStatuses.push({
                            name: nodeName,
                            status: status,
                            online: online,
                            isDC: is_dc,
                            resourcesRunning: resources_running,
                            type: type,
                            sourceFile: filename,
                            sourceLine: 0,
                            sourcePattern: '<node online="..."> (crm_mon XML)'
                        });
                        
                        debugLog('[clusterStatus parser] Found node (crm_mon XML):', nodeName, status, 
                                is_dc ? '(DC)' : '', `(${resources_running} resources)`);
                    }
                });
                
                // Count nodes and resources from CIB if not found in summary
                if (nodesConfigured === null) {
                    // Count only node definitions (not node_state entries)
                    // Node definitions have both 'id' and 'uname' attributes
                    const nodeDefinitions = querySelectorAll(elements, 'node').filter(n => 
                        n.attributes.id && n.attributes.uname && !n.attributes.crmd
                    );
                    if (nodeDefinitions.length > 0) {
                        nodesConfigured = nodeDefinitions.length;
                        debugLog('[clusterStatus parser] Counted nodes from CIB:', nodesConfigured);
                    }
                }
                
                if (resourcesConfigured === null) {
                    // Count only top-level resource primitives (not those in status/lrm sections)
                    // Filter by checking they have class, provider, and type attributes (resource definitions)
                    // and don't have crm-debug-origin (which indicates status section)
                    const resourcePrimitives = querySelectorAll(elements, 'primitive').filter(p => 
                        p.attributes.id && p.attributes.class && p.attributes.type && !p.attributes['crm-debug-origin']
                    );
                    const groups = querySelectorAll(elements, 'group').filter(g => 
                        g.attributes.id && !g.attributes['crm-debug-origin']
                    );
                    const clones = querySelectorAll(elements, 'clone').filter(c => 
                        c.attributes.id && !c.attributes['crm-debug-origin']
                    );
                    
                    // Use unique IDs to avoid counting duplicates
                    const uniqueResourceIds = new Set();
                    resourcePrimitives.forEach(p => uniqueResourceIds.add(p.attributes.id));
                    groups.forEach(g => uniqueResourceIds.add(g.attributes.id));
                    clones.forEach(c => uniqueResourceIds.add(c.attributes.id));
                    
                    resourcesConfigured = uniqueResourceIds.size;
                    if (resourcesConfigured > 0) {
                        debugLog('[clusterStatus parser] Counted resources from CIB:', resourcesConfigured, 
                                '(', resourcePrimitives.length, 'primitives,', groups.length, 'groups,', clones.length, 'clones)');
                    }
                }
            }
            
            // Parse text-based crm_mon output or pcs_status if no XML found
            if (nodeStatuses.length === 0) {
                const lines = content.split('\n');
                let inNodesSection = false;
                let lineNum = 0;
                
                for (const line of lines) {
                    lineNum++;
                    const trimmed = line.trim();
                    
                    // pcs_status header format: "Cluster name: <name>"
                    const pcsClusterMatch = trimmed.match(/^Cluster name:\s+(.+)/i);
                    if (pcsClusterMatch) {
                        clusterName = pcsClusterMatch[1];
                        debugLog('[clusterStatus parser] Found cluster name (pcs_status):', clusterName);
                    }
                    
                    // pcs_status resource count: "  * 5 resource instances configured"
                    const pcsResourcesMatch = trimmed.match(/^\*?\s*(\d+)\s+resource\s+instances?\s+configured/i);
                    if (pcsResourcesMatch) {
                        resourcesConfigured = parseInt(pcsResourcesMatch[1]);
                        debugLog('[clusterStatus parser] Found resources configured (pcs_status):', resourcesConfigured);
                    }
                    
                    // pcs_status node count: "  * 2 nodes configured"
                    const pcsNodesMatch = trimmed.match(/^\*?\s*(\d+)\s+nodes?\s+configured/i);
                    if (pcsNodesMatch) {
                        nodesConfigured = parseInt(pcsNodesMatch[1]);
                        debugLog('[clusterStatus parser] Found nodes configured (pcs_status):', nodesConfigured);
                    }
                    
                    // Extract cluster name and DC from header
                    const stackMatch = trimmed.match(/Stack:\s+(\w+)/i);
                    if (stackMatch) {
                        clusterName = stackMatch[1];
                    }
                    
                    const dcMatch = trimmed.match(/Current DC:\s+([^\s]+)/i);
                    if (dcMatch) {
                        dcNode = dcMatch[1];
                    }
                    
                    const lastUpdateMatch = trimmed.match(/Last updated:\s+(.+)/i);
                    if (lastUpdateMatch) {
                        lastUpdated = lastUpdateMatch[1];
                    }
                    
                    const nodesMatch = trimmed.match(/(\d+)\s+nodes?\s+configured/i);
                    if (nodesMatch) {
                        nodesConfigured = parseInt(nodesMatch[1]);
                    }
                    
                    const resourcesMatch = trimmed.match(/(\d+)\s+resources?\s+configured/i);
                    if (resourcesMatch) {
                        resourcesConfigured = parseInt(resourcesMatch[1]);
                    }
                    
                    // Detect nodes section
                    if (trimmed.match(/^(Online|Offline|Node):/i) || trimmed.match(/^\s*\*?\s*Node\s+/i)) {
                        inNodesSection = true;
                    }
                    
                    // Parse node status lines
                    // Format: "Online: [ node1 node2 ]" or "* Node node1: online"
                    const onlineMatch = trimmed.match(/Online:\s*\[\s*([^\]]+)\s*\]/i);
                    if (onlineMatch) {
                        const nodeNames = onlineMatch[1].trim().split(/\s+/);
                        nodeNames.forEach(name => {
                            if (name && !nodeStatuses.find(n => n.name === name)) {
                                nodeStatuses.push({
                                    name: name,
                                    status: 'online',
                                    online: true,
                                    isDC: name === dcNode,
                                    resourcesRunning: 0,
                                    type: 'member',
                                    sourceFile: filename,
                                    sourceLine: lineNum,
                                    sourcePattern: 'Online: [ ... ]'
                                });
                                debugLog('[clusterStatus parser] Found node (text):', name, 'online');
                            }
                        });
                    }
                    
                    const offlineMatch = trimmed.match(/Offline:\s*\[\s*([^\]]+)\s*\]/i);
                    if (offlineMatch) {
                        const nodeNames = offlineMatch[1].trim().split(/\s+/);
                        nodeNames.forEach(name => {
                            if (name && !nodeStatuses.find(n => n.name === name)) {
                                nodeStatuses.push({
                                    name: name,
                                    status: 'offline',
                                    online: false,
                                    isDC: false,
                                    resourcesRunning: 0,
                                    type: 'member',
                                    sourceFile: filename,
                                    sourceLine: lineNum,
                                    sourcePattern: 'Offline: [ ... ]'
                                });
                                debugLog('[clusterStatus parser] Found node (text):', name, 'offline');
                            }
                        });
                    }
                    
                    // Parse individual node lines: "* Node node1 (1): online"
                    const nodeLineMatch = trimmed.match(/\*?\s*Node\s+([^\s:]+)[^:]*:\s*(\w+)/i);
                    if (nodeLineMatch && inNodesSection) {
                        const nodeName = nodeLineMatch[1];
                        const status = nodeLineMatch[2].toLowerCase();
                        
                        if (!nodeStatuses.find(n => n.name === nodeName)) {
                            nodeStatuses.push({
                                name: nodeName,
                                status: status,
                                online: status === 'online',
                                isDC: nodeName === dcNode,
                                resourcesRunning: 0,
                                type: 'member',
                                sourceFile: filename,
                                sourceLine: lineNum,
                                sourcePattern: '* Node <name>: <status>'
                            });
                            debugLog('[clusterStatus parser] Found node (text line):', nodeName, status);
                        }
                    }
                }
            }
            
            if (nodeStatuses.length === 0 && !clusterName && !dcNode) {
                debugLog('[clusterStatus parser] No cluster status information found');
                return { found: false };
            }
            
            debugLog('[clusterStatus parser] Found cluster status:',
                    'Stack:', clusterName,
                    'DC:', dcNode,
                    'Nodes:', nodesConfigured,
                    'Resources:', resourcesConfigured,
                    'Node count:', nodeStatuses.length);
            
            return {
                found: true,
                clusterName: clusterName,
                dcNode: dcNode,
                nodesConfigured: nodesConfigured,
                resourcesConfigured: resourcesConfigured,
                lastUpdated: lastUpdated,
                quorumStatus: quorumStatus,
                nodeStatuses: nodeStatuses
            };
        }
};

// Parser to detect cluster daemon status (corosync, pacemaker, pcsd)
// Detects if services are enabled/disabled for boot
const clusterDaemonStatusParser = {
    // Target file patterns - pcs_status output which contains Daemon Status section
    filePattern: /\/pcs_status|\/ha\.txt$/,
    
    parse: function(content, filename) {
        debugLog('[clusterDaemonStatus parser] Analyzing daemon status in:', filename);
        
        const daemons = {
            corosync: { active: null, enabled: null },
            pacemaker: { active: null, enabled: null },
            pcsd: { active: null, enabled: null }
        };
        const warnings = [];
        let found = false;
        
        // Look for Daemon Status section in pcs status output
        const lines = content.split('\n');
        let inDaemonSection = false;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Detect Daemon Status section
            if (line.match(/^Daemon Status:?$/i)) {
                inDaemonSection = true;
                debugLog('[clusterDaemonStatus parser] Found Daemon Status section at line', i + 1);
                continue;
            }
            
            // Exit daemon section on empty line or new section
            if (inDaemonSection && (line === '' || line.match(/^[A-Z][a-z]+ [A-Z]/))) {
                if (line === '' || !line.match(/^\s*(corosync|pacemaker|pcsd):/i)) {
                    // Only exit if it's truly a new section, not another daemon line
                    if (!line.match(/^\s*(corosync|pacemaker|pcsd):/i)) {
                        inDaemonSection = false;
                    }
                }
            }
            
            if (inDaemonSection) {
                // Parse daemon status lines: "corosync: active/disabled"
                // Format: <daemon>: <active_status>/<enabled_status>
                const daemonMatch = line.match(/^\s*(corosync|pacemaker|pcsd):\s*(\w+)\/(\w+)/i);
                if (daemonMatch) {
                    const daemon = daemonMatch[1].toLowerCase();
                    const activeStatus = daemonMatch[2].toLowerCase();
                    const enabledStatus = daemonMatch[3].toLowerCase();
                    
                    daemons[daemon] = {
                        active: activeStatus === 'active',
                        enabled: enabledStatus === 'enabled'
                    };
                    found = true;
                    
                    debugLog('[clusterDaemonStatus parser] Found', daemon + ':', activeStatus + '/' + enabledStatus);
                    
                    // Generate warnings for critical issues
                    if (daemon === 'corosync' && enabledStatus === 'disabled') {
                        warnings.push({
                            severity: 'error',
                            daemon: 'corosync',
                            message: 'Corosync is disabled and will not start automatically after reboot. Cluster resources will not start after system restart.',
                            recommendation: 'Run "pcs cluster enable --all" or "systemctl enable corosync" on all nodes to enable automatic cluster startup.'
                        });
                    }
                    
                    if (daemon === 'pacemaker' && enabledStatus === 'disabled') {
                        warnings.push({
                            severity: 'warning',
                            daemon: 'pacemaker',
                            message: 'Pacemaker is disabled and will not start automatically after reboot.',
                            recommendation: 'Run "pcs cluster enable --all" or "systemctl enable pacemaker" on all nodes.'
                        });
                    }
                    
                    if (daemon === 'corosync' && activeStatus !== 'active') {
                        warnings.push({
                            severity: 'error',
                            daemon: 'corosync',
                            message: 'Corosync is not running. The cluster cannot function without corosync.',
                            recommendation: 'Run "pcs cluster start" or "systemctl start corosync" to start the cluster.'
                        });
                    }
                    
                    if (daemon === 'pacemaker' && activeStatus !== 'active') {
                        warnings.push({
                            severity: 'error',
                            daemon: 'pacemaker',
                            message: 'Pacemaker is not running. Cluster resources cannot be managed.',
                            recommendation: 'Run "pcs cluster start" or "systemctl start pacemaker" to start the resource manager.'
                        });
                    }
                }
            }
        }
        
        if (!found) {
            debugLog('[clusterDaemonStatus parser] No daemon status found');
            return { found: false };
        }
        
        debugLog('[clusterDaemonStatus parser] Daemon status:',
                'corosync:', daemons.corosync.active ? 'active' : 'inactive', '/', daemons.corosync.enabled ? 'enabled' : 'disabled',
                'pacemaker:', daemons.pacemaker.active ? 'active' : 'inactive', '/', daemons.pacemaker.enabled ? 'enabled' : 'disabled');
        
        return {
            found: true,
            daemons: daemons,
            warnings: warnings,
            corosyncEnabled: daemons.corosync.enabled,
            pacemakerEnabled: daemons.pacemaker.enabled,
            corosyncActive: daemons.corosync.active,
            pacemakerActive: daemons.pacemaker.active
        };
    }
};

// Parser to detect Azure Scheduled Events (health-azure) configuration
// This detects when the health-azure-events resource is not configured or misconfigured
// which can cause resources to not start on nodes
const azureScheduledEventsParser = {
    filePattern: /\/pcs_status.*|\/crm_mon.*|cib\.xml$/,
    
    parse: function(content, filename) {
        debugLog('[azureScheduledEvents parser] Analyzing Azure scheduled events config in:', filename);
        
        const result = {
            found: false,
            healthAzureConfigured: false,
            healthAzureResource: null,
            nodeHealthStrategy: null,
            nodesWithHealthAzure: [],
            nodesWithoutHealthAzure: [],
            stoppedResources: [],
            onlineNodes: [],
            warnings: []
        };
        
        const lines = content.split('\n');
        let inNodeAttributes = false;
        let inResourceList = false;
        let inNodeList = false;
        let currentNode = null;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const trimmed = line.trim();
            
            // Detect section headers
            if (trimmed.match(/^Node Attributes:?$/i) || trimmed.match(/^Node List:?$/i) && trimmed.includes('Attribute')) {
                inNodeAttributes = true;
                inResourceList = false;
                inNodeList = false;
                continue;
            }
            if (trimmed.match(/^Full List of Resources:?$/i) || trimmed.match(/^Active Resources:?$/i) || trimmed.match(/^Resources:?$/i)) {
                inResourceList = true;
                inNodeAttributes = false;
                inNodeList = false;
                continue;
            }
            if (trimmed.match(/^Node List:?$/i) && !trimmed.includes('Attribute')) {
                inNodeList = true;
                inNodeAttributes = false;
                inResourceList = false;
                continue;
            }
            if (trimmed.match(/^Migration Summary:?$/i) || trimmed.match(/^Operations:?$/i) || trimmed.match(/^Fencing History:?$/i)) {
                inNodeAttributes = false;
                inResourceList = false;
                inNodeList = false;
            }
            
            // Parse node list to find online nodes
            if (inNodeList) {
                // Pattern: "* Node vmculnxcmntdb1 (1): online, feature set 3.19.6"
                const nodeMatch = trimmed.match(/^\*?\s*Node\s+(\S+).*:\s*(online|offline)/i);
                if (nodeMatch && nodeMatch[2].toLowerCase() === 'online') {
                    result.onlineNodes.push(nodeMatch[1]);
                }
            }
            
            // Parse node attributes section
            if (inNodeAttributes) {
                // Detect node context: "* Node: vmculnxcmntdb1 (1):"
                const nodeContextMatch = trimmed.match(/^\*?\s*Node:?\s+(\S+)/i);
                if (nodeContextMatch) {
                    currentNode = nodeContextMatch[1].replace(/:$/, '');
                    continue;
                }
                
                // Check for #health-azure attribute
                // Format: "* #health-azure                  : 0" or "#health-azure: 0"
                const healthAzureMatch = trimmed.match(/^\*?\s*#health-azure\s*:\s*(-?\d+|undefined)/i);
                if (healthAzureMatch && currentNode) {
                    result.healthAzureConfigured = true;
                    result.nodesWithHealthAzure.push({
                        node: currentNode,
                        value: healthAzureMatch[1]
                    });
                    debugLog('[azureScheduledEvents parser] Found #health-azure on', currentNode, '=', healthAzureMatch[1]);
                }
            }
            
            // Parse resource list to find stopped resources
            if (inResourceList) {
                // Pattern for stopped resources:
                // "* SAPHana_QH6_00    (ocf:heartbeat:SAPHana):         Stopped"
                // "  * rsc_st_azure        (stonith:fence_azure_arm):       Stopped"
                const stoppedMatch = trimmed.match(/^\*?\s*(\S+)\s+\([^)]+\):\s+Stopped/i);
                if (stoppedMatch) {
                    const resourceName = stoppedMatch[1];
                    // Skip health-azure-events itself from being flagged
                    if (!resourceName.toLowerCase().includes('health-azure')) {
                        result.stoppedResources.push(resourceName);
                    }
                }
                
                // Detect health-azure-events resource
                // Pattern: "* Clone Set: health-azure-events-clone [health-azure-events]:"
                // or "* health-azure-events   (ocf:heartbeat:azure-events-az):  Started"
                if (trimmed.match(/health-azure-events/i)) {
                    result.healthAzureResource = {
                        found: true,
                        line: trimmed
                    };
                }
            }
            
            // Check for node-health-strategy in cluster properties
            // This appears in pcs property or cluster configuration
            const healthStrategyMatch = trimmed.match(/node-health-strategy\s*[:=]\s*(\S+)/i);
            if (healthStrategyMatch) {
                result.nodeHealthStrategy = healthStrategyMatch[1];
            }
        }
        
        // Also check XML content for CIB format
        if (content.includes('<cib') || content.includes('<nvpair')) {
            // Look for health-azure attribute in nvpair elements
            const healthAzureXmlMatch = content.match(/name=["']#health-azure["']\s+value=["']([^"']+)["']/gi);
            if (healthAzureXmlMatch) {
                result.healthAzureConfigured = true;
            }
            
            // Look for node-health-strategy
            const strategyXmlMatch = content.match(/name=["']node-health-strategy["']\s+value=["']([^"']+)["']/i);
            if (strategyXmlMatch) {
                result.nodeHealthStrategy = strategyXmlMatch[1];
            }
            
            // Look for health-azure-events resource
            if (content.match(/health-azure-events/i)) {
                result.healthAzureResource = { found: true, source: 'cib.xml' };
            }
        }
        
        // Determine if we found meaningful data
        result.found = result.onlineNodes.length > 0 || result.stoppedResources.length > 0 || 
                       result.healthAzureConfigured || result.healthAzureResource;
        
        if (!result.found) {
            return { found: false };
        }
        
        // Generate warnings
        // Case 1: Resources are stopped while nodes are online AND health-azure is not configured
        if (result.stoppedResources.length > 0 && result.onlineNodes.length > 0) {
            if (!result.healthAzureConfigured && !result.healthAzureResource) {
                result.warnings.push({
                    severity: 'error',
                    type: 'health_azure_not_configured',
                    message: `${result.stoppedResources.length} cluster resource(s) are stopped while ${result.onlineNodes.length} node(s) are online. Azure Scheduled Events (health-azure) is NOT configured.`,
                    recommendation: 'Configure Azure Scheduled Events by creating the health-azure-events resource and setting #health-azure attribute on all nodes. See: https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker#configure-pacemaker-for-azure-scheduled-events',
                    stoppedResources: result.stoppedResources,
                    onlineNodes: result.onlineNodes
                });
            }
            
            // Case 2: node-health-strategy is set to custom but health-azure attribute is missing
            if (result.nodeHealthStrategy === 'custom' && !result.healthAzureConfigured) {
                result.warnings.push({
                    severity: 'error',
                    type: 'health_azure_attribute_missing',
                    message: 'node-health-strategy is set to "custom" but #health-azure attribute is not configured on nodes. Resources cannot be scheduled.',
                    recommendation: 'Initialize the #health-azure attribute on all nodes: sudo crm_attribute --node <node-name> --name \'#health-azure\' --update 0',
                    onlineNodes: result.onlineNodes
                });
            }
        }
        
        // Case 3: Some nodes have health-azure configured but not all
        if (result.nodesWithHealthAzure.length > 0 && result.onlineNodes.length > result.nodesWithHealthAzure.length) {
            const nodesWithAttr = result.nodesWithHealthAzure.map(n => n.node);
            const nodesMissing = result.onlineNodes.filter(n => !nodesWithAttr.includes(n));
            if (nodesMissing.length > 0) {
                result.nodesWithoutHealthAzure = nodesMissing;
                result.warnings.push({
                    severity: 'warning',
                    type: 'health_azure_partial',
                    message: `#health-azure attribute is configured on some nodes but missing on: ${nodesMissing.join(', ')}`,
                    recommendation: 'Set the #health-azure attribute on all cluster nodes for consistent behavior.',
                    nodesMissing: nodesMissing
                });
            }
        }
        
        debugLog('[azureScheduledEvents parser] Results:', 
                'healthAzureConfigured:', result.healthAzureConfigured,
                'stoppedResources:', result.stoppedResources.length,
                'onlineNodes:', result.onlineNodes.length,
                'warnings:', result.warnings.length);
        
        return result;
    }
};

const fencingConfigParser = {
        // Target file patterns - match cib.xml anywhere in the archive, pcs_config, pcs_property
        filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/crm.*config$|stonith|\/ha\.txt$|\/pcs_config$|\/pcs_property/,
        
        parse: function(content, filename) {
            debugLog('[fencingConfig parser] Analyzing fencing configuration in:', filename);
            
            const fencingDevices = [];
            let stonithEnabled = null;
            let stonithSourceFile = null;
            let stonithSourcePattern = null;
            
            // If content contains XML (CIB format), use XML parser for upfront extraction
            if (content.includes('<primitive') || content.includes('<nvpair')) {
                debugLog('[fencingConfig parser] Detected XML format, using custom XML parser');
                
                // Extract only the CIB XML section if this is ha.txt with embedded content
                let xmlContent = content;
                if (filename.includes('ha.txt')) {
                    // Try to extract the cibadmin -Q section
                    const cibSection = extractSection(content, filename, '# /usr/sbin/cibadmin -Q', 'cib.xml', debugLog);
                    if (cibSection.found) {
                        xmlContent = cibSection.content;
                        debugLog('[fencingConfig parser] Extracted CIB section from ha.txt:', cibSection.lines.length, 'lines');
                    }
                }
                
                const elements = parseXMLSimple(xmlContent);
                
                // Check stonith-enabled setting from nvpair elements
                const nvpairs = querySelectorAll(elements, 'nvpair');
                nvpairs.forEach(nvpair => {
                    const attrs = nvpair.attributes;
                    if (attrs.name === 'stonith-enabled') {
                        if (attrs.value === 'true') {
                            stonithEnabled = true;
                            stonithSourceFile = filename;
                            stonithSourcePattern = '<nvpair name="stonith-enabled" value="true"/>';
                        } else if (attrs.value === 'false') {
                            stonithEnabled = false;
                            stonithSourceFile = filename;
                            stonithSourcePattern = '<nvpair name="stonith-enabled" value="false"/>';
                        }
                    }
                });
                
                // Extract fencing devices from primitive elements
                const primitives = querySelectorAll(elements, 'primitive');
                debugLog('[fencingConfig parser] Found', primitives.length, 'primitive elements');
                primitives.forEach(primitive => {
                    const attrs = primitive.attributes;
                    const deviceName = attrs.id;
                    const agentType = attrs.type;
                    const agentClass = attrs.class;
                    
                    // Check for Azure fence_azure_arm
                    if (agentType && agentType.includes('fence_azure_arm')) {
                        if (deviceName && !fencingDevices.find(d => d.name === deviceName)) {
                            fencingDevices.push({
                                name: deviceName,
                                type: 'fence_azure_arm',
                                agent: 'Azure Fencing Agent',
                                cloud: 'Azure',
                                sourceFile: filename,
                                sourceLine: 0,
                                pattern: 'XML: <primitive ... type="fence_azure_arm">'
                            });
                            debugLog('[fencingConfig parser] Found Azure fencing agent (XML):', deviceName);
                        }
                    }
                    // Check for other stonith devices
                    else if (agentClass === 'stonith' && deviceName && agentType) {
                        if (!fencingDevices.find(d => d.name === deviceName)) {
                            let agent = agentType;
                            let cloud = null;
                            
                            // Handle external/sbd format
                            if (agentType.startsWith('external/')) {
                                const externalType = agentType.split('/')[1];
                                agent = `External ${externalType.toUpperCase()}`;
                            } else if (agentType.includes('azure')) {
                                agent = 'Azure Fencing';
                                cloud = 'Azure';
                            } else if (agentType.includes('aws')) {
                                agent = 'AWS Fencing';
                                cloud = 'AWS';
                            } else if (agentType.includes('gce')) {
                                agent = 'GCP Fencing';
                                cloud = 'GCP';
                            } else if (agentType.startsWith('fence_')) {
                                const fenceType = agentType.replace('fence_', '');
                                agent = `Fence ${fenceType.toUpperCase()}`;
                            }
                            
                            fencingDevices.push({
                                name: deviceName,
                                type: agentType,
                                agent: agent,
                                cloud: cloud,
                                sourceFile: filename,
                                sourceLine: 0,
                                pattern: `XML: <primitive class="stonith" type="${agentType}">`
                            });
                            debugLog('[fencingConfig parser] Found fencing device (XML):', deviceName, agentType);
                        }
                    }
                });
            }
            
            // Parse line-by-line for non-XML formats (crm config, pcs config, etc.)
            const lines = content.split('\n');
            for (let lineNum = 0; lineNum < lines.length; lineNum++) {
                const line = lines[lineNum];
                const trimmed = line.trim();
                
                // Check if STONITH is enabled (non-XML format)
                // Format: stonith-enabled=true or stonith-enabled: true (pcs format)
                if (trimmed.match(/stonith-enabled[=:\s]*true/i) && !trimmed.includes('<')) {
                    stonithEnabled = true;
                    stonithSourceFile = filename;
                    stonithSourcePattern = 'stonith-enabled: true';
                    debugLog('[fencingConfig parser] STONITH is enabled at line', lineNum + 1);
                }
                
                if (trimmed.match(/stonith-enabled[=:\s]*false/i) && !trimmed.includes('<')) {
                    stonithEnabled = false;
                    stonithSourceFile = filename;
                    stonithSourcePattern = 'stonith-enabled: false';
                    debugLog('[fencingConfig parser] STONITH is disabled at line', lineNum + 1);
                }
                
                // Detect Azure fencing agent in crm config format (non-XML)
                // crm: primitive stonith-fence_azure_arm stonith:fence_azure_arm
                const azureFenceMatch = trimmed.match(/^primitive\s+([^\s]+).*?(?:stonith:)?fence_azure_arm/);
                if (azureFenceMatch && !trimmed.includes('<')) {
                    const deviceName = azureFenceMatch[1];
                    if (!fencingDevices.find(d => d.name === deviceName)) {
                        fencingDevices.push({
                            name: deviceName,
                            type: 'fence_azure_arm',
                            agent: 'Azure Fencing Agent',
                            cloud: 'Azure',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            pattern: 'crm: primitive ... fence_azure_arm'
                        });
                        debugLog('[fencingConfig parser] Found Azure fencing agent (crm):', deviceName, 'at line', lineNum + 1);
                    }
                }
                
                // Detect pcs_config format: Resource: <name> (class=stonith type=fence_azure_arm)
                const pcsAzureFenceMatch = trimmed.match(/^Resource:\s+([^\s]+)\s+\(class=stonith\s+type=fence_azure_arm/);
                if (pcsAzureFenceMatch) {
                    const deviceName = pcsAzureFenceMatch[1];
                    if (!fencingDevices.find(d => d.name === deviceName)) {
                        fencingDevices.push({
                            name: deviceName,
                            type: 'fence_azure_arm',
                            agent: 'Azure Fencing Agent',
                            cloud: 'Azure',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            pattern: 'pcs: Resource ... (class=stonith type=fence_azure_arm)'
                        });
                        debugLog('[fencingConfig parser] Found Azure fencing agent (pcs):', deviceName, 'at line', lineNum + 1);
                    }
                }
                
                // Detect other common fencing agents in crm config format (non-XML)
                const fenceMatch = trimmed.match(/^primitive\s+([^\s]+).*?stonith:(\S+)/);
                if (fenceMatch && !trimmed.includes('<')) {
                    const [, deviceName, agentType] = fenceMatch;
                    if (!fencingDevices.find(d => d.name === deviceName)) {
                        let agent = agentType;
                        let cloud = null;
                        
                        // Identify cloud-specific agents
                        if (agentType.includes('azure')) {
                            agent = 'Azure Fencing';
                            cloud = 'Azure';
                        } else if (agentType.includes('aws')) {
                            agent = 'AWS Fencing';
                            cloud = 'AWS';
                        } else if (agentType.includes('gce')) {
                            agent = 'GCP Fencing';
                            cloud = 'GCP';
                        }
                        
                        fencingDevices.push({
                            name: deviceName,
                            type: agentType,
                            agent: agent,
                            cloud: cloud,
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            pattern: `crm: primitive ... stonith:${agentType}`
                        });
                        debugLog('[fencingConfig parser] Found fencing device (crm):', deviceName, agentType, 'at line', lineNum + 1);
                    }
                }
                
                // Detect pcs_config format for other stonith types: Resource: <name> (class=stonith type=<type>)
                const pcsFenceMatch = trimmed.match(/^Resource:\s+([^\s]+)\s+\(class=stonith\s+type=([^)\s]+)/);
                if (pcsFenceMatch && !fencingDevices.find(d => d.name === pcsFenceMatch[1])) {
                    const [, deviceName, agentType] = pcsFenceMatch;
                    let agent = agentType;
                    let cloud = null;
                    
                    // Identify cloud-specific agents
                    if (agentType.includes('azure')) {
                        agent = 'Azure Fencing';
                        cloud = 'Azure';
                    } else if (agentType.includes('aws')) {
                        agent = 'AWS Fencing';
                        cloud = 'AWS';
                    } else if (agentType.includes('gce')) {
                        agent = 'GCP Fencing';
                        cloud = 'GCP';
                    }
                    
                    fencingDevices.push({
                        name: deviceName,
                        type: agentType,
                        agent: agent,
                        cloud: cloud,
                        sourceFile: filename,
                        sourceLine: lineNum + 1,
                        pattern: `pcs: Resource ... (class=stonith type=${agentType})`
                    });
                    debugLog('[fencingConfig parser] Found fencing device (pcs):', deviceName, agentType, 'at line', lineNum + 1);
                }
            }
            
            // If we found fencing devices but stonith-enabled wasn't explicitly set, infer it's enabled
            if (fencingDevices.length > 0 && stonithEnabled === null) {
                stonithEnabled = true;
                stonithSourceFile = filename;
                stonithSourcePattern = 'Inferred from presence of stonith devices';
                debugLog('[fencingConfig parser] STONITH status inferred as enabled (found', fencingDevices.length, 'devices)');
            }
            
            debugLog('[fencingConfig parser] STONITH enabled:', stonithEnabled);
            debugLog('[fencingConfig parser] Found', fencingDevices.length, 'fencing devices');
            
            return {
                found: true,
                stonithEnabled: stonithEnabled,
                stonithSourceFile: stonithSourceFile,
                stonithSourcePattern: stonithSourcePattern,
                fencingDevices: fencingDevices,
                count: fencingDevices.length
            };
        }
};

const clusterEventsParser = {
        // This is a multi-file rule that accumulates events from multiple log files
        multiFile: true,
        // Process all rotated log files for comprehensive cluster event history
        processAllRotations: true,
        // Target file patterns - pacemaker.log, corosync.log, cluster.log, ha-log, messages
        // Also includes journalctl output and crm_report archives
        // Includes rotated logs (.log-1, .log.1, etc.) and compressed logs (.gz)
        // Also includes ha.txt (supportconfig) which embeds pacemaker/corosync log sections
        filePattern: /\/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?(?:\.gz)?$|\/ha\.txt$/,
        
        // System services and resources that should NOT be detected as cluster resources
        // These are common systemd/init services that can appear in logs with similar formatting
        systemResourceBlacklist: /^(Getty|getty|Login|Console|Session|User|Seat|agetty|mingetty|mgetty|plymouth|systemd-|dbus|polkit|NetworkManager|ModemManager|firewalld|sshd|crond?|rsyslog|auditd|chronyd?|ntpd?)$/i,
        
        // Non-cluster node patterns - tty, pts, console identifiers that are not actual cluster nodes
        nonClusterNodePattern: /^(tty\d*|pts\/?\d*|console|localhost|127\.0\.0\.1|::1|\d+)$/i,
        
        /**
         * Extract log sections from supportconfig ha.txt
         * ha.txt embeds pacemaker/corosync logs under #==[ Log File ]====# markers
         * Returns concatenated content from all matching log sections
         */
        extractLogSectionsFromHaTxt: function(content) {
            const sectionParts = content.split(/^(#==\[.*?\]====.*$)/m);
            const logSections = [];
            
            for (let i = 0; i < sectionParts.length; i++) {
                const part = sectionParts[i];
                
                // Check if this is a Log File section marker containing pacemaker or corosync logs
                if (part.match(/^#==\[\s*Log File\s*\]====/)) {
                    // Check if the marker references cluster log files
                    if (part.match(/pacemaker|corosync|cluster\.log|ha-log/i)) {
                        // Next part is the section content
                        if (i + 1 < sectionParts.length) {
                            const sectionContent = sectionParts[i + 1];
                            if (sectionContent && sectionContent.trim()) {
                                logSections.push(sectionContent);
                                debugLog('[clusterEvents parser] Extracted log section from ha.txt:', part.trim().substring(0, 120));
                            }
                        }
                    }
                }
                
                // Also check Command sections that contain cluster log output
                // e.g., journalctl commands filtering pacemaker/corosync
                if (part.match(/^#==\[\s*Command\s*\]====/)) {
                    if (part.match(/journalctl.*(?:pacemaker|corosync)|pacemaker.*log|corosync.*log/i)) {
                        if (i + 1 < sectionParts.length) {
                            const sectionContent = sectionParts[i + 1];
                            if (sectionContent && sectionContent.trim()) {
                                logSections.push(sectionContent);
                                debugLog('[clusterEvents parser] Extracted command log section from ha.txt:', part.trim().substring(0, 120));
                            }
                        }
                    }
                }
            }
            
            debugLog('[clusterEvents parser] Extracted', logSections.length, 'log sections from ha.txt');
            return logSections;
        },
        
        parse: function(content, filename) {
            debugLog('[clusterEvents parser] Analyzing cluster logs in:', filename, 'lines:', content.split('\n').length);
            
            // For supportconfig ha.txt, extract embedded log sections
            if (filename.includes('ha.txt')) {
                debugLog('[clusterEvents parser] Detected ha.txt (supportconfig), extracting embedded log sections');
                const logSections = this.extractLogSectionsFromHaTxt(content);
                
                if (logSections.length === 0) {
                    debugLog('[clusterEvents parser] No log sections found in ha.txt');
                    return { found: false };
                }
                
                // Parse each extracted log section and merge results
                const allResourceMigrations = [];
                const allFencingEvents = [];
                
                for (const section of logSections) {
                    const result = this.parseLogContent(section, filename);
                    if (result.found) {
                        allResourceMigrations.push(...(result.resourceMigrations || []));
                        allFencingEvents.push(...(result.fencingEvents || []));
                    }
                }
                
                debugLog('[clusterEvents parser] ha.txt total:', allResourceMigrations.length, 'resource events,', allFencingEvents.length, 'fencing events');
                
                if (allResourceMigrations.length === 0 && allFencingEvents.length === 0) {
                    return { found: false };
                }
                
                return {
                    found: true,
                    resourceMigrations: allResourceMigrations,
                    fencingEvents: allFencingEvents,
                    totalEvents: allResourceMigrations.length + allFencingEvents.length,
                    count: allResourceMigrations.length + allFencingEvents.length
                };
            }
            
            // For direct log files, parse content directly
            return this.parseLogContent(content, filename);
        },
        
        parseLogContent: function(content, filename) {
            debugLog('[clusterEvents parser] Parsing log content from:', filename, 'lines:', content.split('\n').length);
            
            const resourceMigrations = [];
            const fencingEvents = [];
            const lines = content.split('\n');
            
            for (let lineNum = 0; lineNum < lines.length; lineNum++) {
                const line = lines[lineNum];
                const trimmed = line.trim();
                
                // Skip empty lines
                if (!trimmed) continue;
                
                // Parse timestamp (various formats supported)
                // ISO format: 2025-11-11T10:30:45.123456+00:00
                // Syslog format: Aug 23 14:31:48
                // Syslog with hostname: Aug 23 14:31:48 hostname process[pid]
                // Journal format: Nov 11 10:30:45.123456
                let timestamp = null;
                const isoMatch = trimmed.match(/^(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)/);
                const syslogMatch = trimmed.match(/^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)/);
                
                if (isoMatch) {
                    timestamp = isoMatch[1];
                } else if (syslogMatch) {
                    timestamp = syslogMatch[1];
                }
                
                // For syslog format, extract just the message part after hostname/process
                // Format: Aug 23 14:31:48 hostname process[pid] (function) level: message
                // We want to search in the full line but extract structured data from the message part
                let messageText = trimmed;
                const syslogParts = trimmed.match(/^\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?\s+\S+\s+\S+\s+(.+)$/);
                if (syslogParts) {
                    messageText = syslogParts[1]; // Everything after hostname and process
                    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.cluster && lineNum < 5) {
                        debugLog('Syslog line', lineNum, 'extracted messageText:', messageText);
                    }
                }
                
                // Log first few lines to see what we're processing
                if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.cluster && lineNum < 5 && (messageText.toLowerCase().includes('unexpected') || messageText.toLowerCase().includes('fence') || messageText.toLowerCase().includes('stonith'))) {
                    debugLog('Line', lineNum, 'messageText:', messageText);
                }
                
                // Detect resource migration/move events
                // Patterns:
                // - "Moving resource <resource> from <node1> to <node2>"
                // - "Migrating <resource> from <node1> to <node2>"
                // - "notice: pcmk_graph_info: Transition: Starting <resource> on <node>"
                // - "notice: Operation <resource>_start_0: ok (node=<node>)"
                // - "Resource <resource> is active on <node> (previously on <node>)"
                
                const moveMatch = messageText.match(/(?:Moving|Migrating)\s+(?:resource\s+)?(\S+)\s+from\s+(\S+)\s+to\s+(\S+)/i);
                if (moveMatch) {
                    const [, resource, fromNode, toNode] = moveMatch;
                    resourceMigrations.push({
                        timestamp: timestamp,
                        resource: resource,
                        fromNode: fromNode,
                        toNode: toNode,
                        action: 'migration',
                        sourceFile: filename,
                        sourceLine: lineNum + 1,
                        logLine: trimmed.substring(0, 200) // Truncate long lines
                    });
                    debugLog('[clusterEvents parser] Found resource migration:', resource, 'from', fromNode, 'to', toNode);
                    continue;
                }
                
                // Starting resource on node
                // Only match Pacemaker cluster resource start events
                // Explicitly reject systemd and init script messages
                const startMatch = messageText.match(/(?:Starting|Transition.*Starting)\s+(\S+)\s+on\s+(\S+)/i);
                if (startMatch) {
                    const [, resource, node] = startMatch;
                    
                    // Reject systemd messages explicitly
                    if (messageText.includes('systemd')) continue;
                    
                    // Reject lines with process ID patterns like [123]:
                    if (/\[\d+\]:/.test(messageText)) continue;
                    
                    // Exclude systemd service type names
                    const isSystemdService = resource.match(/\.(service|target|socket|mount|swap|path|timer|device|scope|slice)$/i) ||
                                            resource.includes('@');  // systemd template units like service@instance
                    
                    // Filter out known system resources (Getty, login services, etc.)
                    const isSystemResource = this.systemResourceBlacklist.test(resource);
                    
                    // Filter out non-cluster node names (tty1, pts/0, console, etc.)
                    const isNonClusterNode = this.nonClusterNodePattern.test(node);
                    
                    // Only add if not systemd service, not system resource, valid cluster node, and not a duplicate
                    if (!isSystemdService && !isSystemResource && !isNonClusterNode &&
                        !resourceMigrations.find(m => m.resource === resource && m.toNode === node && m.sourceLine === lineNum + 1)) {
                        resourceMigrations.push({
                            timestamp: timestamp,
                            resource: resource,
                            fromNode: null,
                            toNode: node,
                            action: 'start',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found resource start:', resource, 'on', node);
                    }
                    continue;
                }
                
                // Stopping resource on node
                // Only match Pacemaker cluster resource stop events
                // Explicitly reject systemd and init script messages
                const stopMatch = messageText.match(/(?:Stopping|Stopped)\s+(\S+)\s+on\s+(\S+)/i);
                if (stopMatch) {
                    const [, resource, node] = stopMatch;
                    
                    // Reject systemd messages explicitly
                    if (messageText.includes('systemd')) continue;
                    
                    // Reject lines with process ID patterns like [123]:
                    if (/\[\d+\]:/.test(messageText)) continue;
                    
                    // Exclude systemd service type names
                    const isSystemdService = resource.match(/\.(service|target|socket|mount|swap|path|timer|device|scope|slice)$/i) ||
                                            resource.includes('@');  // systemd template units like service@instance
                    
                    // Filter out known system resources (Getty, login services, etc.)
                    const isSystemResource = this.systemResourceBlacklist.test(resource);
                    
                    // Filter out non-cluster node names (tty1, pts/0, console, etc.)
                    const isNonClusterNode = this.nonClusterNodePattern.test(node);
                    
                    if (!isSystemdService && !isSystemResource && !isNonClusterNode) {
                        resourceMigrations.push({
                            timestamp: timestamp,
                            resource: resource,
                            fromNode: node,
                            toNode: null,
                            action: 'stop',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found resource stop:', resource, 'on', node);
                    }
                    continue;
                }
                
                // Resource operation format: "Operation resource_start_0: ok (node=nodeX)"
                const opMatch = messageText.match(/Operation\s+(\S+?)_(?:start|stop|monitor|migrate)_\d+:\s*\w+\s*\(node=(\S+)\)/i);
                if (opMatch) {
                    const [, resource, node] = opMatch;
                    const isStart = messageText.includes('_start_');
                    const isStop = messageText.includes('_stop_');
                    
                    if (isStart) {
                        if (!resourceMigrations.find(m => m.resource === resource && m.toNode === node && m.sourceLine === lineNum + 1)) {
                            resourceMigrations.push({
                                timestamp: timestamp,
                                resource: resource,
                                fromNode: null,
                                toNode: node,
                                action: 'start',
                                sourceFile: filename,
                                sourceLine: lineNum + 1,
                                logLine: trimmed.substring(0, 200)
                            });
                            debugLog('[clusterEvents parser] Found resource operation start:', resource, 'on', node);
                        }
                    } else if (isStop) {
                        resourceMigrations.push({
                            timestamp: timestamp,
                            resource: resource,
                            fromNode: node,
                            toNode: null,
                            action: 'stop',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found resource operation stop:', resource, 'on', node);
                    }
                    continue;
                }
                
                // Detect fencing/STONITH events
                // Patterns:
                // - "stonith-ng: Succeeded: st_notify"
                // - "Fencing <node>: success"
                // - "stonith: Succeeded: st_delete_device_0 on <node>"
                // - "Requesting fencing ([on|reboot|off]) of node <node>"
                // - "Requesting fencing (reboot) targeting node <node>" (RHEL/sosreport format)
                // - "fence_azure_arm: Called fence_azure_arm for <node>"
                // - "Node <node> will be fenced"
                
                const fenceRequestMatch = trimmed.match(/Requesting\s+fencing\s+\((\w+)\)\s+(?:of\s+|targeting\s+)?(?:node\s+)?(\S+)/i);
                if (fenceRequestMatch) {
                    const [, action, node] = fenceRequestMatch;
                    fencingEvents.push({
                        timestamp: timestamp,
                        targetNode: node,
                        action: action,
                        status: 'requested',
                        sourceFile: filename,
                        sourceLine: lineNum + 1,
                        logLine: trimmed.substring(0, 200)
                    });
                    debugLog('[clusterEvents parser] Found fencing request:', action, 'of node', node);
                    continue;
                }
                
                const fenceSuccessMatch = messageText.match(/(?:Fencing|stonith.*?fence)\s+(\S+).*?(?:success|succeeded)/i);
                if (fenceSuccessMatch) {
                    const node = fenceSuccessMatch[1];
                    fencingEvents.push({
                        timestamp: timestamp,
                        targetNode: node,
                        action: 'fence',
                        status: 'success',
                        sourceFile: filename,
                        sourceLine: lineNum + 1,
                        logLine: trimmed.substring(0, 200)
                    });
                    debugLog('[clusterEvents parser] Found successful fencing event:', node);
                    continue;
                }
                
                // Additional success patterns
                // "Operation stonith-X_monitor_0: ok" or "Operation X_reboot_0: ok"
                const stonithOpSuccess = messageText.match(/Operation\s+(?:stonith-)?(\S+?)_(?:reboot|monitor|on|off)_\d+:\s*ok/i);
                if (stonithOpSuccess && (messageText.toLowerCase().includes('stonith') || messageText.toLowerCase().includes('fence'))) {
                    const node = stonithOpSuccess[1];
                    if (!fencingEvents.find(e => e.targetNode === node && e.sourceLine === lineNum + 1)) {
                        fencingEvents.push({
                            timestamp: timestamp,
                            targetNode: node,
                            action: 'fence',
                            status: 'success',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found successful stonith operation:', node);
                    }
                    continue;
                }
                
                // "Peer <node> was terminated (reboot) by <initiator> on behalf of"
                // "stonith_api_time: <node> was fenced (reboot) by <source>"
                const peerTerminated = messageText.match(/(?:Peer|peer)\s+(\S+)\s+was\s+(?:terminated|fenced)\s+\((\w+)\)/i);
                if (peerTerminated) {
                    const [, node, action] = peerTerminated;
                    if (!fencingEvents.find(e => e.targetNode === node && e.sourceLine === lineNum + 1)) {
                        fencingEvents.push({
                            timestamp: timestamp,
                            targetNode: node,
                            action: action,
                            status: 'success',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found peer termination (success):', node, action);
                    }
                    continue;
                }
                
                // "Peer <node> was not terminated (reboot)" — fencing failure
                const peerNotTerminated = messageText.match(/(?:Peer|peer)\s+(\S+)\s+was\s+not\s+terminated\s+\((\w+)\)/i);
                if (peerNotTerminated) {
                    const [, node, action] = peerNotTerminated;
                    if (!fencingEvents.find(e => e.targetNode === node && e.sourceLine === lineNum + 1)) {
                        fencingEvents.push({
                            timestamp: timestamp,
                            targetNode: node,
                            action: action,
                            status: 'failed',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found peer termination FAILURE:', node, action);
                    }
                    continue;
                }
                
                // "stonith_api_time: <node> was fenced successfully"
                const apiSuccess = messageText.match(/stonith.*?(\S+)\s+was\s+fenced\s+successfully/i);
                if (apiSuccess) {
                    const node = apiSuccess[1];
                    if (!fencingEvents.find(e => e.targetNode === node && e.sourceLine === lineNum + 1)) {
                        fencingEvents.push({
                            timestamp: timestamp,
                            targetNode: node,
                            action: 'fence',
                            status: 'success',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found stonith API success:', node);
                    }
                    continue;
                }
                
                const fenceFailMatch = messageText.match(/(?:Fencing|stonith.*?fence)\s+(\S+).*?(?:fail|error)/i);
                if (fenceFailMatch) {
                    const node = fenceFailMatch[1];
                    fencingEvents.push({
                        timestamp: timestamp,
                        targetNode: node,
                        action: 'fence',
                        status: 'failed',
                        sourceFile: filename,
                        sourceLine: lineNum + 1,
                        logLine: trimmed.substring(0, 200)
                    });
                    debugLog('[clusterEvents parser] Found failed fencing event:', node);
                    continue;
                }
                
                // "Node <node> will be fenced" / "Cluster node <node> will be fenced"
                const fenceWillMatch = messageText.match(/(?:Cluster\s+node|Node|peer)\s+(\S+)\s+will\s+be\s+fenced/i);
                if (fenceWillMatch) {
                    const node = fenceWillMatch[1];
                    if (!fencingEvents.find(e => e.targetNode === node && e.sourceLine === lineNum + 1)) {
                        fencingEvents.push({
                            timestamp: timestamp,
                            targetNode: node,
                            action: 'fence',
                            status: 'pending',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found pending fencing:', node);
                    }
                    continue;
                }
                
                // fence_azure_arm or other fence agent calls
                const fenceAgentMatch = messageText.match(/(fence_\w+).*?(?:Called|for)\s+.*?(?:node\s+)?(\S+)/i);
                if (fenceAgentMatch && (messageText.toLowerCase().includes('fence') || messageText.toLowerCase().includes('stonith'))) {
                    const [, agent, node] = fenceAgentMatch;
                    if (!fencingEvents.find(e => e.targetNode === node && e.sourceLine === lineNum + 1)) {
                        fencingEvents.push({
                            timestamp: timestamp,
                            targetNode: node,
                            action: 'fence',
                            agent: agent,
                            status: 'in_progress',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 200)
                        });
                        debugLog('[clusterEvents parser] Found fence agent call:', agent, 'for node', node);
                    }
                    continue;
                }
                
                // Resource operation failures and monitor errors
                // "Unexpected result (error: ...) was recorded for monitor of <resource> on <node>"
                const monitorFailureMatch = messageText.match(/Unexpected\s+result\s+\((error|failed|timeout|not running):\s*([^)]+)\).*?(?:for\s+(?:monitor|start|stop|promote|demote)\s+of\s+)?(\S+?)(?::(\d+))?\s+on\s+(\S+)/i);
                if (monitorFailureMatch) {
                    debugLog('Found monitorFailure match on line', lineNum, ':', messageText);
                    const [, errorType, errorReason, resource, instance, node] = monitorFailureMatch;
                    const fullResource = instance ? `${resource}:${instance}` : resource;
                    resourceMigrations.push({
                        timestamp: timestamp,
                        resource: fullResource,
                        fromNode: node,
                        toNode: null,
                        action: 'failure',
                        error: `${errorType}: ${errorReason.trim()}`,
                        sourceFile: filename,
                        sourceLine: lineNum + 1,
                        logLine: trimmed.substring(0, 250)
                    });
                    debugLog('[clusterEvents parser] Found resource failure:', fullResource, 'on', node, '-', errorType);
                    continue;
                }
                
                // Operation timeout: "Resource agent did not complete within Xs"
                const timeoutMatch = messageText.match(/(?:Resource agent did not complete within|operation.* timed out after)\s+(\d+)s/i);
                if (timeoutMatch && (messageText.includes('monitor') || messageText.includes('start') || messageText.includes('stop') || messageText.includes('promote'))) {
                    const timeout = timeoutMatch[1];
                    // Try to extract resource name from the line
                    const resourceMatch = messageText.match(/(?:of|for)\s+([^\s:]+)(?::(\d+))?(?:\s+on\s+(\S+))?/i);
                    if (resourceMatch) {
                        const [, resource, instance, node] = resourceMatch;
                        const fullResource = instance ? `${resource}:${instance}` : resource;
                        resourceMigrations.push({
                            timestamp: timestamp,
                            resource: fullResource,
                            fromNode: node || 'unknown',
                            toNode: null,
                            action: 'timeout',
                            error: `Operation timeout after ${timeout}s`,
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            logLine: trimmed.substring(0, 250)
                        });
                        debugLog('[clusterEvents parser] Found resource timeout:', fullResource, 'after', timeout, 'seconds');
                    }
                    continue;
                }
                
                // Transition failures: "expected 'promoted' but got 'error'"
                const transitionFailMatch = messageText.match(/Transition\s+\d+\s+action\s+\d+\s+\(([^)]+)_(?:monitor|start|stop|promote|demote)_\d+\s+on\s+(\S+)\).*?expected\s+'([^']+)'\s+but\s+got\s+'([^']+)'/i);
                if (transitionFailMatch) {
                    const [, resource, node, expected, actual] = transitionFailMatch;
                    resourceMigrations.push({
                        timestamp: timestamp,
                        resource: resource,
                        fromNode: node,
                        toNode: null,
                        action: 'transition_failure',
                        error: `Expected '${expected}' but got '${actual}'`,
                        sourceFile: filename,
                        sourceLine: lineNum + 1,
                        logLine: trimmed.substring(0, 250)
                    });
                    debugLog('[clusterEvents parser] Found transition failure:', resource, 'on', node, '- expected', expected, 'got', actual);
                    continue;
                }
            }
            
            debugLog('[clusterEvents parser] Found', resourceMigrations.length, 'resource events and', fencingEvents.length, 'fencing events in', filename);
            
            if (resourceMigrations.length === 0 && fencingEvents.length === 0) {
                debugLog('[clusterEvents parser] No cluster events found');
                return { found: false };
            }
            
            debugLog('[clusterEvents parser] Found', resourceMigrations.length, 'resource events and', fencingEvents.length, 'fencing events');
            return {
                found: true,
                resourceMigrations: resourceMigrations,
                fencingEvents: fencingEvents,
                totalEvents: resourceMigrations.length + fencingEvents.length,
                count: resourceMigrations.length + fencingEvents.length
            };
        }
};

const liveMigrationParser = {
        // Target file path patterns
        // supportconfig: */messages or */localmessages (with optional suffixes)
        // sosreport: */var/log/messages or */sos_commands/logs/journalctl*
        // Matches: messages, messages.1, messages-20251007.txt, localmessages, etc.
        filePattern: /\/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|localmessages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
        
        // Parse function receives file content as string
        // Detects Live Migration events by finding the sequence:
        // "hv_utils: Heartbeat IC" -> "hv_balloon" -> "hv_netvsc" within 100 lines
        // Returns array of detected migration events with timestamps
        parse: function(content) {
            const lines = content.split('\n');
            const migrations = [];
            
            debugLog('[liveMigration parser] Analyzing', lines.length, 'lines');
            
            // Debug: Count occurrences of each pattern
            let heartbeatCount = 0;
            let balloonCount = 0;
            let netvscCount = 0;
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                
                // Count patterns for debugging
                if (line.includes('hv_utils: Heartbeat IC')) heartbeatCount++;
                if (line.includes('hv_balloon')) balloonCount++;
                if (line.includes('hv_netvsc')) netvscCount++;
                
                // Look for first pattern: "hv_utils: Heartbeat IC"
                if (line.includes('hv_utils: Heartbeat IC')) {
                    const heartbeatLine = i;
                    const heartbeatTimestamp = SCC_RULES.extractTimestamp(line);
                    
                    debugLog('[liveMigration parser] Found hv_utils at line', i + 1, ':', heartbeatTimestamp);
                    
                    // Search next 100 lines for "hv_balloon"
                    let balloonLine = -1;
                    for (let j = i + 1; j < Math.min(i + 100, lines.length); j++) {
                        if (lines[j].includes('hv_balloon')) {
                            balloonLine = j;
                            debugLog('[liveMigration parser] Found hv_balloon at line', j + 1, '(+' + (j - i) + ' lines)');
                            break;
                        }
                    }
                    
                    // If found hv_balloon, search for "hv_netvsc"
                    if (balloonLine !== -1) {
                        let netvscLine = -1;
                        for (let k = balloonLine + 1; k < Math.min(heartbeatLine + 100, lines.length); k++) {
                            if (lines[k].includes('hv_netvsc')) {
                                netvscLine = k;
                                debugLog('[liveMigration parser] Found hv_netvsc at line', k + 1, '(+' + (k - heartbeatLine) + ' lines from heartbeat)');
                                break;
                            }
                        }
                        
                        // If found all three, we detected a Live Migration
                        if (netvscLine !== -1) {
                            // Extract timestamp from the heartbeat line
                            const timestamp = SCC_RULES.extractTimestamp(lines[heartbeatLine]);
                            
                            debugLog('[liveMigration parser] Extracted timestamp:', timestamp, 'from line:', lines[heartbeatLine].substring(0, 100));
                            
                            migrations.push({
                                timestamp: timestamp || 'Unknown',
                                lineNumber: heartbeatLine + 1,
                                rawLine: lines[heartbeatLine]
                            });
                            
                            debugLog('[liveMigration parser] ✓ Detected migration at line', heartbeatLine + 1, ':', timestamp);
                            
                            // Skip ahead to avoid duplicate detections
                            i = netvscLine;
                        } else {
                            debugLog('[liveMigration parser] ✗ No hv_netvsc found within range');
                        }
                    } else {
                        debugLog('[liveMigration parser] ✗ No hv_balloon found within 100 lines');
                    }
                }
            }
            
            debugLog('[liveMigration parser] Pattern summary: heartbeat=' + heartbeatCount + ', balloon=' + balloonCount + ', netvsc=' + netvscCount);
            debugLog('[liveMigration parser] Found', migrations.length, 'Live Migration events');
            
            return {
                found: migrations.length > 0,
                count: migrations.length,
                events: migrations
            };
        }
};

// Parser to detect SAP SAPInstance resource configuration issues
// Detects START_PROFILE mismatches, InstanceName issues, and validates configuration
// Reference: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux_for_sap_solutions/8/html/configuring_ha_clusters_to_manage_sap_netweaver_or_sap_s4hana_application_server_instances_using_the_rhel_ha_add-on
const sapInstanceConfigParser = {
    // Target file patterns - pcs_config, crm_mon, and cib.xml
    filePattern: /\/pcs_config|\/cib\.xml$/,
    
    parse: function(content, filename) {
        debugLog('[sapInstanceConfig parser] Analyzing SAP instance configuration in:', filename);
        
        const instances = [];
        const warnings = [];
        let found = false;
        
        const lines = content.split('\n');
        let currentResource = null;
        let inSAPInstanceResource = false;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const trimmed = line.trim();
            
            // Detect SAPInstance resource definition
            // Format: "Resource: rsc_sap_PJU_SCS01 (class=ocf provider=heartbeat type=SAPInstance)"
            const resourceMatch = trimmed.match(/Resource:\s+(\S+)\s+\(.*type=SAPInstance\)/i);
            if (resourceMatch) {
                if (currentResource) {
                    instances.push(currentResource);
                }
                currentResource = {
                    resourceName: resourceMatch[1],
                    instanceName: null,
                    startProfile: null,
                    isERS: false,
                    automaticRecover: null,
                    warnings: [],
                    lineNumber: i + 1
                };
                inSAPInstanceResource = true;
                found = true;
                debugLog('[sapInstanceConfig parser] Found SAPInstance resource:', resourceMatch[1]);
                continue;
            }
            
            // Also check for XML format in cib.xml
            // <primitive id="rsc_sap_PJU_SCS01" class="ocf" provider="heartbeat" type="SAPInstance">
            const xmlResourceMatch = trimmed.match(/<primitive\s+id="([^"]+)"[^>]*type="SAPInstance"/i);
            if (xmlResourceMatch) {
                if (currentResource) {
                    instances.push(currentResource);
                }
                currentResource = {
                    resourceName: xmlResourceMatch[1],
                    instanceName: null,
                    startProfile: null,
                    isERS: false,
                    automaticRecover: null,
                    warnings: [],
                    lineNumber: i + 1
                };
                inSAPInstanceResource = true;
                found = true;
                debugLog('[sapInstanceConfig parser] Found SAPInstance resource (XML):', xmlResourceMatch[1]);
                continue;
            }
            
            // Exit resource section on next resource or group definition
            if (inSAPInstanceResource && (trimmed.match(/^Resource:/) || trimmed.match(/^Group:/))) {
                if (currentResource && !trimmed.includes('SAPInstance')) {
                    instances.push(currentResource);
                    currentResource = null;
                    inSAPInstanceResource = false;
                }
            }
            
            // Parse attributes within SAPInstance resource
            if (currentResource) {
                // Attributes line: "Attributes: AUTOMATIC_RECOVER=false InstanceName=PJU_SCS01_ppu-scs START_PROFILE=/sapmnt/PJU/profile/..."
                const attrMatch = trimmed.match(/Attributes:\s+(.*)/i);
                if (attrMatch) {
                    const attrString = attrMatch[1];
                    
                    // Extract InstanceName
                    const instanceNameMatch = attrString.match(/InstanceName=(\S+)/);
                    if (instanceNameMatch) {
                        currentResource.instanceName = instanceNameMatch[1];
                    }
                    
                    // Extract START_PROFILE
                    const startProfileMatch = attrString.match(/START_PROFILE=(\S+)/);
                    if (startProfileMatch) {
                        currentResource.startProfile = startProfileMatch[1];
                    }
                    
                    // Extract IS_ERS
                    const isErsMatch = attrString.match(/IS_ERS=(\S+)/i);
                    if (isErsMatch) {
                        currentResource.isERS = isErsMatch[1].toLowerCase() === 'true';
                    }
                    
                    // Extract AUTOMATIC_RECOVER
                    const autoRecoverMatch = attrString.match(/AUTOMATIC_RECOVER=(\S+)/i);
                    if (autoRecoverMatch) {
                        currentResource.automaticRecover = autoRecoverMatch[1].toLowerCase() === 'true';
                    }
                }
                
                // Also parse XML format nvpair elements
                // <nvpair id="..." name="InstanceName" value="PJU_SCS01_ppu-scs"/>
                const xmlNvpairMatch = trimmed.match(/<nvpair[^>]*name="([^"]+)"[^>]*value="([^"]+)"/i);
                if (xmlNvpairMatch) {
                    const name = xmlNvpairMatch[1];
                    const value = xmlNvpairMatch[2];
                    
                    if (name === 'InstanceName') {
                        currentResource.instanceName = value;
                    } else if (name === 'START_PROFILE') {
                        currentResource.startProfile = value;
                    } else if (name === 'IS_ERS') {
                        currentResource.isERS = value.toLowerCase() === 'true';
                    } else if (name === 'AUTOMATIC_RECOVER') {
                        currentResource.automaticRecover = value.toLowerCase() === 'true';
                    }
                }
            }
        }
        
        // Don't forget the last resource
        if (currentResource) {
            instances.push(currentResource);
        }
        
        // Validate each instance and generate warnings
        instances.forEach(instance => {
            // Validate START_PROFILE
            if (instance.startProfile) {
                // Extract expected format: /sapmnt/<SID>/profile/<SID>_<INSTANCE>_<hostname>
                const profileMatch = instance.startProfile.match(/\/sapmnt\/([^\/]+)\/profile\/([^\/]+)$/);
                if (profileMatch) {
                    const profileFilename = profileMatch[2];
                    // Profile should match pattern: <SID>_<INSTANCE>_<hostname>
                    // e.g., PJU_SCS01_sapascs or PJU_ERS11_sapers
                    
                    // Check if InstanceName hostname matches START_PROFILE hostname
                    if (instance.instanceName) {
                        const instanceParts = instance.instanceName.split('_');
                        const profileParts = profileFilename.split('_');
                        
                        if (instanceParts.length >= 3 && profileParts.length >= 3) {
                            const instanceHostname = instanceParts.slice(2).join('_');
                            const profileHostname = profileParts.slice(2).join('_');
                            
                            if (instanceHostname !== profileHostname) {
                                const warning = {
                                    severity: 'warning',
                                    type: 'hostname_mismatch',
                                    message: `InstanceName hostname "${instanceHostname}" does not match START_PROFILE hostname "${profileHostname}"`,
                                    recommendation: 'Verify that InstanceName and START_PROFILE reference the same virtual hostname for the SAP instance.',
                                    resourceName: instance.resourceName,
                                    instanceName: instance.instanceName,
                                    startProfile: instance.startProfile
                                };
                                instance.warnings.push(warning);
                                warnings.push(warning);
                                debugLog('[sapInstanceConfig parser] Hostname mismatch detected:', instance.resourceName);
                            }
                        }
                    }
                }
            } else {
                // START_PROFILE is required
                const warning = {
                    severity: 'error',
                    type: 'missing_start_profile',
                    message: 'START_PROFILE attribute is missing',
                    recommendation: 'Add START_PROFILE parameter pointing to the SAP instance profile file at /sapmnt/<SID>/profile/<SID>_<INSTANCE>_<virtual_hostname>',
                    resourceName: instance.resourceName
                };
                instance.warnings.push(warning);
                warnings.push(warning);
            }
            
            // Check InstanceName format
            if (instance.instanceName) {
                // Expected format: <SID>_<INSTANCE>_<hostname> e.g., PJU_SCS01_sapascs
                const instanceMatch = instance.instanceName.match(/^([A-Z0-9]{3})_(ASCS|SCS|ERS|D|J)(\d{2})_(.+)$/i);
                if (!instanceMatch) {
                    const warning = {
                        severity: 'warning',
                        type: 'invalid_instance_format',
                        message: `InstanceName "${instance.instanceName}" does not follow expected format <SID>_<INSTANCE>_<hostname>`,
                        recommendation: 'InstanceName should be in format <SID>_<InstanceType><InstanceNumber>_<virtual_hostname>, e.g., PJU_SCS01_sapascs',
                        resourceName: instance.resourceName
                    };
                    instance.warnings.push(warning);
                    warnings.push(warning);
                }
            } else {
                // InstanceName is required
                const warning = {
                    severity: 'error',
                    type: 'missing_instance_name',
                    message: 'InstanceName attribute is missing',
                    recommendation: 'Add InstanceName parameter in format <SID>_<InstanceType><InstanceNumber>_<virtual_hostname>',
                    resourceName: instance.resourceName
                };
                instance.warnings.push(warning);
                warnings.push(warning);
            }
            
            debugLog('[sapInstanceConfig parser] Validated resource:', instance.resourceName,
                    'InstanceName:', instance.instanceName,
                    'START_PROFILE:', instance.startProfile,
                    'Warnings:', instance.warnings.length);
        });
        
        if (!found) {
            debugLog('[sapInstanceConfig parser] No SAPInstance resources found');
            return { found: false };
        }
        
        debugLog('[sapInstanceConfig parser] Found', instances.length, 'SAPInstance resources with', warnings.length, 'warnings');
        
        return {
            found: true,
            instances: instances,
            warnings: warnings,
            instanceCount: instances.length,
            warningCount: warnings.length
        };
    }
};

// Parser to detect SAP instance service errors from cluster logs
// Detects START_PROFILE not found errors and GRAY status service errors
// Reference: https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-nfs-azure-files
const sapInstanceErrorsParser = {
    // Target file patterns - crm_report logs, messages, syslog
    filePattern: /\/analysis\.txt$|\/cluster-log\.txt$|\/messages|\/var\/log\/messages/,
    
    parse: function(content, filename) {
        debugLog('[sapInstanceErrors parser] Analyzing SAP instance errors in:', filename);
        
        const errors = [];
        const startProfileErrors = [];
        const grayStatusErrors = [];
        const filesystemErrors = [];
        let found = false;
        
        const lines = content.split('\n');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Detect START_PROFILE errors
            // Pattern: "SAPInstance(rsc_sap_PJU_ERS11)[16872]: ERROR: Expected /sapmnt/PJU/profile/PJU_ERS11_awenwjeusscs to be the instance START profile"
            const startProfileMatch = line.match(/SAPInstance\(([^)]+)\)\[\d+\]:\s*ERROR:\s*Expected\s+(\S+)\s+to be the instance START profile/i);
            if (startProfileMatch) {
                const resourceName = startProfileMatch[1];
                const profilePath = startProfileMatch[2];
                
                // Extract timestamp if present
                const timestampMatch = line.match(/^(\w+\s+\d+\s+\d+:\d+:\d+)/);
                const timestamp = timestampMatch ? timestampMatch[1] : null;
                
                // Avoid duplicates
                const existingError = startProfileErrors.find(e => 
                    e.resourceName === resourceName && e.profilePath === profilePath);
                
                if (!existingError) {
                    const error = {
                        type: 'start_profile_not_found',
                        severity: 'error',
                        resourceName: resourceName,
                        profilePath: profilePath,
                        timestamp: timestamp,
                        lineNumber: i + 1,
                        message: `SAP profile file "${profilePath}" not found for resource ${resourceName}`,
                        recommendation: 'Verify that the START_PROFILE path points to an existing SAP profile file. The profile filename should match the virtual hostname configured for the SAP instance. Check /sapmnt/<SID>/profile/ for available profiles.',
                        rawLine: line.trim()
                    };
                    startProfileErrors.push(error);
                    errors.push(error);
                    found = true;
                    debugLog('[sapInstanceErrors parser] Found START_PROFILE error:', resourceName, profilePath);
                }
            }
            
            // Detect GRAY status errors
            // Pattern: "SAPInstance(rsc_sap_PJU_SCS01)[37447]: ERROR: SAP instance service msg_server is not running with status GRAY !"
            const grayStatusMatch = line.match(/SAPInstance\(([^)]+)\)\[\d+\]:\s*ERROR:\s*SAP instance service\s+(\S+)\s+is not running with status GRAY/i);
            if (grayStatusMatch) {
                const resourceName = grayStatusMatch[1];
                const serviceName = grayStatusMatch[2];
                
                // Extract timestamp if present
                const timestampMatch = line.match(/^(\w+\s+\d+\s+\d+:\d+:\d+)/);
                const timestamp = timestampMatch ? timestampMatch[1] : null;
                
                // Avoid duplicates
                const existingError = grayStatusErrors.find(e => 
                    e.resourceName === resourceName && e.serviceName === serviceName);
                
                if (!existingError) {
                    const error = {
                        type: 'sap_service_gray_status',
                        severity: 'error',
                        resourceName: resourceName,
                        serviceName: serviceName,
                        timestamp: timestamp,
                        lineNumber: i + 1,
                        message: `SAP service "${serviceName}" is not running (status GRAY) for resource ${resourceName}`,
                        recommendation: 'GRAY status indicates the SAP service failed to start or crashed. Check SAP instance logs under /usr/sap/<SID>/<INSTANCE>/work/ for startup errors. Verify NFS mounts are available and SAP profile is correct.',
                        rawLine: line.trim()
                    };
                    grayStatusErrors.push(error);
                    errors.push(error);
                    found = true;
                    debugLog('[sapInstanceErrors parser] Found GRAY status error:', resourceName, serviceName);
                }
            }
            
            // Detect filesystem unmount errors (related to SAP)
            // Pattern: "Filesystem(fs_PJU_SCS)[38065]: ERROR: Couldn't unmount /usr/sap/PJU/SCS01"
            const fsErrorMatch = line.match(/Filesystem\(([^)]+)\)\[\d+\]:\s*ERROR:\s*Couldn't unmount\s+(\S+)/i);
            if (fsErrorMatch) {
                const resourceName = fsErrorMatch[1];
                const mountPoint = fsErrorMatch[2];
                
                // Extract timestamp if present
                const timestampMatch = line.match(/^(\w+\s+\d+\s+\d+:\d+:\d+)/);
                const timestamp = timestampMatch ? timestampMatch[1] : null;
                
                // Avoid duplicates
                const existingError = filesystemErrors.find(e => 
                    e.resourceName === resourceName && e.mountPoint === mountPoint);
                
                if (!existingError) {
                    const error = {
                        type: 'filesystem_unmount_error',
                        severity: 'warning',
                        resourceName: resourceName,
                        mountPoint: mountPoint,
                        timestamp: timestamp,
                        lineNumber: i + 1,
                        message: `Failed to unmount filesystem "${mountPoint}" for resource ${resourceName}`,
                        recommendation: 'Check for processes still using the filesystem with "lsof" or "fuser". This may indicate SAP processes did not stop cleanly before failover.',
                        rawLine: line.trim()
                    };
                    filesystemErrors.push(error);
                    errors.push(error);
                    found = true;
                    debugLog('[sapInstanceErrors parser] Found filesystem error:', resourceName, mountPoint);
                }
            }
        }
        
        if (!found) {
            debugLog('[sapInstanceErrors parser] No SAP instance errors found');
            return { found: false };
        }
        
        debugLog('[sapInstanceErrors parser] Found', errors.length, 'SAP errors:',
                'START_PROFILE:', startProfileErrors.length,
                'GRAY status:', grayStatusErrors.length,
                'Filesystem:', filesystemErrors.length);
        
        return {
            found: true,
            errors: errors,
            startProfileErrors: startProfileErrors,
            grayStatusErrors: grayStatusErrors,
            filesystemErrors: filesystemErrors,
            errorCount: errors.length,
            summary: {
                startProfileErrorCount: startProfileErrors.length,
                grayStatusErrorCount: grayStatusErrors.length,
                filesystemErrorCount: filesystemErrors.length
            }
        };
    }
};

/**
 * Parser: clusterMaintenanceMode
 * Detects if cluster is in maintenance mode
 * Checks for maintenance-mode property in CIB or crm_mon output
 */
const clusterMaintenanceModeParser = {
    filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/ha\.txt$/,
    
    parse: function(content, filename) {
        debugLog('[clusterMaintenanceMode parser] Analyzing:', filename);
        
        const result = {
            found: false,
            maintenanceMode: null,
            resourcesInMaintenance: [],
            warnings: [],
            sourceFile: null
        };
        
        // Check for cluster-wide maintenance mode
        // CIB format: <nvpair name="maintenance-mode" value="true"/>
        const maintenanceModeMatch = content.match(/name=["']maintenance-mode["']\s+value=["'](true|false)["']/i);
        if (maintenanceModeMatch) {
            result.found = true;
            result.maintenanceMode = maintenanceModeMatch[1].toLowerCase() === 'true';
            result.sourceFile = filename;
            
            if (result.maintenanceMode) {
                result.warnings.push({
                    type: 'cluster_in_maintenance',
                    severity: 'warning',
                    message: 'Cluster is in maintenance mode - resources will not be managed',
                    recommendation: 'Run "crm configure property maintenance-mode=false" to exit maintenance mode when ready'
                });
            }
            debugLog('[clusterMaintenanceMode parser] Found maintenance-mode:', result.maintenanceMode);
        }
        
        // Also check crm_mon output for "Resource management is DISABLED"
        if (content.includes('Resource management is DISABLED')) {
            result.found = true;
            result.maintenanceMode = true;
            result.sourceFile = filename;
            if (!result.warnings.find(w => w.type === 'cluster_in_maintenance')) {
                result.warnings.push({
                    type: 'cluster_in_maintenance',
                    severity: 'warning',
                    message: 'Cluster resource management is DISABLED',
                    recommendation: 'Check if cluster is in maintenance mode or stonith is disabled'
                });
            }
        }
        
        // Check for individual resources in maintenance
        // crm_mon format: (maintenance) or [maintenance]
        const maintenanceResourceMatches = content.matchAll(/(?:Resource|Clone Set|Primary\/Secondary Set|Resource Group):\s+([^\s(]+).*?\(.*?maintenance.*?\)/gi);
        for (const match of maintenanceResourceMatches) {
            result.resourcesInMaintenance.push(match[1]);
        }
        
        if (result.resourcesInMaintenance.length > 0) {
            result.found = true;
            result.warnings.push({
                type: 'resources_in_maintenance',
                severity: 'info',
                message: `${result.resourcesInMaintenance.length} resource(s) in maintenance mode`,
                resources: result.resourcesInMaintenance
            });
        }
        
        return result;
    }
};

/**
 * Parser: sbdConfig
 * Parses SBD (STONITH Block Device) configuration
 * File patterns: /etc/sysconfig/sbd, sbd (crm_report), ha.txt (supportconfig)
 */
const sbdConfigParser = {
    filePattern: /\/sbd$|\/sysconfig\/sbd|\/ha\.txt$/,
    
    parse: function(content, filename) {
        debugLog('[sbdConfig parser] Analyzing:', filename);
        
        const result = {
            found: false,
            sbdDevice: null,
            sbdDevices: [],
            sbdPacemaker: null,
            sbdStartmode: null,
            sbdDelayStart: null,
            sbdWatchdogDev: null,
            sbdWatchdogTimeout: null,
            sbdTimeoutAction: null,
            warnings: [],
            recommendations: [],
            sourceFile: null
        };
        
        // Extract SBD config section if from ha.txt
        let sbdContent = content;
        if (filename.includes('ha.txt')) {
            const section = SCC_RULES.extractSection(content, filename, '# /etc/sysconfig/sbd', 'sbd');
            if (section.found) {
                sbdContent = section.content;
            } else {
                return result;
            }
        }
        
        // Skip if this looks like sbd.txt (dump output) not config
        if (sbdContent.includes('sbd dump') || sbdContent.includes('==[ Command ]')) {
            return result;
        }
        
        const lines = sbdContent.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            // Skip comments
            if (trimmed.startsWith('#') || !trimmed) continue;
            
            // Parse SBD_DEVICE
            const deviceMatch = trimmed.match(/^SBD_DEVICE=["']?([^"'\n]+)["']?/);
            if (deviceMatch) {
                result.found = true;
                result.sbdDevice = deviceMatch[1];
                // Split by semicolon for multiple devices
                result.sbdDevices = deviceMatch[1].split(';').filter(d => d.trim());
                result.sourceFile = filename;
                debugLog('[sbdConfig parser] Found SBD_DEVICE:', result.sbdDevice);
            }
            
            // Parse SBD_PACEMAKER
            const pacemakerMatch = trimmed.match(/^SBD_PACEMAKER=["']?(\w+)["']?/);
            if (pacemakerMatch) {
                result.found = true;
                result.sbdPacemaker = pacemakerMatch[1].toLowerCase();
                if (result.sbdPacemaker !== 'yes') {
                    result.warnings.push({
                        type: 'sbd_pacemaker_disabled',
                        severity: 'warning',
                        message: `SBD_PACEMAKER is not set to "yes" (current: ${result.sbdPacemaker})`,
                        recommendation: 'Set SBD_PACEMAKER=yes for proper Pacemaker integration'
                    });
                }
            }
            
            // Parse SBD_STARTMODE
            const startmodeMatch = trimmed.match(/^SBD_STARTMODE=["']?(\w+)["']?/);
            if (startmodeMatch) {
                result.found = true;
                result.sbdStartmode = startmodeMatch[1].toLowerCase();
                if (result.sbdStartmode !== 'always') {
                    result.warnings.push({
                        type: 'sbd_startmode_not_always',
                        severity: 'info',
                        message: `SBD_STARTMODE is "${result.sbdStartmode}" (recommended: "always")`,
                        recommendation: 'Consider setting SBD_STARTMODE=always for Azure deployments'
                    });
                }
            }
            
            // Parse SBD_DELAY_START
            const delayMatch = trimmed.match(/^SBD_DELAY_START=["']?([^"'\n]+)["']?/);
            if (delayMatch) {
                result.found = true;
                result.sbdDelayStart = delayMatch[1].toLowerCase();
                // Azure recommendation: use numeric value (e.g., 216) not "no" or "yes"
                if (result.sbdDelayStart === 'no' || result.sbdDelayStart === 'yes') {
                    result.warnings.push({
                        type: 'sbd_delay_start_not_numeric',
                        severity: 'warning',
                        message: `SBD_DELAY_START is "${result.sbdDelayStart}" but should be a numeric value`,
                        recommendation: 'Set SBD_DELAY_START to a specific delay value in seconds (e.g., 216) per Azure best practices',
                        documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                    });
                }
            }
            
            // Parse SBD_WATCHDOG_DEV
            const watchdogDevMatch = trimmed.match(/^SBD_WATCHDOG_DEV=["']?([^"'\n]+)["']?/);
            if (watchdogDevMatch) {
                result.found = true;
                result.sbdWatchdogDev = watchdogDevMatch[1];
            }
            
            // Parse SBD_WATCHDOG_TIMEOUT
            const watchdogTimeoutMatch = trimmed.match(/^SBD_WATCHDOG_TIMEOUT=["']?(\d+)["']?/);
            if (watchdogTimeoutMatch) {
                result.found = true;
                result.sbdWatchdogTimeout = parseInt(watchdogTimeoutMatch[1], 10);
            }
            
            // Parse SBD_TIMEOUT_ACTION
            const timeoutActionMatch = trimmed.match(/^SBD_TIMEOUT_ACTION=["']?([^"'\n]+)["']?/);
            if (timeoutActionMatch) {
                result.found = true;
                result.sbdTimeoutAction = timeoutActionMatch[1];
            }
        }
        
        // Add recommendation for SBD device count
        if (result.sbdDevices.length === 2) {
            result.warnings.push({
                type: 'sbd_two_devices',
                severity: 'warning',
                message: 'Only 2 SBD devices configured - this is not recommended',
                recommendation: 'Use 1 or 3 SBD devices. With 2 devices, Pacemaker cannot automatically fence if one becomes unavailable.',
                documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
            });
        } else if (result.sbdDevices.length > 0) {
            result.recommendations.push({
                type: 'sbd_device_count',
                severity: 'info',
                message: `${result.sbdDevices.length} SBD device(s) configured`,
                detail: result.sbdDevices.length === 3 ? 'Optimal configuration for high availability' : 
                        result.sbdDevices.length === 1 ? 'Single device configuration' : `${result.sbdDevices.length} devices configured`
            });
        }
        
        return result;
    }
};

/**
 * Parser: azureFenceAuth
 * Detects if Azure fence agent uses managed identity (MSI) or service principal
 * Parses fence_azure_arm configuration from CIB
 */
const azureFenceAuthParser = {
    filePattern: /cib\.xml$|\/ha\.txt$|\/crm.*config$/,
    
    parse: function(content, filename) {
        debugLog('[azureFenceAuth parser] Analyzing:', filename);
        
        const result = {
            found: false,
            authMethod: null,  // 'msi' or 'service_principal'
            subscriptionId: null,
            resourceGroup: null,
            tenantId: null,
            hasLogin: false,
            hasPassword: false,
            pcmkMonitorRetries: null,
            pcmkActionLimit: null,
            powerTimeout: null,
            pcmkRebootTimeout: null,
            pcmkDelayMax: null,
            pcmkHostMap: null,
            warnings: [],
            recommendations: [],
            sourceFile: null
        };
        
        // Check for fence_azure_arm primitive
        if (!content.includes('fence_azure_arm')) {
            return result;
        }
        
        result.found = true;
        result.sourceFile = filename;
        
        // Check for MSI configuration
        const msiMatch = content.match(/name=["']msi["']\s+value=["'](true|false)["']/i);
        if (msiMatch && msiMatch[1].toLowerCase() === 'true') {
            result.authMethod = 'msi';
            result.recommendations.push({
                type: 'using_msi',
                severity: 'info',
                message: 'Azure fence agent is using Managed Identity (MSI) - recommended configuration'
            });
        }
        
        // Check for service principal indicators (login/passwd)
        const loginMatch = content.match(/name=["']login["']\s+value=["']([^"']+)["']/i);
        if (loginMatch) {
            result.hasLogin = true;
            if (!result.authMethod) {
                result.authMethod = 'service_principal';
            }
        }
        
        const passwdMatch = content.match(/name=["'](?:passwd|password)["']\s+value=/i);
        if (passwdMatch) {
            result.hasPassword = true;
            if (!result.authMethod) {
                result.authMethod = 'service_principal';
            }
        }
        
        // If using service principal, add recommendation to migrate to MSI
        if (result.authMethod === 'service_principal') {
            result.warnings.push({
                type: 'using_service_principal',
                severity: 'warning',
                message: 'Azure fence agent is using Service Principal authentication',
                recommendation: 'Consider migrating to Managed Identity (MSI) for improved security and easier credential management',
                documentationUrl: 'https://techcommunity.microsoft.com/t5/running-sap-applications-on-the/sap-on-azure-high-availability-change-from-spn-to-msi-for/ba-p/3609278'
            });
        }
        
        // Extract subscriptionId
        const subIdMatch = content.match(/name=["']subscriptionId["']\s+value=["']([^"']+)["']/i);
        if (subIdMatch) {
            result.subscriptionId = subIdMatch[1];
        }
        
        // Extract resourceGroup
        const rgMatch = content.match(/name=["']resourceGroup["']\s+value=["']([^"']+)["']/i);
        if (rgMatch) {
            result.resourceGroup = rgMatch[1];
        }
        
        // Extract tenantId
        const tenantMatch = content.match(/name=["']tenantId["']\s+value=["']([^"']+)["']/i);
        if (tenantMatch) {
            result.tenantId = tenantMatch[1];
        }
        
        // Extract pcmk parameters
        const pcmkMonitorRetriesMatch = content.match(/name=["']pcmk_monitor_retries["']\s+value=["'](\d+)["']/i);
        if (pcmkMonitorRetriesMatch) {
            result.pcmkMonitorRetries = parseInt(pcmkMonitorRetriesMatch[1], 10);
        }
        
        const pcmkActionLimitMatch = content.match(/name=["']pcmk_action_limit["']\s+value=["'](\d+)["']/i);
        if (pcmkActionLimitMatch) {
            result.pcmkActionLimit = parseInt(pcmkActionLimitMatch[1], 10);
        }
        
        const powerTimeoutMatch = content.match(/name=["']power_timeout["']\s+value=["'](\d+)["']/i);
        if (powerTimeoutMatch) {
            result.powerTimeout = parseInt(powerTimeoutMatch[1], 10);
        }
        
        const pcmkRebootTimeoutMatch = content.match(/name=["']pcmk_reboot_timeout["']\s+value=["'](\d+)["']/i);
        if (pcmkRebootTimeoutMatch) {
            result.pcmkRebootTimeout = parseInt(pcmkRebootTimeoutMatch[1], 10);
        }
        
        const pcmkDelayMaxMatch = content.match(/name=["']pcmk_delay_max["']\s+value=["'](\d+)["']/i);
        if (pcmkDelayMaxMatch) {
            result.pcmkDelayMax = parseInt(pcmkDelayMaxMatch[1], 10);
        }
        
        const pcmkHostMapMatch = content.match(/name=["']pcmk_host_map["']\s+value=["']([^"']+)["']/i);
        if (pcmkHostMapMatch) {
            result.pcmkHostMap = pcmkHostMapMatch[1];
        }
        
        return result;
    }
};

/**
 * Parser: iscsiConfig
 * Parses iSCSI configuration for SBD devices
 * File patterns: /etc/iscsi/*, iscsiadm output, ha.txt
 */
const iscsiConfigParser = {
    // Match SCC fs-iscsi.txt, sosreport iscsi/ folder, ha.txt, initiatorname.iscsi
    filePattern: /fs-iscsi\.txt$|\/iscsi\/|\/iscsiadm|\/ha\.txt$|initiatorname\.iscsi$/,
    
    parse: function(content, filename) {
        debugLog('[iscsiConfig parser] Analyzing:', filename);
        
        const result = {
            found: false,
            initiatorName: null,
            targets: [],          // Known nodes from iscsiadm -m node
            discoveryServers: [], // Discovery addresses
            sessions: [],         // Active sessions
            hosts: [],            // iSCSI hosts
            nodeStartup: null,
            iscsidConfig: {},     // Key iscsid.conf settings
            serviceStatus: {},
            warnings: [],
            sourceFile: null
        };
        
        // Extract iSCSI section if from ha.txt
        let iscsiContent = content;
        if (filename.includes('ha.txt')) {
            // Look for iSCSI related sections
            const initiatorSection = SCC_RULES.extractSection(content, filename, '# /etc/iscsi/initiatorname.iscsi', 'initiatorname');
            if (initiatorSection.found) {
                iscsiContent = initiatorSection.content;
            }
        }
        
        // Parse InitiatorName
        const initiatorMatch = content.match(/InitiatorName=([^\s\n]+)/i);
        if (initiatorMatch) {
            result.found = true;
            result.initiatorName = initiatorMatch[1];
            result.sourceFile = filename;
            debugLog('[iscsiConfig parser] Found InitiatorName:', result.initiatorName);
        }
        
        // Parse iscsid.conf key settings
        const configSettings = [
            'node.startup',
            'node.session.timeo.replacement_timeout',
            'node.conn[0].timeo.login_timeout',
            'node.conn[0].timeo.logout_timeout',
            'node.session.initial_login_retry_max',
            'node.session.iscsi.FirstBurstLength',
            'node.session.iscsi.MaxBurstLength',
            'discovery.sendtargets.iscsi.MaxRecvDataSegmentLength'
        ];
        
        for (const setting of configSettings) {
            const escapedSetting = setting.replace(/[[\]]/g, '\\$&');
            const regex = new RegExp(escapedSetting + '\\s*=\\s*([^\\n]+)', 'i');
            const match = content.match(regex);
            if (match) {
                result.found = true;
                result.iscsidConfig[setting] = match[1].trim();
            }
        }
        
        // Check node.startup
        if (result.iscsidConfig['node.startup']) {
            result.nodeStartup = result.iscsidConfig['node.startup'].toLowerCase();
            // Note: For SBD with iSCSI, manual is often preferred as pacemaker manages startup
            // automatic can cause issues during boot if target not available
        }
        
        // Parse discovery servers from iscsiadm -m discovery output
        // Format: 10.227.48.28:3260 via sendtargets
        const discoveryMatches = content.matchAll(/(\d+\.\d+\.\d+\.\d+):(\d+)\s+via\s+(\w+)/g);
        const discoverySet = new Set();
        for (const match of discoveryMatches) {
            const key = `${match[1]}:${match[2]}`;
            if (!discoverySet.has(key)) {
                discoverySet.add(key);
                result.found = true;
                result.discoveryServers.push({
                    ip: match[1],
                    port: parseInt(match[2], 10),
                    method: match[3]
                });
            }
        }
        
        // Parse iSCSI targets from iscsiadm -m node output
        // Format: 10.0.0.17:3260,1 iqn.2006-04.nfs.local:nfs
        const targetSet = new Map();
        const targetMatches = content.matchAll(/(\d+\.\d+\.\d+\.\d+):(\d+),\d+\s+(iqn\.[^\s\n(]+)/g);
        for (const match of targetMatches) {
            const iqn = match[3].trim();
            if (!targetSet.has(iqn)) {
                targetSet.set(iqn, {
                    iqn: iqn,
                    portals: []
                });
            }
            const target = targetSet.get(iqn);
            const portalKey = `${match[1]}:${match[2]}`;
            if (!target.portals.find(p => `${p.ip}:${p.port}` === portalKey)) {
                target.portals.push({
                    ip: match[1],
                    port: parseInt(match[2], 10)
                });
            }
        }
        for (const target of targetSet.values()) {
            result.found = true;
            result.targets.push(target);
        }
        
        // Parse active iSCSI sessions from iscsiadm -m session output
        // Format: tcp: [1] 10.0.0.17:3260,1 iqn.2006-04.nfs.local:nfs (non-flash)
        const sessionSet = new Map();
        const sessionMatches = content.matchAll(/tcp:\s+\[(\d+)\]\s+(\d+\.\d+\.\d+\.\d+):(\d+),\d+\s+(iqn\.[^\s\n(]+)(?:\s+\(([^)]+)\))?/g);
        for (const match of sessionMatches) {
            const sessionId = match[1];
            if (!sessionSet.has(sessionId)) {
                result.found = true;
                sessionSet.set(sessionId, {
                    sessionId: parseInt(sessionId, 10),
                    ip: match[2],
                    port: parseInt(match[3], 10),
                    iqn: match[4].trim(),
                    type: match[5] || 'unknown'
                });
            }
        }
        result.sessions = Array.from(sessionSet.values());
        
        // Parse session details for connection state
        // Look for: iSCSI Connection State: LOGGED IN
        const sessionStateMatches = content.matchAll(/Current Portal:\s+(\d+\.\d+\.\d+\.\d+):(\d+)[^]*?iSCSI Connection State:\s*([^\n]+)[^]*?iSCSI Session State:\s*([^\n]+)/g);
        for (const match of sessionStateMatches) {
            const ip = match[1];
            const port = parseInt(match[2], 10);
            const connState = match[3].trim();
            const sessState = match[4].trim();
            
            // Find and update the session
            const session = result.sessions.find(s => s.ip === ip && s.port === port);
            if (session) {
                session.connectionState = connState;
                session.sessionState = sessState;
            }
        }
        
        // Parse iSCSI hosts from iscsiadm -m host output
        // Format: tcp: [2] 10.227.48.95,[<empty>],<empty> <empty>
        const hostMatches = content.matchAll(/Host Number:\s*(\d+)[^]*?State:\s*(\w+)[^]*?Transport:\s*(\w+)[^]*?IPaddress:\s*([^\n]+)/g);
        for (const match of hostMatches) {
            result.found = true;
            result.hosts.push({
                hostNumber: parseInt(match[1], 10),
                state: match[2].trim(),
                transport: match[3].trim(),
                ip: match[4].trim()
            });
        }
        
        // Parse service status
        const iscsiServiceMatch = content.match(/iscsi\.service[^]*?Active:\s*([^\n]+)/);
        if (iscsiServiceMatch) {
            result.serviceStatus.iscsiService = iscsiServiceMatch[1].trim();
        }
        const iscsidServiceMatch = content.match(/iscsid\.service[^]*?Active:\s*([^\n]+)/);
        if (iscsidServiceMatch) {
            result.serviceStatus.iscsidService = iscsidServiceMatch[1].trim();
        }
        
        // Generate warnings
        if (result.sessions.length === 0 && result.targets.length > 0) {
            result.warnings.push({
                type: 'iscsi_no_active_sessions',
                severity: 'warning',
                message: 'iSCSI targets configured but no active sessions',
                recommendation: 'Check iSCSI connectivity and login status'
            });
        }
        
        // Check for session states
        for (const session of result.sessions) {
            if (session.connectionState && session.connectionState !== 'LOGGED IN') {
                result.warnings.push({
                    type: 'iscsi_session_not_logged_in',
                    severity: 'error',
                    message: `iSCSI session to ${session.ip} is not logged in (${session.connectionState})`,
                    recommendation: 'Check iSCSI target availability and network connectivity'
                });
            }
        }
        
        // Check for multipath - expect at least 3 paths per target for Azure iSCSI SBD
        if (result.sessions.length > 0) {
            const sessionsByIqn = new Map();
            for (const session of result.sessions) {
                if (!sessionsByIqn.has(session.iqn)) {
                    sessionsByIqn.set(session.iqn, []);
                }
                sessionsByIqn.get(session.iqn).push(session);
            }
            
            for (const [iqn, sessions] of sessionsByIqn) {
                if (sessions.length < 3) {
                    result.warnings.push({
                        type: 'iscsi_insufficient_paths',
                        severity: 'info',
                        message: `iSCSI target ${iqn} has only ${sessions.length} path(s)`,
                        recommendation: 'Azure iSCSI SBD typically requires 3 paths for high availability'
                    });
                }
            }
        }
        
        return result;
    }
};

// Factory function that creates all cluster parsers
// This function receives SCC_RULES and debugLog from the main worker context
// Assigned to global scope for importScripts() compatibility
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
