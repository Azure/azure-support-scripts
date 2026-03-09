/**
 * @module parsers/unix
 * @description Unix System Parsers for RCA Tool
 *
 * Provides 20 parsers covering core Linux system information: OS identity,
 * filesystem layout, kernel tuning, time synchronisation (Azure PTP), RHUI
 * repository health, crypto policies, Leapp in-place upgrade analysis,
 * and InspectIaaSDisk disk inspection results.
 *
 * ### Parser Inventory
 *
 * #### OS Identity
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `basicEnvironmentParser` | `basic-environment.txt` | Fallback OS identification from supportconfig; detects SAP and EPIC products |
 * | `osReleaseParser` | `os-release`, `sysinfo.txt`, `redhat-release`, `centos-release`, `SuSE-release`, `system-release` | Primary OS identification via `/etc/os-release` fields or distro release files; detects SLES, RHEL, Ubuntu, Oracle, Alma, Rocky |
 *
 * #### Filesystem
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `fstabParser` | `etc/fstab`, `fs-diskio.txt` | Extracts `/etc/fstab` entries with mount options; used alongside storage/fstabAnalysisParser for nofail validation |
 *
 * #### InspectIaaSDisk
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `inspectDiskResultsParser` | `results.txt` | Parses InspectIaaSDisk diagnostic output: request info, filesystem status, OS metadata, mount points, and mount failures |
 *
 * #### Kernel Tuning
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `kernelTuningParser` | `env.txt`, `sysctl.conf`, `sysctl.d/*.conf`, `sysctl_-a` | Parses sysctl parameters from runtime output or static config files; flags SAP HANA and Azure network tuning |
 * | `hugePagesParser` | `proc/meminfo`, `basic-environment.txt`, `memory.txt` | Reports HugePages allocation (total, free, size); flags when huge pages are in use |
 *
 * #### Time Synchronisation (Azure PTP)
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `timeSyncParser` | `env.txt`, `boot.txt`, `proc/` files | Detects hv_utils and PTP clock source modules; checks PHC index assignment |
 * | `ptpClockSourceParser` | `chrony.conf`, `ntp.conf`, `etc/chrony*`, `etc/ntp*` | Verifies chrony/NTP is configured with `refclock PHC /dev/ptp_hyperv` for Azure PTP |
 * | `timeSyncServiceParser` | `ntp.txt`, `chrony*`, `timekeeping.txt`, `systemd/` | Detects which time sync service (chrony/ntpd/systemd-timesyncd) is active and its configuration |
 * | `timedatectlParser` | `ntp.txt`, `timekeeping.txt`, `timedatectl` | Parses `timedatectl` output; checks NTP enabled/synchronised and configured NTP source |
 * | `ptpDeviceParser` | `env.txt`, `boot.txt`, `proc/`, `dev/` | Enumerates PTP devices; checks for `/dev/ptp_hyperv` symlink presence |
 * | `chronyTrackingParser` | `ntp.txt`, `timekeeping.txt`, `chronyc_tracking` | Parses `chronyc tracking` output; reports stratum, system time offset, leap status |
 * | `chronyMakestepParser` | `chrony.conf`, `etc/chrony*` | Checks if `makestep` is configured in chrony.conf for initial large time corrections |
 *
 * #### RHUI (Red Hat Update Infrastructure)
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `rhuiConfigParser` | `updates.txt`, `yum.repos.d/`, `plugin.conf.d/` | Detects Azure RHUI repositories (EUS, non-EUS, E4S, SAP) and dnf plugin configuration |
 * | `eusVersionLockParser` | `updates.txt`, `yum.conf`, `dnf.conf`, `releasever` | Reads `releasever` lock value used for EUS pinning |
 * | `rhelRhuiCheckParser` | `updates.txt`, `rhui/`, `rpm_-qa` | Checks RHUI client package installation, TLS certificate validity, content set entitlements |
 * | `rhuiErrorsParser` | `updates.txt`, `dnf.log`, `yum.log`, `messages` | Detects RHUI connectivity errors (TLS, DNS, 404, repo metadata) from package manager logs |
 *
 * #### Security
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `cryptoPoliciesParser` | `crypto-policies/config`, `updates.txt` | Reports active crypto policy (DEFAULT, LEGACY, FUTURE, FIPS) on RHEL 8+ |
 *
 * #### Leapp In-Place Upgrade
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `leappReportParser` | `leapp-report.txt`, `leapp-report.json` | Parses Leapp pre-upgrade/upgrade report; categorises findings by severity (high, medium, low, info) with remediation hints |
 * | `leappLogParser` | `leapp-upgrade.log`, `leapp.log` | Scans Leapp log for errors, inhibitors, and phase failures during upgrade execution |
 *
 * @see {@link module:worker} for registration in SCC_RULES
 */

