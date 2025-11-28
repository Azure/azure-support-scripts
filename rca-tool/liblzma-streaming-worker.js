// Streaming XZ decompression worker using liblzma
// Processes compressed data in chunks to keep memory usage low

const CACHE_BUST = '?v=' + Date.now();

// Debug flag - will be set from main thread via message
// Can be true (all), false (none), or 'cluster' (cluster-related only)
let DEBUG_MODE = false;

// Debug logging wrapper - only logs if DEBUG_MODE is true
function debugLog(...args) {
    if (DEBUG_MODE === true) {
        console.log(...args);
    } else if (DEBUG_MODE === 'cluster') {
        // Only log cluster-related messages
        const firstArg = args[0];
        if (typeof firstArg === 'string' && 
            (firstArg.includes('cluster') || 
             firstArg.includes('Cluster') || 
             firstArg.includes('pacemaker') || 
             firstArg.includes('crm_mon') || 
             firstArg.includes('corosync') || 
             firstArg.includes('resource') || 
             firstArg.includes('Resource') || 
             firstArg.includes('fencing') || 
             firstArg.includes('STONITH'))) {
            console.log(...args);
        }
    }
}

// ============================================================================
// SCC REPORT ANALYSIS RULES
// ============================================================================
// Add new rules here to extract information from SCC/supportconfig reports
// Each rule defines which file to extract and how to parse it

