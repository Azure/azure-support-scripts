/**
 * Services Parsers for RCA Tool
 * 
 * Contains service and security software detection parsers:
 * - sshService: SSH service issues detection
 * - dlmService: Distributed Lock Manager service detection
 * - azureSiteRecovery: Azure Site Recovery (involflt) detection
 * - guardicoreAgent: Guardicore security agent detection
 * - illumio: Illumio security software detection
 * - trendMicro: Trend Micro Deep Security detection
 * - falconSensor: CrowdStrike Falcon Sensor detection
 * - msDefender: Microsoft Defender detection
 * 
 * These parsers are exported for use in the main worker file.
 * They will be manually assigned to SCC_RULES after SCC_RULES is defined.
 */

// Export service-related parsers
const sshServiceParser = {
    // Target file path patterns - messages, syslog, journalctl, console logs
    filePattern: /\/(messages|localmessages|syslog|journalctl[^\/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$/,
    
    // Parse function receives file content as string
    // Detects SSH service failures and permission issues:
    // - "Failed to start OpenSSH server daemon."
    // - "/var/empty/sshd must be owned by root and not group or world-writable."
    // Returns array of detected SSH service issues with timestamps
    parse: function(content, filename) {
        const lines = content.split('\n');
        const sshIssues = [];
        
        debugLog('[sshService parser] Analyzing', lines.length, 'lines for SSH service issues');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            let issueType = null;
            let message = null;
            
            // Pattern 1: "Failed to start OpenSSH server daemon."
            if (line.match(/Failed to start OpenSSH server daemon/i)) {
                issueType = 'ssh_start_failed';
                message = 'Failed to start OpenSSH server daemon';
            }
            
            // Pattern 2: "/var/empty/sshd must be owned by root and not group or world-writable."
            if (line.match(/\/var\/empty\/sshd must be owned by root and not group or world-writable/i)) {
                issueType = 'ssh_permission_error';
                message = '/var/empty/sshd must be owned by root and not group or world-writable';
            }
            
            if (issueType) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                
                sshIssues.push({
                    timestamp: timestamp || 'Date not detected',
                    lineNumber: i + 1,
                    issueType: issueType,
                    message: message,
                    rawLine: line.trim(),
                    sourceFile: filename
                });
                
                debugLog('[sshService parser] ✓ Detected SSH issue at line', i + 1, ':', timestamp, 'type:', issueType);
            }
        }
        
        debugLog('[sshService parser] Found', sshIssues.length, 'SSH service issues');
        
        return {
            found: sshIssues.length > 0,
            count: sshIssues.length,
            events: sshIssues
        };
    }
};

const dlmServiceParser = {
    filePattern: /sos_commands\/systemd\/systemctl_list-unit-files$/,
    
    parse: function(content, filename) {
        debugLog('[dlmService parser] Analyzing for DLM service in:', filename);
        
        const result = SCC_RULES.detectSystemdService(
            content,
            filename,
            'dlm',
            'error',
            'DLM (Distributed Lock Manager) service is enabled in systemd. This can cause issues with Pacemaker clusters, and should be managed as a cluster resource as defined in the documentation below.'
        );
        
        // Add documentation URL for DLM service
        if (result.found) {
            result.documentationUrl = 'https://access.redhat.com/solutions/878023';
        }
        
        return result;
    }
};

const azureSiteRecoveryParser = {
    filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
    
    parse: function(content, filename) {
        debugLog('[azureSiteRecovery parser] Analyzing for Azure Site Recovery in:', filename);
        
        return SCC_RULES.detectSystemdService(
            content,
            filename,
            'involflt_start',
            'info',
            'Azure Site Recovery (ASR) is enabled on this system. The involflt driver is used for replication.'
        );
    }
};

const guardicoreAgentParser = {
    filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
    
    parse: function(content, filename) {
        debugLog('[guardicoreAgent parser] Analyzing for Guardicore agent in:', filename);
        
        return SCC_RULES.detectSystemdService(
            content,
            filename,
            'gc-agent',
            'warning',
            'Guardicore agent is enabled on this system. This security software provides micro-segmentation and may require exclusions for SAP workloads.'
        );
    }
};

const illumioParser = {
    filePattern: /sos_commands\/systemd\/systemctl_list-units_--all$/,
    
    parse: function(content) {
        debugLog('[illumio parser] Analyzing for Illumio');
        
        // Case-insensitive search for Illumio
        const result = SCC_RULES.grepLines(content, /illumio/i, { firstMatchOnly: true });
        
        if (!result.found) {
            debugLog('[illumio parser] Illumio not detected');
            return { found: false };
        }
        
        debugLog('[illumio parser] Found Illumio:', result.line);
        
        return {
            found: true,
            message: 'Illumio detected. SAP exclusions should be verified in Illumio policy configuration.'
        };
    }
};

const trendMicroParser = {
    filePattern: /sos_commands\/systemd\/systemctl_list-units_--all$/,
    
    parse: function(content) {
        debugLog('[trendMicro parser] Analyzing for Trend Micro');
        
        // Search for lines containing both ds_agent.service and Trend Micro
        const result = SCC_RULES.grepLines(content, /ds_agent\.service.*Trend Micro|Trend Micro.*ds_agent\.service/i, { firstMatchOnly: true });
        
        if (!result.found) {
            debugLog('[trendMicro parser] Trend Micro not detected');
            return { found: false };
        }
        
        debugLog('[trendMicro parser] Found Trend Micro Deep Security:', result.line);
        
        return {
            found: true,
            message: 'Trend Micro Deep Security detected. SAP exclusions should be verified in Deep Security Manager.'
        };
    }
};