// Debug logging - checks global DEBUG_CONFIG from worker.js
function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.unix) {
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

    parse: function(content, filename, _lines) {
        debugLog('[basicEnvironment parser] Analyzing basic-environment in:', filename);
        const lines = _lines || content.split('\n');
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
 * Extracts OS release information from /etc/os-release, /usr/lib/os-release,
 * sysinfo.txt, basic-environment.txt, or distro release files (/etc/redhat-release, etc.)
 * Provides comprehensive distribution identification across different report formats
 */
const osReleaseParser = {
    // Match os-release files from various report types:
    // - /usr/lib/os-release (sosreport - real file, not the /etc symlink)
    // - /etc/os-release (crm_report)
    // - sysinfo.txt (supportconfig SUSE - older format)
    // - basic-environment.txt (supportconfig SUSE - newer format)
    // - /etc/redhat-release, /etc/centos-release, /etc/SuSE-release, /etc/system-release (InspectIaaSDisk, bare systems)
    filePattern: /\/usr\/lib\/os-release$|\/etc\/os-release$|\/sysinfo\.txt$|\/basic-environment\.txt$|\/etc\/(redhat|centos|SuSE|system)-release$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[osRelease parser] Analyzing OS release information in:', filename);
        
        // Check if this is sysinfo.txt (supportconfig SUSE format)
        if (filename.endsWith('sysinfo.txt')) {
            return this.parseSysinfo(content, filename);
        }
        
        // Check if this is basic-environment.txt (supportconfig newer format)
        if (filename.endsWith('basic-environment.txt')) {
            return this.parseBasicEnvironment(content, filename);
        }
        
        // Check if this is a distro release file (redhat-release, centos-release, etc.)
        if (/\/(redhat|centos|SuSE|system)-release$/.test(filename)) {
            return this.parseDistroRelease(content, filename);
        }
        
        // Parse os-release format (sosreport, crm_report)
        const lines = _lines || content.split('\n');
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
        
        // Check for out-of-support distributions
        const eolWarnings = this.checkEolDistribution(name, majorVersion, prettyName);
        
        return {
            found: true,
            name: name,
            version: version,
            versionId: versionId,
            prettyName: prettyName,
            majorVersion: majorVersion,
            minorVersion: minorVersion,
            warnings: eolWarnings,
            hasWarnings: eolWarnings.length > 0,
            isEol: eolWarnings.length > 0
        };
    },
    
    // Check if the distribution is out of general support and may have inaccurate detections
    checkEolDistribution: function(name, majorVersion, prettyName) {
        const warnings = [];
        const nameLower = (name || '').toLowerCase();
        const prettyNameLower = (prettyName || '').toLowerCase();
        const majorVer = parseInt(majorVersion, 10);
        
        // RHEL 7 / CentOS 7 / Oracle Linux 7 detection
        if ((nameLower.includes('red hat') || nameLower.includes('rhel') || 
             nameLower.includes('centos') || nameLower.includes('oracle linux') ||
             prettyNameLower.includes('red hat') || prettyNameLower.includes('centos') ||
             prettyNameLower.includes('oracle linux')) && majorVer === 7) {
            warnings.push({
                type: 'eol_distribution',
                severity: 'warning',
                message: 'RHEL 7 / CentOS 7 is out of general support. Some RCA Tool detectors may be inaccurate for this distribution.',
                recommendation: 'Consider upgrading to a supported distribution (RHEL 8+) for better analysis accuracy.',
                documentationUrl: 'https://access.redhat.com/support/policy/updates/errata'
            });
        }
        
        // SUSE 12 detection (from os-release)
        if ((nameLower.includes('suse') || nameLower.includes('sles') ||
             prettyNameLower.includes('suse') || prettyNameLower.includes('sles')) && majorVer === 12) {
            warnings.push({
                type: 'eol_distribution',
                severity: 'warning',
                message: 'SUSE Linux Enterprise 12 is out of general support. Some RCA Tool detectors may be inaccurate for this distribution.',
                recommendation: 'Consider upgrading to a supported distribution (SLES 15+) for better analysis accuracy.',
                documentationUrl: 'https://www.suse.com/lifecycle/'
            });
        }
        
        return warnings;
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

        // Try to extract version from distribution string
        // e.g. "SUSE Linux Enterprise Server 12 SP3" -> majorVersion = 12
        // e.g. "SUSE Linux Enterprise Server 15 SP5" -> majorVersion = 15
        let majorVersion = null;
        const versionMatch = distribution.match(/\b(1[0-9]|[89])\b/);
        if (versionMatch) {
            majorVersion = versionMatch[1];
        }
        
        // Check for out-of-support distributions from sysinfo.txt
        const eolWarnings = this.checkEolDistribution(null, majorVersion, distribution);

        return {
            found: true,
            name: null,
            version: null,
            versionId: null,
            prettyName: distribution,
            majorVersion: majorVersion,
            minorVersion: null,
            warnings: eolWarnings,
            hasWarnings: eolWarnings.length > 0,
            isEol: eolWarnings.length > 0
        };
    },
    
    // Helper function to parse basic-environment.txt (SUSE supportconfig newer format)
    parseBasicEnvironment: function(content, filename) {
        debugLog('[osRelease parser] Parsing basic-environment.txt format');
        const lines = content.split('\n');
        let prettyName = null;
        let name = null;
        let versionId = null;
        let skipSection = false;

        for (const raw of lines) {
            const trimmed = raw.trim();

            // Treat lines starting with '#' as section headers in supportconfig dumps
            if (trimmed.startsWith('#')) {
                // If the header references a .rpmsave file, skip the following section
                if (trimmed.toLowerCase().includes('.rpmsave')) {
                    skipSection = true;
                } else {
                    skipSection = false;
                }
                continue;
            }

            if (skipSection) continue;
            if (!trimmed) continue;

            // Look for PRETTY_NAME= line
            const prettyMatch = trimmed.match(/^PRETTY_NAME=(?:"|')?([^"']+)(?:"|')?$/i);
            if (prettyMatch) {
                prettyName = prettyMatch[1].trim();
                debugLog('[osRelease parser] Found PRETTY_NAME:', prettyName);
            }

            // Look for NAME= line
            const nameMatch = trimmed.match(/^NAME=(?:"|')?([^"']+)(?:"|')?$/i);
            if (nameMatch) {
                name = nameMatch[1].trim();
                debugLog('[osRelease parser] Found NAME:', name);
            }
            
            // Look for VERSION_ID= line
            const versionIdMatch = trimmed.match(/^VERSION_ID=(?:"|')?([^"']+)(?:"|')?$/i);
            if (versionIdMatch) {
                versionId = versionIdMatch[1].trim();
                debugLog('[osRelease parser] Found VERSION_ID:', versionId);
            }
        }

        if (!prettyName && !name) {
            debugLog('[osRelease parser] No OS info found in basic-environment.txt');
            return { found: false };
        }

        // Extract major and minor version from VERSION_ID or prettyName
        let majorVersion = null;
        let minorVersion = null;
        if (versionId) {
            const parts = versionId.split('.');
            majorVersion = parts[0] || null;
            minorVersion = parts[1] || null;
        } else if (prettyName) {
            // Try to extract version from prettyName like "SUSE Linux Enterprise Server 15 SP7"
            const versionMatch = prettyName.match(/\b(1[0-9]|[789])\b/);
            if (versionMatch) {
                majorVersion = versionMatch[1];
            }
        }
        
        // Check for out-of-support distributions
        const eolWarnings = this.checkEolDistribution(name, majorVersion, prettyName);

        return {
            found: true,
            name: name,
            version: null,
            versionId: versionId,
            prettyName: prettyName,
            majorVersion: majorVersion,
            minorVersion: minorVersion,
            warnings: eolWarnings,
            hasWarnings: eolWarnings.length > 0,
            isEol: eolWarnings.length > 0
        };
    },
    
    // Helper function to parse distro release files (redhat-release, centos-release, etc.)
    // These are simple one-line files like: "Red Hat Enterprise Linux release 8.8 (Ootpa)"
    parseDistroRelease: function(content, filename) {
        debugLog('[osRelease parser] Parsing distro release file:', filename);
        const firstLine = content.split('\n')[0].trim();
        
        if (!firstLine) {
            debugLog('[osRelease parser] Empty distro release file');
            return { found: false };
        }
        
        const prettyName = firstLine;
        let name = null;
        let versionId = null;
        let majorVersion = null;
        let minorVersion = null;
        
        // Try to extract name and version from common formats:
        // "Red Hat Enterprise Linux release 8.8 (Ootpa)" -> name="Red Hat Enterprise Linux", version="8.8"
        // "CentOS Linux release 7.9.2009 (Core)" -> name="CentOS Linux", version="7.9.2009"
        // "SUSE Linux Enterprise Server 15 SP5" -> name="SUSE Linux Enterprise Server", version="15"
        // "Oracle Linux Server release 8.6" -> name="Oracle Linux Server", version="8.6"
        const releaseMatch = firstLine.match(/^(.+?)\s+release\s+([\d.]+)/);
        if (releaseMatch) {
            name = releaseMatch[1].trim();
            versionId = releaseMatch[2];
        } else {
            // Try SUSE-style: "SUSE Linux Enterprise Server 15 SP5"
            const suseMatch = firstLine.match(/^(SUSE.+?)\s+(\d+)/);
            if (suseMatch) {
                name = suseMatch[1].trim();
                versionId = suseMatch[2];
            }
        }
        
        if (versionId) {
            const parts = versionId.split('.');
            majorVersion = parts[0] || null;
            minorVersion = parts[1] || null;
        }
        
        debugLog('[osRelease parser] Parsed distro release:', { name, prettyName, versionId, majorVersion });
        
        // Check for out-of-support distributions
        const eolWarnings = this.checkEolDistribution(name, majorVersion, prettyName);
        
        return {
            found: true,
            name: name,
            version: null,
            versionId: versionId,
            prettyName: prettyName,
            majorVersion: majorVersion,
            minorVersion: minorVersion,
            warnings: eolWarnings,
            hasWarnings: eolWarnings.length > 0,
            isEol: eolWarnings.length > 0
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
    
    parse: function(content, filename, _lines) {
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

/**
 * Parser: inspectDiskResults
 * Extracts metadata from InspectIaaSDisk results.txt files.
 * Parses: Request Info (storage account, operational ID, guestfish version),
 * Filesystem Status (device/uuid/type), Inspection Metadata (OS type, distribution,
 * product name), Mount Points mapping, and Mount success/failure status.
 *
 * @example
 * // results.txt contains sections like:
 * // ========== Request Info ==========
 * // Storage Acct: md-xxx.blob.storage.azure.net
 * // ========== End Request Info ==========
 * // Filesystem Status:
 * // /dev/sda1: xfs [uuid=xxx]
 * // Inspection Metadata for /dev/rootvg/rootlv
 * // Distribution: rhel
 * // Product Name: Red Hat Enterprise Linux release 8.8 (Ootpa)
 * // Mounting /dev/rootvg/rootlv on / SUCCEEDED.
 */
const inspectDiskResultsParser = {
    filePattern: /^results\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[inspectDiskResults parser] Analyzing results.txt:', filename);
        const lines = _lines || content.split('\n');
        
        const result = {
            found: false,
            isInspectDisk: false,
            requestInfo: {},
            filesystemStatus: [],
            inspectionMetadata: {},
            mountPoints: {},
            mountResults: [],
            warnings: []
        };
        
        // Quick validation: InspectIaaSDisk results.txt starts with execution time
        // and contains "Request Info" section
        let hasRequestInfo = false;
        let hasInspectionMetadata = false;
        
        let section = null; // Track which section we're in
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const trimmed = line.trim();
            
            // ===== Section detection =====
            if (trimmed === '========== Request Info ==========') {
                section = 'requestInfo';
                hasRequestInfo = true;
                continue;
            }
            if (trimmed === '========== End Request Info ==========') {
                section = null;
                continue;
            }
            if (trimmed === 'Filesystem Status:') {
                section = 'filesystemStatus';
                continue;
            }
            if (trimmed.startsWith('Inspection Status:') || trimmed.startsWith('Inspection Metadata for')) {
                section = 'inspectionMetadata';
                hasInspectionMetadata = true;
                continue;
            }
            if (trimmed === 'Mount Points:') {
                section = 'mountPoints';
                continue;
            }
            
            // Stop parsing structured header when we hit the manifest/operations section
            if (trimmed.startsWith('Using manifest:') || /^\d{2}:\d{2}:\d{2}\s+Executing Operation/.test(trimmed)) {
                section = null;
                break;
            }
            
            // ===== Section parsing =====
            if (section === 'requestInfo') {
                const kvMatch = trimmed.match(/^(.+?):\s+(.+)$/);
                if (kvMatch) {
                    const key = kvMatch[1].trim();
                    const value = kvMatch[2].trim();
                    if (key === 'Storage Acct') result.requestInfo.storageAccount = value;
                    else if (key === 'Container/Vhd') result.requestInfo.containerVhd = value;
                    else if (key === 'Manifest requested') result.requestInfo.manifest = value;
                    else if (key.includes('Operational ID')) result.requestInfo.operationalId = value;
                    else if (key.includes('Guestfish')) result.requestInfo.guestfishVersion = value;
                }
                continue;
            }
            
            if (section === 'filesystemStatus') {
                // Format: /dev/sda1: xfs [uuid=849d8772-...]
                const fsMatch = trimmed.match(/^(\/dev\/\S+):\s+(\S+)\s+\[uuid=([^\]]*)\]/);
                if (fsMatch) {
                    result.filesystemStatus.push({
                        device: fsMatch[1],
                        type: fsMatch[2],
                        uuid: fsMatch[3] || null
                    });
                } else if (trimmed === '' || trimmed.startsWith('Inspection')) {
                    // End of filesystem status, re-check this line
                    if (trimmed.startsWith('Inspection')) {
                        section = 'inspectionMetadata';
                        hasInspectionMetadata = true;
                    } else {
                        section = null;
                    }
                }
                continue;
            }
            
            if (section === 'inspectionMetadata') {
                const typeMatch = trimmed.match(/^Type:\s+(.+)$/);
                if (typeMatch) {
                    result.inspectionMetadata.type = typeMatch[1].trim();
                    continue;
                }
                const distroMatch = trimmed.match(/^Distribution:\s+(.+)$/);
                if (distroMatch) {
                    result.inspectionMetadata.distribution = distroMatch[1].trim();
                    continue;
                }
                const productMatch = trimmed.match(/^Product Name:\s+(.+)$/);
                if (productMatch) {
                    result.inspectionMetadata.productName = productMatch[1].trim();
                    continue;
                }
                if (trimmed === 'Mount Points:') {
                    section = 'mountPoints';
                    continue;
                }
            }
            
            if (section === 'mountPoints') {
                // Format: /: /dev/rootvg/rootlv
                const mpMatch = trimmed.match(/^(\/\S*)\s*:\s+(\/dev\/\S+)$/);
                if (mpMatch) {
                    result.mountPoints[mpMatch[1]] = mpMatch[2];
                    continue;
                }
            }
            
            // Mount results can appear outside a section marker
            const mountMatch = trimmed.match(/^Mounting\s+(\/dev\/\S+)\s+on\s+(\S+)\s+(SUCCEEDED|FAILED)\./);
            if (mountMatch) {
                const mountEntry = {
                    device: mountMatch[1],
                    mountPoint: mountMatch[2],
                    status: mountMatch[3]
                };
                result.mountResults.push(mountEntry);
                
                if (mountEntry.status === 'FAILED') {
                    result.warnings.push({
                        type: 'inspect_disk_mount_failure',
                        severity: 'error',
                        message: `Mount failed: ${mountEntry.device} on ${mountEntry.mountPoint}`,
                        recommendation: 'Check if the device exists and the filesystem is intact. Verify fstab entries and run fsck if needed.'
                    });
                }
                continue;
            }
        }
        
        if (!hasRequestInfo && !hasInspectionMetadata) {
            debugLog('[inspectDiskResults parser] Not an InspectIaaSDisk results.txt');
            return { found: false };
        }
        
        result.found = true;
        result.isInspectDisk = true;
        result.hasWarnings = result.warnings.length > 0;
        
        debugLog('[inspectDiskResults parser] Parsed:', {
            filesystems: result.filesystemStatus.length,
            mounts: result.mountResults.length,
            distribution: result.inspectionMetadata.distribution,
            product: result.inspectionMetadata.productName,
            warnings: result.warnings.length
        });
        
        return result;
    }
};

const kernelTuningParser = {
    filePattern: /sos_commands\/kernel\/sysctl_-a$|\/env\.txt$|\/etc\/sysctl\.conf$|\/sysctl\.d\/[^\/]*\.conf$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[kernelTuning parser] Analyzing kernel parameters in:', filename);
        
        let sysctlContent = content;
        
        // If this is a sysctl.conf / sysctl.d/*.conf static config file,
        // parse directly — these use the same key=value format but only contain
        // explicitly configured values (not the full sysctl -a runtime dump).
        const isSysctlConf = /\/etc\/sysctl\.conf$|\/sysctl\.d\/[^\/]*\.conf$/.test(filename);
        if (isSysctlConf) {
            debugLog('[kernelTuning parser] Parsing static sysctl config file:', filename);
            // Falls through to the common key=value parsing below
        }
        // If this is SCC's env.txt, extract just the sysctl section
        else if (filename.includes('env.txt')) {
            debugLog('[kernelTuning parser] Extracting sysctl from SCC env.txt');
            
            // Extract content between "# /sbin/sysctl -a" and next "#==[ Command ]" marker
            const lines = _lines || content.split('\n');
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
    },

    /**
     * Merge results from multiple sysctl files (e.g. sysctl.conf + sysctl.d/*.conf).
     * Later file values override earlier ones for the same key.
     * Warnings are recomputed from the merged parameter set.
     */
    mergeResults: function(accumulated, newResult) {
        if (!newResult || !newResult.found) return;
        accumulated.found = true;

        // Merge parameters — later values override earlier ones
        Object.assign(accumulated.parameters, newResult.parameters || {});

        // Recompute all warnings from the merged parameter set
        const parameters = accumulated.parameters;

        // SAP HANA / high-performance warnings
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
        const warnings = [];
        for (const [param, expectedValue] of Object.entries(expectedValues)) {
            if (parameters[param] && parameters[param] !== expectedValue) {
                warnings.push({ parameter: param, expected: expectedValue, actual: parameters[param], documentationUrl: documentation[param] });
            }
        }

        // Azure Network optimization warnings
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
        const azureNetworkWarnings = [];
        for (const [param, expectedValue] of Object.entries(azureNetworkParams)) {
            if (parameters[param]) {
                const normalizedActual = parameters[param].replace(/\s+/g, '\t');
                const normalizedExpected = expectedValue.replace(/\s+/g, '\t');
                if (normalizedActual !== normalizedExpected) {
                    azureNetworkWarnings.push({ parameter: param, expected: expectedValue, actual: parameters[param], documentationUrl: azureNetworkDocUrl });
                }
            }
        }

        accumulated.warnings = warnings;
        accumulated.hasWarnings = warnings.length > 0;
        accumulated.azureNetworkWarnings = azureNetworkWarnings;
        accumulated.hasAzureNetworkWarnings = azureNetworkWarnings.length > 0;
        accumulated.azureNetworkTuned = azureNetworkWarnings.length === 0 && Object.keys(azureNetworkParams).every(p => parameters[p]);

        // Optional network parameters (informational)
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
        for (const [param, expectedValue] of Object.entries(optionalNetworkParams)) {
            if (parameters[param]) {
                const normalizedActual = parameters[param].replace(/\s+/g, '\t');
                const normalizedExpected = expectedValue.replace(/\s+/g, '\t');
                optionalNetworkInfo.push({
                    parameter: param,
                    expected: expectedValue,
                    actual: parameters[param],
                    matches: normalizedActual === normalizedExpected,
                    documentationUrl: azureNetworkDocUrl
                });
            }
        }
        accumulated.optionalNetworkInfo = optionalNetworkInfo;
        accumulated.hasOptionalNetworkInfo = optionalNetworkInfo.length > 0;

        debugLog('[kernelTuning parser] Merged result: parameters:', Object.keys(accumulated.parameters).length, 'warnings:', warnings.length);
    }
};

/**
 * Parser: hugePages
 * Detects and analyzes huge pages configuration from /proc/meminfo
 * Sysctl parameters are enriched from kernelTuning results to avoid duplicate parsing
 * Checks both Transparent Huge Pages (THP) and static huge pages configuration
 * Important for SAP HANA and high-memory workloads
 */
const hugePagesParser = {
    filePattern: /\/proc\/meminfo$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[hugePages parser] Analyzing huge pages configuration in:', filename);
        
        const result = {
            found: false,
            staticHugePages: {},
            transparentHugePages: {},
            sysctlParams: {},
            warnings: [],
            recommendations: []
        };
        
        // Parse /proc/meminfo for huge pages information
        debugLog('[hugePages parser] Parsing meminfo format');
        const lines = _lines || content.split('\n');
            
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;
                
                // Parse huge pages entries from meminfo
                // HugePages_Total:       0
                // HugePages_Free:        0
                // HugePages_Rsvd:        0
                // HugePages_Surp:        0
                // Hugepagesize:       2048 kB
                // Hugetlb:               0 kB
                
                const hugePagesMatch = trimmed.match(/^HugePages_(\w+):\s+(\d+)/i);
                if (hugePagesMatch) {
                    const key = hugePagesMatch[1].toLowerCase();
                    const value = parseInt(hugePagesMatch[2], 10);
                    result.staticHugePages[key] = value;
                    result.found = true;
                    debugLog(`[hugePages parser] Found HugePages_${key}: ${value}`);
                }
                
                const hugepageSizeMatch = trimmed.match(/^Hugepagesize:\s+(\d+)\s+kB/i);
                if (hugepageSizeMatch) {
                    result.staticHugePages.pagesize_kb = parseInt(hugepageSizeMatch[1], 10);
                    result.found = true;
                    debugLog(`[hugePages parser] Found Hugepagesize: ${result.staticHugePages.pagesize_kb} kB`);
                }
                
                const hugetlbMatch = trimmed.match(/^Hugetlb:\s+(\d+)\s+kB/i);
                if (hugetlbMatch) {
                    result.staticHugePages.hugetlb_kb = parseInt(hugetlbMatch[1], 10);
                    result.found = true;
                    debugLog(`[hugePages parser] Found Hugetlb: ${result.staticHugePages.hugetlb_kb} kB`);
                }
                
                // Also check for AnonHugePages (anonymous THP usage)
                const anonHugePagesMatch = trimmed.match(/^AnonHugePages:\s+(\d+)\s+kB/i);
                if (anonHugePagesMatch) {
                    result.transparentHugePages.anon_kb = parseInt(anonHugePagesMatch[1], 10);
                    result.found = true;
                    debugLog(`[hugePages parser] Found AnonHugePages: ${result.transparentHugePages.anon_kb} kB`);
                }
                
                // ShmemHugePages and ShmemPmdMapped for shared memory THP
                const shmemHugePagesMatch = trimmed.match(/^ShmemHugePages:\s+(\d+)\s+kB/i);
                if (shmemHugePagesMatch) {
                    result.transparentHugePages.shmem_kb = parseInt(shmemHugePagesMatch[1], 10);
                    result.found = true;
                }
                
                const shmemPmdMappedMatch = trimmed.match(/^ShmemPmdMapped:\s+(\d+)\s+kB/i);
                if (shmemPmdMappedMatch) {
                    result.transparentHugePages.shmem_pmd_mapped_kb = parseInt(shmemPmdMappedMatch[1], 10);
                    result.found = true;
                }
            }
        
        // Note: Sysctl parameters (vm.nr_hugepages, vm.hugetlb_shm_group, etc.) are
        // extracted from kernelTuning results in the worker to avoid duplicate parsing
        
        // Generate warnings and recommendations based on meminfo data
        if (result.found) {
            // Calculate total static huge pages memory if available
            if (result.staticHugePages.total !== undefined && result.staticHugePages.pagesize_kb) {
                const totalMB = (result.staticHugePages.total * result.staticHugePages.pagesize_kb) / 1024;
                result.staticHugePages.total_mb = totalMB;
                debugLog(`[hugePages parser] Total static huge pages: ${totalMB} MB`);
            }
            
            // Check if static huge pages are configured but not being used
            if (result.staticHugePages.total > 0) {
                const free = result.staticHugePages.free || 0;
                const total = result.staticHugePages.total;
                const usedPercent = ((total - free) / total) * 100;
                
                if (usedPercent < 10 && total > 0) {
                    result.warnings.push({
                        type: 'unused_hugepages',
                        message: `Static huge pages are configured (${total} pages) but mostly unused (${usedPercent.toFixed(1)}% used). Consider reducing allocation to free memory.`,
                        severity: 'warning'
                    });
                }
            }
            
            // Check Transparent Huge Pages (THP) usage
            if (result.transparentHugePages.anon_kb > 0) {
                const anonMB = result.transparentHugePages.anon_kb / 1024;
                result.transparentHugePages.anon_mb = anonMB;
                debugLog(`[hugePages parser] Transparent huge pages in use: ${anonMB} MB`);
                
                // THP should typically be disabled for SAP HANA
                result.recommendations.push({
                    type: 'thp_usage',
                    message: `Transparent Huge Pages (THP) are being used (${anonMB.toFixed(0)} MB). For SAP HANA, THP should be disabled as it can cause performance issues. See SAP Note #2131662.`,
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/large-instances/archived-hli-docs/hana-monitor-troubleshoot#operating-system-os'
                });
            }
        }
        
        if (!result.found) {
            debugLog('[hugePages parser] No huge pages information found');
            return { found: false };
        }
        
        result.hasWarnings = result.warnings.length > 0;
        result.hasRecommendations = result.recommendations.length > 0;
        
        debugLog('[hugePages parser] Parsing complete:', result);
        return result;
    }
};