const SCC_RULES = {
    // Rule: Detect if archive is an SCC report, hb_report, crm_report, or sosreport
    detection: {
        // Patterns to identify reports by filename
        filenamePatterns: [
            /^scc_/,           // SCC/supportconfig reports
            /^nts_/,           // NTS reports
            /^hb_report/,      // hb_report archives (older Pacemaker)
            /^crm_report/,     // crm_report archives (newer Pacemaker)
            /^sosreport-/      // sosreport archives
        ],
        
        // Check if filename matches any report pattern
        isSCCReport: function(filename) {
            return this.filenamePatterns.some(pattern => pattern.test(filename));
        }
    },
    
    // Rule: Extract Azure VM properties from instance_metadata.json
    azureVMProperties: {
        filePattern: /instance_metadata\.json$/,
        
        parse: function(content, filename) {
            debugLog('[azureVMProperties parser] Analyzing Azure VM metadata in:', filename);
            try {
                const metadata = JSON.parse(content);
                // Extract properties from root
                const vmSize = metadata.vmSize || null;
                const offer = metadata.offer || null;
                const publisher = metadata.publisher || null;
                const sku = metadata.sku || null;
                const licenseType = metadata.licenseType || null;
                const billingCode = metadata.billingCode || null;
                
                // Determine PAYG vs BYOS based on official Azure rules
                let billingModel = null;
                let detectionMethod = null;
                
                // Normalize licenseType: treat empty or whitespace-only strings as not-available
                const licenseTypeUpper = (typeof licenseType === 'string' && licenseType.trim() !== '') ? licenseType.trim().toUpperCase() : null;
                const billingCodeNormalized = (typeof billingCode === 'string' && billingCode.trim() !== '') ? billingCode.trim() : null;
                
                // Rule 1: License Type takes precedence (highest confidence)
                if (licenseTypeUpper) {
                    // BYOS License Types
                    if (licenseTypeUpper === 'RHEL_BYOS' || 
                        licenseTypeUpper === 'SLES_BYOS') {
                        billingModel = 'BYOS';
                        detectionMethod = `License Type: ${licenseType}`;
                    }
                    // PAYG License Types - RHEL
                    else if (licenseTypeUpper === 'RHEL_BASE' ||
                             licenseTypeUpper === 'RHEL_SAPAPPS' ||
                             licenseTypeUpper === 'RHEL_BASESAPHA' ||
                             licenseTypeUpper === 'RHEL_SAPHA' ||
                             licenseTypeUpper === 'RHEL_EUS') {
                        billingModel = 'PAYG';
                        detectionMethod = `License Type: ${licenseType}`;
                    }
                    // PAYG License Types - SLES
                    else if (licenseTypeUpper === 'SLES' ||
                             licenseTypeUpper === 'SLES_SAP' ||
                             licenseTypeUpper === 'SLES_STANDARD' ||
                             licenseTypeUpper === 'SLES_HPC') {
                        billingModel = 'PAYG';
                        detectionMethod = `License Type: ${licenseType}`;
                    }
                    // PAYG License Types - Ubuntu Pro
                    else if (licenseTypeUpper === 'UBUNTU_PRO') {
                        billingModel = 'PAYG';
                        detectionMethod = `License Type: ${licenseType}`;
                    }
                }
                
                // Rule 2: Billing Code (if no license type or license type is N/A/NONE)
                // If we still don't have a billing model, or the licenseType is missing/empty/NONE/N/A, try billingCode
                if (!billingModel || !licenseTypeUpper || licenseTypeUpper === 'N/A' || licenseTypeUpper === 'NONE') {
                    if (billingCode) {
                        // BYOS Billing Codes
                        if (billingCode === 'Linux_IaaS' ||
                            billingCode === 'Linux_IaaS_Canonical' ||
                            billingCode === 'Linux_IaaS_Software_Store' ||
                            billingCode === 'Linux_IaaS_Oracle' ||
                            billingCode === 'Linux_IaaS_OpenLogic' ||
                            billingCode === 'Linux_IaaS_Software_RedHat_Support_on_Store' ||
                            billingCode === 'Linux_IaaS_Software_suse_sles_hpc_byos' ||
                            billingCode === 'Linux_IaaS_Software_suse_sles_sap_byos' ||
                            billingCode === 'Linux_IaaS_Software_SUSE_BYOS') {
                            billingModel = 'BYOS';
                            detectionMethod = `Billing Code: ${billingCode}`;
                        }
                        // PAYG Billing Codes
                        else if (billingCode === 'Linux_IaaS_SUSE' ||
                                 billingCode === 'Linux_IaaS_RedHat_Support' ||
                                 billingCode === 'Linux_IaaS_Software_SLES_Basic' ||
                                 billingCode === 'Linux_IaaS_Software_SUSE_Support' ||
                                 billingCode === 'Linux_IaaS_Software_RedHat_Support' ||
                                 billingCode === 'Linux_IaaS_Software_RedHat_HA' ||
                                 billingCode === 'Linux_IaaS_Software_RedHat_SAP_HA' ||
                                 billingCode === 'Linux_IaaS_Software_SLES_for_HPC_Priority' ||
                                 billingCode === 'Linux_IaaS_Software_SLES_for_SAP' ||
                                 billingCode === 'Linux_IaaS_Software_SLES_Standard' ||
                                 billingCode === 'Linux_IaaS_Software_RedHat-SAP_BusApp') {
                            billingModel = 'PAYG';
                            detectionMethod = `Billing Code: ${billingCode}`;
                        }
                    }
                }
                
                
                debugLog('[azureVMProperties parser] VM Size:', vmSize);
                debugLog('[azureVMProperties parser] Publisher:', publisher);
                debugLog('[azureVMProperties parser] Offer:', offer);
                debugLog('[azureVMProperties parser] SKU:', sku);
                debugLog('[azureVMProperties parser] Billing Code:', billingCode);
                debugLog('[azureVMProperties parser] License Type:', licenseType);
                debugLog('[azureVMProperties parser] Billing Model:', billingModel);
                debugLog('[azureVMProperties parser] Detection Method:', detectionMethod);
                
                return {
                    found: true,
                    vmSize: vmSize,
                    publisher: publisher,
                    offer: offer,
                    sku: sku,
                    billingCode: billingCode,
                    licenseType: licenseType,
                    billingModel: billingModel,
                    detectionMethod: detectionMethod
                };
            } catch (e) {
                console.error('[azureVMProperties parser] Failed to parse JSON:', e);
                return { found: false };
            }
        },
        // Rule: Extract Distribution information from sysinfo.txt (some reports)
        sysinfo: {
            filePattern: /sysinfo\.txt$/,

            parse: function(content, filename) {
                debugLog('[sysinfo parser] Analyzing sysinfo in:', filename);
                const lines = content.split('\n');
                let distribution = null;

                for (const line of lines) {
                    const trimmed = line.trim();
                    if (!trimmed) continue;

                    // Look for lines like: Distribution: SUSE Linux Enterprise Server 12 SP3
                    const distMatch = trimmed.match(/^Distribution:\s*(.+)$/i);
                    if (distMatch) {
                        distribution = distMatch[1].trim();
                        debugLog('[sysinfo parser] Found Distribution:', distribution);
                        break;
                    }
                }

                if (!distribution) {
                    debugLog('[sysinfo parser] No Distribution line found in sysinfo.txt');
                    return { found: false };
                }

                return {
                    found: true,
                    distribution: distribution
                };
            }
        }
    },
    
    // Rule: Parse basic-environment.txt (supportconfig) as additional fallback for OS identification
    basicEnvironment: {
        filePattern: /basic-environment\.txt$/,

        parse: function(content, filename) {
            debugLog('[basicEnvironment parser] Analyzing basic-environment in:', filename);
            const lines = content.split('\n');
            let prettyName = null;
            let name = null;
            let product = null;
            let skipSection = false;

            for (let i = 0; i < lines.length; i++) {
                const raw = lines[i];
                const trimmed = raw.trim();

                // Treat lines starting with '#' as section headers in supportconfig dumps
                if (trimmed.startsWith('#')) {
                    // If the header references a .rpmsave file, skip the following section
                    if (trimmed.toLowerCase().includes('.rpmsave')) {
                        skipSection = true;
                    } else {
                        // New header — stop skipping
                        skipSection = false;
                    }
                    continue;
                }

                if (skipSection) continue;

                if (!trimmed) continue;

                // Look for PRETTY_NAME= or NAME= lines (similar to /etc/os-release)
                const prettyMatch = trimmed.match(/^PRETTY_NAME=(?:"|')?([^"']+)(?:"|')?$/i);
                if (prettyMatch) {
                    prettyName = prettyMatch[1].trim();
                    debugLog('[basicEnvironment parser] Found PRETTY_NAME:', prettyName);
                    break;
                }

                const nameMatch = trimmed.match(/^NAME=(?:"|')?([^"']+)(?:"|')?$/i);
                if (nameMatch) {
                    name = nameMatch[1].trim();
                    debugLog('[basicEnvironment parser] Found NAME:', name);
                    // don't break — prefer PRETTY_NAME if present later
                }

                // Some basic-environment dumps include a 'Product: ...' line
                const prodMatch = trimmed.match(/^Product:\s*(.+)$/i);
                if (prodMatch) {
                    product = prodMatch[1].trim();
                    debugLog('[basicEnvironment parser] Found Product:', product);
                }
            }

            const distribution = prettyName || product || name;
            if (!distribution) {
                debugLog('[basicEnvironment parser] No distribution info found');
                return { found: false };
            }

            // Detect SAP-specific product name (e.g. "SUSE Linux Enterprise Server for SAP Applications")
            let sapProductDetected = false;
            // Detect EPIC-specific product name
            let epicProductDetected = false;
            try {
                const checkFields = [prettyName, product, name].filter(Boolean);
                for (const f of checkFields) {
                    if (/\bSAP\b|for\s+SAP|SAP\s+Applications/i.test(f)) {
                        sapProductDetected = true;
                    }
                    if (/\bEPIC\b|Enterprise\s+Portal\s+Integration|for\s+EPIC/i.test(f)) {
                        epicProductDetected = true;
                    }
                }
            } catch (e) {
                // ignore regex errors
            }

            return {
                found: true,
                prettyName: prettyName,
                name: name,
                distribution: distribution,
                sapProductDetected: sapProductDetected,
                epicProductDetected: epicProductDetected
            };
        }
    },
    
    // Rule: Extract OS release information from /etc/os-release
    osRelease: {
        filePattern: /\/(etc|usr\/lib)\/os-release$/,
        
        parse: function(content, filename) {
            debugLog('[osRelease parser] Analyzing OS release information in:', filename);
            const lines = content.split('\n');
            let name = null;
            let version = null;
            let versionId = null;
            let prettyName = null;
            
            for (const line of lines) {
                const trimmed = line.trim();
                
                // Skip empty lines and comments
                if (!trimmed || trimmed.startsWith('#')) continue;
                
                // Parse NAME="Distribution Name"
                const nameMatch = trimmed.match(/^NAME=["']?([^"']+)["']?$/);
                if (nameMatch) {
                    name = nameMatch[1];
                    debugLog('[osRelease parser] Found NAME:', name);
                }
                
                // Parse VERSION="Major.Minor (Codename)" or VERSION="Major.Minor"
                const versionMatch = trimmed.match(/^VERSION=["']?([^"']+)["']?$/);
                if (versionMatch) {
                    version = versionMatch[1];
                    debugLog('[osRelease parser] Found VERSION:', version);
                }
                
                // Parse VERSION_ID="Major.Minor"
                const versionIdMatch = trimmed.match(/^VERSION_ID=["']?([^"']+)["']?$/);
                if (versionIdMatch) {
                    versionId = versionIdMatch[1];
                    debugLog('[osRelease parser] Found VERSION_ID:', versionId);
                }
                
                // Parse PRETTY_NAME="Full Distribution Name with Version"
                const prettyNameMatch = trimmed.match(/^PRETTY_NAME=["']?([^"']+)["']?$/);
                if (prettyNameMatch) {
                    prettyName = prettyNameMatch[1];
                    debugLog('[osRelease parser] Found PRETTY_NAME:', prettyName);
                }
            }
            
            // Extract major and minor version from VERSION_ID
            let majorVersion = null;
            let minorVersion = null;
            if (versionId) {
                const parts = versionId.split('.');
                majorVersion = parts[0] || null;
                minorVersion = parts[1] || null;
            }
            
            debugLog('[osRelease parser] Parsed OS info:', {
                name: name,
                version: version,
                majorVersion: majorVersion,
                minorVersion: minorVersion
            });
            
            return {
                found: true,
                name: name,
                version: version,
                versionId: versionId,
                prettyName: prettyName,
                majorVersion: majorVersion,
                minorVersion: minorVersion
            };
        }
    },
    
    // Rule: Extract cluster node names from ha.txt (supportconfig) or pacemaker.log/corosync.conf (sosreport)
    clusterNodes: {
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
                
                // Pattern 3: CIB XML node format: <node id="1" uname="vmupelhscs001">
                // Prioritize uname over id (uname is the actual hostname, id can be numeric)
                const xmlNodeMatch = trimmed.match(/<node\s+[^>]*>/i);
                if (xmlNodeMatch) {
                    const fullMatch = xmlNodeMatch[0];
                    // Try to extract uname first
                    const unameMatch = fullMatch.match(/uname="([^"]+)"/);
                    if (unameMatch) {
                        nodeSet.add(unameMatch[1]);
                        debugLog('[clusterNodes parser] Found node from XML uname:', unameMatch[1]);
                        continue;
                    }
                    // Fallback to id if uname not found (but skip numeric-only ids)
                    const idMatch = fullMatch.match(/id="([^"]+)"/);
                    if (idMatch && !idMatch[1].match(/^\d+$/)) {
                        nodeSet.add(idMatch[1]);
                        debugLog('[clusterNodes parser] Found node from XML id:', idMatch[1]);
                        continue;
                    }
                }
                
                // Pattern 4: Simple "name: hostname" (not inside nodelist)
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
    },
    
    // Rule: Extract hosts file from network.txt (supportconfig) or etc/hosts (sosreport/crm_report/hb_report)
    hostsFile: {
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
            const lines = content.split('\n');
            const hosts = [];
            const hostnames = new Set();
            
            // Check if this is a direct /etc/hosts file (sosreport) or network.txt (supportconfig)
            const isDirectHostsFile = filename && filename.includes('/etc/hosts');
            
            let inHostsSection = isDirectHostsFile; // If direct hosts file, we're already in the section
            
            for (const line of lines) {
                // For supportconfig network.txt, detect /etc/hosts section boundaries
                if (!isDirectHostsFile) {
                    // If we're in the hosts section, check for end marker
                    if (inHostsSection && line.trim().startsWith('#==[ Configuration File ]===')) {
                        debugLog('[hostsFile parser] Found end marker, stopping');
                        break;
                    }
                    
                    // Detect start of /etc/hosts section
                    if (!inHostsSection) {
                        if (line.includes('# /etc/hosts')) {
                            inHostsSection = true;
                            debugLog('[hostsFile parser] Found /etc/hosts section start');
                            continue;
                        }
                        continue; // Skip lines until we find the start
                    }
                }
                
                // Now we're in the hosts section (or processing direct hosts file)
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
    },
    
    // Rule: Extract and validate corosync.conf from ha.txt (supportconfig) or corosync.conf (sosreport)
    corosyncConfig: {
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
            const lines = content.split('\n');
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
            
            // Check if this is a direct corosync.conf file (sosreport) or ha.txt (supportconfig)
            const isDirectCorosyncFile = filename && filename.includes('corosync.conf');
            
            // Find the corosync.conf section
            let inCorosyncSection = isDirectCorosyncFile; // If direct file, we're already in the section
            let corosyncLines = [];
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                
                // For supportconfig ha.txt, detect section boundaries
                if (!isDirectCorosyncFile) {
                    // Check for end marker if we're in the section
                    if (inCorosyncSection && line.trim().startsWith('#==[ Configuration File ]===')) {
                        debugLog('[corosyncConfig parser] Found end marker at line', i + 1);
                        break;
                    }
                    
                    // Detect start of corosync.conf section
                    if (!inCorosyncSection) {
                        if (line.includes('# /etc/corosync/corosync.conf')) {
                            inCorosyncSection = true;
                            debugLog('[corosyncConfig parser] Found corosync.conf section at line', i + 1);
                            continue;
                        }
                        continue;
                    }
                }
                
                // We're in the corosync.conf section (or processing direct file)
                corosyncLines.push(line);
            }
            
            if (corosyncLines.length === 0) {
                debugLog('[corosyncConfig parser] No corosync.conf found in ha.txt');
                return {
                    found: false,
                    warnings: []
                };
            }
            
            debugLog('[corosyncConfig parser] Extracted', corosyncLines.length, 'lines from corosync.conf');
            corosyncConf = corosyncLines.join('\n');
            
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
    },
    
    // Rule: Detect Pacemaker cluster resources
    pacemakerResources: {
        // Target file patterns - pacemaker CIB (Cluster Information Base) or crm config
        // supportconfig: */ha.txt (contains embedded crm_mon or cib.xml sections)
        // sosreport/crm_report: */cib.xml, */crm_mon*.txt, */crm*config, */pacemaker.log
        filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/crm.*config$|pacemaker\.log$|\/ha\.txt$/,
        
        parse: function(content, filename) {
            debugLog('[pacemakerResources parser] Analyzing pacemaker configuration in:', filename);
            
            const resources = [];
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
            
            for (const line of contentLines) {
                const trimmed = line.trim();
                
                // XML format: <primitive id="rsc_ip" class="ocf" provider="heartbeat" type="IPaddr2">
                const xmlMatch = trimmed.match(/<primitive\s+id="([^"]+)".*?type="([^"]+)".*?(?:provider="([^"]+)")?/);
                if (xmlMatch) {
                    const [, id, type, provider] = xmlMatch;
                    resources.push({
                        name: id,
                        type: type,
                        provider: provider || 'unknown',
                        format: 'xml',
                        node: null  // Node info not in XML, will be enriched from crm_mon
                    });
                    debugLog('[pacemakerResources parser] Found resource (XML):', id, type);
                    continue;
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
                        node: null  // Node info not in crm config, will be enriched from crm_mon
                    });
                    debugLog('[pacemakerResources parser] Found resource (crm):', name, type);
                    continue;
                }
                
                // crm_mon format variations:
                // * rsc_ip_ABC (ocf::heartbeat:IPaddr2): Started node1
                // * rsc_ip_ABC (ocf::heartbeat:IPaddr2):    Started node1
                // rsc_ip_ABC (ocf::heartbeat:IPaddr2): Started node1 (without asterisk)
                // Indented format (within Resource Group):
                //   * fs_NAP_ASCS       (ocf::heartbeat:Filesystem):     Started ccecccsprd01
                // Also captures: Stopped, Master, Slave, etc.
                
                // Debug: log lines that might be crm_mon output
                if (trimmed.includes('(ocf::') || trimmed.includes('(stonith:')) {
                    debugLog('[pacemakerResources parser] Checking crm_mon line:', trimmed.substring(0, 100));
                }
                
                const monMatch = trimmed.match(/^\*?\s*(\S+)\s+\((\S+)::(\S+):(\S+)\):\s+(\w+)(?:\s+(\S+))?/);
                if (monMatch) {
                    const [, name, cls, provider, type, status, node] = monMatch;
                    
                    // Check if resource already exists (from XML or crm config)
                    const existing = resources.find(r => r.name === name);
                    if (existing) {
                        // Enrich existing resource with node info
                        existing.node = node || null;
                        existing.status = status;
                        debugLog('[pacemakerResources parser] Enriched resource with node info:', name, 'on', node || 'unknown', 'status:', status);
                    } else {
                        // Add new resource
                        resources.push({
                            name: name,
                            type: type,
                            provider: provider,
                            class: cls,
                            format: 'crm_mon',
                            node: node || null,
                            status: status
                        });
                        debugLog('[pacemakerResources parser] Found resource (crm_mon):', name, type, 'on', node || 'unknown', 'status:', status);
                    }
                    continue;
                }
                
                // Pattern for lines without parentheses but with colon separator
                // Example:   * stonith-sbd (stonith:external/sbd):  Started cceccerprd02
                // Format: name (type:provider/agent): Status node
                const stonithMatch = trimmed.match(/^\*?\s*(\S+)\s+\((\S+):(\S+)\/(\S+)\):\s+(\w+)(?:\s+(\S+))?/);
                if (stonithMatch) {
                    const [, name, type, provider, agent, status, node] = stonithMatch;
                    
                    const existing = resources.find(r => r.name === name);
                    if (existing) {
                        existing.node = node || null;
                        existing.status = status;
                        debugLog('[pacemakerResources parser] Enriched resource (stonith):', name, 'on', node || 'unknown');
                    } else {
                        resources.push({
                            name: name,
                            type: agent,
                            provider: provider,
                            class: type,
                            format: 'crm_mon_stonith',
                            node: node || null,
                            status: status
                        });
                        debugLog('[pacemakerResources parser] Found resource (stonith format):', name, agent, 'on', node || 'unknown');
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
            
            // Second pass: Extract node information from XML rsc_location constraints
            // These show where resources are configured to run
            // Format: <rsc_location id="loc-..." rsc="resource_name" role="Started" node="nodename" score="..."/>
            debugLog('[pacemakerResources parser] Looking for rsc_location constraints in XML...');
            for (const line of contentLines) {
                const trimmed = line.trim();
                const locMatch = trimmed.match(/<rsc_location\s+.*?rsc="([^"]+)".*?node="([^"]+)".*?(?:role="([^"]+)")?/);
                if (locMatch) {
                    const [, rscName, node, role] = locMatch;
                    const resource = resources.find(r => r.name === rscName);
                    if (resource && !resource.node) {
                        resource.node = node;
                        resource.status = role || 'Started';
                        debugLog('[pacemakerResources parser] Enriched from XML constraint:', rscName, 'on', node, 'role:', role || 'Started');
                    }
                }
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
            
            return {
                found: true,
                resources: resources,
                count: resources.length,
                failedActions: failedActions,
                failedActionsCount: failedActions.length
            };
        }
    },
    
    // Rule: Detect corosync runtime status from corosync-cfgtool
    corosyncStatus: {
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
    },
    
    // Rule: Detect fencing/STONITH configuration
    fencingConfig: {
        // Target file patterns - match cib.xml anywhere in the archive
        filePattern: /cib\.xml$|\/crm_mon.*\.txt$|\/crm.*config$|stonith|\/ha\.txt$/,
        
        parse: function(content, filename) {
            debugLog('[fencingConfig parser] Analyzing fencing configuration in:', filename);
            
            const fencingDevices = [];
            const lines = content.split('\n');
            let stonithEnabled = null;
            let stonithSourceFile = null;
            let stonithSourcePattern = null;
            
            for (let lineNum = 0; lineNum < lines.length; lineNum++) {
                const line = lines[lineNum];
                const trimmed = line.trim();
                
                // Check if STONITH is enabled
                // Format: stonith-enabled=true or <nvpair name="stonith-enabled" value="true"/>
                if (trimmed.match(/stonith-enabled[=\s]*true/i)) {
                    stonithEnabled = true;
                    stonithSourceFile = filename;
                    stonithSourcePattern = 'stonith-enabled=true';
                    debugLog('[fencingConfig parser] STONITH is enabled at line', lineNum + 1);
                } else if (trimmed.match(/name="stonith-enabled".*value="true"/i)) {
                    stonithEnabled = true;
                    stonithSourceFile = filename;
                    stonithSourcePattern = '<nvpair name="stonith-enabled" value="true"/>';
                    debugLog('[fencingConfig parser] STONITH is enabled (XML) at line', lineNum + 1);
                }
                
                if (trimmed.match(/stonith-enabled[=\s]*false/i)) {
                    stonithEnabled = false;
                    stonithSourceFile = filename;
                    stonithSourcePattern = 'stonith-enabled=false';
                    debugLog('[fencingConfig parser] STONITH is disabled at line', lineNum + 1);
                } else if (trimmed.match(/name="stonith-enabled".*value="false"/i)) {
                    stonithEnabled = false;
                    stonithSourceFile = filename;
                    stonithSourcePattern = '<nvpair name="stonith-enabled" value="false"/>';
                    debugLog('[fencingConfig parser] STONITH is disabled (XML) at line', lineNum + 1);
                }
                
                // Detect Azure fencing agent: fence_azure_arm
                // XML: <primitive id="stonith-fence_azure_arm" type="fence_azure_arm">
                // crm: primitive stonith-fence_azure_arm stonith:fence_azure_arm
                const azureFenceMatch = trimmed.match(/(?:primitive.*?id="|primitive\s+)([^"\s]+).*?fence_azure_arm/);
                if (azureFenceMatch) {
                    const deviceName = azureFenceMatch[1];
                    if (!fencingDevices.find(d => d.name === deviceName)) {
                        const isXml = trimmed.includes('<primitive');
                        fencingDevices.push({
                            name: deviceName,
                            type: 'fence_azure_arm',
                            agent: 'Azure Fencing Agent',
                            cloud: 'Azure',
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            pattern: isXml ? 'XML: <primitive ... type="fence_azure_arm">' : 'crm: primitive ... fence_azure_arm'
                        });
                        debugLog('[fencingConfig parser] Found Azure fencing agent:', deviceName, 'at line', lineNum + 1);
                    }
                }
                
                // Detect other common fencing agents
                const fenceMatch = trimmed.match(/(?:primitive.*?id="|primitive\s+)([^"\s]+).*?stonith:(\S+)/);
                if (fenceMatch) {
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
                        
                        const isXml = trimmed.includes('<primitive');
                        fencingDevices.push({
                            name: deviceName,
                            type: agentType,
                            agent: agent,
                            cloud: cloud,
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            pattern: isXml ? 'XML: <primitive ... class="stonith">' : `crm: primitive ... stonith:${agentType}`
                        });
                        debugLog('[fencingConfig parser] Found fencing device:', deviceName, agentType, 'at line', lineNum + 1);
                    }
                }
                
                // Also check XML format: <primitive ... class="stonith" type="fence_XXX"> or type="external/XXX">
                const xmlFenceMatch = trimmed.match(/<primitive\s+id="([^"]+)".*?class="stonith".*?type="([^"]+)"/);
                if (xmlFenceMatch) {
                    const [, deviceName, agentType] = xmlFenceMatch;
                    if (!fencingDevices.find(d => d.name === deviceName)) {
                        let agent = agentType;
                        let cloud = null;
                        
                        // Handle external/sbd format
                        if (agentType.startsWith('external/')) {
                            const externalType = agentType.split('/')[1];
                            agent = `External ${externalType.toUpperCase()}`;
                        } else if (agentType.includes('azure') || agentType.includes('fence_azure_arm')) {
                            agent = 'Azure Fencing';
                            cloud = 'Azure';
                        } else if (agentType.includes('aws')) {
                            agent = 'AWS Fencing';
                            cloud = 'AWS';
                        } else if (agentType.includes('gce')) {
                            agent = 'GCP Fencing';
                            cloud = 'GCP';
                        } else if (agentType.startsWith('fence_')) {
                            // Generic fence agent
                            const fenceType = agentType.replace('fence_', '');
                            agent = `Fence ${fenceType.toUpperCase()}`;
                        }
                        
                        fencingDevices.push({
                            name: deviceName,
                            type: agentType,
                            agent: agent,
                            cloud: cloud,
                            sourceFile: filename,
                            sourceLine: lineNum + 1,
                            pattern: `XML: <primitive class="stonith" type="${agentType}">`
                        });
                        debugLog('[fencingConfig parser] Found fencing device (XML):', deviceName, agentType, 'at line', lineNum + 1);
                    }
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
    },
    
    // Rule: Detect cluster events (resource migrations and fencing events) from pacemaker/cluster logs
    clusterEvents: {
        // Target file patterns - pacemaker.log, corosync.log, cluster.log, ha-log, messages
        // Also includes journalctl output and crm_report archives
        filePattern: /\/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
        
        parse: function(content, filename) {
            debugLog('[clusterEvents parser] Analyzing cluster logs in:', filename);
            
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
                // Syslog format: Nov 11 10:30:45
                // Journal format: Nov 11 10:30:45.123456
                let timestamp = null;
                const isoMatch = trimmed.match(/^(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)/);
                const syslogMatch = trimmed.match(/^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)/);
                
                if (isoMatch) {
                    timestamp = isoMatch[1];
                } else if (syslogMatch) {
                    timestamp = syslogMatch[1];
                }
                
                // Detect resource migration/move events
                // Patterns:
                // - "Moving resource <resource> from <node1> to <node2>"
                // - "Migrating <resource> from <node1> to <node2>"
                // - "notice: pcmk_graph_info: Transition: Starting <resource> on <node>"
                // - "notice: Operation <resource>_start_0: ok (node=<node>)"
                // - "Resource <resource> is active on <node> (previously on <node>)"
                
                const moveMatch = trimmed.match(/(?:Moving|Migrating)\s+(?:resource\s+)?(\S+)\s+from\s+(\S+)\s+to\s+(\S+)/i);
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
                const startMatch = trimmed.match(/(?:Starting|Transition.*Starting)\s+(\S+)\s+on\s+(\S+)/i);
                if (startMatch) {
                    const [, resource, node] = startMatch;
                    
                    // Reject systemd messages explicitly
                    if (trimmed.includes('systemd')) continue;
                    
                    // Reject lines with process ID patterns like [123]:
                    if (/\[\d+\]:/.test(trimmed)) continue;
                    
                    // Exclude systemd service type names
                    const isSystemdService = resource.match(/\.(service|target|socket|mount|swap|path|timer|device|scope|slice)$/i) ||
                                            resource.includes('@');  // systemd template units like service@instance
                    
                    // Only add if not systemd service and not a duplicate from same line
                    if (!isSystemdService && 
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
                const stopMatch = trimmed.match(/(?:Stopping|Stopped)\s+(\S+)\s+on\s+(\S+)/i);
                if (stopMatch) {
                    const [, resource, node] = stopMatch;
                    
                    // Reject systemd messages explicitly
                    if (trimmed.includes('systemd')) continue;
                    
                    // Reject lines with process ID patterns like [123]:
                    if (/\[\d+\]:/.test(trimmed)) continue;
                    
                    // Exclude systemd service type names
                    const isSystemdService = resource.match(/\.(service|target|socket|mount|swap|path|timer|device|scope|slice)$/i) ||
                                            resource.includes('@');  // systemd template units like service@instance
                    
                    if (!isSystemdService) {
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
                const opMatch = trimmed.match(/Operation\s+(\S+?)_(?:start|stop|monitor|migrate)_\d+:\s*\w+\s*\(node=(\S+)\)/i);
                if (opMatch) {
                    const [, resource, node] = opMatch;
                    const isStart = trimmed.includes('_start_');
                    const isStop = trimmed.includes('_stop_');
                    
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
                // - "fence_azure_arm: Called fence_azure_arm for <node>"
                // - "Node <node> will be fenced"
                
                const fenceRequestMatch = trimmed.match(/Requesting\s+fencing\s+\((\w+)\)\s+(?:of\s+)?(?:node\s+)?(\S+)/i);
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
                
                const fenceSuccessMatch = trimmed.match(/(?:Fencing|stonith.*?fence)\s+(\S+).*?(?:success|succeeded)/i);
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
                const stonithOpSuccess = trimmed.match(/Operation\s+(?:stonith-)?(\S+?)_(?:reboot|monitor|on|off)_\d+:\s*ok/i);
                if (stonithOpSuccess && (trimmed.toLowerCase().includes('stonith') || trimmed.toLowerCase().includes('fence'))) {
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
                const peerTerminated = trimmed.match(/(?:Peer|peer)\s+(\S+)\s+was\s+(?:terminated|fenced)\s+\((\w+)\)/i);
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
                
                // "stonith_api_time: <node> was fenced successfully"
                const apiSuccess = trimmed.match(/stonith.*?(\S+)\s+was\s+fenced\s+successfully/i);
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
                
                const fenceFailMatch = trimmed.match(/(?:Fencing|stonith.*?fence)\s+(\S+).*?(?:fail|error)/i);
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
                
                // "Node <node> will be fenced"
                const fenceWillMatch = trimmed.match(/(?:Node|peer)\s+(\S+)\s+will\s+be\s+fenced/i);
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
                const fenceAgentMatch = trimmed.match(/(fence_\w+).*?(?:Called|for)\s+.*?(?:node\s+)?(\S+)/i);
                if (fenceAgentMatch && (trimmed.toLowerCase().includes('fence') || trimmed.toLowerCase().includes('stonith'))) {
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
            }
            
            if (resourceMigrations.length === 0 && fencingEvents.length === 0) {
                debugLog('[clusterEvents parser] No cluster events found');
                return { found: false };
            }
            
            debugLog('[clusterEvents parser] Found', resourceMigrations.length, 'resource events and', fencingEvents.length, 'fencing events');
            return {
                found: true,
                resourceMigrations: resourceMigrations,
                fencingEvents: fencingEvents,
                totalEvents: resourceMigrations.length + fencingEvents.length
            };
        }
    },
    
    // Rule: Detect Hyper-V Live Migration events from message logs
    liveMigration: {
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
                    const heartbeatTimestamp = this.extractTimestamp(line);
                    
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
                            const timestamp = this.extractTimestamp(lines[heartbeatLine]);
                            
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
                count: migrations.length,
                events: migrations
            };
        },
        
        // Helper function to extract timestamp from log line
        extractTimestamp: function(line) {
            // Common syslog timestamp patterns:
            // 1. "2025-10-23T14:30:45.123456+00:00"
            // 2. "Oct 23 14:30:45"
            // 3. "2025-10-23 14:30:45"
            
            // Try ISO timestamp
            const isoMatch = line.match(/(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)/);
            if (isoMatch) return isoMatch[1];
            
            // Try syslog format (Month Day Time)
            const syslogMatch = line.match(/((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})/);
            if (syslogMatch) return syslogMatch[1];
            
            // Try simple date format
            const simpleMatch = line.match(/(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/);
            if (simpleMatch) return simpleMatch[1];
            
            return null;
        }
    },
    
    // Rule: Detect Linux kernel reboots from message logs
    kernelReboots: {
        // Target file path patterns (same as liveMigration)
        // supportconfig: */messages or */localmessages (with optional suffixes)
        // sosreport: */var/log/messages or */sos_commands/logs/journalctl*
        filePattern: /\/(messages|localmessages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
        
        // Parse function receives file content as string
        // Detects kernel reboots by finding patterns:
        // - "Linux version" (kernel boot message)
        // - "Command line:" (kernel command line)
        // - System restart messages
        // Returns array of detected reboot events with timestamps and kernel versions
        parse: function(content) {
            const lines = content.split('\n');
            const reboots = [];
            
            debugLog('[kernelReboots parser] Analyzing', lines.length, 'lines for kernel reboots');
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                
                // Pattern 1: "Linux version X.Y.Z" - primary boot message
                const kernelMatch = line.match(/kernel:\s*Linux version\s+([\d\.\-\w]+)/i);
                if (kernelMatch) {
                    const timestamp = this.extractTimestamp(line);
                    const kernelVersion = kernelMatch[1];
                    
                    reboots.push({
                        timestamp: timestamp || 'Unknown',
                        lineNumber: i + 1,
                        kernelVersion: kernelVersion,
                        type: 'kernel_boot',
                        rawLine: line.trim()
                    });
                    
                    debugLog('[kernelReboots parser] ✓ Detected kernel boot at line', i + 1, ':', timestamp, 'version:', kernelVersion);
                    continue;
                }
                
                // Pattern 2: systemd reboot messages
                if (line.match(/systemd.*Shutting down/i) || 
                    line.match(/systemd.*Starting Reboot/i) ||
                    line.match(/systemd.*Stopped target.*Shutdown/i)) {
                    const timestamp = this.extractTimestamp(line);
                    
                    // Check if we already have a reboot event very close to this timestamp
                    const isDuplicate = reboots.some(r => {
                        if (!timestamp || !r.timestamp) return false;
                        // Simple duplicate check - same line or very close
                        return Math.abs(r.lineNumber - (i + 1)) < 5;
                    });
                    
                    if (!isDuplicate) {
                        reboots.push({
                            timestamp: timestamp || 'Unknown',
                            lineNumber: i + 1,
                            kernelVersion: null,
                            type: 'systemd_shutdown',
                            rawLine: line.trim()
                        });
                        
                        debugLog('[kernelReboots parser] ✓ Detected systemd shutdown at line', i + 1, ':', timestamp);
                    }
                    continue;
                }
                
                // Pattern 3: "reboot: " messages
                if (line.match(/kernel:\s*reboot:/i)) {
                    const timestamp = this.extractTimestamp(line);
                    
                    reboots.push({
                        timestamp: timestamp || 'Unknown',
                        lineNumber: i + 1,
                        kernelVersion: null,
                        type: 'reboot_message',
                        rawLine: line.trim()
                    });
                    
                    debugLog('[kernelReboots parser] ✓ Detected reboot message at line', i + 1, ':', timestamp);
                    continue;
                }
            }
            
            debugLog('[kernelReboots parser] Found', reboots.length, 'reboot events');
            
            return {
                count: reboots.length,
                events: reboots
            };
        },
        
        // Helper function to extract timestamp from log line (reuse from liveMigration)
        extractTimestamp: function(line) {
            // Try ISO timestamp
            const isoMatch = line.match(/(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)/);
            if (isoMatch) return isoMatch[1];
            
            // Try syslog format (Month Day Time)
            const syslogMatch = line.match(/((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})/);
            if (syslogMatch) return syslogMatch[1];
            
            // Try simple date format
            const simpleMatch = line.match(/(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/);
            if (simpleMatch) return simpleMatch[1];
            
            return null;
        }
    },
    
    // Rule: Detect Out of Memory (OOM) killer events from message logs
    oomKiller: {
        // Target file path patterns (same as liveMigration and kernelReboots)
        // supportconfig: */messages or */localmessages (with optional suffixes)
        // sosreport: */var/log/messages or */sos_commands/logs/journalctl*
        filePattern: /\/(messages|localmessages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
        
        // Parse function receives file content as string
        // Detects OOM killer events by finding patterns:
        // - "Out of memory: Kill process" or "Out of memory: Killed process"
        // - "oom-killer:" or "oom_reaper:"
        // - Memory statistics and killed process information
        // Returns array of detected OOM events with process details
        parse: function(content) {
            const lines = content.split('\n');
            const oomEvents = [];
            
            debugLog('[oomKiller parser] Analyzing', lines.length, 'lines for OOM killer events');
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                
                // Pattern 1: "Out of memory: Kill process" or "Out of memory: Killed process"
                const oomKillMatch = line.match(/Out of memory:.*Kill(?:ed)? process\s+(\d+)\s+\(([^)]+)\)/i);
                if (oomKillMatch) {
                    const timestamp = this.extractTimestamp(line);
                    const pid = oomKillMatch[1];
                    const processName = oomKillMatch[2];
                    
                    // Try to find memory score on the same line or nearby lines
                    let score = null;
                    const scoreMatch = line.match(/score\s+(\d+)/i);
                    if (scoreMatch) {
                        score = scoreMatch[1];
                    }
                    
                    // Try to find total VM info
                    let totalVM = null;
                    const vmMatch = line.match(/total-vm:(\d+)kB/i);
                    if (vmMatch) {
                        totalVM = vmMatch[1] + 'kB';
                    }
                    
                    oomEvents.push({
                        timestamp: timestamp || 'Unknown',
                        lineNumber: i + 1,
                        pid: pid,
                        processName: processName,
                        score: score,
                        totalVM: totalVM,
                        type: 'oom_kill',
                        rawLine: line.trim()
                    });
                    
                    debugLog('[oomKiller parser] ✓ Detected OOM kill at line', i + 1, ':', timestamp, 'process:', processName, 'pid:', pid);
                    continue;
                }
                
                // Pattern 2: "oom-killer:" invocation (usually precedes the kill message)
                if (line.match(/invoked oom-killer:/i)) {
                    const timestamp = this.extractTimestamp(line);
                    
                    // Extract the process that invoked OOM killer
                    let invokedBy = null;
                    const invokeMatch = line.match(/\]\s+([^\s]+)\s+invoked oom-killer:/i);
                    if (invokeMatch) {
                        invokedBy = invokeMatch[1];
                    }
                    
                    // Extract memory allocation info if present
                    let order = null;
                    const orderMatch = line.match(/order=(\d+)/i);
                    if (orderMatch) {
                        order = orderMatch[1];
                    }
                    
                    // Check if we already have an event very close to this
                    const isDuplicate = oomEvents.some(e => {
                        return Math.abs(e.lineNumber - (i + 1)) < 3;
                    });
                    
                    if (!isDuplicate) {
                        oomEvents.push({
                            timestamp: timestamp || 'Unknown',
                            lineNumber: i + 1,
                            pid: null,
                            processName: null,
                            invokedBy: invokedBy,
                            order: order,
                            type: 'oom_invoked',
                            rawLine: line.trim()
                        });
                        
                        debugLog('[oomKiller parser] ✓ Detected OOM invocation at line', i + 1, ':', timestamp, 'by:', invokedBy);
                    }
                    continue;
                }
                
                // Pattern 3: "oom_reaper:" messages (cleanup after OOM kill)
                if (line.match(/oom_reaper:/i)) {
                    const timestamp = this.extractTimestamp(line);
                    
                    // Extract PID if present
                    let pid = null;
                    const pidMatch = line.match(/reaped process\s+(\d+)/i);
                    if (pidMatch) {
                        pid = pidMatch[1];
                    }
                    
                    // Check if we already have an event very close to this
                    const isDuplicate = oomEvents.some(e => {
                        return Math.abs(e.lineNumber - (i + 1)) < 3;
                    });
                    
                    if (!isDuplicate) {
                        oomEvents.push({
                            timestamp: timestamp || 'Unknown',
                            lineNumber: i + 1,
                            pid: pid,
                            processName: null,
                            type: 'oom_reaper',
                            rawLine: line.trim()
                        });
                        
                        debugLog('[oomKiller parser] ✓ Detected OOM reaper at line', i + 1, ':', timestamp);
                    }
                    continue;
                }
                
                // Pattern 4: "Cannot allocate memory" errors
                if (line.match(/Cannot allocate memory/i)) {
                    const timestamp = this.extractTimestamp(line);
                    
                    // Extract process name if present
                    let processName = null;
                    const processMatch = line.match(/\]\s+([^\s:]+):/);
                    if (processMatch) {
                        processName = processMatch[1];
                    }
                    
                    // Check if we already have an event very close to this
                    const isDuplicate = oomEvents.some(e => {
                        return Math.abs(e.lineNumber - (i + 1)) < 3;
                    });
                    
                    if (!isDuplicate) {
                        oomEvents.push({
                            timestamp: timestamp || 'Unknown',
                            lineNumber: i + 1,
                            pid: null,
                            processName: processName,
                            type: 'alloc_failure',
                            rawLine: line.trim()
                        });
                        
                        debugLog('[oomKiller parser] ✓ Detected allocation failure at line', i + 1, ':', timestamp, 'process:', processName);
                    }
                    continue;
                }
            }
            
            debugLog('[oomKiller parser] Found', oomEvents.length, 'OOM killer events');
            
            return {
                count: oomEvents.length,
                events: oomEvents
            };
        },
        
        // Helper function to extract timestamp from log line
        extractTimestamp: function(line) {
            // Try ISO timestamp
            const isoMatch = line.match(/(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)/);
            if (isoMatch) return isoMatch[1];
            
            // Try syslog format (Month Day Time)
            const syslogMatch = line.match(/((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})/);
            if (syslogMatch) return syslogMatch[1];
            
            // Try simple date format
            const simpleMatch = line.match(/(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/);
            if (simpleMatch) return simpleMatch[1];
            
            return null;
        }
    },
    
    // Rule: Validate Azure-specific RPM packages
    rpmPackages: {
        // Target file patterns
        // supportconfig: */rpm.txt
        // sosreport: */installed-rpms or */sos_commands/rpm/package-data
        filePattern: /\/(rpm\.txt|installed-rpms|package-data)$/,
        
        // Parse function receives rpm.txt content
        // Validates Azure-required packages with specific version requirements
        parse: function(content) {
            const lines = content.split('\n');
            
            debugLog('[rpmPackages parser] Analyzing', lines.length, 'lines');
            
            // Required Azure packages with minimum version requirements
            const requiredPackages = {
                'fence-agents': { version: '4.4', operator: 'gte' },
                'python3-azure-mgmt-compute': { version: '17.0', operator: 'gte' },
                'python3-azure-identity': { version: '1.0', operator: 'gte' },
                'cloud-netconfig-azure': { version: '1.3', operator: 'gte' },
                'resource-agents': { version: '4.3', operator: 'gte' },
                'python3-azure-core': { minVersion: '1.9', maxVersion: '1.22', operator: 'range' }
            };
            
            const foundPackages = {};
            const warnings = [];
            
            // Parse RPM listing
            // Common RPM formats:
            // - "package-name-1.2.3-4.el8.x86_64"
            // - "package-name-1.2.3-4.noarch"
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;
                
                // Try to match RPM package format
                // Pattern: package-name-version-release.arch
                for (const [pkgName, requirements] of Object.entries(requiredPackages)) {
                    // Look for package name at start of line
                    const pkgRegex = new RegExp(`^${pkgName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}-(\\d+\\.\\d+(?:\\.\\d+)?)`);
                    const match = trimmed.match(pkgRegex);
                    
                    if (match) {
                        const version = match[1];
                        foundPackages[pkgName] = version;
                        debugLog('[rpmPackages parser] Found', pkgName, 'version', version);
                        
                        // Validate version
                        if (requirements.operator === 'gte') {
                            if (!this.compareVersion(version, requirements.version, 'gte')) {
                                warnings.push({
                                    package: pkgName,
                                    expected: `>= ${requirements.version}`,
                                    actual: version,
                                    severity: 'error',
                                    message: `Package ${pkgName} version is ${version}, but should be >= ${requirements.version} for Azure environments`,
                                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                                });
                                debugLog('[rpmPackages parser] WARNING:', pkgName, 'version too old');
                            }
                        } else if (requirements.operator === 'range') {
                            // Check if version is INSIDE the problematic range (inverted logic)
                            if (this.compareVersion(version, requirements.minVersion, 'gte') && 
                                this.compareVersion(version, requirements.maxVersion, 'lte')) {
                                warnings.push({
                                    package: pkgName,
                                    expected: `< ${requirements.minVersion} or > ${requirements.maxVersion}`,
                                    actual: version,
                                    severity: 'error',
                                    message: `Package ${pkgName} version is ${version}, but should be lower than ${requirements.minVersion} or higher than ${requirements.maxVersion} for Azure environments`,
                                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                                });
                                debugLog('[rpmPackages parser] WARNING:', pkgName, 'version in problematic range');
                            }
                        }
                    }
                }
            }
            
            // Check for missing packages
            for (const [pkgName, requirements] of Object.entries(requiredPackages)) {
                if (!foundPackages[pkgName]) {
                    warnings.push({
                        package: pkgName,
                        expected: requirements.operator === 'gte' ? `>= ${requirements.version}` : `${requirements.minVersion} - ${requirements.maxVersion}`,
                        actual: 'not found',
                        severity: 'error',
                        message: `Required package ${pkgName} not found in rpm.txt`,
                        documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                    });
                    debugLog('[rpmPackages parser] WARNING:', pkgName, 'not found');
                }
            }
            
            return {
                found: true,
                packages: foundPackages,
                warnings: warnings
            };
        },
        
        // Helper function to compare versions
        compareVersion: function(actual, expected, operator) {
            const parseVersion = (v) => {
                const parts = v.split('.').map(p => parseInt(p, 10));
                return {
                    major: parts[0] || 0,
                    minor: parts[1] || 0,
                    patch: parts[2] || 0
                };
            };
            
            const actualParts = parseVersion(actual);
            const expectedParts = parseVersion(expected);
            
            switch (operator) {
                case 'exact':
                    return actualParts.major === expectedParts.major && 
                           actualParts.minor === expectedParts.minor;
                           
                case 'gte': // greater than or equal
                    if (actualParts.major > expectedParts.major) return true;
                    if (actualParts.major < expectedParts.major) return false;
                    if (actualParts.minor > expectedParts.minor) return true;
                    if (actualParts.minor < expectedParts.minor) return false;
                    return actualParts.patch >= expectedParts.patch;
                    
                case 'lte': // less than or equal
                    if (actualParts.major < expectedParts.major) return true;
                    if (actualParts.major > expectedParts.major) return false;
                    if (actualParts.minor < expectedParts.minor) return true;
                    if (actualParts.minor > expectedParts.minor) return false;
                    return actualParts.patch <= expectedParts.patch;
                    
                default:
                    return false;
            }
        }
    },
    
    // Rule: Detect Falcon Sensor (CrowdStrike) and check SAP exceptions
    falconSensor: {
        // Target file patterns - RPM list and process list
        filePattern: /\/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$/,
        
        parse: function(content) {
            const lines = content.split('\n');
            debugLog('[falconSensor parser] Analyzing', lines.length, 'lines for Falcon Sensor');
            
            let detected = false;
            let version = null;
            let runningProcess = false;
            const sapExceptions = {
                checked: false,
                paths: []
            };
            
            // Check for Falcon Sensor package or process
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;
                
                // Check RPM package: falcon-sensor-X.Y.Z
                const rpmMatch = trimmed.match(/^falcon-sensor-([\d.]+)/);
                if (rpmMatch) {
                    detected = true;
                    version = rpmMatch[1];
                    debugLog('[falconSensor parser] Found Falcon Sensor RPM:', version);
                }
                
                // Check running process
                if (trimmed.includes('falcon-sensor') || trimmed.includes('/opt/CrowdStrike')) {
                    runningProcess = true;
                    debugLog('[falconSensor parser] Found Falcon Sensor process');
                }
            }
            
            if (!detected) {
                debugLog('[falconSensor parser] Falcon Sensor not detected');
                return { found: false };
            }
            
            // If detected, check for SAP exclusions in config files
            // Common Falcon config locations: /opt/CrowdStrike/falconctl or policy files
            // For now, we'll mark as needing manual verification
            debugLog('[falconSensor parser] Falcon Sensor detected, version:', version);
            
            return {
                found: true,
                version: version,
                runningProcess: runningProcess,
                sapExceptionsConfigured: null, // null = unknown, needs config file check
                message: 'Falcon Sensor detected. SAP exclusions should be verified manually in /opt/CrowdStrike configuration.'
            };
        }
    },
    
    // Rule: Check Falcon Sensor SAP exclusions in config files
    falconSensorConfig: {
        filePattern: /\/(falconctl|CrowdStrike.*config|falcon.*conf)$/i,
        
        parse: function(content) {
            debugLog('[falconSensorConfig parser] Checking Falcon config for SAP exclusions');
            
            // SAP paths that should be excluded
            const sapPaths = [
                '/usr/sap',
                '/hana/shared',
                '/hana/data',
                '/hana/log',
                '/sapmnt',
                '/usr/sap/*/SYS/exe'
            ];
            
            const foundExclusions = [];
            const lines = content.split('\n');
            
            for (const line of lines) {
                const lower = line.toLowerCase();
                
                // Check for exclusion configurations
                if (lower.includes('exclude') || lower.includes('exception')) {
                    for (const sapPath of sapPaths) {
                        if (line.includes(sapPath)) {
                            foundExclusions.push(sapPath);
                            debugLog('[falconSensorConfig parser] Found SAP exclusion:', sapPath);
                        }
                    }
                }
            }
            
            return {
                found: true,
                exclusions: foundExclusions,
                hasExclusions: foundExclusions.length > 0
            };
        }
    },
    
    // Rule: Detect Microsoft Defender and check SAP exceptions
    msDefender: {
        filePattern: /\/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$/,
        
        parse: function(content) {
            const lines = content.split('\n');
            debugLog('[msDefender parser] Analyzing', lines.length, 'lines for MS Defender');
            
            let detected = false;
            let version = null;
            let runningProcess = false;
            
            // Check for Microsoft Defender package or process
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;
                
                // Check RPM package: mdatp (Microsoft Defender ATP)
                const rpmMatch = trimmed.match(/^mdatp-([\d.]+)/);
                if (rpmMatch) {
                    detected = true;
                    version = rpmMatch[1];
                    debugLog('[msDefender parser] Found MS Defender RPM:', version);
                }
                
                // Check running process
                if (trimmed.includes('mdatp') || trimmed.includes('wdavdaemon') || trimmed.includes('/opt/microsoft/mdatp')) {
                    runningProcess = true;
                    debugLog('[msDefender parser] Found MS Defender process');
                }
            }
            
            if (!detected) {
                debugLog('[msDefender parser] MS Defender not detected');
                return { found: false };
            }
            
            debugLog('[msDefender parser] MS Defender detected, version:', version);
            
            return {
                found: true,
                version: version,
                runningProcess: runningProcess,
                sapExceptionsConfigured: null, // null = unknown, needs config check
                message: 'Microsoft Defender detected. SAP exclusions should be verified with: mdatp exclusion list'
            };
        }
    },
    
    // Rule: Check MS Defender SAP exclusions
    msDefenderConfig: {
        filePattern: /\/(mdatp.*|defender.*config)$/i,
        
        parse: function(content) {
            debugLog('[msDefenderConfig parser] Checking MS Defender config for SAP exclusions');
            
            // SAP paths that should be excluded
            const sapPaths = [
                '/usr/sap',
                '/hana/shared',
                '/hana/data',
                '/hana/log',
                '/sapmnt',
                '/usr/sap/*/SYS/exe'
            ];
            
            const foundExclusions = [];
            const lines = content.split('\n');
            
            for (const line of lines) {
                const lower = line.toLowerCase();
                
                // Check for exclusion configurations
                if (lower.includes('exclusion') || lower.includes('exclude')) {
                    for (const sapPath of sapPaths) {
                        if (line.includes(sapPath)) {
                            foundExclusions.push(sapPath);
                            debugLog('[msDefenderConfig parser] Found SAP exclusion:', sapPath);
                        }
                    }
                }
            }
            
            return {
                found: true,
                exclusions: foundExclusions,
                hasExclusions: foundExclusions.length > 0
            };
        }
    },
    
    // Rule: Detect Illumio
    illumio: {
        filePattern: /sos_commands\/systemd\/systemctl_list-units_--all$/,
        
        parse: function(content) {
            const lines = content.split('\n');
            debugLog('[illumio parser] Analyzing', lines.length, 'lines for Illumio');
            
            let detected = false;
            
            // Check for Illumio in systemctl output
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;
                
                if (trimmed.includes('Illumio') || trimmed.includes('illumio')) {
                    detected = true;
                    debugLog('[illumio parser] Found Illumio:', trimmed);
                    break;
                }
            }
            
            if (!detected) {
                debugLog('[illumio parser] Illumio not detected');
                return { found: false };
            }
            
            debugLog('[illumio parser] Illumio detected');
            
            return {
                found: true,
                message: 'Illumio detected. SAP exclusions should be verified in Illumio policy configuration.'
            };
        }
    },
    
    // Rule: Detect Trend Micro Deep Security
    trendMicro: {
        filePattern: /sos_commands\/systemd\/systemctl_list-units_--all$/,
        
        parse: function(content) {
            const lines = content.split('\n');
            debugLog('[trendMicro parser] Analyzing', lines.length, 'lines for Trend Micro');
            
            let detected = false;
            
            // Check for Trend Micro Deep Security in systemctl output
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;
                
                if (trimmed.includes('ds_agent.service') && trimmed.includes('Trend Micro')) {
                    detected = true;
                    debugLog('[trendMicro parser] Found Trend Micro Deep Security:', trimmed);
                    break;
                }
            }
            
            if (!detected) {
                debugLog('[trendMicro parser] Trend Micro not detected');
                return { found: false };
            }
            
            debugLog('[trendMicro parser] Trend Micro Deep Security detected');
            
            return {
                found: true,
                message: 'Trend Micro Deep Security detected. SAP exclusions should be verified in Deep Security Manager.'
            };
        }
    },
    
    // Rule: Extract kernel tuning parameters from sysctl
    kernelTuning: {
        filePattern: /sos_commands\/kernel\/sysctl_-a$/,
        
        parse: function(content, filename) {
            debugLog('[kernelTuning parser] Analyzing kernel parameters in:', filename);
            
            const lines = content.split('\n');
            const parameters = {};
            const warnings = [];
            
            // Expected values for SAP HANA / high-performance workloads
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
            
            // Parse sysctl output
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed || trimmed.startsWith('#')) continue;
                
                // Parse "key = value" format
                const match = trimmed.match(/^([^\s=]+)\s*=\s*(.+)$/);
                if (match) {
                    const key = match[1].trim();
                    const value = match[2].trim();
                    parameters[key] = value;
                }
            }
            
            // Check for expected values
            for (const [param, expectedValue] of Object.entries(expectedValues)) {
                if (parameters[param]) {
                    const actualValue = parameters[param];
                    if (actualValue !== expectedValue) {
                        warnings.push({
                            parameter: param,
                            expected: expectedValue,
                            actual: actualValue,
                            documentationUrl: documentation[param]
                        });
                        debugLog(`[kernelTuning parser] Warning: ${param} = ${actualValue}, expected ${expectedValue}`);
                    } else {
                        debugLog(`[kernelTuning parser] OK: ${param} = ${actualValue}`);
                    }
                }
            }
            
            return {
                found: true,
                parameters: parameters,
                warnings: warnings,
                hasWarnings: warnings.length > 0
            };
        }
    },
    
    // Rule: Extract fstab file
    fstab: {
        filePattern: /\/etc\/fstab$/,
        
        parse: function(content, filename) {
            debugLog('[fstab parser] Analyzing fstab in:', filename);
            
            return {
                found: true,
                content: content
            };
        }
    }
    
    // ADD MORE RULES HERE
    // Example:
    // systemInfo: {
    //     filePattern: /\/basic-environment\.txt$/,
    //     parse: function(content) {
    //         // Extract system information
    //         return { /* parsed data */ };
    //     }
    // }
};

