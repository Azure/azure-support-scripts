/**
 * @module parsers/packages
 * @description Installed-package detection and Azure package version validation.
 *
 * ### distroPackagesParser
 *
 * Parses package listings from RPM, DEB, DNF, and YUM output files.
 * Handles three distinct format families:
 *
 * | Format | Source files | Behaviour |
 * |--------|-------------|-----------|
 * | dpkg   | `dpkg_-l` | Returns raw content with header lines stripped. |
 * | dnf/yum | `dnf_list_installed`, `yum_list_installed` | Returns filtered raw content. |
 * | rpm    | `rpm.txt` (SCC), `installed-rpms`, `package-data` (SOS) | Validates Azure-required packages against minimum version rules. |
 * | zypper history | `var/log/zypp/history` (InspectIaaSDisk) | Extracts latest install of each package; validates Azure-critical packages. |
 * | dnf/yum log | `var/log/dnf.log`, `var/log/yum.log` (InspectIaaSDisk) | Extracts installed packages from log; validates Azure-critical packages. |
 *
 * For RPM listings the parser checks these Azure-critical packages:
 *
 * | Package | Requirement |
 * |---------|-------------|
 * | fence-agents | >= 4.4 |
 * | python3-azure-mgmt-compute | >= 17.0 |
 * | python3-azure-identity | >= 1.0 |
 * | cloud-netconfig-azure | >= 1.3 |
 * | resource-agents | >= 4.3 |
 * | python3-azure-core | < 1.9 or > 1.22 (problematic range) |
 *
 * Returns:
 * - RPM validated: `{ found, packages, warnings }`
 * - Raw listings: `{ found, isDpkg|isRpmRaw, rawContent, filename, packageCount }`
 *
 * Loaded by the Web Worker via `importScripts()`.
 *
 * @see {@link module:worker} for registration in SCC_RULES
 */

// Debug logging - checks global DEBUG_CONFIG from worker.js
function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.packages) {
        console.log('[packages.js]', ...args);
    }
}

