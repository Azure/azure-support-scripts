// Package detection parser (RPM/DEB/DNF/YUM)
// This file is loaded by liblzma-streaming-worker.js via importScripts()

// Define the distroPackages parser for SCC_RULES
const distroPackagesParser = {
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
};

// Note: This parser is manually assigned to SCC_RULES.distroPackages in the worker file
// after SCC_RULES is defined, to avoid "SCC_RULES is not defined" errors during loading.