// ============================================================================
// END SCC RULES
// ============================================================================

// Load the streaming WASM module
importScripts(
    './liblzma-wasm/dist-streaming/liblzma-xz-streaming.js' + CACHE_BUST
);

let moduleReady = false;
let Module = null;

// Initialize the WASM module
LZMA_XZ_Streaming_Module({
    locateFile: (path) => {
        if (path.endsWith('.wasm')) {
            // Return the correct path relative to worker location
            const wasmPath = './liblzma-wasm/dist-streaming/liblzma-xz-streaming.wasm' + CACHE_BUST;
            debugLog('[XZ Streaming Worker] Loading WASM from:', wasmPath);
            return wasmPath;
        }
        return path;
    }
}).then((mod) => {
    Module = mod;
    debugLog('[XZ Streaming Worker] Module object received');
    
    // Verify critical properties are available
    if (!Module.HEAPU8) {
        console.error('[XZ Streaming Worker] HEAPU8 not available in module');
        console.error('[XZ Streaming Worker] Available properties:', Object.keys(Module));
        self.postMessage({ error: 'WASM module initialization incomplete: HEAPU8 missing' });
        moduleReady = false;
        return;
    }
    if (!Module._xz_stream_init || !Module._xz_stream_process) {
        console.error('[XZ Streaming Worker] Required functions not available');
        console.error('[XZ Streaming Worker] Available functions:', Object.keys(Module).filter(k => k.startsWith('_')));
        self.postMessage({ error: 'WASM module initialization incomplete: functions missing' });
        moduleReady = false;
        return;
    }
    
    moduleReady = true;
    debugLog('[XZ Streaming Worker] Module initialized successfully');
    debugLog('[XZ Streaming Worker] HEAPU8 available:', !!Module.HEAPU8);
    debugLog('[XZ Streaming Worker] Exported functions:', Object.keys(Module).filter(k => k.startsWith('_')));
    
    // Signal to main thread that worker is ready
    self.postMessage({ ready: true });
    debugLog('[XZ Streaming Worker] Ready message sent to main thread');
}).catch((err) => {
    console.error('[XZ Streaming Worker] Module initialization failed:', err);
    self.postMessage({ error: 'WASM module initialization failed: ' + err.message });
});