// Define the distroPackages parser for SCC_RULES
const distroPackagesParser = {
    // Target file patterns
    // supportconfig: */rpm.txt
    // sosreport (RHEL/SLES): */installed-rpms or */sos_commands/rpm/package-data or */sos_commands/dnf/dnf_list_installed or */sos_commands/yum/yum_list_installed
    // sosreport (Debian/Ubuntu): */sos_commands/dpkg/dpkg_-l (installed-debs is a symlink)
    // InspectIaaSDisk (SUSE): device_0/var/log/zypp/history
    // InspectIaaSDisk (RHEL): device_0/var/log/dnf.log, device_0/var/log/yum.log
    filePattern: /\/(rpm\.txt|installed-rpms|package-data|dpkg_-l|dnf[_-]list[_-]installed|yum[_-]list[_-]installed|var\/log\/zypp\/history|var\/log\/(?:dnf|yum)\.log)$/,
    
    // Parse function receives package list content
    // Validates Azure-required packages with specific version requirements
    parse: function(content, filename, _lines) {
        const lines = _lines || content.split('\n');
        
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
        
        // If this is a zypper history file (InspectIaaSDisk SUSE), parse install records
        if (filename && /var\/log\/zypp\/history$/.test(filename)) {
            debugLog('[distroPackages parser] Detected zypper history format');
            return this.parseZypperHistory(content, filename, lines);
        }

        // If this is a dnf.log or yum.log (InspectIaaSDisk RHEL), parse install records
        if (filename && /var\/log\/(dnf|yum)\.log$/.test(filename)) {
            debugLog('[distroPackages parser] Detected dnf/yum log format');
            return this.parseDnfYumLog(content, filename, lines);
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
        
        // FIPS-related package detection
        // These packages indicate FIPS mode is configured on the system
        const fipsPackagePatterns = [
            /^dracut-fips-/,
            /^fipscheck-/,
            /^fips-mode-setup-/,
            /^crypto-policies-/
        ];
        const fipsPackages = [];

        // Parse RPM listing
        // Common RPM formats:
        // - "package-name-1.2.3-4.el8.x86_64"
        // - "package-name-1.2.3-4.noarch"
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;

            // Check for FIPS-related packages
            for (const fipsPattern of fipsPackagePatterns) {
                if (fipsPattern.test(trimmed)) {
                    // Extract RPM token (before whitespace) then name and version
                    // installed-rpms format: "dracut-fips-049-233.git20240115.el8.x86_64 Wed Jan 17 00:00:00 2024"
                    const rpmToken = trimmed.split(/\s+/)[0];
                    const fm = rpmToken.match(/^([a-z][a-z0-9_-]*?)-([\d]+[\d.]*\S*?)(?:\.[a-z][a-z0-9_]*)?$/i);
                    if (fm) {
                        fipsPackages.push({ name: fm[1], version: fm[2] });
                        debugLog('[distroPackages parser] Found FIPS package:', fm[1], fm[2]);
                    }
                    break;
                }
            }
            
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
        
        const hasDracutFips = fipsPackages.some(p => p.name === 'dracut-fips');
        debugLog('[distroPackages parser] FIPS packages found:', fipsPackages.length, 'dracut-fips:', hasDracutFips);

        return {
            found: true,
            packages: foundPackages,
            warnings: warnings,
            fipsPackages: fipsPackages,
            hasDracutFips: hasDracutFips
        };
    },

    /**
     * Validate a name→version package map against Azure-critical requirements.
     * Uses prefix matching for names (e.g. 'fence-agents' matches 'fence-agents-azure-arm')
     * and extracts the leading numeric version (e.g. '4.12.1+git...' → '4.12.1').
     */
    _validatePackageMap: function(packageMap) {
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

        for (const [reqName, requirements] of Object.entries(requiredPackages)) {
            // Find matching package: exact match first, then prefix match
            let matchedVersion = null;
            for (const [pkgName, info] of Object.entries(packageMap)) {
                if (pkgName === reqName || pkgName.startsWith(reqName + '-')) {
                    // Extract leading numeric version: "4.12.1+git..." → "4.12.1"
                    const vm = info.version.match(/^(\d+\.\d+(?:\.\d+)?)/);
                    if (vm) {
                        matchedVersion = vm[1];
                        foundPackages[pkgName] = matchedVersion;
                        debugLog('[distroPackages parser] Matched', reqName, '→', pkgName, 'version', matchedVersion);
                        break;
                    }
                }
            }

            if (!matchedVersion) {
                warnings.push({
                    package: reqName,
                    expected: requirements.operator === 'gte' ? `>= ${requirements.version}` : `< ${requirements.minVersion} or > ${requirements.maxVersion}`,
                    actual: 'not found',
                    severity: 'error',
                    message: `Required package ${reqName} not found in package list`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                });
                continue;
            }

            if (requirements.operator === 'gte') {
                if (!SCC_RULES.compareVersion(matchedVersion, requirements.version, 'gte')) {
                    warnings.push({
                        package: reqName,
                        expected: `>= ${requirements.version}`,
                        actual: matchedVersion,
                        severity: 'error',
                        message: `Package ${reqName} version is ${matchedVersion}, but should be >= ${requirements.version} for Azure environments`,
                        documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                    });
                }
            } else if (requirements.operator === 'range') {
                if (SCC_RULES.compareVersion(matchedVersion, requirements.minVersion, 'gte') &&
                    SCC_RULES.compareVersion(matchedVersion, requirements.maxVersion, 'lte')) {
                    warnings.push({
                        package: reqName,
                        expected: `< ${requirements.minVersion} or > ${requirements.maxVersion}`,
                        actual: matchedVersion,
                        severity: 'error',
                        message: `Package ${reqName} version is ${matchedVersion}, but should be lower than ${requirements.minVersion} or higher than ${requirements.maxVersion} for Azure environments`,
                        documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker'
                    });
                }
            }
        }

        // FIPS package detection in the package map
        const fipsPackageNames = ['dracut-fips', 'fipscheck', 'fips-mode-setup', 'crypto-policies'];
        const fipsPackages = [];
        for (const [pkgName, info] of Object.entries(packageMap)) {
            if (fipsPackageNames.some(fp => pkgName === fp || pkgName.startsWith(fp + '-'))) {
                fipsPackages.push({ name: pkgName, version: info.version });
            }
        }
        const hasDracutFips = fipsPackages.some(p => p.name === 'dracut-fips' || p.name.startsWith('dracut-fips-'));

        return { packages: foundPackages, warnings, fipsPackages, hasDracutFips };
    },

    /**
     * Parse zypper history (/var/log/zypp/history) from InspectIaaSDisk.
     * Format: date|action|name|version|arch|user|repo|checksum|hash
     * Actions: install, remove, radd, command
     * Keeps the latest install of each package, then validates Azure-critical ones.
     */
    parseZypperHistory: function(content, filename, lines) {
        const packageMap = {};  // name -> { version, date }
        let installCount = 0;

        for (const line of lines) {
            if (line.startsWith('#') || !line.includes('|')) continue;
            const parts = line.split('|');
            if (parts.length < 4) continue;
            const action = parts[1].trim();
            if (action !== 'install') continue;
            const name = parts[2].trim();
            const version = parts[3].trim();
            const date = parts[0].trim();
            if (!name || !version) continue;
            // Keep latest install (zypper history is chronological)
            packageMap[name] = { version, date };
            installCount++;
        }

        debugLog('[distroPackages parser] Zypper history:', installCount, 'install records,', Object.keys(packageMap).length, 'unique packages');

        // Validate Azure-critical packages directly from the package map
        const validationResult = this._validatePackageMap(packageMap);

        // Build raw content showing latest installed packages (sorted by name)
        const sortedPkgs = Object.entries(packageMap).sort((a, b) => a[0].localeCompare(b[0]));
        const rawLines = sortedPkgs.map(([name, info]) => `${name}|${info.version}|${info.date}`);
        const rawContent = rawLines.join('\n');

        return {
            found: true,
            isZypperHistory: true,
            isRpmRaw: true,
            rawContent: rawContent,
            filename: filename,
            packageCount: sortedPkgs.length,
            packages: validationResult.packages || {},
            warnings: validationResult.warnings || [],
            fipsPackages: validationResult.fipsPackages || [],
            hasDracutFips: validationResult.hasDracutFips || false
        };
    },

    /**
     * Parse /var/log/dnf.log or /var/log/yum.log from InspectIaaSDisk.
     * dnf.log format: "date time SUBDOC action: pkg-name-version.arch"
     * yum.log format: "Mon DD HH:MM:SS action: pkg-name-version.arch"
     * Extracts installed packages and validates Azure-critical ones.
     */
    parseDnfYumLog: function(content, filename, lines) {
        const packageMap = {};  // name -> { version, date }
        let installCount = 0;

        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;

            // dnf.log: "2024-01-15T10:30:00+0000 SUBDOC Installed: package-1.2.3-4.el8.x86_64"
            // yum.log: "Jan 15 10:30:00 Installed: package-1.2.3-4.el8.x86_64"
            const m = trimmed.match(/(?:^\d{4}-\d{2}-\d{2}|^[A-Z][a-z]{2}\s+\d+).*?Installed:\s*(.+)/i);
            if (!m) continue;

            const pkgStr = m[1].trim();
            // Extract name and version from RPM-style: name-version-release.arch
            const pm = pkgStr.match(/^(.+?)-(\d+[\d.]*\S*?)(?:\.[a-z][a-z0-9_]*)?$/i);
            if (!pm) continue;

            const name = pm[1];
            const version = pm[2];
            const date = trimmed.substring(0, 19);
            packageMap[name] = { version, date };
            installCount++;
        }

        debugLog('[distroPackages parser] dnf/yum log:', installCount, 'install records,', Object.keys(packageMap).length, 'unique packages');

        if (Object.keys(packageMap).length === 0) {
            return { found: false };
        }

        // Validate Azure-critical packages directly from the package map
        const validationResult = this._validatePackageMap(packageMap);

        const sortedPkgs = Object.entries(packageMap).sort((a, b) => a[0].localeCompare(b[0]));
        const rawLines = sortedPkgs.map(([name, info]) => `${name}|${info.version}|${info.date}`);
        const rawContent = rawLines.join('\n');

        return {
            found: true,
            isDnfYumLog: true,
            isRpmRaw: true,
            rawContent: rawContent,
            filename: filename,
            packageCount: sortedPkgs.length,
            packages: validationResult.packages || {},
            warnings: validationResult.warnings || [],
            fipsPackages: validationResult.fipsPackages || [],
            hasDracutFips: validationResult.hasDracutFips || false
        };
    }
};

// Note: This parser is manually assigned to SCC_RULES.distroPackages in the worker file
// after SCC_RULES is defined, to avoid "SCC_RULES is not defined" errors during loading.