const falconSensorParser = {
    // Target file patterns - RPM list and process list
    filePattern: /\/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$/,
    
    parse: function(content) {
        return SCC_RULES.detectSecuritySoftware(
            content,
            'falconSensor parser',
            'falcon-sensor',
            ['falcon-sensor', '/opt/CrowdStrike'],
            'Falcon Sensor',
            'Falcon Sensor detected. SAP exclusions should be verified manually in /opt/CrowdStrike configuration.'
        );
    }
};

const falconSensorConfigParser = {
    filePattern: /\/(falconctl|CrowdStrike.*config|falcon.*conf)$/i,
    
    parse: function(content) {
        return SCC_RULES.checkSAPExclusions(
            content,
            'falconSensorConfig parser',
            ['exclude', 'exception']
        );
    }
};

const msDefenderParser = {
    filePattern: /\/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$/,
    
    parse: function(content) {
        return SCC_RULES.detectSecuritySoftware(
            content,
            'msDefender parser',
            'mdatp',
            ['mdatp', 'wdavdaemon', '/opt/microsoft/mdatp'],
            'MS Defender',
            'Microsoft Defender detected. SAP exclusions should be verified with: mdatp exclusion list'
        );
    }
};

const msDefenderConfigParser = {
    filePattern: /\/(mdatp.*|defender.*config)$/i,
    
    parse: function(content) {
        return SCC_RULES.checkSAPExclusions(
            content,
            'msDefenderConfig parser',
            ['exclusion', 'exclude']
        );
    }
};

/**
 * Parser: involfltVersion
 * Extracts Microsoft InMage/ASR filter driver version from modules.txt
 * Analyzes Azure Site Recovery involflt kernel module version and load status
 */
const involfltVersionParser = {
    filePattern: /modules\.txt$/,
    
    parse: function(content, filename) {
        debugLog('[involfltVersion parser] Analyzing involflt version in:', filename);
        
        let version = null;
        let buildDate = null;
        let filename_path = null;
        let description = null;
        let loaded = false;
        
        // Extract modinfo involflt section from modules.txt
        const lines = content.split('\n');
        const modinfoLines = [];
        let inSection = false;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Check if involflt is in the loaded modules list (format: "involflt              897024  14")
            if (!loaded && line.match(/^involflt\s+\d+/)) {
                loaded = true;
                debugLog('[involfltVersion parser] involflt is loaded');
            }
            
            // Start collecting after finding the modinfo involflt command marker
            if (line.includes('# /sbin/modinfo involflt')) {
                inSection = true;
                debugLog('[involfltVersion parser] Found modinfo involflt section at line', i + 1);
                continue; // Skip the marker line itself
            }
            
            // Stop at next Command section marker
            if (inSection && line.trim().startsWith('#==[ Command ]')) {
                debugLog('[involfltVersion parser] Found end of modinfo section at line', i + 1);
                break;
            }
            
            // Collect lines while in section
            if (inSection) {
                modinfoLines.push(line);
            }
        }
        
        // Parse the extracted modinfo section
        if (modinfoLines.length > 0) {
            debugLog('[involfltVersion parser] Extracted', modinfoLines.length, 'lines from modinfo section');
            
            for (const line of modinfoLines) {
                // Extract version (format: "version:        Oct 23 2024 [ 02:41:25 ]")
                const versionMatch = line.match(/^version:\s*(.+)$/);
                if (versionMatch) {
                    version = versionMatch[1].trim();
                    
                    // Try to extract just the date part
                    const dateMatch = version.match(/([A-Za-z]+\s+\d+\s+\d{4})/);
                    if (dateMatch) {
                        buildDate = dateMatch[1];
                    }
                    
                    debugLog('[involfltVersion parser] Version:', version);
                }
                
                // Extract filename path
                const filenameMatch = line.match(/^filename:\s*(.+)$/);
                if (filenameMatch) {
                    filename_path = filenameMatch[1].trim();
                    debugLog('[involfltVersion parser] Filename:', filename_path);
                }
                
                // Extract description
                const descMatch = line.match(/^description:\s*(.+)$/);
                if (descMatch) {
                    description = descMatch[1].trim();
                    debugLog('[involfltVersion parser] Description:', description);
                }
            }
        }
        
        if (!version && !loaded) {
            debugLog('[involfltVersion parser] involflt not found');
            return { found: false };
        }
        
        return {
            found: true,
            loaded: loaded,
            version: version,
            buildDate: buildDate,
            filename: filename_path,
            description: description,
            source: 'modinfo'
        };
    }
};

/**
 * Parser: involfltKernelVersion
 * Extracts involflt runtime version from kernel messages
 * Detects Azure Site Recovery filter driver version from kernel logs
 */
const involfltKernelVersionParser = {
    filePattern: /messages.*\.txt$|boot\.txt$/,
    
    parse: function(content, filename) {
        debugLog('[involfltKernelVersion parser] Analyzing involflt kernel version in:', filename);
        debugLog('[involfltKernelVersion parser] Content length:', content.length);
        
        // Search for pattern: "involflt[involflt_init:XXXX (INFO)]: Version - X.X.X.X"
        // Make regex more flexible to handle variations
        const versionMatch = content.match(/involflt\[involflt_init[^\]]*\]:\s*Version\s*-\s*([\d.]+)/i);
        
        if (versionMatch) {
            const version = versionMatch[1].trim();
            debugLog('[involfltKernelVersion parser] Found kernel version:', version);
            
            return {
                found: true,
                version: version,
                source: 'kernel_log',
                detectionFile: filename
            };
        }
        
        debugLog('[involfltKernelVersion parser] No kernel version found in file');
        // Don't return {found: false} - return null so we don't overwrite a previous positive result
        return null;
    }
};