// Parse TAR headers incrementally as data arrives
class IncrementalTARParser {
    constructor() {
        this.buffer = new Uint8Array(0);
        this.files = [];
        this.directories = new Set();
        this.fileTypes = {};
        this.offset = 0;
        this.totalParsed = 0;
        this.foundEndMarker = false;
        
        // SCC report analysis state
        this.isSCCReport = false;
        this.sccReportName = null;
        this.analysisResults = {}; // Stores parsed results by rule name (no raw file content)
    }

    // Add decompressed chunk to buffer and parse what we can
    addChunk(chunk) {
        // Append to buffer
        const newBuffer = new Uint8Array(this.buffer.length + chunk.length);
        newBuffer.set(this.buffer);
        newBuffer.set(chunk, this.buffer.length);
        this.buffer = newBuffer;

        // Parse complete TAR entries
        this.parseAvailableEntries();
    }

    parseAvailableEntries() {
        while (this.buffer.length - this.offset >= 512) {
            // Check for end marker (two consecutive zero blocks)
            if (this.isEndMarker(this.offset)) {
                this.foundEndMarker = true;
                debugLog('[TAR Parser] Found TAR end marker');
                break;
            }

            // Need full header + potential data
            const header = this.parseHeader(this.offset);
            if (!header) {
                break; // Invalid or incomplete header
            }

            const entrySize = 512 + Math.ceil(header.size / 512) * 512;
            
            // Check if we have the complete entry
            if (this.buffer.length - this.offset < entrySize) {
                break; // Wait for more data
            }

            // Process entry
            this.processEntry(header);

            // Move to next entry
            this.offset += entrySize;
            this.totalParsed++;
        }

        // Trim processed data from buffer to keep memory low
        // Be aggressive about trimming - keep only 512KB of unprocessed data
        if (this.offset > 512 * 1024) {
            this.buffer = this.buffer.slice(this.offset);
            this.offset = 0;
        }
    }

