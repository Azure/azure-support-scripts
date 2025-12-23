// Unix System Parsers
// Extracts OS release information, basic environment, filesystem configuration, and kernel tuning

// Debug configuration - set to true to enable debug logging
const DEBUG_UNIX = false;

function debugLog(...args) {
    if (DEBUG_UNIX) {
        console.log('[unix.js]', ...args);
    }
}

/**
 * Parser: basicEnvironment
 * Extracts distribution information from basic-environment.txt (supportconfig format)
 * Provides fallback OS identification with SAP and EPIC product detection
 */
const basicEnvironmentParser = {
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
};

/**
 * Parser: osRelease
 * Extracts OS release information from /etc/os-release, /usr/lib/os-release, or sysinfo.txt
 * Provides comprehensive distribution identification across different report formats
 */
const osReleaseParser = {
    // Match os-release files from various report types:
    // - /usr/lib/os-release (sosreport - real file, not the /etc symlink)
    // - /etc/os-release (crm_report)
    // - sysinfo.txt (supportconfig SUSE)
    filePattern: /\/usr\/lib\/os-release$|\/etc\/os-release$|\/sysinfo\.txt$/,
    
    parse: function(content, filename) {
        debugLog('[osRelease parser] Analyzing OS release information in:', filename);
        
        // Check if this is sysinfo.txt (supportconfig SUSE format)
        if (filename.endsWith('sysinfo.txt')) {
            return this.parseSysinfo(content, filename);
        }
        
        // Parse os-release format (sosreport, crm_report)
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
    },
    
    // Helper function to parse sysinfo.txt (SUSE supportconfig format)
    parseSysinfo: function(content, filename) {
        debugLog('[osRelease parser] Parsing sysinfo.txt format');
        const lines = content.split('\n');
        let distribution = null;

        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;

            // Look for lines like: Distribution: SUSE Linux Enterprise Server 12 SP3
            const distMatch = trimmed.match(/^Distribution:\s*(.+)$/i);
            if (distMatch) {
                distribution = distMatch[1].trim();
                debugLog('[osRelease parser] Found Distribution:', distribution);
                break;
            }
        }

        if (!distribution) {
            debugLog('[osRelease parser] No Distribution line found in sysinfo.txt');
            return { found: false };
        }

        return {
            found: true,
            name: null,
            version: null,
            versionId: null,
            prettyName: distribution,
            majorVersion: null,
            minorVersion: null
        };
    }
};

/**
 * Parser: fstab
 * Extracts filesystem table from /etc/fstab or SCC's fs-diskio.txt
 * Provides mount point configuration and filesystem information
 */