/**
 * Parser: timeSync
 * Detects Azure time synchronization configuration on Linux VMs
 * Checks for hv_utils module loaded and PTP clock source availability
 * 
 * Reference: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync
 */
const timeSyncParser = {
    // Target lsmod output from sosreport or SCC
    // sosreport: sos_commands/kernel/lsmod
    // SCC: modules.txt (contains # /sbin/lsmod section)
    filePattern: /sos_commands\/kernel\/lsmod$|\/modules\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[timeSync parser] Analyzing time sync in:', filename);
        
        // For SCC modules.txt, extract just the lsmod section
        let lsmodContent = content;
        let sourceFile = filename;
        if (filename.includes('modules.txt')) {
            debugLog('[timeSync parser] Extracting lsmod section from SCC modules.txt');
            const sectionResult = SCC_RULES.extractSection(content, filename, '# /sbin/lsmod', '/sbin/lsmod');
            if (!sectionResult.found) {
                debugLog('[timeSync parser] lsmod section not found in modules.txt');
                return { found: false };
            }
            lsmodContent = sectionResult.content;
            sourceFile = 'modules.txt (lsmod)';
            debugLog('[timeSync parser] Extracted', sectionResult.lines.length, 'lines from lsmod section');
        }
        
        const result = {
            found: false,
            hvUtilsLoaded: false,
            hvVmbusLoaded: false,
            hvNetvscLoaded: false,
            hypervModules: [],
            ptpDevices: [],
            warnings: [],
            recommendations: [],
            detectionFile: sourceFile
        };
        
        const lines = lsmodContent.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            
            // Parse module lines: "module_name    size  used_by dependents..."
            const parts = trimmed.split(/\s+/);
            if (parts.length < 2) continue;
            
            const moduleName = parts[0].toLowerCase();
            
            // Check for hv_utils (Hyper-V integration services for time sync)
            if (moduleName === 'hv_utils') {
                result.hvUtilsLoaded = true;
                result.found = true;
                result.hypervModules.push('hv_utils');
                debugLog('[timeSync parser] Found hv_utils module loaded');
            }
            
            // Check for hv_vmbus (Hyper-V VMBus)
            if (moduleName === 'hv_vmbus') {
                result.hvVmbusLoaded = true;
                result.found = true;
                result.hypervModules.push('hv_vmbus');
                debugLog('[timeSync parser] Found hv_vmbus module loaded');
            }
            
            // Check for hv_netvsc (Hyper-V network driver)
            if (moduleName === 'hv_netvsc') {
                result.hvNetvscLoaded = true;
                result.found = true;
                result.hypervModules.push('hv_netvsc');
                debugLog('[timeSync parser] Found hv_netvsc module loaded');
            }
            
            // Track other Hyper-V/hyperv related modules
            if ((moduleName.startsWith('hv_') || moduleName.includes('hyperv')) && 
                !result.hypervModules.includes(moduleName)) {
                result.hypervModules.push(moduleName);
                result.found = true;
            }
        }
        
        // Generate warnings only if we're on a Hyper-V environment
        const isHypervEnvironment = result.hypervModules.length > 0;
        
        if (isHypervEnvironment && !result.hvUtilsLoaded) {
            result.warnings.push({
                type: 'hv_utils_missing',
                severity: 'error',
                message: 'hv_utils kernel module is not loaded. This module is required for Azure time synchronization.',
                recommendation: 'Ensure Hyper-V integration services are installed. On RHEL/CentOS: yum install hyperv-daemons. On Ubuntu: apt install linux-cloud-tools-common',
                documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#integration-services'
            });
        }
        
        if (result.hvUtilsLoaded) {
            debugLog('[timeSync parser] Time sync module hv_utils is loaded correctly');
        }
        
        result.hasWarnings = result.warnings.length > 0;
        result.hasErrors = result.warnings.some(w => w.severity === 'error');
        result.isHypervEnvironment = isHypervEnvironment;
        
        debugLog('[timeSync parser] Parse result:', result);
        return result;
    }
};

/**
 * Parser: ptpClockSource
 * Checks for PTP clock source configuration in chrony
 * Reference: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#chrony
 */
