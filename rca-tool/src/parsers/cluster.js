/**
 * Cluster Parsers for RCA Tool
 * 
 * Contains Pacemaker, Corosync, and fencing/STONITH analysis parsers:
 * - corosyncConfig: Corosync configuration validation
 * - pacemakerResources: Pacemaker resource detection
 * - corosyncStatus: Corosync runtime status
 * - clusterStatus: Overall cluster health/status
 * - fencingConfig: STONITH/fencing configuration
 * - clusterEvents: Resource migrations and fencing events
 * 
 * These parsers are exported for use in the main worker file.
 * They will be manually assigned to SCC_RULES after SCC_RULES is defined.
 */

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

// NOTE: pacemakerResources, corosyncStatus, clusterStatus, fencingConfig, and clusterEvents parsers
// are too large to extract at this time (over 1000 lines each).
// This file will be completed in the next phase of extraction.
// For now, they remain in the main worker file.

// Export only the extracted parsers
// More parsers will be added here as they are extracted