const fstabParser = {
    filePattern: /\/etc\/fstab$|\/fs-diskio\.txt$/,
    
    parse: function(content, filename) {
        debugLog('[fstab parser] Analyzing fstab in:', filename);
        
        // If this is fs-diskio.txt from SCC, extract just the fstab section
        if (filename.includes('fs-diskio.txt')) {
            debugLog('[fstab parser] Extracting fstab from SCC fs-diskio.txt');
            return this.extractFstabFromSCC(content, filename);
        }
        
        return SCC_RULES.extractRawFile(content, filename);
    },
    
    // Helper to extract fstab section from SCC's fs-diskio.txt
    extractFstabFromSCC: function(content, filename) {
        const lines = content.split('\n');
        let fstabContent = [];
        let inFstabSection = false;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Start of fstab section
            if (line.includes('# /etc/fstab')) {
                inFstabSection = true;
                continue;
            }
            
            // End of fstab section (empty line or next section marker)
            if (inFstabSection && (line.trim() === '' || line.startsWith('#=='))) {
                break;
            }
            
            // Collect fstab lines
            if (inFstabSection) {
                fstabContent.push(line);
            }
        }
        
        if (fstabContent.length === 0) {
            debugLog('[fstab parser] No fstab section found in fs-diskio.txt');
            return { found: false };
        }
        
        const extractedFstab = fstabContent.join('\n');
        debugLog('[fstab parser] Extracted', fstabContent.length, 'lines from fstab section');
        
        return {
            found: true,
            content: extractedFstab,
            filename: filename,
            source: 'SCC fs-diskio.txt'
        };
    }
};
const kernelTuningParser = {
    filePattern: /sos_commands\/kernel\/sysctl_-a$|\/env\.txt$/,
    
    parse: function(content, filename) {
        debugLog('[kernelTuning parser] Analyzing kernel parameters in:', filename);
        
        let sysctlContent = content;
        
        // If this is SCC's env.txt, extract just the sysctl section
        if (filename.includes('env.txt')) {
            debugLog('[kernelTuning parser] Extracting sysctl from SCC env.txt');
            
            // Extract content between "# /sbin/sysctl -a" and next "#==[ Command ]" marker
            const lines = content.split('\n');
            const extractedLines = [];
            let inSection = false;
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                
                // Start collecting after finding the marker
                if (line.includes('# /sbin/sysctl -a')) {
                    inSection = true;
                    continue; // Skip the marker line itself
                }
                
                // Stop at next section marker
                if (inSection && line.trim().startsWith('#==[ Command ]')) {
                    break;
                }
                
                // Stop at empty line followed by section marker
                if (inSection && line.trim() === '' && i + 1 < lines.length && lines[i + 1].trim().startsWith('#==')) {
                    break;
                }
                
                // Collect lines while in section
                if (inSection) {
                    extractedLines.push(line);
                }
            }
            
            if (extractedLines.length === 0) {
                debugLog('[kernelTuning parser] Sysctl section not found in env.txt');
                return { found: false };
            }
            
            sysctlContent = extractedLines.join('\n');
            debugLog('[kernelTuning parser] Extracted', extractedLines.length, 'lines from sysctl section');
        }
        
        // Parse sysctl output using utility function
        const parsed = SCC_RULES.parseKeyValueFile(sysctlContent, {
            pattern: /^([^\s=]+)\s*=\s*(.+)$/,  // sysctl uses "key = value" format
            skipComments: true,
            skipEmpty: true
        });
        
        const parameters = parsed.parameters;
        const warnings = [];
        const azureNetworkWarnings = [];
        
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
        
        // Azure Network optimization parameters
        // Documentation: https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-optimize-network-bandwidth#linux-virtual-machines
        const azureNetworkParams = {
            'net.ipv4.tcp_mem': '4096\t87380\t67108864',
            'net.ipv4.udp_mem': '4096\t87380\t33554432',
            'net.ipv4.tcp_rmem': '4096\t87380\t67108864',
            'net.ipv4.tcp_wmem': '4096\t65536\t67108864',
            'net.core.rmem_default': '33554432',
            'net.core.wmem_default': '33554432',
            'net.ipv4.udp_wmem_min': '16384',
            'net.ipv4.udp_rmem_min': '16384',
            'net.core.wmem_max': '134217728',
            'net.core.rmem_max': '134217728',
            'net.core.busy_poll': '50',
            'net.core.busy_read': '50',
            'net.ipv4.tcp_congestion_control': 'bbr'
        };
        
        const azureNetworkDocUrl = 'https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-optimize-network-bandwidth#linux-virtual-machines';
        
        // Check Azure Network optimization parameters
        for (const [param, expectedValue] of Object.entries(azureNetworkParams)) {
            if (parameters[param]) {
                const actualValue = parameters[param];
                // Normalize whitespace: replace tabs/multiple spaces with single tab for comparison
                const normalizedActual = actualValue.replace(/\s+/g, '\t');
                const normalizedExpected = expectedValue.replace(/\s+/g, '\t');
                
                if (normalizedActual !== normalizedExpected) {
                    azureNetworkWarnings.push({
                        parameter: param,
                        expected: expectedValue,
                        actual: actualValue,
                        documentationUrl: azureNetworkDocUrl
                    });
                    debugLog(`[kernelTuning parser] Azure Network Warning: ${param} = ${actualValue}, expected ${expectedValue}`);
                } else {
                    debugLog(`[kernelTuning parser] Azure Network OK: ${param} = ${actualValue}`);
                }
            }
        }
        
        // Optional Network Tuning parameters (informational only)
        const optionalNetworkParams = {
            'net.ipv4.tcp_timestamps': '1',
            'net.ipv4.tcp_tw_reuse': '1',
            'net.ipv4.ip_local_port_range': '1024\t65535',
            'net.core.netdev_budget': '1000',
            'net.core.optmem_max': '65535',
            'net.ipv4.tcp_frto': '0',
            'net.core.somaxconn': '32768',
            'net.core.netdev_max_backlog': '32768',
            'net.core.dev_weight': '64',
            'net.core.default_qdisc': 'fq'
        };
        
        const optionalNetworkInfo = [];
        
        // Check optional parameters (informational, not warnings)
        for (const [param, expectedValue] of Object.entries(optionalNetworkParams)) {
            if (parameters[param]) {
                const actualValue = parameters[param];
                // Normalize whitespace: replace tabs/multiple spaces with single tab for comparison
                const normalizedActual = actualValue.replace(/\s+/g, '\t');
                const normalizedExpected = expectedValue.replace(/\s+/g, '\t');
                
                optionalNetworkInfo.push({
                    parameter: param,
                    expected: expectedValue,
                    actual: actualValue,
                    matches: normalizedActual === normalizedExpected,
                    documentationUrl: azureNetworkDocUrl
                });
                
                if (normalizedActual === normalizedExpected) {
                    debugLog(`[kernelTuning parser] Optional Network OK: ${param} = ${actualValue}`);
                } else {
                    debugLog(`[kernelTuning parser] Optional Network Info: ${param} = ${actualValue}, recommended ${expectedValue}`);
                }
            }
        }
        
        return {
            found: true,
            parameters: parameters,
            warnings: warnings,
            hasWarnings: warnings.length > 0,
            azureNetworkWarnings: azureNetworkWarnings,
            hasAzureNetworkWarnings: azureNetworkWarnings.length > 0,
            azureNetworkTuned: azureNetworkWarnings.length === 0 && Object.keys(azureNetworkParams).every(p => parameters[p]),
            optionalNetworkInfo: optionalNetworkInfo,
            hasOptionalNetworkInfo: optionalNetworkInfo.length > 0
        };
    }
};