const ptpClockSourceParser = {
    // Target chrony sources output or chrony.conf
    // sosreport: sos_commands/chrony/chronyc_sources, etc/chrony.conf
    // SCC: ntp.txt (contains # /usr/bin/chronyc -n sources -v and # /etc/chrony.conf sections)
    filePattern: /sos_commands\/chrony\/chronyc_sources$|\/etc\/chrony\.conf$|\/etc\/chrony\/chrony\.conf$|\/ntp\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[ptpClockSource parser] Analyzing in:', filename);
        
        // For SCC ntp.txt, try both chronyc sources and chrony.conf sections
        if (filename.includes('ntp.txt')) {
            // Try chronyc sources first
            const sourcesResult = SCC_RULES.extractSection(content, filename, '# /usr/bin/chronyc -n sources', '/usr/bin/chronyc -n sources');
            if (sourcesResult.found) {
                const initResult = { found: false, hasPtpSource: false, ptpDevice: null, ptpActive: false, usesPtpHypervSymlink: false, chronySources: [], warnings: [], recommendations: [], detectionFile: 'ntp.txt (chronyc sources)' };
                debugLog('[ptpClockSource parser] Using chronyc sources section from SCC ntp.txt');
                return this.parseChronycSources(sourcesResult.content, filename, initResult);
            }
            
            // Try chrony.conf as fallback
            const confResult = SCC_RULES.extractSection(content, filename, '# /etc/chrony.conf', '/etc/chrony.conf');
            if (confResult.found) {
                const initResult = { found: false, hasPtpSource: false, ptpDevice: null, ptpActive: false, usesPtpHypervSymlink: false, chronySources: [], warnings: [], recommendations: [], detectionFile: 'ntp.txt (chrony.conf)' };
                debugLog('[ptpClockSource parser] Using chrony.conf section from SCC ntp.txt');
                return this.parseChronyConf(confResult.content, filename, initResult);
            }
            
            debugLog('[ptpClockSource parser] No relevant sections found in ntp.txt');
            return { found: false };
        }
        
        const result = {
            found: false,
            hasPtpSource: false,
            ptpDevice: null,
            ptpActive: false,
            usesPtpHypervSymlink: false,
            chronySources: [],
            warnings: [],
            recommendations: [],
            detectionFile: filename
        };
        
        // Check if this is chrony.conf (configuration file)
        if (filename.includes('chrony.conf')) {
            return this.parseChronyConf(content, filename, result);
        }
        
        // Parse chronyc sources output
        return this.parseChronycSources(content, filename, result);
    },
    
    parseChronyConf: function(content, filename, result) {
        debugLog('[ptpClockSource parser] Parsing chrony.conf');
        
        const lines = content.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            
            // Look for refclock PHC /dev/ptp... configuration
            const refclockMatch = trimmed.match(/^refclock\s+PHC\s+(\/dev\/ptp[^\s]+)/i);
            if (refclockMatch) {
                result.hasPtpSource = true;
                result.ptpDevice = refclockMatch[1];
                result.found = true;
                debugLog('[ptpClockSource parser] Found PTP refclock:', result.ptpDevice);
                
                if (result.ptpDevice.includes('ptp_hyperv')) {
                    result.usesPtpHypervSymlink = true;
                } else if (result.ptpDevice.match(/\/dev\/ptp\d+$/)) {
                    result.warnings.push({
                        type: 'ptp_hardcoded_device',
                        severity: 'warning',
                        message: `Chrony is configured with hardcoded PTP device ${result.ptpDevice}. This may cause issues if device order changes.`,
                        recommendation: 'Use /dev/ptp_hyperv symlink instead of hardcoded device.',
                        documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#check-for-ptp-clock-source'
                    });
                }
            }
        }
        
        if (!result.hasPtpSource) {
            result.recommendations.push({
                type: 'ptp_not_configured',
                message: 'Chrony is not configured to use PTP clock source from Azure host.',
                recommendation: 'For best time accuracy, configure chrony: refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0 stratum 2',
                documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#chrony'
            });
        }
        
        result.hasWarnings = result.warnings.length > 0;
        result.hasRecommendations = result.recommendations.length > 0;
        return result;
    },
    
    parseChronycSources: function(content, filename, result) {
        debugLog('[ptpClockSource parser] Parsing chronyc sources');
        
        const lines = content.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            
            // Parse chronyc sources output format
            // # = local reference (PHC/PTP), ^ = remote server (NTP)
            // * = current sync source
            
            const phcMatch = trimmed.match(/^([#^])([*+\-?x~])\s+PHC(\d+)/i);
            if (phcMatch) {
                const status = phcMatch[2];
                const phcNum = phcMatch[3];
                
                result.hasPtpSource = true;
                result.ptpDevice = `/dev/ptp${phcNum}`;
                result.found = true;
                
                if (status === '*') {
                    result.ptpActive = true;
                    debugLog('[ptpClockSource parser] PTP is active sync source');
                }
                
                result.chronySources.push({
                    type: 'PHC',
                    name: `PHC${phcNum}`,
                    active: status === '*',
                    status: status
                });
            }
            
            // Track NTP sources
            const ntpMatch = trimmed.match(/^\^([*+\-?x~])\s+(\S+)/);
            if (ntpMatch) {
                result.chronySources.push({
                    type: 'NTP',
                    name: ntpMatch[2],
                    active: ntpMatch[1] === '*',
                    status: ntpMatch[1]
                });
                result.found = true;
            }
        }
        
        if (result.hasPtpSource && !result.ptpActive) {
            result.warnings.push({
                type: 'ptp_not_active',
                severity: 'warning',
                message: 'PTP clock source is configured but not currently the active sync source.',
                recommendation: 'Check chrony status and ensure PTP device is accessible.',
                documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#chrony'
            });
        }
        
        result.hasWarnings = result.warnings.length > 0;
        return result;
    }
};

/**
 * Parser: timeSyncService
 * Checks if chrony or ntpd service is running
 * Reference: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync
 */
const timeSyncServiceParser = {
    // Target systemctl list-unit-files (sosreport) or systemd-status.txt/ntp.txt (SCC)
    // SCC ntp.txt contains "# /bin/systemctl status chronyd.service" section
    filePattern: /sos_commands\/systemd\/systemctl_list-unit-files$|\/systemd-status\.txt$|\/ntp\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[timeSyncService parser] Analyzing:', filename);
        
        const result = {
            found: false,
            chronyEnabled: false,
            chronyStatus: null,
            chronyRunning: false,
            ntpdEnabled: false,
            ntpdStatus: null,
            ntpdRunning: false,
            timesyncdEnabled: false,
            timesyncdStatus: null,
            timesyncdMasked: false,
            timesyncdRunning: false,
            warnings: [],
            recommendations: [],
            detectionFile: filename
        };
        
        // Check if this is an SCC systemd-status.txt or ntp.txt file
        const isSCCSystemd = filename.includes('systemd-status.txt');
        const isSCCNtp = filename.includes('ntp.txt');
        const isSCC = isSCCSystemd || isSCCNtp;
        
        if (isSCCNtp) {
            // For SCC ntp.txt, extract chronyd service status section
            const chronydSection = SCC_RULES.extractSection(
                content,
                'ntp.txt',
                '# /bin/systemctl status chronyd.service',
                '/bin/systemctl status chronyd.service'
            );
            
            if (chronydSection.found) {
                result.found = true;
                result.detectionFile = 'ntp.txt (chronyd.service)';
                
                const lines = chronydSection.content.split('\n');
                for (const line of lines) {
                    // Parse "Loaded: loaded (...; enabled|disabled; ...)"
                    const loadedMatch = line.match(/Loaded:\s+loaded\s*\([^;]+;\s*(\w+);/i);
                    if (loadedMatch) {
                        const status = loadedMatch[1].toLowerCase();
                        result.chronyEnabled = (status === 'enabled');
                        result.chronyStatus = status;
                    }
                    
                    // Parse "Active: active (running)|inactive|failed"
                    const activeMatch = line.match(/Active:\s+(\w+)\s*(?:\((\w+)\))?/i);
                    if (activeMatch) {
                        const state = activeMatch[1].toLowerCase();
                        result.chronyRunning = (state === 'active');
                    }
                }
            }
            
            // Generate warnings for SCC ntp.txt
            if (result.found) {
                if (result.chronyEnabled && !result.chronyRunning) {
                    result.warnings.push({
                        type: 'chrony_not_running',
                        severity: 'error',
                        message: 'chrony service is enabled but not running.',
                        recommendation: 'Start chrony service: systemctl start chronyd',
                        documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                    });
                }
            }
            
            result.hasWarnings = result.warnings.length > 0;
            result.hasErrors = result.warnings.some(w => w.severity === 'error');
            
            debugLog('[timeSyncService parser] Result:', result);
            return result;
        }
        
        if (isSCCSystemd) {
            // Extract chronyd service status
            // In SCC systemd-status.txt, sections are marked like "# /bin/systemctl status 'chronyd.service'"
            const chronydSection = SCC_RULES.extractSection(
                content,
                filename,
                "/bin/systemctl status 'chronyd.service'",
                null
            );
            
            if (chronydSection.found) {
                result.found = true;
                result.detectionFile = 'systemd-status.txt (chronyd.service)';
                
                const lines = chronydSection.content.split('\n');
                for (const line of lines) {
                    // Parse "Loaded: loaded (...; enabled|disabled; ...)"
                    const loadedMatch = line.match(/Loaded:\s+loaded\s*\([^;]+;\s*(\w+);/i);
                    if (loadedMatch) {
                        const status = loadedMatch[1].toLowerCase();
                        result.chronyEnabled = (status === 'enabled');
                        result.chronyStatus = status;
                    }
                    
                    // Parse "Active: active (running)|inactive|failed"
                    const activeMatch = line.match(/Active:\s+(\w+)\s*(?:\((\w+)\))?/i);
                    if (activeMatch) {
                        const state = activeMatch[1].toLowerCase();
                        result.chronyRunning = (state === 'active');
                    }
                }
            }
            
            // Extract ntpd service status
            const ntpdSection = SCC_RULES.extractSection(
                content,
                filename,
                "/bin/systemctl status 'ntpd.service'",
                null
            );
            
            if (ntpdSection.found) {
                result.found = true;
                if (!result.detectionFile.includes('ntpd')) {
                    result.detectionFile = result.detectionFile.replace(')', ', ntpd.service)');
                }
                
                const lines = ntpdSection.content.split('\n');
                for (const line of lines) {
                    const loadedMatch = line.match(/Loaded:\s+loaded\s*\([^;]+;\s*(\w+);/i);
                    if (loadedMatch) {
                        const status = loadedMatch[1].toLowerCase();
                        result.ntpdEnabled = (status === 'enabled');
                        result.ntpdStatus = status;
                    }
                    
                    const activeMatch = line.match(/Active:\s+(\w+)\s*(?:\((\w+)\))?/i);
                    if (activeMatch) {
                        const state = activeMatch[1].toLowerCase();
                        result.ntpdRunning = (state === 'active');
                    }
                }
            }
            
            // Extract systemd-timesyncd service status
            const timesyncdSection = SCC_RULES.extractSection(
                content,
                filename,
                "/bin/systemctl status 'systemd-timesyncd.service'",
                null
            );
            
            if (timesyncdSection.found) {
                result.found = true;
                if (!result.detectionFile.includes('timesyncd')) {
                    result.detectionFile = result.detectionFile.replace(')', ', systemd-timesyncd.service)');
                }
                
                const lines = timesyncdSection.content.split('\n');
                for (const line of lines) {
                    const loadedMatch = line.match(/Loaded:\s+(\w+)\s*\([^;]+;\s*(\w+);/i);
                    if (loadedMatch) {
                        const loadState = loadedMatch[1].toLowerCase();
                        const status = loadedMatch[2].toLowerCase();
                        result.timesyncdMasked = (loadState === 'masked');
                        result.timesyncdEnabled = (status === 'enabled');
                        result.timesyncdStatus = status;
                    }
                    
                    const activeMatch = line.match(/Active:\s+(\w+)\s*(?:\((\w+)\))?/i);
                    if (activeMatch) {
                        const state = activeMatch[1].toLowerCase();
                        result.timesyncdRunning = (state === 'active');
                    }
                }
            }
        } else if (!isSCCNtp) {
            // sosreport format: parse systemctl list-unit-files
            const lines = _lines || content.split('\n');
            
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;
                
                // Parse unit file status lines: "service.service  enabled|disabled|masked"
                const match = trimmed.match(/^(chronyd?\.service|ntpd?\.service|systemd-timesyncd\.service)\s+(\w+)/i);
                if (match) {
                    const service = match[1].toLowerCase();
                    const status = match[2].toLowerCase();
                    result.found = true;
                    
                    if (service.includes('chrony')) {
                        result.chronyEnabled = (status === 'enabled');
                        result.chronyStatus = status;
                        if (status === 'alias') {
                            result.chronyEnabled = true; // alias means it's linked to another unit
                        }
                    } else if (service.includes('ntpd') || service === 'ntp.service') {
                        result.ntpdEnabled = (status === 'enabled');
                        result.ntpdStatus = status;
                    } else if (service.includes('timesyncd')) {
                        result.timesyncdEnabled = (status === 'enabled');
                        result.timesyncdMasked = (status === 'masked');
                        result.timesyncdStatus = status;
                    }
                }
            }
        }
        
        // Generate warnings
        if (result.found) {
            // Check if any time service is enabled
            const hasTimeService = result.chronyEnabled || result.ntpdEnabled;
            
            if (!hasTimeService) {
                result.warnings.push({
                    type: 'no_time_service',
                    severity: 'error',
                    message: 'No time synchronization service (chrony or ntpd) is enabled.',
                    recommendation: 'Enable chrony service: systemctl enable --now chronyd',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                });
            } else {
                // Check if enabled service is actually running (SCC only)
                if (isSCC) {
                    if (result.chronyEnabled && !result.chronyRunning) {
                        result.warnings.push({
                            type: 'chrony_not_running',
                            severity: 'error',
                            message: 'chrony service is enabled but not running.',
                            recommendation: 'Start chrony service: systemctl start chronyd',
                            documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                        });
                    }
                    
                    if (result.ntpdEnabled && !result.ntpdRunning) {
                        result.warnings.push({
                            type: 'ntpd_not_running',
                            severity: 'error',
                            message: 'ntpd service is enabled but not running.',
                            recommendation: 'Start ntpd service: systemctl start ntpd',
                            documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                        });
                    }
                }
            }
            
            // Check if timesyncd is not masked (should be disabled/masked when using chrony)
            if (result.timesyncdEnabled && !result.timesyncdMasked && result.chronyEnabled) {
                result.warnings.push({
                    type: 'timesyncd_conflict',
                    severity: 'warning',
                    message: 'systemd-timesyncd is enabled alongside chrony. This may cause conflicts.',
                    recommendation: 'Mask timesyncd when using chrony: systemctl mask systemd-timesyncd',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                });
            }
            
            // Check if timesyncd is running when it shouldn't be (SCC only)
            if (isSCC && result.timesyncdRunning && result.chronyRunning) {
                result.warnings.push({
                    type: 'timesyncd_running_conflict',
                    severity: 'error',
                    message: 'systemd-timesyncd is running alongside chrony. This will cause conflicts.',
                    recommendation: 'Stop and mask timesyncd: systemctl stop systemd-timesyncd && systemctl mask systemd-timesyncd',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                });
            }
            
            // Info: timesyncd properly masked
            if (result.timesyncdMasked && result.chronyEnabled) {
                result.recommendations.push({
                    type: 'timesyncd_masked',
                    severity: 'info',
                    message: 'systemd-timesyncd is properly masked while chrony is enabled.'
                });
            }
        }
        
        result.hasWarnings = result.warnings.length > 0;
        result.hasErrors = result.warnings.some(w => w.severity === 'error');
        
        debugLog('[timeSyncService parser] Result:', result);
        return result;
    }
};

/**
 * Parser: timedatectl
 * Parses timedatectl output for NTP synchronized status
 * Reference: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync
 */
const timedatectlParser = {
    // sosreport: sos_commands/systemd/timedatectl
    // SCC: ntp.txt (contains # /usr/bin/timedatectl section)
    filePattern: /sos_commands\/systemd\/timedatectl$|\/ntp\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[timedatectl parser] Analyzing:', filename);
        
        // For SCC ntp.txt, extract just the timedatectl section
        let timedatectlContent = content;
        let sourceFile = filename;
        if (filename.includes('ntp.txt')) {
            debugLog('[timedatectl parser] Extracting timedatectl section from SCC ntp.txt');
            const sectionResult = SCC_RULES.extractSection(content, filename, '# /usr/bin/timedatectl', '/usr/bin/timedatectl');
            if (!sectionResult.found) {
                debugLog('[timedatectl parser] timedatectl section not found in ntp.txt');
                return { found: false };
            }
            timedatectlContent = sectionResult.content;
            sourceFile = 'ntp.txt (timedatectl)';
            debugLog('[timedatectl parser] Extracted', sectionResult.lines.length, 'lines from timedatectl section');
        }
        
        const result = {
            found: false,
            ntpEnabled: false,
            ntpSynchronized: false,
            ntpService: null,
            localTime: null,
            timezone: null,
            warnings: [],
            recommendations: [],
            detectionFile: sourceFile
        };
        
        const lines = timedatectlContent.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            
            // Parse key: value format
            const colonIdx = trimmed.indexOf(':');
            if (colonIdx === -1) continue;
            
            const key = trimmed.substring(0, colonIdx).trim().toLowerCase();
            const value = trimmed.substring(colonIdx + 1).trim().toLowerCase();
            
            // NTP enabled (older format)
            if (key === 'ntp enabled') {
                result.ntpEnabled = (value === 'yes');
                result.found = true;
            }
            
            // NTP synchronized (older format) or System clock synchronized (newer)
            if (key === 'ntp synchronized' || key === 'system clock synchronized') {
                result.ntpSynchronized = (value === 'yes');
                result.found = true;
            }
            
            // NTP service (newer format)
            if (key === 'ntp service') {
                result.ntpService = value;
                result.ntpEnabled = (value === 'active' || value === 'running');
                result.found = true;
            }
            
            // Local time
            if (key === 'local time') {
                result.localTime = trimmed.substring(colonIdx + 1).trim();
                result.found = true;
            }
            
            // Time zone
            if (key === 'time zone') {
                result.timezone = trimmed.substring(colonIdx + 1).trim();
            }
        }
        
        // Generate warnings
        if (result.found) {
            if (!result.ntpSynchronized) {
                result.warnings.push({
                    type: 'not_synchronized',
                    severity: 'error',
                    message: 'System clock is not synchronized with NTP.',
                    recommendation: 'Check time service status and network connectivity to time sources.',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                });
            }
            
            if (!result.ntpEnabled) {
                result.warnings.push({
                    type: 'ntp_disabled',
                    severity: 'error',
                    message: 'NTP service is not enabled.',
                    recommendation: 'Enable NTP: timedatectl set-ntp true',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                });
            }
        }
        
        result.hasWarnings = result.warnings.length > 0;
        result.hasErrors = result.warnings.some(w => w.severity === 'error');
        
        debugLog('[timedatectl parser] Result:', result);
        return result;
    }
};

/**
 * Parser: ptpDevice
 * Checks for PTP devices and /dev/ptp_hyperv symlink
 * Reference: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#check-for-ptp-clock-source
 */
const ptpDeviceParser = {
    // Target ls -lanR /dev output (sosreport) or udev.txt (SCC)
    // sosreport: sos_commands/block/ls_-lanR_.dev
    // SCC: udev.txt (contains # /sbin/udevadm info -e section)
    filePattern: /sos_commands\/block\/ls_-lanR_\.dev$|\/udev\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[ptpDevice parser] Analyzing:', filename);
        
        const result = {
            found: false,
            ptpDevices: [],
            hasPtpHypervSymlink: false,
            ptpHypervTarget: null,
            warnings: [],
            recommendations: [],
            detectionFile: filename
        };
        
        // Check if this is an SCC udev.txt file
        const isSCC = filename.includes('udev.txt');
        
        if (isSCC) {
            // For SCC udev.txt, extract udevadm info -e section and parse it
            const sectionResult = SCC_RULES.extractSection(content, filename, '# /sbin/udevadm info -e', '/sbin/udevadm info -e');
            if (!sectionResult.found) {
                debugLog('[ptpDevice parser] udevadm info -e section not found in udev.txt');
                return { found: false };
            }
            
            result.detectionFile = 'udev.txt (udevadm info -e)';
            const lines = sectionResult.content.split('\n');
            
            // Parse udevadm info -e format, looking for PTP devices
            // Format is blocks separated by blank lines:
            // P: /devices/virtual/ptp/ptp0
            // N: ptp0
            // S: ptp_hyperv
            // E: DEVLINKS=/dev/ptp_hyperv
            let currentDevice = null;
            let inPtpDevice = false;
            
            for (const line of lines) {
                const trimmed = line.trim();
                
                // Empty line starts a new device block
                if (!trimmed) {
                    currentDevice = null;
                    inPtpDevice = false;
                    continue;
                }
                
                // P: line indicates device path
                if (trimmed.startsWith('P:')) {
                    const devPath = trimmed.substring(2).trim();
                    if (devPath.includes('/ptp/ptp')) {
                        inPtpDevice = true;
                        currentDevice = {};
                    }
                    continue;
                }
                
                if (inPtpDevice) {
                    // N: line is the device name
                    if (trimmed.startsWith('N:')) {
                        const devName = trimmed.substring(2).trim();
                        if (devName.match(/^ptp\d+$/)) {
                            result.ptpDevices.push(devName);
                            result.found = true;
                            debugLog('[ptpDevice parser] Found PTP device:', devName);
                        }
                    }
                    
                    // S: line is symlink name
                    if (trimmed.startsWith('S:')) {
                        const symlink = trimmed.substring(2).trim();
                        if (symlink === 'ptp_hyperv') {
                            result.hasPtpHypervSymlink = true;
                            result.found = true;
                            debugLog('[ptpDevice parser] Found ptp_hyperv symlink via S:');
                        }
                    }
                    
                    // E: DEVLINKS can also contain symlinks
                    if (trimmed.startsWith('E: DEVLINKS=')) {
                        const devlinks = trimmed.substring(12).trim();
                        if (devlinks.includes('ptp_hyperv')) {
                            result.hasPtpHypervSymlink = true;
                            result.found = true;
                            // Extract target from DEVNAME if available
                            debugLog('[ptpDevice parser] Found ptp_hyperv in DEVLINKS');
                        }
                    }
                    
                    // E: DEVNAME gives us the actual device
                    if (trimmed.startsWith('E: DEVNAME=')) {
                        const devName = trimmed.substring(11).trim();
                        if (devName.match(/\/dev\/ptp\d+$/)) {
                            const ptpDev = devName.replace('/dev/', '');
                            result.ptpHypervTarget = ptpDev;
                        }
                    }
                }
            }
        } else {
            // sosreport format: parse ls -lanR /dev output
            const lines = _lines || content.split('\n');
            
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed) continue;
                
                // Look for ptp devices (character devices)
                // crw-------   1 0  0 246,   0 Jan 15 18:07 ptp0
                const ptpDevMatch = trimmed.match(/^c[\w-]+\s+\d+\s+\d+\s+\d+\s+\d+,\s*\d+\s+\w+\s+\d+\s+[\d:]+\s+(ptp\d+)$/);
                if (ptpDevMatch) {
                    result.ptpDevices.push(ptpDevMatch[1]);
                    result.found = true;
                    debugLog('[ptpDevice parser] Found PTP device:', ptpDevMatch[1]);
                }
                
                // Look for ptp_hyperv symlink
                // lrwxrwxrwx  1 0 0    4 Jan 15 18:07 ptp_hyperv -> ptp0
                const symlinkMatch = trimmed.match(/^l[\w-]+\s+\d+\s+\d+\s+\d+\s+\d+\s+\w+\s+\d+\s+[\d:]+\s+ptp_hyperv\s+->\s+(.+)$/);
                if (symlinkMatch) {
                    result.hasPtpHypervSymlink = true;
                    result.ptpHypervTarget = symlinkMatch[1];
                    result.found = true;
                    debugLog('[ptpDevice parser] Found ptp_hyperv symlink ->', result.ptpHypervTarget);
                }
            }
        }
        
        // Generate warnings
        if (result.ptpDevices.length > 0 && !result.hasPtpHypervSymlink) {
            result.warnings.push({
                type: 'ptp_hyperv_symlink_missing',
                severity: 'warning',
                message: '/dev/ptp_hyperv symlink is not present. Using hardcoded device names may cause issues after kernel updates.',
                recommendation: 'Create a udev rule to create /dev/ptp_hyperv symlink. See documentation for details.',
                documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#check-for-ptp-clock-source'
            });
        }
        
        if (result.ptpDevices.length === 0 && result.found === false) {
            // We parsed the file but found no PTP devices - might indicate kernel issue
            result.recommendations.push({
                type: 'no_ptp_devices',
                severity: 'info',
                message: 'No PTP devices found. Ensure kernel supports PTP and hv_utils module is loaded.'
            });
        }
        
        result.hasWarnings = result.warnings.length > 0;
        
        debugLog('[ptpDevice parser] Result:', result);
        return result;
    }
};