    isEndMarker(offset) {
        if (this.buffer.length - offset < 1024) return false;
        for (let i = 0; i < 1024; i++) {
            if (this.buffer[offset + i] !== 0) return false;
        }
        return true;
    }

    parseHeader(offset) {
        if (this.buffer.length - offset < 512) return null;

        // Read filename (null-terminated)
        let filename = '';
        for (let i = 0; i < 100; i++) {
            if (this.buffer[offset + i] === 0) break;
            filename += String.fromCharCode(this.buffer[offset + i]);
        }

        if (!filename) return null;

        // Read size (octal string at offset 124, 12 bytes)
        let sizeStr = '';
        for (let i = 124; i < 136; i++) {
            const c = this.buffer[offset + i];
            if (c === 0 || c === 32) break;
            sizeStr += String.fromCharCode(c);
        }

        const size = parseInt(sizeStr.trim(), 8) || 0;

        // Read type flag (offset 156)
        const typeflag = this.buffer[offset + 156];

        return { filename, size, typeflag, offset };
    }

    processEntry(header) {
        const { filename, size, typeflag, offset } = header;

        // Detect SCC report using rules
        if (!this.isSCCReport && SCC_RULES.detection.isSCCReport(filename)) {
            this.isSCCReport = true;
            this.sccReportName = filename.split('/')[0];
            debugLog('[TAR Parser] Detected SCC report:', this.sccReportName);
        }

        // Process SCC rules if this is an SCC report
        if (this.isSCCReport && size > 0) {
            this.processSCCRules(filename, size, offset);
        }

        // Track directories
        if (filename.includes('/')) {
            const parts = filename.split('/');
            let path = '';
            for (let i = 0; i < parts.length - 1; i++) {
                path += parts[i] + '/';
                this.directories.add(path);
            }
        }

        // Track file types
        const ext = filename.includes('.') ? filename.split('.').pop().toLowerCase() : 'none';
        this.fileTypes[ext] = (this.fileTypes[ext] || 0) + 1;

        // Store file entry
        this.files.push({
            name: filename,
            size: size,
            type: typeflag === 53 ? 'dir' : 'file'
        });
    }

