// Distribution and Environment Metadata Parsers
// Extracts OS release information, basic environment, and distribution metadata

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
