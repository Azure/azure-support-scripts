// Streaming XZ decompression worker using liblzma
// Processes compressed data in chunks to keep memory usage low

console.log('[Worker] Loading version: 2025-12-23-nested-gzip');

// Global error handler to catch uncaught exceptions
self.onerror = function(message, source, lineno, colno, error) {
    console.error('[Worker] Uncaught error:', message);
    console.error('[Worker] Source:', source, 'Line:', lineno, 'Column:', colno);
    console.error('[Worker] Error object:', error);
    if (error && error.stack) {
        console.error('[Worker] Stack trace:', error.stack);
    }
    // Try to send error message to main thread
    try {
        self.postMessage({ 
            error: 'Worker uncaught error: ' + message + ' at ' + source + ':' + lineno 
        });
    } catch (e) {
        console.error('[Worker] Failed to send error message:', e);
    }
    return true; // Prevent default error handling
};

// Import utility functions (only in Web Worker context)
if (typeof importScripts === 'function') {
    // Import pako for gzip decompression of nested .gz files
    try {
        importScripts('https://cdn.jsdelivr.net/npm/pako@2.1.0/dist/pako.min.js');
        console.log('[Worker] pako library loaded for nested .gz decompression');
    } catch (e) {
        console.warn('[Worker] Failed to load pako library:', e);
        console.warn('[Worker] Nested .gz file decompression will not be available');
    }
    
    importScripts('utils.js');
    // Import external parser modules
    importScripts('parsers/packages.js');
    importScripts('parsers/unix.js');
    importScripts('parsers/services.js');
    importScripts('parsers/events.js');
    importScripts('parsers/azure.js');
    importScripts('parsers/cluster.js');
    importScripts('parsers/storage.js');
    console.log('[Worker] Running in Web Worker context');
    console.log('[Worker] Browser:', typeof navigator !== 'undefined' ? navigator.userAgent : 'unknown');
}

// Debug flag - will be set from main thread via message
// Debug configuration - set specific parsers to true to enable their debug logging
const DEBUG_CONFIG = {
    automation: false,
    azure: false,
    cluster: false,
    unix: false,
    events: false,
    packages: false,
    services: false,
    worker: false
};