/**
 * Parser: chronyTracking
 * Parses chronyc tracking output for time offset and sync status
 * Reference: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync
 */
const chronyTrackingParser = {
    // sosreport: sos_commands/chrony/chronyc_tracking
    // SCC: ntp.txt (contains # /usr/bin/chronyc -n tracking section)
    filePattern: /sos_commands\/chrony\/chronyc_tracking$|\/ntp\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[chronyTracking parser] Analyzing:', filename);
        
        // For SCC ntp.txt, extract just the chronyc tracking section
        let trackingContent = content;
        let sourceFile = filename;
        if (filename.includes('ntp.txt')) {
            debugLog('[chronyTracking parser] Extracting chronyc tracking section from SCC ntp.txt');
            const sectionResult = SCC_RULES.extractSection(content, filename, '# /usr/bin/chronyc -n tracking', '/usr/bin/chronyc -n tracking');
            if (!sectionResult.found) {
                debugLog('[chronyTracking parser] chronyc tracking section not found in ntp.txt');
                return { found: false };
            }
            trackingContent = sectionResult.content;
            sourceFile = 'ntp.txt (chronyc tracking)';
            debugLog('[chronyTracking parser] Extracted', sectionResult.lines.length, 'lines from chronyc tracking section');
        }
        
        const result = {
            found: false,
            referenceId: null,
            referenceName: null,
            stratum: null,
            systemTime: null,
            systemTimeSeconds: null,
            lastOffset: null,
            lastOffsetSeconds: null,
            rmsOffset: null,
            updateInterval: null,
            leapStatus: null,
            isPtpSource: false,
            isPhcSource: false,
            warnings: [],
            recommendations: [],
            detectionFile: sourceFile
        };
        
        const lines = trackingContent.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            
            const colonIdx = trimmed.indexOf(':');
            if (colonIdx === -1) continue;
            
            const key = trimmed.substring(0, colonIdx).trim().toLowerCase();
            const value = trimmed.substring(colonIdx + 1).trim();
            
            if (key === 'reference id') {
                // Reference ID    : 50484330 (PHC0)
                result.referenceId = value;
                result.found = true;
                
                const phcMatch = value.match(/\(PHC(\d+)\)/i);
                if (phcMatch) {
                    result.referenceName = `PHC${phcMatch[1]}`;
                    result.isPhcSource = true;
                    result.isPtpSource = true;
                }
            }
            
            if (key === 'stratum') {
                result.stratum = parseInt(value, 10);
            }
            
            if (key === 'system time') {
                // System time     : 0.000002584 seconds slow of NTP time
                result.systemTime = value;
                const timeMatch = value.match(/([\d.]+)\s+seconds?\s+(slow|fast)/i);
                if (timeMatch) {
                    result.systemTimeSeconds = parseFloat(timeMatch[1]);
                    if (timeMatch[2].toLowerCase() === 'slow') {
                        result.systemTimeSeconds = -result.systemTimeSeconds;
                    }
                }
            }
            
            if (key === 'last offset') {
                // Last offset     : +0.000000718 seconds
                result.lastOffset = value;
                const offsetMatch = value.match(/([+-]?[\d.]+)\s+seconds?/i);
                if (offsetMatch) {
                    result.lastOffsetSeconds = parseFloat(offsetMatch[1]);
                }
            }
            
            if (key === 'rms offset') {
                result.rmsOffset = value;
            }
            
            if (key === 'update interval') {
                result.updateInterval = value;
            }
            
            if (key === 'leap status') {
                result.leapStatus = value;
            }
        }
        
        // Generate warnings based on time offset
        if (result.found && result.lastOffsetSeconds !== null) {
            const absOffset = Math.abs(result.lastOffsetSeconds);
            
            // Warning if offset > 100ms
            if (absOffset > 0.1) {
                result.warnings.push({
                    type: 'high_time_offset',
                    severity: 'warning',
                    message: `Time offset is ${(absOffset * 1000).toFixed(1)}ms. High offset may indicate time sync issues.`,
                    recommendation: 'Check time source connectivity and consider running chronyc makestep.',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                });
            }
            
            // Error if offset > 1 second
            if (absOffset > 1.0) {
                result.warnings.push({
                    type: 'critical_time_offset',
                    severity: 'error',
                    message: `Time offset is ${absOffset.toFixed(3)} seconds. This may cause application issues.`,
                    recommendation: 'Immediately investigate time synchronization. Check PTP device and chrony configuration.',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync'
                });
            }
        }
        
        // Info: using PTP source
        if (result.isPtpSource) {
            result.recommendations.push({
                type: 'using_ptp',
                severity: 'info',
                message: `Time is synchronized from PTP source (${result.referenceName}). This is the recommended configuration for Azure VMs.`
            });
        }
        
        // Check leap status
        if (result.leapStatus && result.leapStatus.toLowerCase() !== 'normal') {
            result.warnings.push({
                type: 'leap_status_abnormal',
                severity: 'warning',
                message: `Chrony leap status is "${result.leapStatus}" instead of "Normal".`,
                recommendation: 'Check chrony and time source status.'
            });
        }
        
        result.hasWarnings = result.warnings.length > 0;
        result.hasErrors = result.warnings.some(w => w.severity === 'error');
        
        debugLog('[chronyTracking parser] Result:', result);
        return result;
    }
};