    // Process all SCC rules against current file
    processSCCRules(filename, size, offset) {
        // Skip PaxHeaders - they are TAR extended headers, not actual file content
        if (filename.includes('/PaxHeaders/') || filename.endsWith('/PaxHeaders')) {
            return;
        }
        
        // Iterate through all rules (except detection)
        for (const [ruleName, rule] of Object.entries(SCC_RULES)) {
            if (ruleName === 'detection' || !rule.filePattern) continue;
            
            // Check if filename matches rule pattern
            if (rule.filePattern.test(filename)) {
                debugLog(`[TAR Parser] Matched rule '${ruleName}' for file:`, filename);
                
                // Extract file content
                const dataOffset = offset + 512;
                if (this.buffer.length >= dataOffset + size) {
                    const content = this.extractFileContent(dataOffset, size);
                    if (content) {
                        // For rules that process multiple files (like liveMigration, kernelReboots, and oomKiller)
                        // we need to accumulate results instead of replacing
                        const isMultiFileRule = ruleName === 'liveMigration' || ruleName === 'kernelReboots' || ruleName === 'oomKiller';
                        
                        // NOTE: We don't store file content in extractedFiles anymore to save memory
                        // Content is parsed immediately and discarded
                        
                        // Parse using rule's parse function (pass filename for format detection)
                        try {
                            const result = rule.parse(content, filename);
                            
                            if (isMultiFileRule) {
                                // Accumulate results for multi-file rules
                                if (!this.analysisResults[ruleName]) {
                                    this.analysisResults[ruleName] = {
                                        count: 0,
                                        events: []
                                    };
                                }
                                
                                // For kernelReboots, deduplicate events based on timestamp and type
                                if (ruleName === 'kernelReboots') {
                                    let newEventsAdded = 0;
                                    result.events.forEach(newEvent => {
                                        // Check if this event already exists (same timestamp and type)
                                        const isDuplicate = this.analysisResults[ruleName].events.some(existingEvent => {
                                            return existingEvent.timestamp === newEvent.timestamp && 
                                                   existingEvent.type === newEvent.type &&
                                                   existingEvent.kernelVersion === newEvent.kernelVersion;
                                        });
                                        
                                        if (!isDuplicate) {
                                            this.analysisResults[ruleName].events.push({
                                                ...newEvent,
                                                sourceFile: filename
                                            });
                                            newEventsAdded++;
                                        }
                                    });
                                    this.analysisResults[ruleName].count = this.analysisResults[ruleName].events.length;
                                    debugLog(`[TAR Parser] Rule '${ruleName}' accumulated ${newEventsAdded} new events (${result.count - newEventsAdded} duplicates skipped, total: ${this.analysisResults[ruleName].count})`);
                                } else {
                                    // Merge results without deduplication for other multi-file rules
                                    this.analysisResults[ruleName].count += result.count;
                                    this.analysisResults[ruleName].events.push(...result.events.map(e => ({
                                        ...e,
                                        sourceFile: filename
                                    })));
                                    
                                    debugLog(`[TAR Parser] Rule '${ruleName}' accumulated ${result.count} new events (total: ${this.analysisResults[ruleName].count})`);
                                }
                            } else {
                                // Single file rule - for fencingConfig and pacemakerResources, merge/keep best result
                                if (ruleName === 'fencingConfig') {
                                    // Keep the result with the most information
                                    const existing = this.analysisResults[ruleName];
                                    
                                    // If no existing result, use this one
                                    if (!existing) {
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (first):`, result);
                                    } else {
                                        // Merge: prefer explicit stonithEnabled over null, accumulate devices
                                        const merged = {
                                            found: existing.found || result.found,
                                            stonithEnabled: result.stonithEnabled !== null ? result.stonithEnabled : existing.stonithEnabled,
                                            stonithSourceFile: result.stonithEnabled !== null ? result.stonithSourceFile : existing.stonithSourceFile,
                                            stonithSourcePattern: result.stonithEnabled !== null ? result.stonithSourcePattern : existing.stonithSourcePattern,
                                            fencingDevices: [...existing.fencingDevices],
                                            count: existing.count
                                        };
                                        
                                        // Add new devices that don't already exist
                                        result.fencingDevices.forEach(newDevice => {
                                            if (!merged.fencingDevices.find(d => d.name === newDevice.name)) {
                                                merged.fencingDevices.push(newDevice);
                                                merged.count++;
                                            }
                                        });
                                        
                                        this.analysisResults[ruleName] = merged;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged with existing (${merged.count} devices, stonith: ${merged.stonithEnabled})`);
                                    }
                                } else if (ruleName === 'pacemakerResources') {
                                    // Keep the result with resources, or merge resources
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.found) {
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (first):`, result);
                                    } else if (result.found) {
                                        // Merge resources and enrich with node information
                                        let newResourcesAdded = 0;
                                        let enrichedResources = 0;
                                        
                                        result.resources.forEach(newRes => {
                                            const existingRes = existing.resources.find(r => r.name === newRes.name);
                                            if (existingRes) {
                                                // Enrich existing resource with new data (especially node info from crm_mon)
                                                let wasEnriched = false;
                                                if (newRes.node && !existingRes.node) {
                                                    existingRes.node = newRes.node;
                                                    existingRes.status = newRes.status;
                                                    wasEnriched = true;
                                                }
                                                if (newRes.status && !existingRes.status) {
                                                    existingRes.status = newRes.status;
                                                    wasEnriched = true;
                                                }
                                                if (wasEnriched) {
                                                    enrichedResources++;
                                                    debugLog(`[TAR Parser] Enriched resource '${newRes.name}' with node/status info`);
                                                }
                                            } else {
                                                // Add new resource only if it's truly new
                                                existing.resources.push(newRes);
                                                newResourcesAdded++;
                                                debugLog(`[TAR Parser] Added new resource '${newRes.name}'`);
                                            }
                                        });
                                        existing.count = existing.resources.length;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged: ${newResourcesAdded} new resources added, ${enrichedResources} enriched, ${result.resources.length - newResourcesAdded - enrichedResources} duplicates skipped (${existing.count} total)`);
                                    }
                                } else if (ruleName === 'clusterNodes') {
                                    // Merge and deduplicate cluster nodes from multiple files
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.nodes || existing.nodes.length === 0) {
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (first): ${result.nodes.length} nodes`);
                                    } else {
                                        // Merge node lists and deduplicate
                                        const nodeSet = new Set([...existing.nodes, ...result.nodes]);
                                        // Merge node-to-IP mappings
                                        const mergedMap = {...existing.nodeToIpMap, ...result.nodeToIpMap};
                                        this.analysisResults[ruleName] = {
                                            nodes: Array.from(nodeSet).sort(),
                                            nodeToIpMap: mergedMap
                                        };
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged (${this.analysisResults[ruleName].nodes.length} unique nodes, ${Object.keys(mergedMap).length} mappings)`);
                                    }
                                } else {
                                    // Other single file rules - replace result
                                    this.analysisResults[ruleName] = result;
                                    debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully:`, result);
                                }
                            }
                        } catch (e) {
                            console.error(`[TAR Parser] Rule '${ruleName}' parse failed:`, e);
                        }
                    }
                }
            }
        }
    }

    extractFileContent(offset, size) {
        const contentBytes = this.buffer.slice(offset, offset + size);
        try {
            return new TextDecoder('utf-8').decode(contentBytes);
        } catch (e) {
            console.error('[TAR Parser] Failed to decode file content:', e);
            return null;
        }
    }

    getAnalysis() {
        // Full analysis mode (always enabled)
        // Get raw cluster nodes (may be IPs or hostnames)
        const clusterNodesData = this.analysisResults.clusterNodes || { nodes: [], nodeToIpMap: {} };
        let clusterNodes = clusterNodesData.nodes || [];
        const nodeToIpMap = clusterNodesData.nodeToIpMap || {};
        const hostsData = this.analysisResults.hostsFile || null;
        const liveMigrationData = this.analysisResults.liveMigration || null;
        const kernelRebootsData = this.analysisResults.kernelReboots || null;
        const oomKillerData = this.analysisResults.oomKiller || null;
        const corosyncData = this.analysisResults.corosyncConfig || null;
        const rpmPackagesData = this.analysisResults.rpmPackages || null;
        const pacemakerResourcesData = this.analysisResults.pacemakerResources || null;
        const fencingConfigData = this.analysisResults.fencingConfig || null;
        const clusterEventsData = this.analysisResults.clusterEvents || null;
        
        // Antivirus detection results
        const falconSensorData = this.analysisResults.falconSensor || { found: false };
        const falconConfigData = this.analysisResults.falconSensorConfig || { found: false };
        const msDefenderData = this.analysisResults.msDefender || { found: false };
        const msDefenderConfigData = this.analysisResults.msDefenderConfig || { found: false };
        const illumioData = this.analysisResults.illumio || { found: false };
        const trendMicroData = this.analysisResults.trendMicro || { found: false };
        
        // Combine antivirus results
        const antivirusResults = {
            falconSensor: {
                detected: falconSensorData.found,
                version: falconSensorData.version,
                runningProcess: falconSensorData.runningProcess,
                sapExceptions: falconConfigData.hasExclusions || false,
                exclusionPaths: falconConfigData.exclusions || [],
                message: falconSensorData.message
            },
            msDefender: {
                detected: msDefenderData.found,
                version: msDefenderData.version,
                runningProcess: msDefenderData.runningProcess,
                sapExceptions: msDefenderConfigData.hasExclusions || false,
                exclusionPaths: msDefenderConfigData.exclusions || [],
                message: msDefenderData.message
            },
            illumio: {
                detected: illumioData.found,
                message: illumioData.message
            },
            trendMicro: {
                detected: trendMicroData.found,
                message: trendMicroData.message
            },
            // Overall status
            anyDetected: falconSensorData.found || msDefenderData.found || illumioData.found || trendMicroData.found,
            allHaveExceptions: (falconSensorData.found ? (falconConfigData.hasExclusions || false) : true) && 
                              (msDefenderData.found ? (msDefenderConfigData.hasExclusions || false) : true)
        };
        
        debugLog('[TAR Parser] getAnalysis() called');
        debugLog('[TAR Parser] analysisResults:', this.analysisResults);
        debugLog('[TAR Parser] Raw cluster nodes:', clusterNodes);
        debugLog('[TAR Parser] Node-to-IP mappings:', nodeToIpMap);
        
        // Resolve cluster nodes using multiple strategies:
        // 1. If we have nodeToIpMap (from corosync.conf), use it to resolve IPs back to hostnames
        // 2. Then use hosts file to resolve any remaining IPs to hostnames
        // 3. Remove duplicates (IPs that have corresponding hostnames in the same list)
        if (clusterNodes.length > 0) {
            const resolvedNodes = [];
            const ipToHostnameMap = {}; // Reverse mapping: IP -> hostname
            
            // Build reverse map from nodeToIpMap
            for (const [hostname, ip] of Object.entries(nodeToIpMap)) {
                ipToHostnameMap[ip] = hostname;
            }
            
            clusterNodes.forEach(node => {
                // Check if it's an IP address
                if (node.match(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) {
                    // First, check if we have a hostname mapping from corosync.conf
                    if (ipToHostnameMap[node]) {
                        const hostname = ipToHostnameMap[node];
                        debugLog(`[TAR Parser] Resolved IP ${node} to hostname ${hostname} (from corosync nodeToIpMap)`);
                        resolvedNodes.push(hostname);
                    }
                    // If not, try to resolve using hosts file
                    else if (hostsData) {
                        const hostEntry = hostsData.entries.find(entry => entry.ip === node);
                        if (hostEntry && hostEntry.hostnames.length > 0) {
                            // Use the first hostname
                            const hostname = hostEntry.hostnames[0];
                            debugLog(`[TAR Parser] Resolved IP ${node} to hostname ${hostname} (from hosts file)`);
                            resolvedNodes.push(hostname);
                        } else {
                            // Keep the IP if we can't resolve it
                            debugLog(`[TAR Parser] Could not resolve IP ${node}, keeping as-is`);
                            resolvedNodes.push(node);
                        }
                    } else {
                        resolvedNodes.push(node);
                    }
                } else {
                    // It's a hostname - check if we have an IP mapping for validation
                    if (nodeToIpMap[node]) {
                        debugLog(`[TAR Parser] Hostname ${node} maps to IP ${nodeToIpMap[node]} (from corosync.conf)`);
                    }
                    resolvedNodes.push(node);
                }
            });
            
            // Deduplicate resolved nodes (in case same hostname was added multiple times)
            clusterNodes = Array.from(new Set(resolvedNodes)).sort();
            debugLog('[TAR Parser] Resolved cluster nodes (deduplicated):', clusterNodes);
        }
        
        let nodesInHosts = [];
        let nodesMissingFromHosts = [];
        
        if (hostsData && clusterNodes.length > 0) {
            const hostsSet = new Set(hostsData.allHostnames);
            const hostsIpSet = new Set(hostsData.entries.map(e => e.ip));
            
            clusterNodes.forEach(node => {
                let foundInHosts = false;
                
                // Check if the node (hostname) is directly in hosts file
                if (hostsSet.has(node)) {
                    foundInHosts = true;
                    debugLog(`[TAR Parser] Node ${node} found directly in hosts file`);
                }
                // Check if we have an IP mapping for this hostname and that IP is in hosts file
                else if (nodeToIpMap[node] && hostsIpSet.has(nodeToIpMap[node])) {
                    foundInHosts = true;
                    debugLog(`[TAR Parser] Node ${node} found in hosts file via IP ${nodeToIpMap[node]}`);
                }
                
                if (foundInHosts) {
                    nodesInHosts.push(node);
                } else {
                    nodesMissingFromHosts.push(node);
                }
            });
            
            debugLog('[TAR Parser] Nodes found in hosts file:', nodesInHosts);
            debugLog('[TAR Parser] Nodes missing from hosts file:', nodesMissingFromHosts);
        }
        
        return {
            fileCount: this.files.length,
            directories: Array.from(this.directories).sort(),
            fileTypes: this.fileTypes,
            files: this.files.slice(0, 50), // Return first 50 files
            totalParsed: this.totalParsed,
            // SCC report information
            isSCCReport: this.isSCCReport,
            sccReportName: this.sccReportName,
            // Rule-based analysis results
            azureVMProperties: this.analysisResults.azureVMProperties || null,
            osRelease: this.analysisResults.osRelease || this.analysisResults.sysinfo || this.analysisResults.basicEnvironment || null,
            clusterNodes: clusterNodes,
            nodeToIpMap: nodeToIpMap,
            hostsFile: hostsData,
            liveMigration: liveMigrationData,
            kernelReboots: kernelRebootsData,
            oomKiller: oomKillerData,
            corosyncConfig: corosyncData,
            corosyncStatus: this.analysisResults.corosyncStatus || null,
            rpmPackages: rpmPackagesData,
            pacemakerResources: pacemakerResourcesData,
            fencingConfig: fencingConfigData,
            clusterEvents: clusterEventsData,
            antivirus: antivirusResults,
            kernelTuning: this.analysisResults.kernelTuning || null,
            fstab: this.analysisResults.fstab || null,
            // Cross-validation results
            nodesInHosts: nodesInHosts,
            nodesMissingFromHosts: nodesMissingFromHosts
        };
    }

    finish() {
        // Parse any remaining complete entries
        this.parseAvailableEntries();
        return this.getAnalysis();
    }
}

// Handle messages from main thread
self.onmessage = async function(e) {
    // Handle debug mode setting
    if (e.data.command === 'set_debug') {
        DEBUG_MODE = e.data.enabled;
        debugLog(`[Worker] Debug mode ${DEBUG_MODE ? 'enabled' : 'disabled'}`);
        return;
    }
    
    // Handle TAR-only analysis (for already decompressed data like from gzip)
    if (e.data.cmd === 'analyze_tar') {
        try {
            const { tarData } = e.data;
            debugLog(`[Worker] Starting TAR analysis: ${tarData.byteLength} bytes`);
            
            // Initialize TAR parser
            const tarParser = new IncrementalTARParser();
            
            // Process the TAR data
            const tarBytes = new Uint8Array(tarData);
            tarParser.addChunk(tarBytes);
            
            // Get analysis results
            const analysis = tarParser.getAnalysis();
            
            debugLog(`[Worker] TAR analysis complete: ${analysis.fileCount} files`);
            
            try {
                self.postMessage({
                    success: true,
                    analysis: analysis,
                    progress: 100
                });
                debugLog('[Worker] Success message sent to main thread');
            } catch (err) {
                console.error('[Worker] Error sending message:', err);
                self.postMessage({ error: 'Failed to send results: ' + err.message });
            }
            
            return;
        } catch (err) {
            console.error('[Worker] TAR analysis error:', err);
            self.postMessage({ error: 'TAR analysis failed: ' + err.message });
            return;
        }
    }
    
    // Handle streaming XZ decompression (existing code)
    if (e.data.cmd === 'decompress_streaming') {
        if (!moduleReady || !Module || !Module.HEAPU8) {
            self.postMessage({ error: 'WASM module not properly initialized' });
            return;
        }

        try {
            const { compressedData, chunkSize } = e.data;
            const inputSize = compressedData.byteLength;
            const effectiveChunkSize = chunkSize || (256 * 1024); // 256KB default

            debugLog(`[XZ Streaming Worker] Starting streaming decompression: ${inputSize} bytes input`);

            // Initialize streaming decoder
            const errBufSize = 256;
            const errBuf = Module._malloc(errBufSize);
            const handle = Module._xz_stream_init(errBuf, errBufSize);

            if (!handle) {
                const errMsg = Module.UTF8ToString(errBuf);
                Module._free(errBuf);
                throw new Error(`Failed to initialize stream: ${errMsg}`);
            }

            debugLog('[XZ Streaming Worker] Stream initialized');

            // Initialize TAR parser
            const tarParser = new IncrementalTARParser();

            // Process input in chunks
            let inputOffset = 0;
            let totalDecompressed = 0;
            let chunkCount = 0;
            let streamComplete = false;
            let lastStatus = 0;

            while (inputOffset < inputSize) {
                // Get next chunk of input
                const remainingInput = inputSize - inputOffset;
                const currentChunkSize = Math.min(effectiveChunkSize, remainingInput);
                const isLastChunk = (inputOffset + currentChunkSize >= inputSize);

                // Copy input chunk to WASM memory
                const inputPtr = Module._malloc(currentChunkSize);
                Module.HEAPU8.set(
                    new Uint8Array(compressedData, inputOffset, currentChunkSize),
                    inputPtr
                );

                // Allocate status and output length variables
                const outLenPtr = Module._malloc(4);
                const statusPtr = Module._malloc(4);

                // Process chunk
                const outputPtr = Module._xz_stream_process(
                    handle,
                    inputPtr,
                    currentChunkSize,
                    outLenPtr,
                    statusPtr
                );

                const outLen = Module.getValue(outLenPtr, 'i32');
                const status = Module.getValue(statusPtr, 'i32');
                lastStatus = status;

                debugLog(`[XZ Streaming Worker] Chunk ${chunkCount}: input=${currentChunkSize}, output=${outLen}, status=${status}, isLast=${isLastChunk}`);

                // Free input and status buffers
                Module._free(inputPtr);
                Module._free(outLenPtr);
                Module._free(statusPtr);

                // Check for output
                if (outputPtr && outLen > 0) {
                    // Copy output data to a new buffer
                    const outputData = new Uint8Array(outLen);
                    outputData.set(Module.HEAPU8.subarray(outputPtr, outputPtr + outLen));
                    
                    // Free WASM memory immediately
                    Module._free(outputPtr);

                    // Feed to TAR parser
                    tarParser.addChunk(outputData);
                    totalDecompressed += outLen;

                    // Send progress update
                    const progress = Math.floor((inputOffset / inputSize) * 100);
                    self.postMessage({
                        progress,
                        decompressed: totalDecompressed,
                        analysis: tarParser.getAnalysis()
                    });
                    
                    // Hint to GC that outputData can be collected
                    // (it's been processed by tarParser.addChunk)
                } else if (outputPtr) {
                    // Free even if no data
                    Module._free(outputPtr);
                }

                // Check status
                if (status < 0) {
                    const errMsg = Module.UTF8ToString(Module._xz_stream_error(handle));
                    Module._xz_stream_free(handle);
                    Module._free(errBuf);
                    throw new Error(`Decompression error: ${errMsg} (status=${status})`);
                }

                if (status === 1) {
                    // Stream finished
                    streamComplete = true;
                    debugLog('[XZ Streaming Worker] Stream finished');
                    break;
                }

                // Move to next chunk
                inputOffset += currentChunkSize;
                chunkCount++;

                // Yield to prevent blocking and allow GC
                if (chunkCount % 10 === 0) {
                    await new Promise(resolve => setTimeout(resolve, 0));
                }
                
                // More aggressive GC hint every 50 chunks (helps browser reclaim memory)
                if (chunkCount % 50 === 0) {
                    await new Promise(resolve => setTimeout(resolve, 10));
                }
            }

            // Cleanup
            Module._xz_stream_free(handle);
            Module._free(errBuf);

            // Final analysis
            const finalAnalysis = tarParser.finish();

            // Check if TAR archive is complete (has end marker)
            // An incomplete TAR (from truncated XZ) won't have the end marker
            if (!tarParser.foundEndMarker && finalAnalysis.fileCount > 0) {
                debugLog('[XZ Streaming Worker] WARNING: TAR archive missing end marker - file may be truncated');
                
                self.postMessage({
                    success: true,
                    partialSuccess: true,
                    totalDecompressed,
                    analysis: {
                        ...finalAnalysis,
                        corruptionDetected: true,
                        corruptionMessage: 'TAR archive is incomplete - file appears to be truncated or corrupted',
                        xzBlocksProcessed: chunkCount,
                        bytesProcessed: inputOffset,
                        totalInputBytes: inputSize,
                        percentProcessed: Math.floor((inputOffset / inputSize) * 100)
                    }
                });
                return;
            }

            debugLog(`[XZ Streaming Worker] Complete: ${totalDecompressed} bytes decompressed, ${finalAnalysis.fileCount} files`);

            self.postMessage({
                success: true,
                totalDecompressed,
                analysis: finalAnalysis
            });

        } catch (error) {
            console.error('[XZ Streaming Worker] Error:', error);
            
            // Check if we got partial data before the error
            const partialAnalysis = tarParser ? tarParser.getAnalysis() : null;
            
            if (partialAnalysis && partialAnalysis.fileCount > 0) {
                // We have partial data - report it along with the error
                debugLog(`[XZ Streaming Worker] Partial success: ${totalDecompressed} bytes decompressed, ${partialAnalysis.fileCount} files before error`);
                
                self.postMessage({
                    success: true,
                    partialSuccess: true,
                    totalDecompressed,
                    analysis: {
                        ...partialAnalysis,
                        corruptionDetected: true,
                        corruptionMessage: error.message || 'File appears to be corrupted or truncated',
                        xzBlocksProcessed: chunkCount,
                        bytesProcessed: inputOffset,
                        totalInputBytes: inputSize
                    }
                });
            } else {
                // Complete failure
                self.postMessage({
                    error: error.message || 'Unknown streaming decompression error'
                });
            }
        }
    }
};

debugLog('[XZ Streaming Worker] Worker initialized, waiting for module...');