// Debug logging wrapper - only logs if the specific debug flag is enabled
function debugLog(...args) {
    // Check if this is a parser-specific log by looking at the first argument
    const firstArg = args[0];
    if (typeof firstArg === 'string') {
        // Extract parser name from log message like "[parserName parser]"
        const parserMatch = firstArg.match(/\[(\w+)(?:\s+parser|\s+worker)?\]/);
        if (parserMatch) {
            const parserName = parserMatch[1].toLowerCase();
            if (DEBUG_CONFIG[parserName]) {
                console.log(...args);
            }
        } else if (DEBUG_CONFIG.worker) {
            // General worker logs
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
    // ========================================================================
    // UTILITY FUNCTIONS - Wrappers that call imported utilities with debugLog
    // ========================================================================
    
    grepLines: function(content, patterns, options = {}) {
        return RCA_UTILITIES.grepLines(content, patterns, options);
    },
    
    detectSystemdService: function(content, filename, serviceName, severity, message) {
        return RCA_UTILITIES.detectSystemdService(content, filename, serviceName, severity, message, debugLog);
    },
    
    checkSAPExclusions: function(content, parserName, exclusionKeywords = ['exclude', 'exclusion']) {
        return RCA_UTILITIES.checkSAPExclusions(content, parserName, exclusionKeywords, debugLog);
    },
    
    detectRPMPackage: function(content, packagePrefix, parserName = '') {
        return RCA_UTILITIES.detectRPMPackage(content, packagePrefix, parserName, debugLog);
    },
    
    detectProcess: function(content, processIndicators, parserName = '') {
        return RCA_UTILITIES.detectProcess(content, processIndicators, parserName, debugLog);
    },
    
    detectSecuritySoftware: function(content, parserName, packagePrefix, processIndicators, displayName, message) {
        return RCA_UTILITIES.detectSecuritySoftware(content, parserName, packagePrefix, processIndicators, displayName, message, debugLog);
    },
    
    extractSection: function(content, filename, sectionMarker, directFilePattern) {
        return RCA_UTILITIES.extractSection(content, filename, sectionMarker, directFilePattern, debugLog);
    },
    
    parseKeyValueFile: function(content, options = {}) {
        return RCA_UTILITIES.parseKeyValueFile(content, options, debugLog);
    },
    
    extractRawFile: function(content, filename) {
        return RCA_UTILITIES.extractRawFile(content, filename, debugLog);
    },
    
    extractTimestamp: function(line) {
        return RCA_UTILITIES.extractTimestamp(line);
    },
    
    stripAnsiCodes: function(text) {
        return RCA_UTILITIES.stripAnsiCodes(text);
    },
    
    deduplicateEvents: function(existingEvents, newEvents, comparisonFields, debugLog) {
        if (typeof RCA_UTILITIES !== 'undefined') {
            return RCA_UTILITIES.deduplicateEvents(existingEvents, newEvents, comparisonFields, debugLog);
        }
        
        // Inline fallback
        const addedEvents = [];
        let duplicateCount = 0;
        
        newEvents.forEach(newEvent => {
            const isDuplicate = existingEvents.some(existingEvent => {
                return comparisonFields.every(field => existingEvent[field] === newEvent[field]);
            });
            
            if (!isDuplicate) {
                addedEvents.push(newEvent);
            } else {
                duplicateCount++;
            }
        });
        
        return { addedEvents, duplicateCount };
    },
    
    compareVersion: function(actual, expected, operator) {
        return RCA_UTILITIES.compareVersion(actual, expected, operator);
    },
    
    deduplicateEvents: function(existingEvents, newEvents, comparisonFields) {
        return RCA_UTILITIES.deduplicateEvents(existingEvents, newEvents, comparisonFields, debugLog);
    },
    
    // ========================================================================
    // DETECTION RULES
    // ========================================================================
    
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
    
    // Cluster parsers are imported from parsers/cluster.js after SCC_RULES is defined

    // Rule: Detect automation tool usage (Ansible, Puppet, Chef, etc.)
    automation: {
        // Target file path patterns - messages, syslog, journalctl
        filePattern: /\/(messages|localmessages|syslog|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
        
        // Parse function receives file content as string
        // Detects automation tool usage:
        // - "ansible-command: " (Ansible command executions)
        // - "ansible-setup: " (Ansible setup/facts gathering)
        // - "puppet-agent: " (Puppet agent executions)
        // - "puppet apply" (Puppet apply commands)
        // - "puppet-run: " (Puppet run executions)
        // - "chef-client: " (Chef client executions)
        // - "chef-solo: " (Chef solo executions)
        // - "chef-apply: " (Chef apply executions)
        // Future: SaltStack, etc.
        // Returns array of detected automation events with timestamps and full command lines
        parse: function(content, filename) {
            const lines = content.split('\n');
            const automationEvents = [];
            
            debugLog('[automation parser] Analyzing', lines.length, 'lines for automation tool usage');
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                
                let toolType = null;
                let patternType = null;
                let command = null;
                
                // Pattern 1: Ansible command execution
                if (line.includes('ansible-command:')) {
                    toolType = 'ansible';
                    patternType = 'command';
                    // Extract everything after "ansible-command: "
                    const ansibleMatch = line.match(/ansible-command:\s*(.+)/);
                    if (ansibleMatch) {
                        command = ansibleMatch[1].trim();
                    }
                }
                
                // Pattern 2: Ansible setup/facts gathering
                if (line.includes('ansible-setup:')) {
                    toolType = 'ansible';
                    patternType = 'setup';
                    // Extract everything after "ansible-setup: "
                    const ansibleMatch = line.match(/ansible-setup:\s*(.+)/);
                    if (ansibleMatch) {
                        command = ansibleMatch[1].trim();
                    }
                }
                
                // Pattern 3: Puppet agent execution
                if (line.includes('puppet-agent:')) {
                    toolType = 'puppet';
                    patternType = 'agent';
                    // Extract everything after "puppet-agent: "
                    const puppetMatch = line.match(/puppet-agent:\s*(.+)/);
                    if (puppetMatch) {
                        command = puppetMatch[1].trim();
                    }
                }
                
                // Pattern 4: Puppet apply
                if (line.includes('puppet apply')) {
                    toolType = 'puppet';
                    patternType = 'apply';
                    // Extract the puppet apply command
                    const puppetMatch = line.match(/(puppet apply.+)/);
                    if (puppetMatch) {
                        command = puppetMatch[1].trim();
                    }
                }
                
                // Pattern 5: Puppet run
                if (line.includes('puppet-run:')) {
                    toolType = 'puppet';
                    patternType = 'run';
                    // Extract everything after "puppet-run: "
                    const puppetMatch = line.match(/puppet-run:\s*(.+)/);
                    if (puppetMatch) {
                        command = puppetMatch[1].trim();
                    }
                }
                
                // Pattern 6: Chef client execution (format: chef-client[PID]: message)
                // Capture important events and include next 5 lines for context
                if (line.includes('chef-client[')) {
                    const chefMatch = line.match(/chef-client\[\d+\]:\s*(.+)/);
                    if (chefMatch) {
                        const message = SCC_RULES.stripAnsiCodes(chefMatch[1].trim());
                        // Capture important events with context
                        if (message.includes('Starting Chef') || 
                            message.includes('Chef Infra Client finished') ||
                            message.includes('Chef Run complete') ||
                            message.includes('Chef Client finished') ||
                            message.includes('Synchronizing Cookbooks') ||
                            message.includes('Installing Cookbook Gems') ||
                            message.includes('Compiling Cookbooks') ||
                            message.includes('Converging') ||
                            message.includes('FATAL:') ||
                            message.includes('ERROR:')) {
                            toolType = 'chef';
                            patternType = 'client';
                            
                            // Capture the current line plus next 5 lines for context
                            const contextLines = [message];
                            for (let j = 1; j <= 5 && (i + j) < lines.length; j++) {
                                const nextLine = lines[i + j];
                                const nextMatch = nextLine.match(/chef-client\[\d+\]:\s*(.+)/);
                                if (nextMatch) {
                                    contextLines.push(SCC_RULES.stripAnsiCodes(nextMatch[1].trim()));
                                } else {
                                    break; // Stop if next line is not chef-client
                                }
                            }
                            command = contextLines.join(' | ');
                        }
                    }
                }
                
                // Pattern 7: Chef solo (format: chef-solo[PID]: message)
                if (line.includes('chef-solo[')) {
                    const chefMatch = line.match(/chef-solo\[\d+\]:\s*(.+)/);
                    if (chefMatch) {
                        const message = SCC_RULES.stripAnsiCodes(chefMatch[1].trim());
                        // Capture important events with context
                        if (message.includes('Starting Chef') || 
                            message.includes('Chef Solo finished') ||
                            message.includes('Chef Run complete') ||
                            message.includes('Synchronizing Cookbooks') ||
                            message.includes('Compiling Cookbooks') ||
                            message.includes('Converging') ||
                            message.includes('FATAL:') ||
                            message.includes('ERROR:')) {
                            toolType = 'chef';
                            patternType = 'solo';
                            
                            // Capture the current line plus next 5 lines for context
                            const contextLines = [message];
                            for (let j = 1; j <= 5 && (i + j) < lines.length; j++) {
                                const nextLine = lines[i + j];
                                const nextMatch = nextLine.match(/chef-solo\[\d+\]:\s*(.+)/);
                                if (nextMatch) {
                                    contextLines.push(SCC_RULES.stripAnsiCodes(nextMatch[1].trim()));
                                } else {
                                    break;
                                }
                            }
                            command = contextLines.join(' | ');
                        }
                    }
                }
                
                // Pattern 8: Chef apply (format: chef-apply[PID]: message)
                if (line.includes('chef-apply[')) {
                    const chefMatch = line.match(/chef-apply\[\d+\]:\s*(.+)/);
                    if (chefMatch) {
                        const message = SCC_RULES.stripAnsiCodes(chefMatch[1].trim());
                        // Capture important events with context
                        if (message.includes('Starting Chef') || 
                            message.includes('Chef Apply finished') ||
                            message.includes('Chef Run complete') ||
                            message.includes('Compiling Cookbooks') ||
                            message.includes('Converging') ||
                            message.includes('FATAL:') ||
                            message.includes('ERROR:')) {
                            toolType = 'chef';
                            patternType = 'apply';
                            
                            // Capture the current line plus next 5 lines for context
                            const contextLines = [message];
                            for (let j = 1; j <= 5 && (i + j) < lines.length; j++) {
                                const nextLine = lines[i + j];
                                const nextMatch = nextLine.match(/chef-apply\[\d+\]:\s*(.+)/);
                                if (nextMatch) {
                                    contextLines.push(SCC_RULES.stripAnsiCodes(nextMatch[1].trim()));
                                } else {
                                    break;
                                }
                            }
                            command = contextLines.join(' | ');
                        }
                    }
                }
                
                // Future patterns can be added here:
                // - SaltStack: "salt-minion"
                
                if (toolType) {
                    const timestamp = SCC_RULES.extractTimestamp(line);
                    
                    automationEvents.push({
                        timestamp: timestamp || 'Date not detected',
                        lineNumber: i + 1,
                        toolType: toolType,
                        patternType: patternType,
                        command: command,
                        rawLine: line.trim(),
                        sourceFile: filename
                    });
                    
                    debugLog('[automation parser] ✓ Detected', toolType, 'at line', i + 1, ':', timestamp);
                }
            }
            
            debugLog('[automation parser] Found', automationEvents.length, 'automation events');
            
            return {
                found: automationEvents.length > 0,
                count: automationEvents.length,
                events: automationEvents
            };
        }
    },
    
    // Rule: Validate distribution packages (RPM and DEB)
    distroPackages: {
        // Target file patterns
        // supportconfig: */rpm.txt
        // sosreport (RHEL/SLES): */installed-rpms or */sos_commands/rpm/package-data or */sos_commands/dnf/dnf_list_installed or */sos_commands/yum/yum_list_installed
        // sosreport (Debian/Ubuntu): */sos_commands/dpkg/dpkg_-l (installed-debs is a symlink)
        filePattern: /\/(rpm\.txt|installed-rpms|package-data|dpkg_-l|dnf[_-]list[_-]installed|yum[_-]list[_-]installed)$/,
        
        // Parse function receives package list content
        // Validates Azure-required packages with specific version requirements
        parse: function(content, filename) {
            const lines = content.split('\n');
            
            debugLog('[distroPackages parser] Analyzing', lines.length, 'lines from', filename);
            
            // If this is a dpkg file, return raw content for display
            if (filename && filename.includes('dpkg')) {
                debugLog('[distroPackages parser] Detected dpkg format, returning raw content');
                return {
                    found: true,
                    isDpkg: true,
                    rawContent: content,
                    filename: filename,
                    packageCount: lines.filter(l => l.trim() && !l.startsWith('Desired') && !l.startsWith('|') && !l.startsWith('+++')).length
                };
            }
            
            // If this is a dnf/yum list file, return raw content for display
            if (filename && (filename.includes('dnf_list_installed') || filename.includes('dnf-list-installed') || filename.includes('dnf_list-installed') || filename.includes('yum_list_installed') || filename.includes('yum-list-installed') || filename.includes('yum_list-installed'))) {
                // Filter out yum/dnf header lines before displaying
                const filteredLines = lines.filter(l => {
                    const trimmed = l.trim();
                    if (!trimmed) return true; // Keep empty lines for formatting
                    // Skip header lines
                    if (l.startsWith('Installed Packages') || 
                        l.startsWith('Last metadata') || 
                        l.startsWith('Loaded plugins') ||
                        l.match(/^:\s+(manager|plugins)/) ||  // Continuation lines from Loaded plugins
                        l.match(/^Repository.*is listed more than once/)) {
                        return false;
                    }
                    return true;
                });
                const filteredContent = filteredLines.join('\n');
                const pkgCount = lines.filter(l => l.trim() && !l.startsWith('Installed') && !l.startsWith('Last metadata') && !l.startsWith('Loaded plugins')).length;
                debugLog('[distroPackages parser] Detected dnf/yum format, returning raw content');
                debugLog('[distroPackages parser] Filename:', filename);
                debugLog('[distroPackages parser] Content length:', content.length);
                debugLog('[distroPackages parser] Package count:', pkgCount);
                debugLog('[distroPackages parser] First 500 chars:', content.substring(0, 500));
                return {
                    found: true,
                    isRpmRaw: true,
                    rawContent: filteredContent,
                    filename: filename,
                    packageCount: pkgCount
                };
            }
            
            // If this is rpm.txt from supportconfig (SUSE), return raw content for display
            if (filename && filename.includes('rpm.txt')) {
                // Extract the section with package list (usually after "# rpm -qa --queryformat")
                // Filter out command headers and keep the formatted package list
                const filteredLines = [];
                let inPackageList = false;
                
                for (const line of lines) {
                    // Detect start of package list section
                    if (line.match(/^# rpm -qa --queryformat.*NAME.*DISTRIBUTION.*VERSION/i)) {
                        inPackageList = true;
                        continue; // Skip the command line itself
                    }
                    // Detect start of a new command section (end of package list)
                    if (line.startsWith('#==[ Command ]======') || line.match(/^# rpm -qa --queryformat.*SIGPGP/i)) {
                        inPackageList = false;
                    }
                    
                    // Include lines if we're in the package list section
                    if (inPackageList) {
                        filteredLines.push(line);
                    }
                }
                
                const filteredContent = filteredLines.join('\n');
                const pkgCount = filteredLines.filter(l => {
                    const trimmed = l.trim();
                    // Count only package lines (not header or empty lines)
                    return trimmed && !trimmed.startsWith('NAME') && !trimmed.startsWith('DISTRIBUTION');
                }).length;
                
                debugLog('[distroPackages parser] Detected rpm.txt format (SUSE supportconfig), returning raw content');
                debugLog('[distroPackages parser] Filename:', filename);
                debugLog('[distroPackages parser] Package count:', pkgCount);
                
                return {
                    found: true,
                    isRpmRaw: true,
                    rawContent: filteredContent,
                    filename: filename,
                    packageCount: pkgCount
                };
            }
            
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
                        debugLog('[distroPackages parser] Found', pkgName, 'version', version);
                        
                        // Validate version
                        if (requirements.operator === 'gte') {
                            if (!SCC_RULES.compareVersion(version, requirements.version, 'gte')) {
                                warnings.push({
                                    package: pkgName,
                                    expected: `>= ${requirements.version}`,
                                    actual: version,
                                    severity: 'error',
                                    message: `Package ${pkgName} version is ${version}, but should be >= ${requirements.version} for Azure environments`,
                                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                                });
                                debugLog('[distroPackages parser] WARNING:', pkgName, 'version too old');
                            }
                        } else if (requirements.operator === 'range') {
                            // Check if version is INSIDE the problematic range (inverted logic)
                            if (SCC_RULES.compareVersion(version, requirements.minVersion, 'gte') && 
                                SCC_RULES.compareVersion(version, requirements.maxVersion, 'lte')) {
                                warnings.push({
                                    package: pkgName,
                                    expected: `< ${requirements.minVersion} or > ${requirements.maxVersion}`,
                                    actual: version,
                                    severity: 'error',
                                    message: `Package ${pkgName} version is ${version}, but should be lower than ${requirements.minVersion} or higher than ${requirements.maxVersion} for Azure environments`,
                                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                                });
                                debugLog('[distroPackages parser] WARNING:', pkgName, 'version in problematic range');
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
                        message: `Required package ${pkgName} not found in package list`,
                        documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                    });
                    debugLog('[distroPackages parser] WARNING:', pkgName, 'not found');
                }
            }
            
            return {
                found: true,
                packages: foundPackages,
                warnings: warnings
            };
        }
    },
    
    // Rule: Detect Azure Site Recovery (ASR) service
    azureSiteRecovery: {
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
    },
    
    // Rule: Detect Puppet agent (configuration management)
    puppetAgent: {
        filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
        
        parse: function(content, filename) {
            debugLog('[puppetAgent parser] Analyzing for Puppet agent in:', filename);
            
            return SCC_RULES.detectSystemdService(
                content,
                filename,
                'puppet',
                'info',
                'Puppet agent is enabled on this system. This configuration management tool automates system configuration and management.'
            );
        }
    },
    
    // Rule: Detect Chef client (configuration management)
    chefClient: {
        filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
        
        parse: function(content, filename) {
            debugLog('[chefClient parser] Analyzing for Chef client in:', filename);
            
            return SCC_RULES.detectSystemdService(
                content,
                filename,
                'chef-client',
                'info',
                'Chef client is enabled on this system. This configuration management tool automates infrastructure deployment and management.'
            );
        }
    },
    
    // Rule: Detect NVMe drives in sosreports
    nvmeList: {
        filePattern: /sos_commands\/nvme\/nvme_list$/,
        
        parse: function(content, filename) {
            debugLog('[nvmeList parser] Analyzing NVMe drives in:', filename);
            
            // Count non-empty lines
            const lines = content.split('\n').filter(line => line.trim().length > 0);
            
            // If only 2 lines (header), no NVMe drives present
            if (lines.length <= 2) {
                debugLog('[nvmeList parser] No NVMe drives detected (header only)');
                return {
                    found: false,
                    hasNVMe: false
                };
            }
            
            // More than 2 lines means NVMe drives are present
            debugLog('[nvmeList parser] NVMe drives detected:', lines.length - 2, 'drives');
            
            return {
                found: true,
                hasNVMe: true,
                driveCount: lines.length - 2,
                content: content,
                filename: filename
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

// Manual parser assignments - Load external parsers after SCC_RULES is fully defined
// This avoids "SCC_RULES is not defined" errors during module loading

// From parsers/packages.js
if (typeof distroPackagesParser !== 'undefined') {
    SCC_RULES.distroPackages = distroPackagesParser;
}

// From parsers/unix.js
if (typeof basicEnvironmentParser !== 'undefined') {
    SCC_RULES.basicEnvironment = basicEnvironmentParser;
}
if (typeof osReleaseParser !== 'undefined') {
    SCC_RULES.osRelease = osReleaseParser;
}
if (typeof fstabParser !== 'undefined') {
    SCC_RULES.fstab = fstabParser;
}
if (typeof kernelTuningParser !== 'undefined') {
    SCC_RULES.kernelTuning = kernelTuningParser;
}
if (typeof hugePagesParser !== 'undefined') {
    SCC_RULES.hugePages = hugePagesParser;
}
if (typeof timeSyncParser !== 'undefined') {
    SCC_RULES.timeSync = timeSyncParser;
}
if (typeof ptpClockSourceParser !== 'undefined') {
    SCC_RULES.ptpClockSource = ptpClockSourceParser;
}
if (typeof timeSyncServiceParser !== 'undefined') {
    SCC_RULES.timeSyncService = timeSyncServiceParser;
}
if (typeof timedatectlParser !== 'undefined') {
    SCC_RULES.timedatectl = timedatectlParser;
}
if (typeof ptpDeviceParser !== 'undefined') {
    SCC_RULES.ptpDevice = ptpDeviceParser;
}
if (typeof chronyTrackingParser !== 'undefined') {
    SCC_RULES.chronyTracking = chronyTrackingParser;
}
if (typeof chronyMakestepParser !== 'undefined') {
    SCC_RULES.chronyMakestep = chronyMakestepParser;
}

// From parsers/services.js
if (typeof sshServiceParser !== 'undefined') {
    SCC_RULES.sshService = sshServiceParser;
}
if (typeof dlmServiceParser !== 'undefined') {
    SCC_RULES.dlmService = dlmServiceParser;
}
if (typeof azureSiteRecoveryParser !== 'undefined') {
    SCC_RULES.azureSiteRecovery = azureSiteRecoveryParser;
}
if (typeof guardicoreAgentParser !== 'undefined') {
    SCC_RULES.guardicoreAgent = guardicoreAgentParser;
}
if (typeof illumioParser !== 'undefined') {
    SCC_RULES.illumio = illumioParser;
}
if (typeof trendMicroParser !== 'undefined') {
    SCC_RULES.trendMicro = trendMicroParser;
}
if (typeof falconSensorParser !== 'undefined') {
    SCC_RULES.falconSensor = falconSensorParser;
}
if (typeof falconSensorConfigParser !== 'undefined') {
    SCC_RULES.falconSensorConfig = falconSensorConfigParser;
}
if (typeof msDefenderParser !== 'undefined') {
    SCC_RULES.msDefender = msDefenderParser;
}
if (typeof msDefenderConfigParser !== 'undefined') {
    SCC_RULES.msDefenderConfig = msDefenderConfigParser;
}
if (typeof involfltVersionParser !== 'undefined') {
    SCC_RULES.involfltVersion = involfltVersionParser;
}
if (typeof involfltKernelVersionParser !== 'undefined') {
    SCC_RULES.involfltKernelVersion = involfltKernelVersionParser;
}

// From parsers/events.js  
if (typeof emergencyModeParser !== 'undefined') {
    SCC_RULES.emergencyMode = emergencyModeParser;
}
if (typeof kernelRebootsParser !== 'undefined') {
    SCC_RULES.kernelReboots = kernelRebootsParser;
}
if (typeof oomKillerParser !== 'undefined') {
    SCC_RULES.oomKiller = oomKillerParser;
}
if (typeof xfsErrorsParser !== 'undefined') {
    SCC_RULES.xfsErrors = xfsErrorsParser;
}

// From parsers/azure.js
if (typeof azureVMPropertiesParser !== 'undefined') {
    SCC_RULES.azureVMProperties = azureVMPropertiesParser;
}
if (typeof suseCloudRegisterParser !== 'undefined') {
    SCC_RULES.suseCloudRegister = suseCloudRegisterParser;
}

// From parsers/cluster.js
// Initialize cluster parsers with required dependencies
if (typeof createClusterParsers !== 'undefined') {
    const clusterParsers = createClusterParsers(SCC_RULES, debugLog, parseXMLSimple, querySelectorAll);
    SCC_RULES.clusterNodes = clusterParsers.clusterNodes;
    SCC_RULES.hostsFile = clusterParsers.hostsFile;
    SCC_RULES.corosyncConfig = clusterParsers.corosyncConfig;
    SCC_RULES.pacemakerResources = clusterParsers.pacemakerResources;
    SCC_RULES.corosyncStatus = clusterParsers.corosyncStatus;
    SCC_RULES.clusterStatus = clusterParsers.clusterStatus;
    SCC_RULES.clusterDaemonStatus = clusterParsers.clusterDaemonStatus;
    SCC_RULES.azureScheduledEvents = clusterParsers.azureScheduledEvents;
    SCC_RULES.fencingConfig = clusterParsers.fencingConfig;
    SCC_RULES.clusterEvents = clusterParsers.clusterEvents;
    SCC_RULES.liveMigration = clusterParsers.liveMigration;
}

// From parsers/storage.js
if (typeof lvmConfigParser !== 'undefined') {
    SCC_RULES.lvmConfig = lvmConfigParser;
}
if (typeof raidConfigParser !== 'undefined') {
    SCC_RULES.raidConfig = raidConfigParser;
}
if (typeof btrfsConfigParser !== 'undefined') {
    SCC_RULES.btrfsConfig = btrfsConfigParser;
}
if (typeof blockDevicesParser !== 'undefined') {
    SCC_RULES.blockDevices = blockDevicesParser;
}
if (typeof fstabAnalysisParser !== 'undefined') {
    SCC_RULES.fstabAnalysis = fstabAnalysisParser;
}

// From parsers/unix.js - RHUI/EUS parsers
if (typeof rhuiConfigParser !== 'undefined') {
    SCC_RULES.rhuiConfig = rhuiConfigParser;
}
if (typeof eusVersionLockParser !== 'undefined') {
    SCC_RULES.eusVersionLock = eusVersionLockParser;
}
if (typeof rhelRhuiCheckParser !== 'undefined') {
    SCC_RULES.rhelRhuiCheck = rhelRhuiCheckParser;
}
if (typeof cryptoPoliciesParser !== 'undefined') {
    SCC_RULES.cryptoPolicies = cryptoPoliciesParser;
}
if (typeof rhuiErrorsParser !== 'undefined') {
    SCC_RULES.rhuiErrors = rhuiErrorsParser;
}
if (typeof leappReportParser !== 'undefined') {
    SCC_RULES.leappReport = leappReportParser;
}
if (typeof leappLogParser !== 'undefined') {
    SCC_RULES.leappLog = leappLogParser;
}
// ============================================================================

// Load the streaming WASM module
importScripts(
    './liblzma-wasm/dist-streaming/liblzma-xz-streaming.js'
);

let moduleReady = false;
let Module = null;

// Initialize the WASM module
LZMA_XZ_Streaming_Module({
    locateFile: (path) => {
        if (path.endsWith('.wasm')) {
            // Return the correct path relative to worker location
            const wasmPath = './liblzma-wasm/dist-streaming/liblzma-xz-streaming.wasm';
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
        this.nextLongFilename = null; // For GNU TAR long filename extension
        this.paxExtendedHeaders = {};  // For PAX extended attributes
        this.usedPaxFormat = false;  // Track if PAX extended headers were used
        this.processedLogFiles = {}; // Track processed log files to limit rotations (performance optimization)
        
        // Nested compression statistics
        this.nestedGzipTotalCount = 0; // Total .gz files found in archive
        this.nestedGzipTotalCompressedBytes = 0; // Total compressed size of all .gz files
        this.nestedGzipCount = 0; // .gz files actually decompressed
        this.nestedGzipCompressedBytes = 0; // Compressed size of decompressed files
        this.nestedGzipDecompressedBytes = 0; // Decompressed size
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

        // Read type flag first (offset 156)
        const typeflag = this.buffer[offset + 156];

        // Read filename (null-terminated, first 100 bytes)
        let filename = '';
        for (let i = 0; i < 100; i++) {
            if (this.buffer[offset + i] === 0) break;
            filename += String.fromCharCode(this.buffer[offset + i]);
        }

        // Read prefix field (offset 345, 155 bytes) for POSIX ustar format
        let prefix = '';
        for (let i = 345; i < 500; i++) {
            if (this.buffer[offset + i] === 0) break;
            prefix += String.fromCharCode(this.buffer[offset + i]);
        }

        // Combine prefix and filename if prefix exists
        if (prefix) {
            filename = prefix + '/' + filename;
        }

        // Use long filename from previous GNU extension if available
        if (this.nextLongFilename) {
            filename = this.nextLongFilename;
            this.nextLongFilename = null;
        }

        // Use path from PAX extended headers if available
        if (this.paxExtendedHeaders.path) {
            filename = this.paxExtendedHeaders.path;
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

        // Debug: Log when parsing headers for key files
        if (filename.includes('dpkg') || filename.includes('usr/lib/os-release')) {
            debugLog(`[TAR Parser] parseHeader:`, filename, `size=${size}, prefix='${prefix}', name_len=${filename.length}, typeflag=${typeflag}`);
        }

        return { filename, size, typeflag, offset };
    }

    processEntry(header) {
        const { filename, size, typeflag, offset } = header;

        // Handle GNU TAR long filename extension (typeflag='L' or 76)
        if (typeflag === 76 || typeflag === 'L'.charCodeAt(0)) {
            // This entry contains a long filename for the NEXT entry
            // Extract the long filename from the data section
            const dataOffset = offset + 512;
            let longName = '';
            const maxRead = Math.min(size, this.buffer.length - dataOffset);
            for (let i = 0; i < maxRead; i++) {
                const c = this.buffer[dataOffset + i];
                if (c === 0) break;
                longName += String.fromCharCode(c);
            }
            this.nextLongFilename = longName;
            debugLog(`[TAR Parser] Found long filename:`, longName);
            return; // Don't process this as a regular file
        }

        // Handle PAX extended headers (typeflag='x' (120) or 'g' (103))
        if (typeflag === 120 || typeflag === 103 || typeflag === 'x'.charCodeAt(0) || typeflag === 'g'.charCodeAt(0)) {
            this.usedPaxFormat = true;  // Mark that this archive uses PAX format
            const dataOffset = offset + 512;
            let paxData = '';
            const maxRead = Math.min(size, this.buffer.length - dataOffset);
            for (let i = 0; i < maxRead; i++) {
                const c = this.buffer[dataOffset + i];
                if (c === 0) break;
                paxData += String.fromCharCode(c);
            }
            
            // Parse PAX extended headers (format: "length key=value\n")
            const lines = paxData.split('\n');
            for (const line of lines) {
                if (!line.trim()) continue;
                // PAX format: "111 path=sosreport-..." or "111 path = sosreport-..."
                const match = line.match(/^\d+\s+(\S+)\s*=\s*(.*)$/);
                if (match) {
                    const key = match[1];
                    const value = match[2];
                    this.paxExtendedHeaders[key] = value;
                    if (key === 'path' || key === 'linkpath') {
                        debugLog(`[TAR Parser] Found PAX ${key}:`, value);
                    }
                }
            }
            return; // Don't process PAX headers as regular files
        }

        // Debug: Log when we see key files
        if (filename.endsWith('dpkg_-l') || filename.endsWith('os-release')) {
            debugLog(`[TAR Parser] processEntry:`, filename, `size=${size}, typeflag=${typeflag}`);
        }

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

        // Clear PAX headers after processing regular file (typeflag '0' or 48)
        if (typeflag === 48 || typeflag === 0 || typeflag === '0'.charCodeAt(0)) {
            this.paxExtendedHeaders = {};
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
        
        // Track ALL .gz files in the archive (not just the ones we decompress)
        if (filename.toLowerCase().endsWith('.gz') && (typeflag === 48 || typeflag === 0 || typeflag === '0'.charCodeAt(0))) {
            this.nestedGzipTotalCount++;
            this.nestedGzipTotalCompressedBytes += size;
        }
    }

    // Process all SCC rules against current file
    processSCCRules(filename, size, offset) {
        // Skip PaxHeaders - they are TAR extended headers, not actual file content
        if (filename.includes('/PaxHeaders/') || filename.endsWith('/PaxHeaders')) {
            return;
        }
        
        // Performance optimization: Limit processing of compressed rotated log files
        // Track which base log files we've seen and limit compressed rotations to 3 most recent
        // Uncompressed rotated logs are processed without limit
        if (!this.processedLogFiles) {
            this.processedLogFiles = {}; // Track: baseFileName -> [rotation numbers for compressed files]
        }
        
        // Check if this is a compressed rotated log file (messages.1.gz, messages-20241215.bz2, etc.)
        const compressedRotationMatch = filename.match(/\/(messages|localmessages|journalctl[^/]*|pacemaker\.log|corosync\.log)([.-]\d+)?(?:\.gz|\.bz2|\.xz)$/);
        if (compressedRotationMatch) {
            const baseFile = compressedRotationMatch[1];
            const rotation = compressedRotationMatch[2] || '.current';
            
            if (!this.processedLogFiles[baseFile]) {
                this.processedLogFiles[baseFile] = [];
            }
            
            // Check if any rule needs all rotations for this file
            const needsAllRotations = Object.values(SCC_RULES).some(rule => 
                rule.processAllRotations && rule.filePattern && rule.filePattern.test(filename)
            );
            
            if (!needsAllRotations) {
                // Limit to 3 versions of compressed log files (current + 2 rotations)
                // This prevents processing dozens of old compressed rotated logs
                if (this.processedLogFiles[baseFile].length >= 3) {
                    debugLog(`[TAR Parser] Skipping compressed rotated log (limit reached):`, filename);
                    return;
                }
            }
            
            this.processedLogFiles[baseFile].push(rotation);
            const limitInfo = needsAllRotations ? 'no limit' : `${this.processedLogFiles[baseFile].length}/3`;
            debugLog(`[TAR Parser] Processing compressed log file ${baseFile} rotation ${rotation} (${limitInfo})`);
        }
        
        // Debug: Log when we see key files
        if (filename.endsWith('dpkg_-l') || filename.endsWith('os-release')) {
            debugLog(`[TAR Parser] Processing file:`, filename, `size=${size}`);
        }
        
        // Iterate through all rules (except detection)
        for (const [ruleName, rule] of Object.entries(SCC_RULES)) {
            if (ruleName === 'detection' || !rule.filePattern) continue;
            
            // Debug: Log pattern testing for key files
            if (filename.includes('os-release') || filename.includes('dpkg') || filename.includes('installed-rpms') || filename.includes('package-data') || filename.includes('dnf.log') || filename.includes('/block/') || filename.includes('/fstab')) {
                debugLog(`[TAR Parser] Testing rule '${ruleName}' pattern ${rule.filePattern} against:`, filename);
            }
            
            // Check if filename matches rule pattern
            if (rule.filePattern.test(filename)) {
                debugLog(`[TAR Parser] Matched rule '${ruleName}' for file:`, filename);
                
                // Special debug for storage-related rules
                if (ruleName === 'blockDevices' || ruleName === 'fstabAnalysis') {
                    console.log(`[Worker] STORAGE: Matched ${ruleName} for file:`, filename);
                }
                
                // Extract file content
                const dataOffset = offset + 512;
                
                // Special case: cloudregister.txt can be huge (1GB+), only extract first 100KB
                let extractSize = size;
                if (ruleName === 'suseCloudRegister') {
                    const maxSize = 100 * 1024; // 100 KB
                    extractSize = Math.min(size, maxSize);
                    debugLog(`[TAR Parser] cloudregister.txt size ${size} bytes, extracting first ${extractSize} bytes`);
                }
                
                if (this.buffer.length >= dataOffset + extractSize) {
                    const content = this.extractFileContent(dataOffset, extractSize, filename);
                    if (content) {
                        // For rules that process multiple files (like liveMigration, kernelReboots, oomKiller, xfsErrors, emergencyMode, sshService, automation, clusterEvents, rhuiErrors, and blockDevices)
                        // we need to accumulate results instead of replacing
                        const isMultiFileRule = ruleName === 'liveMigration' || ruleName === 'kernelReboots' || ruleName === 'oomKiller' || ruleName === 'xfsErrors' || ruleName === 'emergencyMode' || ruleName === 'sshService' || ruleName === 'automation' || ruleName === 'clusterEvents' || ruleName === 'rhuiErrors' || ruleName === 'blockDevices';
                        
                        // NOTE: We don't store file content in extractedFiles anymore to save memory
                        // Content is parsed immediately and discarded
                        
                        // Parse using rule's parse function (pass filename for format detection)
                        try {
                            const result = rule.parse(content, filename);
                            
                            if (isMultiFileRule) {
                                // Accumulate results for multi-file rules
                                // rhuiErrors and blockDevices have different structures, so initialize separately
                                if (!this.analysisResults[ruleName] && ruleName !== 'rhuiErrors' && ruleName !== 'blockDevices') {
                                    this.analysisResults[ruleName] = {
                                        count: 0,
                                        events: []
                                    };
                                }
                                
                                // Handle blockDevices accumulation - merges disks, partitions, and UUID maps
                                if (ruleName === 'blockDevices') {
                                    if (!this.analysisResults[ruleName]) {
                                        this.analysisResults[ruleName] = result;
                                    } else {
                                        // Merge result into existing
                                        this.mergeBlockDevicesResult(this.analysisResults[ruleName], result);
                                    }
                                    debugLog(`[TAR Parser] Rule 'blockDevices' accumulated from ${filename} (disks: ${this.analysisResults[ruleName].disks?.length || 0}, partitions: ${this.analysisResults[ruleName].partitions?.length || 0})`);
                                }
                                // For kernelReboots, xfsErrors, emergencyMode, sshService, automation, clusterEvents, and rhuiErrors, deduplicate events based on timestamp and relevant fields
                                else if (ruleName === 'kernelReboots' || ruleName === 'xfsErrors' || ruleName === 'emergencyMode' || ruleName === 'sshService' || ruleName === 'automation' || ruleName === 'clusterEvents' || ruleName === 'rhuiErrors') {
                                    // Define comparison fields for each rule type
                                    const comparisonFields = ruleName === 'kernelReboots' 
                                        ? ['timestamp', 'type', 'kernelVersion']
                                        : ruleName === 'xfsErrors'
                                        ? ['timestamp', 'device', 'message']
                                        : ruleName === 'emergencyMode'
                                        ? ['timestamp', 'lineNumber']
                                        : ruleName === 'sshService'
                                        ? ['timestamp', 'issueType', 'message']
                                        : ruleName === 'automation'
                                        ? ['timestamp', 'toolType', 'command']
                                        : null; // clusterEvents handled separately below
                                    
                                    if (ruleName === 'clusterEvents') {
                                        // clusterEvents has two arrays: resourceMigrations and fencingEvents
                                        if (!this.analysisResults[ruleName].resourceMigrations) {
                                            this.analysisResults[ruleName].resourceMigrations = [];
                                        }
                                        if (!this.analysisResults[ruleName].fencingEvents) {
                                            this.analysisResults[ruleName].fencingEvents = [];
                                        }
                                        
                                        // Deduplicate resource migrations
                                        const migrationFields = ['timestamp', 'resource', 'fromNode', 'toNode', 'action'];
                                        const migrationResult = SCC_RULES.deduplicateEvents(
                                            this.analysisResults[ruleName].resourceMigrations,
                                            result.resourceMigrations || [],
                                            migrationFields
                                        );
                                        this.analysisResults[ruleName].resourceMigrations.push(...migrationResult.addedEvents);
                                        
                                        // Deduplicate fencing events
                                        const fencingFields = ['timestamp', 'targetNode', 'action', 'status'];
                                        const fencingResult = SCC_RULES.deduplicateEvents(
                                            this.analysisResults[ruleName].fencingEvents,
                                            result.fencingEvents || [],
                                            fencingFields
                                        );
                                        this.analysisResults[ruleName].fencingEvents.push(...fencingResult.addedEvents);
                                        
                                        this.analysisResults[ruleName].count = this.analysisResults[ruleName].resourceMigrations.length + this.analysisResults[ruleName].fencingEvents.length;
                                        
                                        debugLog(`[TAR Parser] Rule 'clusterEvents' accumulated ${migrationResult.addedEvents.length} migrations, ${fencingResult.addedEvents.length} fencing events (${migrationResult.duplicateCount + fencingResult.duplicateCount} duplicates skipped, total: ${this.analysisResults[ruleName].count})`);
                                    } else if (ruleName === 'rhuiErrors') {
                                        // RHUI errors rule has special structure - merge boolean flags and arrays
                                        if (!this.analysisResults[ruleName]) {
                                            this.analysisResults[ruleName] = {
                                                found: false,
                                                hasCertExpiration: false,
                                                hasHttp403: false,
                                                hasHttp400: false,
                                                hasConnectionError: false,
                                                errors: [],
                                                affectedRepos: [],
                                                warnings: [],
                                                recommendations: []
                                            };
                                        }
                                        
                                        // Merge boolean flags (OR them together)
                                        this.analysisResults[ruleName].found = this.analysisResults[ruleName].found || result.found;
                                        this.analysisResults[ruleName].hasCertExpiration = this.analysisResults[ruleName].hasCertExpiration || result.hasCertExpiration;
                                        this.analysisResults[ruleName].hasHttp403 = this.analysisResults[ruleName].hasHttp403 || result.hasHttp403;
                                        this.analysisResults[ruleName].hasHttp400 = this.analysisResults[ruleName].hasHttp400 || result.hasHttp400;
                                        this.analysisResults[ruleName].hasConnectionError = this.analysisResults[ruleName].hasConnectionError || result.hasConnectionError;
                                        
                                        // Add errors (with source file)
                                        result.errors.forEach(err => {
                                            this.analysisResults[ruleName].errors.push({
                                                ...err,
                                                sourceFile: filename
                                            });
                                        });
                                        
                                        // Add unique affected repos
                                        result.affectedRepos.forEach(repo => {
                                            if (!this.analysisResults[ruleName].affectedRepos.includes(repo)) {
                                                this.analysisResults[ruleName].affectedRepos.push(repo);
                                            }
                                        });
                                        
                                        // Add unique warnings (by type)
                                        result.warnings.forEach(warning => {
                                            if (!this.analysisResults[ruleName].warnings.find(w => w.type === warning.type)) {
                                                this.analysisResults[ruleName].warnings.push(warning);
                                            }
                                        });
                                        
                                        debugLog(`[TAR Parser] Rule 'rhuiErrors' accumulated from ${filename} (found: ${result.found}, errors: ${result.errors.length}, total errors: ${this.analysisResults[ruleName].errors.length})`);
                                    } else {
                                        // Add sourceFile to new events
                                        const newEventsWithSource = result.events.map(event => ({
                                            ...event,
                                            sourceFile: filename
                                        }));
                                        
                                        // Use utility function for deduplication
                                        const dedupeResult = SCC_RULES.deduplicateEvents(
                                            this.analysisResults[ruleName].events,
                                            newEventsWithSource,
                                            comparisonFields
                                        );
                                        
                                        // Add non-duplicate events
                                        this.analysisResults[ruleName].events.push(...dedupeResult.addedEvents);
                                        this.analysisResults[ruleName].count = this.analysisResults[ruleName].events.length;
                                        
                                        debugLog(`[TAR Parser] Rule '${ruleName}' accumulated ${dedupeResult.addedEvents.length} new events (${dedupeResult.duplicateCount} duplicates skipped, total: ${this.analysisResults[ruleName].count})`);
                                    }
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
                                } else if (ruleName === 'distroPackages') {
                                    // distroPackages: prefer raw format over Azure validation format
                                    const existing = this.analysisResults[ruleName];
                                    
                                    // Priority: raw content (isRpmRaw or isDpkg) > Azure validation (packages/warnings)
                                    const isRawFormat = result.isRpmRaw || result.isDpkg;
                                    const existingIsRaw = existing && (existing.isRpmRaw || existing.isDpkg);
                                    
                                    if (!existing || isRawFormat && !existingIsRaw) {
                                        // No existing result, or this is raw and existing is validation
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (${isRawFormat ? 'raw format' : 'validation format'}):`, result);
                                    } else if (!isRawFormat && existingIsRaw) {
                                        // This is validation but existing is raw - keep existing
                                        debugLog(`[TAR Parser] Rule '${ruleName}' skipping validation format (already have raw format)`);
                                    } else {
                                        // Both same type, use newer
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' replaced with newer result`);
                                    }
                                } else if (ruleName === 'involfltKernelVersion') {
                                    // involfltKernelVersion: preserve positive result (found: true) once found
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.found) {
                                        // No existing result or existing is negative - update if we have a result
                                        if (result) {
                                            this.analysisResults[ruleName] = result;
                                            debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully:`, result);
                                        }
                                    } else {
                                        // Already have a positive result - keep it
                                        debugLog(`[TAR Parser] Rule '${ruleName}' already found, keeping existing result`);
                                    }
                                } else if (ruleName === 'azureScheduledEvents') {
                                    // azureScheduledEvents: merge results from multiple files (pcs_status, crm_mon, cib.xml)
                                    const existing = this.analysisResults[ruleName];
                                    
                                    if (!existing || !existing.found) {
                                        this.analysisResults[ruleName] = result;
                                        debugLog(`[TAR Parser] Rule '${ruleName}' parsed successfully (first):`, result);
                                    } else if (result.found) {
                                        // Merge results: accumulate nodes, resources, and warnings
                                        // Keep healthAzureConfigured if either found it
                                        existing.healthAzureConfigured = existing.healthAzureConfigured || result.healthAzureConfigured;
                                        
                                        // Keep healthAzureResource if either found it
                                        if (result.healthAzureResource && !existing.healthAzureResource) {
                                            existing.healthAzureResource = result.healthAzureResource;
                                        }
                                        
                                        // Keep nodeHealthStrategy if either found it
                                        if (result.nodeHealthStrategy && !existing.nodeHealthStrategy) {
                                            existing.nodeHealthStrategy = result.nodeHealthStrategy;
                                        }
                                        
                                        // Merge nodesWithHealthAzure (dedupe by node name)
                                        result.nodesWithHealthAzure.forEach(newNode => {
                                            if (!existing.nodesWithHealthAzure.find(n => n.node === newNode.node)) {
                                                existing.nodesWithHealthAzure.push(newNode);
                                            }
                                        });
                                        
                                        // Merge onlineNodes (dedupe)
                                        result.onlineNodes.forEach(node => {
                                            if (!existing.onlineNodes.includes(node)) {
                                                existing.onlineNodes.push(node);
                                            }
                                        });
                                        
                                        // Merge stoppedResources (dedupe)
                                        result.stoppedResources.forEach(res => {
                                            if (!existing.stoppedResources.includes(res)) {
                                                existing.stoppedResources.push(res);
                                            }
                                        });
                                        
                                        debugLog(`[TAR Parser] Rule '${ruleName}' merged (onlineNodes: ${existing.onlineNodes.length}, stoppedResources: ${existing.stoppedResources.length})`);
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

    extractFileContent(offset, size, filename) {
        const contentBytes = this.buffer.slice(offset, offset + size);
        
        // Check if content is gzipped (magic bytes: 0x1f 0x8b)
        const isGzipped = contentBytes.length >= 2 && contentBytes[0] === 0x1f && contentBytes[1] === 0x8b;
        
        if (isGzipped) {
            console.log(`[TAR Parser] Detected gzipped file: ${filename} (${size} bytes)`);
            try {
                debugLog(`[TAR Parser] Decompressing nested .gz file: ${filename} (${size} bytes compressed)`);
                
                // Send progress update for nested decompression
                console.log(`[TAR Parser] Sending nested decompression progress message for: ${filename}`);
                self.postMessage({
                    progress: true,
                    message: `Decompressing nested file: ${filename.split('/').pop()}`
                });
                
                // Use native browser DecompressionStream if available (modern browsers)
                if (typeof DecompressionStream !== 'undefined') {
                    // DecompressionStream is async, we need to handle it differently
                    // For now, fall back to synchronous pako-style decompression
                    debugLog('[TAR Parser] DecompressionStream API available but async - using alternative method');
                }
                
                // Use pako library for gzip decompression (synchronous)
                // pako.inflate returns Uint8Array
                if (typeof pako !== 'undefined' && pako.inflate) {
                    console.log(`[TAR Parser] Using pako to decompress ${filename}`);
                    const decompressed = pako.inflate(contentBytes);
                    const decodedText = new TextDecoder('utf-8').decode(decompressed);
                    
                    // Track nested decompression statistics
                    this.nestedGzipCount++;
                    this.nestedGzipCompressedBytes += size;
                    this.nestedGzipDecompressedBytes += decompressed.length;
                    
                    console.log(`[TAR Parser] Successfully decompressed ${filename}: ${size} → ${decompressed.length} bytes`);
                    debugLog(`[TAR Parser] Successfully decompressed ${filename}: ${size} → ${decompressed.length} bytes`);
                    return decodedText;
                } else {
                    console.warn('[TAR Parser] pako library not available, cannot decompress .gz file:', filename);
                    console.warn('[TAR Parser] pako object:', typeof pako);
                    debugLog('[TAR Parser] Attempting to decode as-is (will likely fail)');
                    // Fall through to regular decoding
                }
            } catch (e) {
                console.error('[TAR Parser] Failed to decompress gzipped file:', filename, e);
                console.error('[TAR Parser] Attempting to decode as-is (will likely fail)');
                // Fall through to regular decoding attempt
            }
        }
        
        try {
            return new TextDecoder('utf-8').decode(contentBytes);
        } catch (e) {
            console.error('[TAR Parser] Failed to decode file content:', filename, e);
            return null;
        }
    }
    
    mergeAzureVMProperties() {
        const azureVMProps = this.analysisResults.azureVMProperties;
        const suseCloudReg = this.analysisResults.suseCloudRegister;
        
        // If no Azure VM properties found, return null
        if (!azureVMProps) {
            // If we have SUSE cloud registration, create a minimal Azure VM properties object
            if (suseCloudReg && suseCloudReg.found) {
                return {
                    billingModel: suseCloudReg.billingModel,
                    detectionMethod: suseCloudReg.detectionMethod + ' (SUSE only)',
                    registrationServer: suseCloudReg.registrationServer,
                    registrationType: suseCloudReg.registrationType
                };
            }
            return null;
        }
        
        // If no SUSE cloud registration or it didn't find anything, return Azure VM properties as-is
        if (!suseCloudReg || !suseCloudReg.found) {
            return azureVMProps;
        }
        
        // Both sources available - merge intelligently
        const merged = { ...azureVMProps };
        
        // If azureVMProperties doesn't have billing model, use SUSE cloud registration
        if (!merged.billingModel && suseCloudReg.billingModel) {
            merged.billingModel = suseCloudReg.billingModel;
            merged.detectionMethod = suseCloudReg.detectionMethod;
            merged.registrationServer = suseCloudReg.registrationServer;
            merged.registrationType = suseCloudReg.registrationType;
            debugLog('[mergeAzureVMProperties] Using SUSE cloud registration for billing model');
        }
        // If both have billing models, prefer SUSE cloud registration for SUSE VMs
        // (it's more reliable and specific to SUSE)
        else if (merged.billingModel && suseCloudReg.billingModel) {
            // Add SUSE registration as additional information
            merged.suseRegistrationServer = suseCloudReg.registrationServer;
            merged.suseRegistrationType = suseCloudReg.registrationType;
            merged.suseDetectionMethod = suseCloudReg.detectionMethod;
            
            // If they disagree, log a warning and prefer SUSE cloud registration for SUSE systems
            if (merged.billingModel !== suseCloudReg.billingModel) {
                debugLog(`[mergeAzureVMProperties] Billing model mismatch: Azure metadata says ${merged.billingModel}, SUSE registration says ${suseCloudReg.billingModel}`);
                // For SUSE systems, prefer the SUSE cloud registration (it's more accurate)
                if (merged.publisher && merged.publisher.toLowerCase() === 'suse') {
                    merged.billingModel = suseCloudReg.billingModel;
                    merged.detectionMethod = suseCloudReg.detectionMethod + ' (preferred over Azure metadata)';
                    debugLog('[mergeAzureVMProperties] Using SUSE cloud registration for SUSE VM');
                } else {
                    // For non-SUSE, add SUSE data as secondary source
                    merged.alternativeBillingModel = suseCloudReg.billingModel;
                    merged.alternativeDetectionMethod = suseCloudReg.detectionMethod;
                }
            } else {
                debugLog('[mergeAzureVMProperties] Both sources agree on billing model:', merged.billingModel);
            }
        }
        
        return merged;
    }

    /**
     * Merge results from blockDevices parser (multi-file parser)
     * Accumulates disk, partition, and UUID data across multiple files
     */
    mergeBlockDevicesResult(existing, newResult) {
        // Merge found flag
        existing.found = existing.found || newResult.found;
        
        // Merge arrays (disks, partitions, warnings) avoiding duplicates
        for (const key of ['disks', 'partitions', 'warnings']) {
            if (Array.isArray(newResult[key])) {
                if (!existing[key]) existing[key] = [];
                for (const item of newResult[key]) {
                    // Avoid duplicates by checking for unique identifier
                    const isDupe = existing[key].some(e => 
                        (e.name && e.name === item.name) || 
                        (e.device && e.device === item.device)
                    );
                    if (!isDupe) {
                        existing[key].push(item);
                    }
                }
            }
        }
        
        // Merge maps (uuidMap, deviceMap, mountPoints)
        for (const key of ['uuidMap', 'deviceMap', 'mountPoints']) {
            if (newResult[key] && typeof newResult[key] === 'object') {
                if (!existing[key]) existing[key] = {};
                Object.assign(existing[key], newResult[key]);
            }
        }
        
        // Merge raw output
        if (newResult.rawOutput && typeof newResult.rawOutput === 'object') {
            if (!existing.rawOutput) existing.rawOutput = {};
            Object.assign(existing.rawOutput, newResult.rawOutput);
        }
    }

    /**
     * Correlate fstab entries with block device information
     * Detects UUID mismatches, missing UUIDs, and filesystem type mismatches
     */
    correlateFstabWithBlockDevices() {
        const fstab = this.analysisResults.fstabAnalysis;
        const blockDevices = this.analysisResults.blockDevices;
        
        if (!fstab?.found || !blockDevices?.found) {
            debugLog('[Storage] Cannot correlate: fstab or blockDevices not found');
            return null;
        }
        
        // Create a storage correlation result
        const correlation = {
            found: true,
            mountedVolumes: [],
            warnings: [],
            errors: []
        };
        
        for (const entry of (fstab.entries || [])) {
            const mountInfo = {
                mountpoint: entry.mountpoint,
                source: entry.source,
                fstabFstype: entry.fstype,
                actualDevice: null,
                actualUuid: null,
                actualFstype: null,
                status: 'unknown',
                issues: []
            };
            
            if (entry.sourceType === 'uuid' && entry.uuid) {
                // Look up UUID in block devices
                const device = blockDevices.uuidMap?.[entry.uuid] || 
                              blockDevices.uuidMap?.[entry.uuid.toLowerCase()] ||
                              blockDevices.uuidMap?.[entry.uuid.toUpperCase()];
                
                if (device) {
                    const deviceInfo = blockDevices.deviceMap?.[device];
                    mountInfo.actualDevice = device;
                    mountInfo.actualUuid = deviceInfo?.uuid;
                    mountInfo.actualFstype = deviceInfo?.fstype;
                    mountInfo.status = 'found';
                    
                    // Check for filesystem type mismatch
                    if (entry.fstype !== 'auto' && deviceInfo?.fstype && 
                        entry.fstype.toLowerCase() !== deviceInfo.fstype.toLowerCase()) {
                        mountInfo.status = 'warning';
                        mountInfo.issues.push({
                            type: 'fstype_mismatch',
                            message: `Filesystem type mismatch: fstab expects '${entry.fstype}' but device has '${deviceInfo.fstype}'`,
                            severity: 'warning'
                        });
                        correlation.warnings.push({
                            mountpoint: entry.mountpoint,
                            message: `Filesystem type mismatch for ${entry.mountpoint}: fstab='${entry.fstype}', actual='${deviceInfo.fstype}'`
                        });
                    }
                } else {
                    // UUID not found - this is a problem
                    mountInfo.status = 'error';
                    mountInfo.issues.push({
                        type: 'uuid_not_found',
                        message: `UUID '${entry.uuid}' referenced in fstab not found on any block device`,
                        severity: 'error'
                    });
                    correlation.errors.push({
                        mountpoint: entry.mountpoint,
                        uuid: entry.uuid,
                        message: `UUID ${entry.uuid} for ${entry.mountpoint} not found on any device. The disk may have been replaced or reformatted.`
                    });
                }
            } else if (entry.sourceType === 'device' && entry.device) {
                // Direct device reference
                const deviceInfo = blockDevices.deviceMap?.[entry.device];
                if (deviceInfo) {
                    mountInfo.actualDevice = entry.device;
                    mountInfo.actualUuid = deviceInfo.uuid;
                    mountInfo.actualFstype = deviceInfo.fstype;
                    mountInfo.status = 'found';
                } else {
                    // Might be a symlink path
                    mountInfo.status = 'symlink';
                }
            }
            
            correlation.mountedVolumes.push(mountInfo);
        }
        
        // Add summary
        correlation.summary = {
            totalEntries: fstab.entries?.length || 0,
            foundDevices: correlation.mountedVolumes.filter(m => m.status === 'found').length,
            warnings: correlation.warnings.length,
            errors: correlation.errors.length
        };
        
        debugLog('[Storage] Correlation complete:', correlation.summary);
        return correlation;
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
        const xfsErrorsData = this.analysisResults.xfsErrors || null;
        const corosyncData = this.analysisResults.corosyncConfig || null;
        const distroPackagesData = this.analysisResults.distroPackages || null;
        const pacemakerResourcesData = this.analysisResults.pacemakerResources || null;
        const fencingConfigData = this.analysisResults.fencingConfig || null;
        const clusterEventsData = this.analysisResults.clusterEvents || null;
        
        if (clusterEventsData && clusterEventsData.count > 0) {
            console.log('[Analysis] Cluster Events:', clusterEventsData.count, 'total -', (clusterEventsData.resourceMigrations || []).length, 'resource events,', (clusterEventsData.fencingEvents || []).length, 'fencing events');
        }
        
        // Get OS information to filter distribution-specific checks
        const osReleaseData = this.analysisResults.osRelease || this.analysisResults.sysinfo || this.analysisResults.basicEnvironment || null;
        const isSUSE = osReleaseData && osReleaseData.name && 
                      (osReleaseData.name.toLowerCase().includes('suse') || 
                       (osReleaseData.prettyName && osReleaseData.prettyName.toLowerCase().includes('suse')));
        
        // Filter corosync warnings for SUSE-specific checks
        if (corosyncData && corosyncData.warnings && !isSUSE) {
            // Remove the transport warning for non-SUSE distributions
            corosyncData.warnings = corosyncData.warnings.filter(warning => 
                warning.parameter !== 'totem.transport'
            );
            debugLog('[TAR Parser] Filtered totem.transport warning for non-SUSE distribution');
        }
        
        // Antivirus detection results
        const falconSensorData = this.analysisResults.falconSensor || { found: false };
        const falconConfigData = this.analysisResults.falconSensorConfig || { found: false };
        const msDefenderData = this.analysisResults.msDefender || { found: false };
        const msDefenderConfigData = this.analysisResults.msDefenderConfig || { found: false };
        const illumioData = this.analysisResults.illumio || { found: false };
        const trendMicroData = this.analysisResults.trendMicro || { found: false };
        const azureSiteRecoveryData = this.analysisResults.azureSiteRecovery || { found: false };
        const guardicoreAgentData = this.analysisResults.guardicoreAgent || { found: false };
        const puppetAgentData = this.analysisResults.puppetAgent || { found: false };
        const chefClientData = this.analysisResults.chefClient || { found: false };
        
        // Combine antivirus and Azure services results
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
            guardicoreAgent: {
                detected: guardicoreAgentData.found,
                enabled: guardicoreAgentData.enabled || false,
                severity: guardicoreAgentData.severity,
                message: guardicoreAgentData.message,
                detectionFile: guardicoreAgentData.detectionFile,
                detectionLine: guardicoreAgentData.detectionLine,
                detectionContent: guardicoreAgentData.detectionContent
            },
            puppetAgent: {
                detected: puppetAgentData.found,
                enabled: puppetAgentData.enabled || false,
                severity: puppetAgentData.severity,
                message: puppetAgentData.message,
                detectionFile: puppetAgentData.detectionFile,
                detectionLine: puppetAgentData.detectionLine,
                detectionContent: puppetAgentData.detectionContent
            },
            chefClient: {
                detected: chefClientData.found,
                enabled: chefClientData.enabled || false,
                severity: chefClientData.severity,
                message: chefClientData.message,
                detectionFile: chefClientData.detectionFile,
                detectionLine: chefClientData.detectionLine,
                detectionContent: chefClientData.detectionContent
            },
            azureSiteRecovery: {
                detected: azureSiteRecoveryData.found,
                enabled: azureSiteRecoveryData.enabled || false,
                severity: azureSiteRecoveryData.severity,
                message: azureSiteRecoveryData.message,
                detectionFile: azureSiteRecoveryData.detectionFile,
                detectionLine: azureSiteRecoveryData.detectionLine,
                detectionContent: azureSiteRecoveryData.detectionContent
            },
            // Overall status
            anyDetected: falconSensorData.found || msDefenderData.found || illumioData.found || trendMicroData.found || azureSiteRecoveryData.found || guardicoreAgentData.found || puppetAgentData.found || chefClientData.found,
            allHaveExceptions: (falconSensorData.found ? (falconConfigData.hasExclusions || false) : true) && 
                              (msDefenderData.found ? (msDefenderConfigData.hasExclusions || false) : true)
        };
        
        // Cluster services results (separate from antivirus and Azure services)
        const dlmServiceData = this.analysisResults.dlmService || { found: false };
        const clusterServicesResults = {
            dlmService: {
                detected: dlmServiceData.found,
                enabled: dlmServiceData.enabled || false,
                severity: dlmServiceData.severity,
                message: dlmServiceData.message,
                documentationUrl: dlmServiceData.documentationUrl,
                detectionFile: dlmServiceData.detectionFile,
                detectionLine: dlmServiceData.detectionLine,
                detectionContent: dlmServiceData.detectionContent
            }
        };
        
        debugLog('[TAR Parser] getAnalysis() called');
        debugLog('[TAR Parser] analysisResults:', this.analysisResults);
        
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
                        resolvedNodes.push(hostname);
                    }
                    // If not, try to resolve using hosts file
                    else if (hostsData) {
                        const hostEntry = hostsData.entries.find(entry => entry.ip === node);
                        if (hostEntry && hostEntry.hostnames.length > 0) {
                            // Use the first hostname
                            const hostname = hostEntry.hostnames[0];
                            resolvedNodes.push(hostname);
                        } else {
                            // Keep the IP if we can't resolve it
                            resolvedNodes.push(node);
                        }
                    } else {
                        resolvedNodes.push(node);
                    }
                } else {
                    // It's a hostname - check if we have an IP mapping for validation
                    resolvedNodes.push(node);
                }
            });
            
            // Deduplicate resolved nodes (in case same hostname was added multiple times)
            clusterNodes = Array.from(new Set(resolvedNodes)).sort();
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
        
        const analysisData = {
            fileCount: this.files.length,
            directories: Array.from(this.directories).sort(),
            fileTypes: this.fileTypes,
            files: this.files.slice(0, 50), // Return first 50 files
            totalParsed: this.totalParsed,
            // Nested compression statistics
            nestedGzipTotalCount: this.nestedGzipTotalCount,
            nestedGzipTotalCompressedBytes: this.nestedGzipTotalCompressedBytes,
            nestedGzipCount: this.nestedGzipCount,
            nestedGzipCompressedBytes: this.nestedGzipCompressedBytes,
            nestedGzipDecompressedBytes: this.nestedGzipDecompressedBytes,
            // SCC report information
            isSCCReport: this.isSCCReport,
            sccReportName: this.sccReportName,
            // Rule-based analysis results
            azureVMProperties: this.mergeAzureVMProperties(),
            osRelease: this.analysisResults.osRelease || this.analysisResults.sysinfo || this.analysisResults.basicEnvironment || null,
            clusterNodes: clusterNodes,
            nodeToIpMap: nodeToIpMap,
            hostsFile: hostsData,
            liveMigration: liveMigrationData,
            kernelReboots: kernelRebootsData,
            oomKiller: oomKillerData,
            xfsErrors: xfsErrorsData,
            corosyncConfig: corosyncData,
            corosyncStatus: this.analysisResults.corosyncStatus || null,
            clusterStatus: this.analysisResults.clusterStatus || null,
            clusterDaemonStatus: this.analysisResults.clusterDaemonStatus || null,
            azureScheduledEvents: this.analysisResults.azureScheduledEvents || null,
            distroPackages: distroPackagesData,
            pacemakerResources: pacemakerResourcesData,
            fencingConfig: fencingConfigData,
            clusterEvents: clusterEventsData,
            antivirus: antivirusResults,
            clusterServices: clusterServicesResults,
            kernelTuning: this.analysisResults.kernelTuning || null,
            hugePages: this.analysisResults.hugePages || null,
            timeSync: this.analysisResults.timeSync || null,
            ptpClockSource: this.analysisResults.ptpClockSource || null,
            timeSyncService: this.analysisResults.timeSyncService || null,
            timedatectl: this.analysisResults.timedatectl || null,
            ptpDevice: this.analysisResults.ptpDevice || null,
            chronyTracking: this.analysisResults.chronyTracking || null,
            chronyMakestep: this.analysisResults.chronyMakestep || null,
            lvmConfig: this.analysisResults.lvmConfig || null,
            raidConfig: this.analysisResults.raidConfig || null,
            btrfsConfig: this.analysisResults.btrfsConfig || null,
            fstab: this.analysisResults.fstab || null,
            blockDevices: this.analysisResults.blockDevices || null,
            fstabAnalysis: this.analysisResults.fstabAnalysis || null,
            storageCorrelation: this.correlateFstabWithBlockDevices(),
            nvmeList: this.analysisResults.nvmeList || null,
            involfltVersion: this.analysisResults.involfltVersion || null,
            involfltKernelVersion: this.analysisResults.involfltKernelVersion || null,
            emergencyMode: this.analysisResults.emergencyMode || null,
            sshService: this.analysisResults.sshService || null,
            automation: this.analysisResults.automation || null,
            rhuiConfig: this.analysisResults.rhuiConfig || null,
            eusVersionLock: this.analysisResults.eusVersionLock || null,
            rhelRhuiCheck: this.analysisResults.rhelRhuiCheck || null,
            cryptoPolicies: this.analysisResults.cryptoPolicies || null,
            rhuiErrors: this.analysisResults.rhuiErrors || null,
            leappReport: this.analysisResults.leappReport || null,
            leappLog: this.analysisResults.leappLog || null,
            usedPaxFormat: this.usedPaxFormat || false,  // Flag if PAX format was detected
            // Cross-validation results
            nodesInHosts: nodesInHosts,
            nodesMissingFromHosts: nodesMissingFromHosts
        };
        
        // Enrich huge pages data with sysctl parameters from kernelTuning if available
        // This avoids duplicate parsing of sysctl output
        if (analysisData.hugePages && analysisData.kernelTuning && analysisData.kernelTuning.parameters) {
            const params = analysisData.kernelTuning.parameters;
            const hp = analysisData.hugePages;
            // Extract huge pages sysctl parameters from already-parsed kernel tuning data
            if (params['vm.nr_hugepages'] !== undefined && hp.sysctlParams.nr_hugepages === undefined) {
                hp.sysctlParams.nr_hugepages = parseInt(params['vm.nr_hugepages'], 10);
                hp.found = true;
            }
            if (params['vm.nr_overcommit_hugepages'] !== undefined && hp.sysctlParams.nr_overcommit_hugepages === undefined) {
                hp.sysctlParams.nr_overcommit_hugepages = parseInt(params['vm.nr_overcommit_hugepages'], 10);
                hp.found = true;
            }
            if (params['vm.hugetlb_shm_group'] !== undefined && hp.sysctlParams.hugetlb_shm_group === undefined) {
                hp.sysctlParams.hugetlb_shm_group = parseInt(params['vm.hugetlb_shm_group'], 10);
                hp.found = true;
            }
        }
        // Add SAP HANA huge pages recommendation if huge pages are not configured
        if (analysisData.hugePages && analysisData.hugePages.found) {
            const hp = analysisData.hugePages;
            // Check if static huge pages are configured (from sysctl or meminfo)
            const nrHugepages = hp.sysctlParams.nr_hugepages !== undefined ? hp.sysctlParams.nr_hugepages : 
                               (hp.staticHugePages.total !== undefined ? hp.staticHugePages.total : 0);
            // For SAP HANA workloads, check if huge pages are configured
            if (nrHugepages === 0 && !hp.recommendations.some(r => r.type === 'sap_hugepages')) {
                hp.recommendations.push({
                    type: 'sap_hugepages',
                    message: 'No static huge pages configured. For SAP HANA workloads, huge pages should be configured to improve performance and prevent memory fragmentation.',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/dbms-guide-general#linux-kernel-settings'
                });
                hp.hasRecommendations = true;
            }
        }
        
        // Post-processing: Regenerate azureScheduledEvents warnings after merging data from multiple files
        if (analysisData.azureScheduledEvents && analysisData.azureScheduledEvents.found) {
            const ase = analysisData.azureScheduledEvents;
            // Clear existing warnings and regenerate based on merged data
            ase.warnings = [];
            
            // Case 1: Resources are stopped while nodes are online AND health-azure is not configured
            if (ase.stoppedResources.length > 0 && ase.onlineNodes.length > 0) {
                if (!ase.healthAzureConfigured && !ase.healthAzureResource) {
                    ase.warnings.push({
                        severity: 'error',
                        type: 'health_azure_not_configured',
                        message: `${ase.stoppedResources.length} cluster resource(s) are stopped while ${ase.onlineNodes.length} node(s) are online. Azure Scheduled Events (health-azure) is NOT configured.`,
                        recommendation: 'Configure Azure Scheduled Events by creating the health-azure-events resource and setting #health-azure attribute on all nodes. See: https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker#configure-pacemaker-for-azure-scheduled-events',
                        stoppedResources: ase.stoppedResources,
                        onlineNodes: ase.onlineNodes
                    });
                }
                
                // Case 2: node-health-strategy is set to custom but health-azure attribute is missing
                if (ase.nodeHealthStrategy === 'custom' && !ase.healthAzureConfigured) {
                    ase.warnings.push({
                        severity: 'error',
                        type: 'health_azure_attribute_missing',
                        message: 'node-health-strategy is set to "custom" but #health-azure attribute is not configured on nodes. Resources cannot be scheduled.',
                        recommendation: 'Initialize the #health-azure attribute on all nodes: sudo crm_attribute --node <node-name> --name \'#health-azure\' --update 0',
                        onlineNodes: ase.onlineNodes
                    });
                }
            }
            
            // Case 3: Some nodes have health-azure configured but not all
            if (ase.nodesWithHealthAzure && ase.nodesWithHealthAzure.length > 0 && ase.onlineNodes.length > ase.nodesWithHealthAzure.length) {
                const nodesWithAttr = ase.nodesWithHealthAzure.map(n => n.node);
                const nodesMissing = ase.onlineNodes.filter(n => !nodesWithAttr.includes(n));
                if (nodesMissing.length > 0) {
                    ase.nodesWithoutHealthAzure = nodesMissing;
                    ase.warnings.push({
                        severity: 'warning',
                        type: 'health_azure_partial',
                        message: `#health-azure attribute is configured on some nodes but missing on: ${nodesMissing.join(', ')}`,
                        recommendation: 'Set the #health-azure attribute on all cluster nodes for consistent behavior.',
                        nodesMissing: nodesMissing
                    });
                }
            }
            
            debugLog('[TAR Parser] azureScheduledEvents post-processing: warnings regenerated:', ase.warnings.length);
        }
        
        return analysisData;
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
        const mode = e.data.enabled;
        // Update DEBUG_CONFIG based on the debug mode
        if (mode === 'cluster') {
            DEBUG_CONFIG.cluster = true;
            DEBUG_CONFIG.worker = true;
            console.log('[Worker] Cluster debug mode enabled');
        } else if (mode === true || mode === 'on') {
            // Enable all debug flags
            Object.keys(DEBUG_CONFIG).forEach(key => DEBUG_CONFIG[key] = true);
            console.log('[Worker] All debug modes enabled');
        } else if (mode === 'app') {
            DEBUG_CONFIG.azure = true;
            DEBUG_CONFIG.services = true;
            DEBUG_CONFIG.worker = true;
            console.log('[Worker] App debug mode enabled');
        } else {
            // Disable all debug flags
            Object.keys(DEBUG_CONFIG).forEach(key => DEBUG_CONFIG[key] = false);
            console.log('[Worker] Debug mode disabled');
        }
        return;
    }
    
    // Handle plain text console log analysis (no TAR, no compression)
    if (e.data.cmd === 'analyze_plaintext') {
        console.log('[Worker] Received analyze_plaintext command');
        try {
            const { textData, filename } = e.data;
            console.log(`[Worker] Starting plain text analysis: ${filename}, ${textData.byteLength} bytes`);
            debugLog(`[Worker] Starting plain text analysis: ${filename}, ${textData.byteLength} bytes`);
            
            // Convert to text
            console.log('[Worker] Converting to text...');
            const decoder = new TextDecoder('utf-8');
            const textContent = decoder.decode(new Uint8Array(textData));
            console.log('[Worker] Text decoded, length:', textContent.length);
            
            // Create a synthetic analysis structure matching TAR analysis format
            console.log('[Worker] Creating analysis structure...');
            const analysis = {
                reportType: 'console-log',
                reportName: filename,
                fileCount: 1,
                totalSize: textData.byteLength,
                // Add empty arrays for formatter compatibility
                directories: [],
                files: [filename],
                fileTypes: { 'log': 1 },
                // Initialize event arrays to avoid undefined errors in formatter
                oomKiller: { found: false, events: [] },
                kernelReboots: { found: false, events: [] },
                liveMigration: { found: false, events: [] },
                xfsErrors: { found: false, events: [] },
                emergencyMode: { found: false, events: [] },
                sshService: { found: false, events: [] },
                automation: { found: false, events: [] }
            };
            console.log('[Worker] Analysis structure created');
            
            // Run event detection parsers that work on kernel logs
            console.log('[Worker] Preparing event parsers...');
            const eventParsers = {
                oomKiller: SCC_RULES.oomKiller,
                kernelReboots: SCC_RULES.kernelReboots,
                liveMigration: SCC_RULES.liveMigration,
                xfsErrors: SCC_RULES.xfsErrors,
                emergencyMode: SCC_RULES.emergencyMode,
                sshService: SCC_RULES.sshService,
                automation: SCC_RULES.automation
            };
            console.log('[Worker] Event parsers ready, starting analysis...');
            
            let eventsFound = 0;
            
            for (const [parserName, parser] of Object.entries(eventParsers)) {
                console.log(`[Worker] Checking parser: ${parserName}`);
                if (parser && parser.parse) {
                    console.log(`[Worker] Running parser: ${parserName}`);
                    debugLog(`[Worker] Running parser: ${parserName}`);
                    const result = parser.parse(textContent, filename);
                    console.log(`[Worker] Parser ${parserName} completed`);
                    
                    if (result) {
                        // Add sourceFile to all events for plain text logs
                        if (result.events && Array.isArray(result.events)) {
                            result.events.forEach(event => {
                                if (!event.sourceFile) {
                                    event.sourceFile = filename;
                                }
                            });
                        }
                        
                        // Always store the result, even if found=false
                        analysis[parserName] = result;
                        
                        if (result.found && result.events) {
                            eventsFound += result.events.length;
                            debugLog(`[Worker] ${parserName}: found ${result.events.length} events`);
                        }
                    }
                }
            }
            
            debugLog(`[Worker] Plain text analysis complete: ${eventsFound} total events`);
            
            // Validate analysis object before sending
            debugLog(`[Worker] Analysis object keys:`, Object.keys(analysis));
            
            try {
                // Test if the analysis object can be serialized
                JSON.stringify(analysis);
                debugLog(`[Worker] Analysis object successfully serialized`);
            } catch (serErr) {
                console.error('[Worker] Analysis serialization error:', serErr);
                self.postMessage({ error: 'Failed to serialize analysis: ' + serErr.message });
                return;
            }
            
            self.postMessage({
                success: true,
                analysis: analysis,
                progress: 100
            });
            
        } catch (err) {
            console.error('[Worker] Plain text analysis error:', err);
            console.error('[Worker] Error stack:', err.stack);
            self.postMessage({ error: 'Plain text analysis failed: ' + err.message + '\nStack: ' + err.stack });
        }
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