/**
 * Parser: chronyMakestep
 * Checks chrony.conf for makestep configuration
 * Reference: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync
 */
const chronyMakestepParser = {
    // sosreport: etc/chrony.conf or etc/chrony/chrony.conf
    // SCC: ntp.txt (contains # /etc/chrony.conf section)
    filePattern: /\/etc\/chrony\.conf$|\/etc\/chrony\/chrony\.conf$|\/ntp\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[chronyMakestep parser] Analyzing:', filename);
        
        // For SCC ntp.txt, extract just the chrony.conf section
        let chronyConfContent = content;
        let sourceFile = filename;
        if (filename.includes('ntp.txt')) {
            debugLog('[chronyMakestep parser] Extracting chrony.conf section from SCC ntp.txt');
            const sectionResult = SCC_RULES.extractSection(content, filename, '# /etc/chrony.conf', '/etc/chrony.conf');
            if (!sectionResult.found) {
                debugLog('[chronyMakestep parser] chrony.conf section not found in ntp.txt');
                return { found: false };
            }
            chronyConfContent = sectionResult.content;
            sourceFile = 'ntp.txt (chrony.conf)';
            debugLog('[chronyMakestep parser] Extracted', sectionResult.lines.length, 'lines from chrony.conf section');
        }
        
        const result = {
            found: false,
            hasMakestep: false,
            makestepThreshold: null,
            makestepLimit: null,
            hasRefclock: false,
            refclockDevice: null,
            refclockPollInterval: null,
            usesHypervSymlink: false,
            warnings: [],
            recommendations: [],
            detectionFile: sourceFile
        };
        
        const lines = chronyConfContent.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            
            // Parse makestep directive: makestep <threshold> <limit>
            const makestepMatch = trimmed.match(/^makestep\s+([\d.]+)\s+(\d+)/i);
            if (makestepMatch) {
                result.hasMakestep = true;
                result.makestepThreshold = parseFloat(makestepMatch[1]);
                result.makestepLimit = parseInt(makestepMatch[2], 10);
                result.found = true;
                debugLog('[chronyMakestep parser] Found makestep:', result.makestepThreshold, result.makestepLimit);
            }
            
            // Parse refclock directive
            const refclockMatch = trimmed.match(/^refclock\s+PHC\s+(\/dev\/[^\s]+)(?:\s+poll\s+(\d+))?/i);
            if (refclockMatch) {
                result.hasRefclock = true;
                result.refclockDevice = refclockMatch[1];
                result.refclockPollInterval = refclockMatch[2] ? parseInt(refclockMatch[2], 10) : null;
                result.usesHypervSymlink = result.refclockDevice.includes('ptp_hyperv');
                result.found = true;
                debugLog('[chronyMakestep parser] Found refclock:', result.refclockDevice);
            }
        }
        
        // Generate warnings and recommendations
        if (result.found) {
            // Check makestep configuration
            if (!result.hasMakestep) {
                result.recommendations.push({
                    type: 'no_makestep',
                    severity: 'info',
                    message: 'makestep directive not configured. Large time jumps may not be corrected automatically.',
                    recommendation: 'Consider adding: makestep 1.0 3'
                });
            }
            
            // Check if refclock uses hardcoded device
            if (result.hasRefclock && !result.usesHypervSymlink && result.refclockDevice.match(/\/dev\/ptp\d+$/)) {
                result.warnings.push({
                    type: 'hardcoded_ptp_device',
                    severity: 'warning',
                    message: `Chrony is using hardcoded PTP device ${result.refclockDevice}. Device order may change after kernel updates.`,
                    recommendation: 'Use /dev/ptp_hyperv symlink instead: refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#chrony'
                });
            }
            
            // Check if no PTP refclock configured
            if (!result.hasRefclock) {
                result.warnings.push({
                    type: 'no_ptp_refclock',
                    severity: 'warning',
                    message: 'Chrony is not configured with PTP refclock from Azure host.',
                    recommendation: 'Add to chrony.conf: refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#chrony'
                });
            }
            
            // Good: using ptp_hyperv symlink
            if (result.usesHypervSymlink) {
                result.recommendations.push({
                    type: 'using_hyperv_symlink',
                    severity: 'info',
                    message: 'Chrony is correctly using /dev/ptp_hyperv symlink.'
                });
            }
        }
        
        result.hasWarnings = result.warnings.length > 0;
        
        debugLog('[chronyMakestep parser] Result:', result);
        return result;
    }
};

/**
 * Parser: rhuiConfig
 * Detects RHUI (Red Hat Update Infrastructure) configuration on Azure RHEL VMs
 * Checks EUS version lock consistency and RHUI repository configuration
 */
const rhuiConfigParser = {
    filePattern: /\/(rh-cloud.*\.repo|rhui-.*\.repo|yum\.repos\.d\.txt|dnf\.repos\.d\.txt|yum\.repos\.d\/.*\.repo)$/,
    parse: function(content, filename, _lines) {
        debugLog('[RHUI parser] Analyzing:', filename);
        const result = {
            found: false,
            repos: [],
            hasEusRepos: false,
            hasMicrosoftRepo: false,
            warnings: [],
            recommendations: []
        };
        const lines = _lines || content.split('\n');
        let currentRepo = null;
        const rhuiRepoPattern = /^(rhui-)?microsoft.*/i;
        const eusRepoPattern = /.*-(eus|e4s)-.*/i;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line || line.startsWith('#')) continue;
            const repoMatch = line.match(/^\[([^\]]+)\]$/);
            if (repoMatch) {
                if (currentRepo) {
                    result.repos.push(currentRepo);
                }
                currentRepo = {
                    name: repoMatch[1],
                    enabled: true,
                    isMicrosoft: rhuiRepoPattern.test(repoMatch[1]),
                    isEus: eusRepoPattern.test(repoMatch[1]),
                    baseurl: null
                };
                continue;
            }
            if (currentRepo) {
                const enabledMatch = line.match(/^enabled\s*=\s*(\d+)/i);
                if (enabledMatch) {
                    currentRepo.enabled = enabledMatch[1] === '1';
                }
                const baseurlMatch = line.match(/^baseurl\s*=\s*(.+)/i);
                if (baseurlMatch) {
                    currentRepo.baseurl = baseurlMatch[1];
                }
            }
        }
        if (currentRepo) {
            result.repos.push(currentRepo);
        }
        for (const repo of result.repos) {
            if (repo.isMicrosoft && repo.enabled) {
                result.hasMicrosoftRepo = true;
                result.found = true;
            }
            if (repo.isEus && repo.enabled) {
                result.hasEusRepos = true;
                result.found = true;
            }
        }
        if (result.repos.length > 0) {
            result.found = true;
        }
        const enabledMicrosoftRepos = result.repos.filter(r => r.isMicrosoft && r.enabled);
        if (enabledMicrosoftRepos.length === 0 && result.repos.some(r => r.isMicrosoft)) {
            result.warnings.push({
                type: 'rhui_repo_disabled',
                message: 'Microsoft RHUI repository is installed but not enabled',
                recommendation: 'Enable the repository with: yum-config-manager --enable <repo-name>',
                documentationUrl: 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui'
            });
        }
        debugLog('[RHUI parser] Found:', result);
        return result;
    }
};

/**
 * Parser: eusVersionLock
 * Detects EUS (Extended Update Support) version lock configuration on RHEL VMs
 * Checks /etc/yum/vars/releasever or /etc/dnf/vars/releasever
 */
const eusVersionLockParser = {
    filePattern: /\/(releasever|yum-vars\.txt|dnf-vars\.txt|etc\/yum\/vars|etc\/dnf\/vars|dnf\/vars\/releasever|yum\/vars\/releasever)$/,
    parse: function(content, filename, _lines) {
        debugLog('[EUS Version Lock parser] Analyzing:', filename);
        const result = {
            found: false,
            hasReleaseverFile: false,
            releasever: null,
            source: filename,
            warnings: [],
            recommendations: []
        };
        const trimmedContent = content.trim();
        if (trimmedContent) {
            const versionMatch = trimmedContent.match(/^(\d+(\.\d+)?)/m);
            if (versionMatch) {
                result.releasever = versionMatch[1];
                result.hasReleaseverFile = true;
                result.found = true;
                debugLog('[EUS Version Lock parser] Found releasever:', result.releasever);
            } else if (trimmedContent.match(/^[0-9]/)) {
                result.releasever = trimmedContent.split('\n')[0].trim();
                result.hasReleaseverFile = true;
                result.found = true;
            }
        }
        debugLog('[EUS Version Lock parser] Result:', result);
        return result;
    }
};

/**
 * Parser: rhelRhuiCheck
 * Comprehensive RHUI health check for Red Hat VMs on Azure
 * Validates RHUI packages, certificates, and configuration consistency
 */
const rhelRhuiCheckParser = {
    filePattern: /\/(installed-rpms|rpm-qa\.txt|rpm_-qa|package-data)$/,
    parse: function(content, filename, _lines) {
        debugLog('[RHEL RHUI Check parser] Analyzing:', filename);
        const result = {
            found: false,
            rhuiPackages: [],
            hasRhuiPackage: false,
            rhuiType: null,
            isEus: false,
            isSap: false,
            warnings: [],
            recommendations: []
        };
        const lines = _lines || content.split('\n');
        const rhuiPackagePattern = /^(rhui-[a-zA-Z0-9\-\.]+)/;
        const eusPattern = /-eus-|-e4s-/i;
        const sapPattern = /-sap-/i;
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            const match = trimmed.match(rhuiPackagePattern);
            if (match) {
                const pkgName = match[1];
                result.rhuiPackages.push(pkgName);
                result.hasRhuiPackage = true;
                result.found = true;
                if (eusPattern.test(pkgName)) {
                    result.isEus = true;
                    result.rhuiType = 'EUS';
                }
                if (sapPattern.test(pkgName)) {
                    result.isSap = true;
                    result.rhuiType = result.isEus ? 'SAP-EUS' : 'SAP';
                }
                if (!result.rhuiType) {
                    result.rhuiType = 'Standard';
                }
            }
        }
        if (!result.hasRhuiPackage) {
            result.warnings.push({
                type: 'rhui_package_missing',
                message: 'No RHUI package found. RHEL VMs on Azure require RHUI packages for updates.',
                recommendation: 'Install the appropriate RHUI package for your subscription type.',
                documentationUrl: 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/troubleshoot-linux-rhui-certificate-issues#cause-3-rhui-package-is-missing'
            });
        }
        debugLog('[RHEL RHUI Check parser] Found:', result);
        return result;
    }
};

/**
 * Parser: cryptoPolicies
 * Checks crypto policies on RHEL 8+ systems (can affect RHUI connectivity)
 */
const cryptoPoliciesParser = {
    filePattern: /\/crypto-policies\/(config|state\/current)$/,
    parse: function(content, filename, _lines) {
        debugLog('[Crypto Policies parser] Analyzing:', filename);
        const result = {
            found: false,
            policy: null,
            isDefault: true,
            warnings: [],
            recommendations: []
        };
        const trimmedContent = content.trim();
        if (trimmedContent) {
            result.policy = trimmedContent.split('\n')[0].trim();
            result.found = true;
            result.isDefault = result.policy === 'DEFAULT' || result.policy === 'DEFAULT:SHA1';
            if (!result.isDefault) {
                result.warnings.push({
                    type: 'crypto_policy_non_default',
                    message: `Crypto policy is set to '${result.policy}' instead of 'DEFAULT'. This can cause RHUI certificate verification failures.`,
                    recommendation: 'Set crypto policy to DEFAULT: update-crypto-policies --set DEFAULT',
                    documentationUrl: 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues#cause-5-verification-error-in-rhel-version-8-or-9-ca-certificate-key-too-weak'
                });
            }
        }
        debugLog('[Crypto Policies parser] Found:', result);
        return result;
    }
};

/**
 * Parser: rhuiErrors
 * Detects RHUI connectivity issues from dnf/yum logs
 * Identifies certificate expiration, HTTP errors, and EUS availability issues
 */
const rhuiErrorsParser = {
    filePattern: /\/(dnf\.log|yum\.log|rhsm\.log)(\.\d+)?$/,
    processAllRotations: true,
    parse: function(content, filename, _lines) {
        debugLog('[RHUI Errors parser] Analyzing:', filename);
        const result = {
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
        const lines = _lines || content.split('\n');
        const certExpirationPatterns = [
            /SSL certificate problem.*expired/i,
            /certificate has expired/i,
            /Peer's Certificate has expired/i,
            /CERTIFICATE_VERIFY_FAILED/i,
            /SSL peer certificate.*not valid/i,
            /certificate verify failed/i,
            /unable to get local issuer certificate/i
        ];
        const http403Pattern = /Status code: 403 for https:\/\/rhui-?\d*\.?microsoft\.com/i;
        const http400Pattern = /Status code: 400 for https:\/\/rhui-?\d*\.?microsoft\.com([^\s]*)/i;
        const repoErrorPattern = /Failed to download metadata for repo[:\s]+['"]?([^'":\s]+)['"]?[:\s]*(.*)$/i;
        const curlTimeoutPattern = /Curl error \(28\).*Timeout|Operation timed out/i;
        const curlConnectionPattern = /Curl error \(7\)|Could not resolve host|Connection timed out|Connection refused|Curl error \(6\)/i;
        const http404Pattern = /Status code: 404/i;
        const seenErrors = new Set();
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            for (const pattern of certExpirationPatterns) {
                if (pattern.test(line)) {
                    result.hasCertExpiration = true;
                    result.found = true;
                    const errorKey = 'cert_expired';
                    if (!seenErrors.has(errorKey)) {
                        seenErrors.add(errorKey);
                        result.errors.push({
                            type: 'certificate_expired',
                            line: i + 1,
                            message: 'RHUI client certificate has expired',
                            sample: line.trim().substring(0, 200)
                        });
                    }
                    break;
                }
            }
            if (http403Pattern.test(line)) {
                result.hasHttp403 = true;
                result.found = true;
                const errorKey = 'http_403';
                if (!seenErrors.has(errorKey)) {
                    seenErrors.add(errorKey);
                    result.errors.push({
                        type: 'http_403',
                        line: i + 1,
                        message: 'HTTP 403 Forbidden from RHUI servers - client certificate likely expired or invalid',
                        sample: line.trim().substring(0, 200)
                    });
                }
            }
            const http400Match = line.match(http400Pattern);
            if (http400Match) {
                result.hasHttp400 = true;
                result.found = true;
                const url = http400Match[1] || '';
                const eusVersionMatch = url.match(/\/eus\/rhel\d+\/rhui\/(\d+\.\d+)\//);
                const eusVersion = eusVersionMatch ? eusVersionMatch[1] : null;
                const errorKey = 'http_400_' + (eusVersion || 'unknown');
                if (!seenErrors.has(errorKey)) {
                    seenErrors.add(errorKey);
                    result.errors.push({
                        type: 'http_400',
                        line: i + 1,
                        message: eusVersion 
                            ? `HTTP 400 Bad Request - EUS version ${eusVersion} may no longer be available`
                            : 'HTTP 400 Bad Request from RHUI servers',
                        eusVersion: eusVersion,
                        sample: line.trim().substring(0, 200)
                    });
                }
            }
            const repoMatch = line.match(repoErrorPattern);
            if (repoMatch) {
                const repoName = repoMatch[1];
                const errorDetails = repoMatch[2] || '';
                const isRhuiRepo = /rhui|microsoft/i.test(repoName) || /rhui|microsoft/i.test(errorDetails);
                
                if (!result.affectedRepos.includes(repoName)) {
                    result.affectedRepos.push(repoName);
                    result.found = true;
                }
                
                // Detect specific error types from the error details
                if (curlTimeoutPattern.test(line) && isRhuiRepo) {
                    result.hasConnectionError = true;
                    const errorKey = `timeout_${repoName}`;
                    if (!seenErrors.has(errorKey)) {
                        seenErrors.add(errorKey);
                        result.errors.push({
                            type: 'timeout',
                            line: i + 1,
                            repo: repoName,
                            message: `Connection timeout to RHUI server for repo '${repoName}'`,
                            sample: line.trim().substring(0, 300)
                        });
                    }
                } else if (curlConnectionPattern.test(line) && isRhuiRepo) {
                    result.hasConnectionError = true;
                    const errorKey = `connection_${repoName}`;
                    if (!seenErrors.has(errorKey)) {
                        seenErrors.add(errorKey);
                        result.errors.push({
                            type: 'connection_error',
                            line: i + 1,
                            repo: repoName,
                            message: `Connection error to RHUI server for repo '${repoName}'`,
                            sample: line.trim().substring(0, 300)
                        });
                    }
                } else if (http404Pattern.test(line) && !isRhuiRepo) {
                    // Non-RHUI repo with 404 (like EPEL mirror issues)
                    const errorKey = `http404_${repoName}`;
                    if (!seenErrors.has(errorKey)) {
                        seenErrors.add(errorKey);
                        result.errors.push({
                            type: 'http_404',
                            line: i + 1,
                            repo: repoName,
                            message: `Metadata download failed for '${repoName}' (mirror sync issue)`,
                            sample: line.trim().substring(0, 300)
                        });
                    }
                } else if (isRhuiRepo) {
                    // Generic RHUI repo error
                    const errorKey = `repo_error_${repoName}`;
                    if (!seenErrors.has(errorKey)) {
                        seenErrors.add(errorKey);
                        result.errors.push({
                            type: 'repo_error',
                            line: i + 1,
                            repo: repoName,
                            message: `Failed to download metadata for RHUI repo '${repoName}'`,
                            sample: line.trim().substring(0, 300)
                        });
                    }
                }
            }
            // Also check for connection errors on lines without repo match (standalone error lines)
            if (!repoMatch && (curlTimeoutPattern.test(line) || curlConnectionPattern.test(line)) && /rhui|microsoft/i.test(line)) {
                result.hasConnectionError = true;
                result.found = true;
                const errorKey = 'connection_error';
                if (!seenErrors.has(errorKey)) {
                    seenErrors.add(errorKey);
                    result.errors.push({
                        type: 'connection_error',
                        line: i + 1,
                        message: 'Network connectivity issue to RHUI servers',
                        sample: line.trim().substring(0, 200)
                    });
                }
            }
        }
        if (result.hasCertExpiration || result.hasHttp403) {
            result.warnings.push({
                type: 'rhui_cert_expired',
                message: 'RHUI client certificate appears to be expired or invalid',
                recommendation: 'Reinstall the RHUI package to renew certificates: sudo yum reinstall $(rpm -qa | grep rhui)',
                documentationUrl: 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues'
            });
        }
        if (result.hasHttp400) {
            const eusError = result.errors.find(e => e.type === 'http_400' && e.eusVersion);
            if (eusError) {
                result.warnings.push({
                    type: 'eus_version_unavailable',
                    message: `EUS version ${eusError.eusVersion} may no longer be available on Azure RHUI`,
                    recommendation: 'Update /etc/dnf/vars/releasever to a supported EUS version, or switch to standard RHUI repos',
                    documentationUrl: 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui#rhel-eus-and-version-locking-rhel-vms'
                });
            } else {
                result.warnings.push({
                    type: 'rhui_bad_request',
                    message: 'HTTP 400 errors from RHUI servers indicate configuration issues',
                    recommendation: 'Verify RHUI configuration and try reinstalling the RHUI package',
                    documentationUrl: 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues'
                });
            }
        }
        if (result.hasConnectionError) {
            result.warnings.push({
                type: 'rhui_connectivity',
                message: 'Network connectivity issues to RHUI servers detected',
                recommendation: 'Check network configuration, NSG rules, and firewall settings. Ensure the VM can reach rhui-*.microsoft.com on port 443',
                documentationUrl: 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui#troubleshoot-connection-problems-to-azure-rhui'
            });
        }
        debugLog('[RHUI Errors parser] Found:', result);
        return result;
    }
};

/**
 * Parser: leappReport
 * Detects Red Hat Leapp in-place upgrade issues from leapp-report.txt
 * Parses risk factors, errors, and recommendations from upgrade analysis
 * 
 * Reference: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/upgrading_from_rhel_8_to_rhel_9/index
 */
const leappReportParser = {
    filePattern: /var\/log\/leapp\/leapp-report\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[leappReport parser] Analyzing:', filename);
        
        const result = {
            found: false,
            hasErrors: false,
            hasHighRisk: false,
            hasMediumRisk: false,
            upgradeBlocked: false,
            totalIssues: 0,
            errorCount: 0,
            highRiskCount: 0,
            mediumRiskCount: 0,
            lowRiskCount: 0,
            infoCount: 0,
            issues: [],
            errors: [],      // Items with (error) flag
            highRisk: [],    // High risk items (warnings)
            mediumRisk: [],  // Medium risk items
            info: [],        // Info items
            thirdPartyPackages: [],
            warnings: [],
            recommendations: [],
            detectionFile: filename
        };
        
        // Split by separator line
        const entries = content.split(/^-{30,}$/m).filter(e => e.trim());
        
        for (const entry of entries) {
            const lines = entry.trim().split('\n');
            if (lines.length < 2) continue;
            
            let riskFactor = null;
            let isError = false;
            let title = null;
            let summary = '';
            let remediation = null;
            let relatedLinks = [];
            let key = null;
            
            let currentField = null;
            
            for (const line of lines) {
                // Parse Risk Factor
                const riskMatch = line.match(/^Risk Factor:\s*(\w+)(?:\s*\(error\))?/i);
                if (riskMatch) {
                    riskFactor = riskMatch[1].toLowerCase();
                    isError = /\(error\)/i.test(line);
                    currentField = null;
                    continue;
                }
                
                // Parse Title
                const titleMatch = line.match(/^Title:\s*(.+)/);
                if (titleMatch) {
                    title = titleMatch[1].trim();
                    currentField = null;
                    continue;
                }
                
                // Parse Summary (can be multiline)
                const summaryMatch = line.match(/^Summary:\s*(.*)/);
                if (summaryMatch) {
                    summary = summaryMatch[1];
                    currentField = 'summary';
                    continue;
                }
                
                // Parse Remediation
                const remediationMatch = line.match(/^Remediation:\s*(.*)/);
                if (remediationMatch) {
                    remediation = remediationMatch[1];
                    currentField = 'remediation';
                    continue;
                }
                
                // Parse Related links
                if (/^Related links:/i.test(line)) {
                    currentField = 'links';
                    continue;
                }
                
                // Parse Key
                const keyMatch = line.match(/^Key:\s*(\w+)/);
                if (keyMatch) {
                    key = keyMatch[1];
                    currentField = null;
                    continue;
                }
                
                // Continue multiline fields
                if (currentField === 'summary' && line.trim()) {
                    summary += ' ' + line.trim();
                } else if (currentField === 'remediation' && line.trim()) {
                    remediation += ' ' + line.trim();
                } else if (currentField === 'links') {
                    const linkMatch = line.match(/^\s*-\s*(.+?):\s*(https?:\/\/\S+)/);
                    if (linkMatch) {
                        relatedLinks.push({ text: linkMatch[1], url: linkMatch[2] });
                    }
                }
            }
            
            if (!title) continue;
            
            result.found = true;
            result.totalIssues++;
            
            const issue = {
                riskFactor: riskFactor,
                isError: isError,
                title: title,
                summary: summary.trim(),
                remediation: remediation,
                relatedLinks: relatedLinks,
                key: key
            };
            
            result.issues.push(issue);
            
            // Categorize by risk level
            if (isError) {
                result.errors.push(issue);
                result.errorCount++;
                result.hasErrors = true;
                result.upgradeBlocked = true;
            } else if (riskFactor === 'high') {
                result.highRisk.push(issue);
                result.highRiskCount++;
                result.hasHighRisk = true;
            } else if (riskFactor === 'medium') {
                result.mediumRisk.push(issue);
                result.mediumRiskCount++;
                result.hasMediumRisk = true;
            } else if (riskFactor === 'low') {
                result.lowRiskCount++;
            } else if (riskFactor === 'info') {
                result.info.push(issue);
                result.infoCount++;
            }
            
            // Extract third-party packages if mentioned
            if (title.includes('not signed by the distribution vendor')) {
                const pkgMatch = summary.match(/The following packages have not been signed[^:]*:([\s\S]*?)(?:Related links|Remediation|$)/i);
                if (pkgMatch) {
                    const pkgList = pkgMatch[1].match(/-\s*(\S+)/g);
                    if (pkgList) {
                        result.thirdPartyPackages = pkgList.map(p => p.replace(/^-\s*/, ''));
                    }
                }
            }
        }
        
        // Generate warnings
        if (result.upgradeBlocked) {
            result.warnings.push({
                type: 'leapp_upgrade_blocked',
                severity: 'error',
                message: `Leapp detected ${result.errorCount} error(s) that will block the upgrade`,
                recommendation: 'Review and resolve all errors before attempting the upgrade',
                documentationUrl: 'https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/upgrading_from_rhel_8_to_rhel_9/index'
            });
        }
        
        if (result.hasHighRisk && !result.upgradeBlocked) {
            result.warnings.push({
                type: 'leapp_high_risk',
                severity: 'warning',
                message: `Leapp detected ${result.highRiskCount} high-risk warning(s) that should be reviewed before upgrade`,
                recommendation: 'Review high-risk items and ensure you understand their implications'
            });
        }
        
        if (result.thirdPartyPackages.length > 0) {
            result.warnings.push({
                type: 'leapp_third_party',
                severity: 'warning',
                message: `${result.thirdPartyPackages.length} third-party packages detected that may need manual handling`,
                recommendation: 'Consider removing third-party packages before upgrade and reinstalling after'
            });
        }
        
        debugLog('[leappReport parser] Found:', result);
        return result;
    }
};

/**
 * Parser: leappLog
 * Detects detailed errors from leapp-preupgrade.log or leapp-upgrade.log
 * Captures curl errors, DNS failures, and other technical issues
 * 
 * Reference: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/upgrading_from_rhel_8_to_rhel_9/index
 */
const leappLogParser = {
    filePattern: /var\/log\/leapp\/leapp-(preupgrade|upgrade)\.log$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[leappLog parser] Analyzing:', filename);
        
        const result = {
            found: false,
            hasErrors: false,
            hasCurlErrors: false,
            hasDnsErrors: false,
            hasRhuiErrors: false,
            errorCount: 0,
            warningCount: 0,
            criticalCount: 0,
            errors: [],
            curlErrors: [],
            dnsErrors: [],
            rhuiErrors: [],
            warnings: [],
            recommendations: [],
            detectionFile: filename
        };
        
        const lines = _lines || content.split('\n');
        const seenErrors = new Set();
        
        // Patterns for different error types
        // Format: Curl error (6): Couldn't resolve host name for https://... [Could not resolve host: ...]
        // Primary pattern (with URL) - requires 'for' to properly capture message
        const curlErrorWithUrlPattern = /Curl error \((\d+)\):\s*(.+?)\s+for\s+(https?:\/\/[^\s\[]+)(?:\s*\[([^\]]+)\])?/i;
        // Fallback pattern (without URL)
        const curlErrorSimplePattern = /Curl error \((\d+)\):\s*([^\[\n]+)/i;
        const dnsErrorPattern = /Could not resolve host[:\s]*([^\]\s]+)|Couldn't resolve host name/i;
        const errorLinePattern = /^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}[.\d]*\s+ERROR\s+/;
        const criticalLinePattern = /^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}[.\d]*\s+CRITICAL\s+/;
        const rhuiPattern = /rhui.*microsoft|microsoft.*rhui/i;
        const failedCommandPattern = /failed with exit code (\d+)/i;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Check for curl errors - try pattern with URL first, then simple fallback
            let curlMatch = line.match(curlErrorWithUrlPattern);
            let hasUrl = true;
            if (!curlMatch) {
                curlMatch = line.match(curlErrorSimplePattern);
                hasUrl = false;
            }
            if (curlMatch) {
                result.found = true;
                result.hasCurlErrors = true;
                
                const errorCode = curlMatch[1];
                const errorMessage = curlMatch[2] ? curlMatch[2].trim() : '';
                const url = hasUrl ? (curlMatch[3] || '') : '';
                const detail = hasUrl ? (curlMatch[4] || '') : '';
                
                // Check if it's a DNS error (curl error 6)
                if (errorCode === '6' || dnsErrorPattern.test(line)) {
                    result.hasDnsErrors = true;
                    let host = 'unknown';
                    if (url) {
                        try { host = new URL(url).hostname; } catch (e) { /* ignore */ }
                    }
                    if (host === 'unknown' && detail) {
                        const hostMatch = detail.match(/host:\s*(\S+)/i);
                        if (hostMatch) host = hostMatch[1];
                    }
                    const errorKey = `dns_${host}`;
                    if (!seenErrors.has(errorKey)) {
                        seenErrors.add(errorKey);
                        result.dnsErrors.push({
                            type: 'dns_resolution',
                            curlCode: parseInt(errorCode),
                            line: i + 1,
                            host: host,
                            url: url,
                            message: errorMessage || 'Couldn\'t resolve host name',
                            sample: line.trim().substring(0, 400)
                        });
                        result.errorCount++;
                    }
                }
                
                // Check if RHUI related
                if (rhuiPattern.test(line) || rhuiPattern.test(url)) {
                    result.hasRhuiErrors = true;
                    const errorKey = `rhui_curl_${errorCode}`;
                    if (!seenErrors.has(errorKey)) {
                        seenErrors.add(errorKey);
                        result.rhuiErrors.push({
                            type: 'rhui_connection',
                            curlCode: parseInt(errorCode),
                            line: i + 1,
                            url: url,
                            message: errorMessage || 'Connection error',
                            sample: line.trim().substring(0, 400)
                        });
                    }
                }
                
                // General curl error
                const errorKey = `curl_${errorCode}_${url}`;
                if (!seenErrors.has(errorKey)) {
                    seenErrors.add(errorKey);
                    result.curlErrors.push({
                        type: 'curl_error',
                        curlCode: parseInt(errorCode),
                        line: i + 1,
                        url: url,
                        message: errorMessage || 'Unknown error',
                        detail: detail,
                        sample: line.trim().substring(0, 400)
                    });
                }
            }
            
            // Check for ERROR level log lines
            if (errorLinePattern.test(line)) {
                result.found = true;
                result.hasErrors = true;
                
                // Extract the error message
                const msgMatch = line.match(/ERROR\s+PID:\s*\d+\s+[\w.]+:\s*(.+)/);
                if (msgMatch) {
                    const errorMsg = msgMatch[1];
                    const errorKey = `error_${errorMsg.substring(0, 50)}`;
                    if (!seenErrors.has(errorKey)) {
                        seenErrors.add(errorKey);
                        result.errors.push({
                            type: 'leapp_error',
                            line: i + 1,
                            message: errorMsg.substring(0, 300),
                            sample: line.trim().substring(0, 400)
                        });
                        result.errorCount++;
                    }
                }
            }
            
            // Check for CRITICAL level log lines
            if (criticalLinePattern.test(line)) {
                result.found = true;
                result.hasErrors = true;
                result.criticalCount++;
            }
        }
        
        // Generate warnings based on findings
        if (result.hasDnsErrors) {
            const hosts = result.dnsErrors.map(e => e.host).filter((v, i, a) => a.indexOf(v) === i);
            result.warnings.push({
                type: 'leapp_dns_failure',
                severity: 'error',
                message: `DNS resolution failed for: ${hosts.join(', ')}`,
                recommendation: 'Check DNS configuration (/etc/resolv.conf), NSG rules, and network connectivity. Ensure the VM can resolve rhui*.microsoft.com',
                documentationUrl: 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui#troubleshoot-connection-problems-to-azure-rhui'
            });
        }
        
        if (result.hasRhuiErrors && !result.hasDnsErrors) {
            result.warnings.push({
                type: 'leapp_rhui_connection',
                severity: 'error',
                message: 'RHUI connection errors detected during Leapp upgrade',
                recommendation: 'Check network connectivity to Azure RHUI servers. Verify firewall rules allow HTTPS (443) to rhui*.microsoft.com',
                documentationUrl: 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui#troubleshoot-connection-problems-to-azure-rhui'
            });
        }
        
        debugLog('[leappLog parser] Found:', result);
        return result;
    }
};