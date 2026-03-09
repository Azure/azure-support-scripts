/**
 * @module parsers/azure
 * @description Azure VM metadata, billing model detection, and Azure Linux Agent configuration.
 *
 * ### azureVMPropertiesParser
 *
 * Extracts Azure VM properties from the IMDS (Instance Metadata Service)
 * snapshot captured by supportconfig or sosreport.
 *
 * | Property | Source |
 * |----------|--------|
 * | vmSize, publisher, offer, sku | `compute` object |
 * | licenseType | `compute.licenseType` |
 * | billingCode | `compute.billingCode` |
 * | osDiskType, dataDisks | `compute.storageProfile` |
 *
 * Billing model (PAYG vs BYOS) is determined by a two-rule cascade:
 * 1. **licenseType** takes precedence (e.g. `RHEL_BYOS`, `SLES`, `UBUNTU_PRO`).
 * 2. **billingCode** is used as fallback (e.g. `Linux_IaaS_SUSE`, `Linux_IaaS`).
 *
 * Input files:
 * - SOS: `instance_metadata.json` (JSON)
 * - SCC: `public_cloud/metadata.txt` (key-value pairs, parsed by `parseSCCMetadata()`)
 *
 * Returns: `{ found, vmSize, publisher, offer, sku, billingCode, licenseType,`
 * `billingModel, detectionMethod, osDiskType, dataDisks, hasUltraDisk, hasPremiumV2 }`
 *
 * ### suseCloudRegisterParser
 *
 * Detects SUSE cloud registration server from `public_cloud/cloudregister.txt`
 * and infers the billing model:
 * - PAYG: smt-azure, susecloud.net, update.suse.com
 * - BYOS: scc.suse.com, custom RMT servers
 *
 * Returns: `{ found, billingModel, detectionMethod, registrationServer, registrationType }`
 *
 * ### waagentConfigParser
 *
 * Parses `/etc/waagent.conf` — the Azure Linux Agent (walinuxagent)
 * configuration file.  Extracts key settings and flags potential concerns.
 *
 * | Setting group | Keys extracted |
 * |---------------|---------------|
 * | Extensions | `Extensions.Enabled` |
 * | Provisioning | `Provisioning.Agent`, `Provisioning.Enabled` |
 * | Resource disk | `ResourceDisk.Format`, `ResourceDisk.EnableSwap`, `ResourceDisk.SwapSizeMB`, `ResourceDisk.MountPoint` |
 * | Firewall | `OS.EnableFirewall` |
 * | FIPS | `OS.EnableFIPS` |
 * | SCSI timeout | `OS.RootDeviceScsiTimeout` |
 * | Logging | `Logs.Verbose`, `Logs.Collect` |
 * | AutoUpdate | `AutoUpdate.Enabled`, `AutoUpdate.GAFamily` |
 *
 * Warnings are raised when:
 * - Extensions are disabled (`Extensions.Enabled=n`)
 * - Swap is enabled on the resource disk (`ResourceDisk.EnableSwap=y`)
 * - The OS-level firewall is disabled (`OS.EnableFirewall=n`)
 * - FIPS mode is enabled (`OS.EnableFIPS=y`)
 *
 * Input files: `/etc/waagent.conf` (INI-like key=value, no sections)
 *
 * Returns: `{ found, config, warnings }`
 *
 * ### waagentLogParser
 *
 * Parses `waagent.log` — the Azure Linux Agent runtime log.
 * Extracts agent version, goal state errors, extension operation failures,
 * resource disk errors, IMDS connectivity issues, and extension status summaries.
 *
 * | Category | Detection Pattern |
 * |----------|-------------------|
 * | Agent version | `[HEARTBEAT] Agent WALinuxAgent-X.Y.Z` |
 * | Goal state errors | `Error fetching the goal state` |
 * | Extension errors | `op=Enable, message=...Error` with ERROR level |
 * | Resource disk errors | `ResourceDisk` with ERROR level |
 * | IMDS errors | `IMDS_CONNECTION_ERROR` |
 * | Extension status | `Extension status:` lines listing extension states |
 * | Status file errors | `no status file was reported` warnings |
 *
 * Input files: `waagent.log` (timestamped log lines)
 *
 * Returns: `{ found, agentVersion, agentVersionHistory, errors, warnings,
 *   goalStateErrors, extensionErrors, resourceDiskErrors, imdsErrors,
 *   extensionStatusSummary, hasErrors, hasWarnings }`
 *
 * @see {@link module:worker} for registration in SCC_RULES
 */

// Debug logging - checks global DEBUG_CONFIG from worker.js
function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.azure) {
        console.log('[azure.js]', ...args);
    }
}

const azureVMPropertiesParser = {
    filePattern: /(?:instance_metadata\.json|public_cloud\/metadata\.txt)$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[azureVMProperties parser] Analyzing Azure VM metadata in:', filename);
        
        // Check if this is a key-value text file (SCC format) or JSON (sosreport format)
        if (filename.endsWith('metadata.txt')) {
            // Parse SCC format: key: value pairs
            debugLog('[azureVMProperties parser] Parsing SCC metadata.txt format');
            return this.parseSCCMetadata(content);
        }
        
        // Parse JSON format (sosreport)
        try {
            const metadata = JSON.parse(content);
            // Extract properties from root or compute object
            const compute = metadata.compute || metadata;
            const vmSize = compute.vmSize || metadata.vmSize || null;
            const offer = compute.offer || metadata.offer || null;
            const publisher = compute.publisher || metadata.publisher || null;
            const sku = compute.sku || metadata.sku || null;
            const licenseType = compute.licenseType || metadata.licenseType || null;
            const billingCode = compute.billingCode || metadata.billingCode || null;
            
            // Extract storage profile information
            let osDiskType = null;
            let dataDisks = [];
            
            if (compute.storageProfile) {
                // Extract OS disk type
                if (compute.storageProfile.osDisk && compute.storageProfile.osDisk.managedDisk) {
                    osDiskType = compute.storageProfile.osDisk.managedDisk.storageAccountType || null;
                }
                
                // Extract data disks
                if (compute.storageProfile.dataDisks && Array.isArray(compute.storageProfile.dataDisks)) {
                    dataDisks = compute.storageProfile.dataDisks.map(disk => ({
                        lun: disk.lun,
                        name: disk.name || null,
                        diskSizeGB: disk.diskSizeGB || null,
                        storageAccountType: disk.managedDisk ? disk.managedDisk.storageAccountType : null
                    }));
                }
            }
            
            // Determine PAYG vs BYOS based on official Azure rules
            let billingModel = null;
            let detectionMethod = null;
            
            // Normalize licenseType: treat empty or whitespace-only strings as not-available
            const licenseTypeUpper = (typeof licenseType === 'string' && licenseType.trim() !== '') ? licenseType.trim().toUpperCase() : null;
            
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
            debugLog('[azureVMProperties parser] OS Disk Type:', osDiskType);
            debugLog('[azureVMProperties parser] Data Disks Count:', dataDisks.length);
            
            return {
                found: true,
                vmSize: vmSize,
                publisher: publisher,
                offer: offer,
                sku: sku,
                billingCode: billingCode,
                licenseType: licenseType,
                billingModel: billingModel,
                detectionMethod: detectionMethod,
                osDiskType: osDiskType,
                dataDisks: dataDisks,
                hasUltraDisk: osDiskType === 'UltraSSD_LRS' || dataDisks.some(d => d.storageAccountType === 'UltraSSD_LRS'),
                hasPremiumV2: osDiskType === 'PremiumV2_LRS' || dataDisks.some(d => d.storageAccountType === 'PremiumV2_LRS')
            };
        } catch (e) {
            debugLog('[azureVMProperties parser] Failed to parse JSON:', e);
            return { found: false };
        }
    },
    
    // Helper function to parse SCC metadata.txt format (key: value pairs)
    parseSCCMetadata: function(content) {
        debugLog('[azureVMProperties parser] Parsing SCC metadata key-value format');
        const lines = content.split('\n');
        
        let vmSize = null;
        let offer = null;
        let publisher = null;
        let sku = null;
        let licenseType = null;
        let billingCode = null;
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            
            // Parse key: value format
            const match = trimmed.match(/^(\w+):\s*(.+)$/);
            if (match) {
                const key = match[1];
                const value = match[2].trim();
                
                switch (key) {
                    case 'vmSize':
                        vmSize = value;
                        break;
                    case 'offer':
                        offer = value;
                        break;
                    case 'publisher':
                        publisher = value;
                        break;
                    case 'sku':
                        sku = value;
                        break;
                    case 'licenseType':
                        licenseType = value;
                        break;
                    case 'billingCode':
                        billingCode = value;
                        break;
                }
            }
        }
        
        // Determine PAYG vs BYOS based on official Azure rules
        let billingModel = null;
        let detectionMethod = null;
        
        // Normalize licenseType: treat empty or whitespace-only strings as not-available
        const licenseTypeUpper = (typeof licenseType === 'string' && licenseType.trim() !== '') ? licenseType.trim().toUpperCase() : null;
        
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
    }
};

const suseCloudRegisterParser = {
    filePattern: /public_cloud\/cloudregister\.txt$/,
    
    parse: function(content, filename, _lines) {
        debugLog('[suseCloudRegister parser] *** PARSING ***', filename);
        debugLog('[suseCloudRegister parser] Content length:', content.length);
        debugLog('[suseCloudRegister parser] Analyzing SUSE cloud registration in:', filename);
        
        let billingModel = null;
        let detectionMethod = null;
        let registrationServer = null;
        let registrationType = null;
        
        // Performance optimization: cloudregister.txt can be huge (1GB+)
        // Only read first 100KB which should contain registration info
        const maxChars = 100 * 1024; // 100 KB
        const truncatedContent = content.length > maxChars ? content.substring(0, maxChars) : content;
        debugLog('[suseCloudRegister parser] Truncated length:', truncatedContent.length);
        
        // Parse cloudregister.txt to extract registration information
        const lines = truncatedContent.split('\n');
        debugLog('[suseCloudRegister parser] Number of lines:', lines.length);
        
        // Show first few lines for debugging
        debugLog('[suseCloudRegister parser] First 3 lines:', lines.slice(0, 3));
        
        // Limit search to first 1000 lines for performance
        const searchLimit = Math.min(1000, lines.length);
        debugLog('[suseCloudRegister parser] Searching first', searchLimit, 'lines');
        
        for (let i = 0; i < searchLimit; i++) {
            const line = lines[i].trim();
            
            // Pattern 1: Log format: "Registration: /usr/sbin/SUSEConnect --url https://..."
            const connectMatch = line.match(/SUSEConnect\s+--url\s+(https?:\/\/[^\s]+)/i);
            if (connectMatch) {
                registrationServer = connectMatch[1].trim();
                debugLog('[suseCloudRegister parser] Found registration server (SUSEConnect) on line', i, ':', registrationServer);
                break; // Found it, no need to continue
            }
            
            // Pattern 2: Simple key=value format: "url = https://..."
            if (line.match(/url/i) && line.includes('=')) {
                const urlMatch = line.match(/url\s*=\s*(.+)/i);
                if (urlMatch) {
                    registrationServer = urlMatch[1].trim();
                    debugLog('[suseCloudRegister parser] Found registration server (url=) on line', i, ':', registrationServer);
                    break;
                }
            }
            
            // Pattern 3: Simple key=value format: "server = https://..."
            if (line.match(/server/i) && line.includes('=')) {
                const serverMatch = line.match(/server\s*=\s*(.+)/i);
                if (serverMatch && !registrationServer) {
                    registrationServer = serverMatch[1].trim();
                    debugLog('[suseCloudRegister parser] Found registration server (server=) on line', i, ':', registrationServer);
                    break;
                }
            }
        }
        
        debugLog('[suseCloudRegister parser] Final registrationServer:', registrationServer);
        
        // Determine BYOS vs PAYG based on registration server
        if (registrationServer) {
            const serverLower = registrationServer.toLowerCase();
            
            // PAYG indicators: Microsoft-managed SMT servers
            if (serverLower.includes('smt-azure') || 
                serverLower.includes('smt.suse.de') ||
                serverLower.includes('susecloud.net') ||
                serverLower.includes('update.suse.com')) {
                billingModel = 'PAYG';
                registrationType = 'Microsoft SMT (Subscription Management Tool)';
                detectionMethod = `Cloud Registration: ${registrationServer}`;
                debugLog('[suseCloudRegister parser] Detected PAYG via SMT server');
            }
            // BYOS indicators: SUSE Customer Center or custom RMT
            else if (serverLower.includes('scc.suse.com') ||
                     serverLower.includes('customer.suse.com')) {
                billingModel = 'BYOS';
                registrationType = 'SUSE Customer Center (SCC)';
                detectionMethod = `Cloud Registration: ${registrationServer}`;
                debugLog('[suseCloudRegister parser] Detected BYOS via SCC');
            }
            // Custom RMT server (likely BYOS)
            else if (serverLower.includes('rmt') || !serverLower.includes('suse')) {
                billingModel = 'BYOS';
                registrationType = 'Custom RMT Server';
                detectionMethod = `Cloud Registration: ${registrationServer}`;
                debugLog('[suseCloudRegister parser] Detected likely BYOS via custom RMT');
            }
        }
        
        if (!billingModel) {
            debugLog('[suseCloudRegister parser] Could not determine billing model from cloudregister.txt');
            return { found: false };
        }
        
        return {
            found: true,
            billingModel: billingModel,
            detectionMethod: detectionMethod,
            registrationServer: registrationServer,
            registrationType: registrationType
        };
    }
};

/**
 * Parses /etc/waagent.conf — the Azure Linux Agent configuration file.
 *
 * The file uses a simple `Key=Value` format with `#` comments (no INI
 * sections).  The parser extracts operationally-important settings and
 * raises warnings for risky configurations.
 */
const waagentConfigParser = {
    filePattern: /\/etc\/waagent\.conf$/,

    parse: function(content, filename, _lines) {
        debugLog('[waagentConfig parser] Analyzing waagent.conf:', filename);

        const config = {};
        const warnings = [];
        const lines = content.split('\n');

        for (const line of lines) {
            const trimmed = line.trim();
            // Skip blank lines and comments
            if (!trimmed || trimmed.startsWith('#')) continue;

            const eqIdx = trimmed.indexOf('=');
            if (eqIdx === -1) continue;

            const key = trimmed.substring(0, eqIdx).trim();
            const value = trimmed.substring(eqIdx + 1).trim();

            if (key) {
                config[key] = value;
            }
        }

        debugLog('[waagentConfig parser] Parsed keys:', Object.keys(config).length);

        if (Object.keys(config).length === 0) {
            return { found: false };
        }

        // --- Extract key settings into a structured summary ---
        const summary = {
            extensionsEnabled: this._normBool(config['Extensions.Enabled']),
            provisioningAgent: config['Provisioning.Agent'] || config['Provisioning.Enabled'] || null,
            resourceDiskFormat: this._normBool(config['ResourceDisk.Format']),
            resourceDiskEnableSwap: this._normBool(config['ResourceDisk.EnableSwap']),
            resourceDiskSwapSizeMB: config['ResourceDisk.SwapSizeMB'] ? parseInt(config['ResourceDisk.SwapSizeMB'], 10) : null,
            resourceDiskMountPoint: config['ResourceDisk.MountPoint'] || null,
            enableFirewall: this._normBool(config['OS.EnableFirewall']),
            enableFIPS: this._normBool(config['OS.EnableFIPS']),
            rootDeviceScsiTimeout: config['OS.RootDeviceScsiTimeout'] ? parseInt(config['OS.RootDeviceScsiTimeout'], 10) : null,
            logsVerbose: this._normBool(config['Logs.Verbose']),
            logsCollect: this._normBool(config['Logs.Collect']),
            autoUpdateEnabled: this._normBool(config['AutoUpdate.Enabled']),
            autoUpdateGAFamily: config['AutoUpdate.GAFamily'] || null,
        };

        // --- Warnings ---
        if (summary.extensionsEnabled === false) {
            warnings.push({
                severity: 'warning',
                setting: 'Extensions.Enabled',
                value: config['Extensions.Enabled'],
                message: 'VM extensions are disabled — extensions (monitoring, backups, CSE) will not run.'
            });
        }

        if (summary.resourceDiskEnableSwap === true) {
            const size = summary.resourceDiskSwapSizeMB || 0;
            warnings.push({
                severity: 'info',
                setting: 'ResourceDisk.EnableSwap',
                value: `${config['ResourceDisk.EnableSwap']} (${size} MB)`,
                message: 'Swap is enabled on the resource (temporary) disk. Data on this disk is not persistent across VM maintenance events.'
            });
        }

        if (summary.enableFirewall === false) {
            warnings.push({
                severity: 'warning',
                setting: 'OS.EnableFirewall',
                value: config['OS.EnableFirewall'],
                message: 'The Azure agent OS-level firewall (wire-server access control) is disabled.'
            });
        }

        if (summary.enableFIPS === true) {
            warnings.push({
                severity: 'info',
                setting: 'OS.EnableFIPS',
                value: config['OS.EnableFIPS'],
                message: 'FIPS mode is enabled for the Azure agent.'
            });
        }

        if (summary.autoUpdateEnabled === false) {
            warnings.push({
                severity: 'info',
                setting: 'AutoUpdate.Enabled',
                value: config['AutoUpdate.Enabled'],
                message: 'Auto-update of the Azure Linux Agent is disabled.'
            });
        }

        debugLog('[waagentConfig parser] Summary:', JSON.stringify(summary));
        debugLog('[waagentConfig parser] Warnings:', warnings.length);

        return {
            found: true,
            config: config,         // raw key-value map
            summary: summary,       // structured important settings
            warnings: warnings
        };
    },

    /** Normalise y/n/yes/no/true/false → boolean | null */
    _normBool: function(val) {
        if (val === undefined || val === null) return null;
        const v = val.toString().trim().toLowerCase();
        if (v === 'y' || v === 'yes' || v === 'true') return true;
        if (v === 'n' || v === 'no' || v === 'false') return false;
        return null;
    }
};

/**
 * Parser: waagentLog
 * Parses waagent.log — the Azure Linux Agent runtime log.
 * Extracts agent version history, categorised errors and warnings,
 * goal state fetch failures, extension operation errors, resource disk
 * problems, and IMDS connectivity issues.
 */
const waagentLogParser = {
    filePattern: /\/waagent\.log$/,

    parse: function(content, filename, _lines) {
        debugLog('[waagentLog parser] Analyzing waagent.log:', filename);

        const lines = _lines || content.split('\n');
        debugLog('[waagentLog parser] Total lines:', lines.length);

        // Timestamp regex: 2026-02-19T06:05:04.123456Z
        const tsRegex = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.\d+Z\s+/;

        // ── Agent version tracking ──
        const versionHistory = [];
        let currentVersion = null;
        const heartbeatRegex = /WALinuxAgent-(\S+)\s+is running/;

        // ── Error / warning categorisation ──
        const goalStateErrors = [];    // Goal state fetch failures
        const extensionErrors = [];    // Extension enable/install failures
        const resourceDiskErrors = []; // Resource disk mount/swap failures
        const imdsErrors = [];         // IMDS connectivity failures
        const statusFileWarnings = []; // Missing / corrupt status files
        const otherErrors = [];        // Uncategorised errors
        const otherWarnings = [];      // Uncategorised warnings

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (!line) continue;

            // Extract timestamp
            const tsMatch = line.match(tsRegex);
            const timestamp = tsMatch ? tsMatch[1].replace('T', ' ') : null;

            // ── Heartbeat / version ──
            const hbMatch = line.match(heartbeatRegex);
            if (hbMatch) {
                const ver = hbMatch[1];
                if (ver !== currentVersion) {
                    currentVersion = ver;
                    versionHistory.push({ version: ver, firstSeen: timestamp });
                }
                continue; // heartbeat lines don't need further categorisation
            }

            // ── ERROR lines ──
            if (line.includes(' ERROR ')) {
                const entry = { timestamp: timestamp, line: line.substring(0, 500), lineNumber: i + 1 };

                if (line.includes('Error fetching the goal state')) {
                    // Extract correlation ID if present
                    const corrMatch = line.match(/correlation ID: ([0-9a-f-]+)/i);
                    entry.correlationId = corrMatch ? corrMatch[1] : null;
                    goalStateErrors.push(entry);
                } else if (line.includes('op=Enable') || line.includes('op=Install')) {
                    // Extension operation failure
                    const nameMatch = line.match(/name=([^,\s]+)/);
                    const opMatch = line.match(/op=([^,\s]+)/);
                    const msgMatch = line.match(/message=(.+)/);
                    entry.extensionName = nameMatch ? nameMatch[1] : 'unknown';
                    entry.operation = opMatch ? opMatch[1] : 'unknown';
                    entry.message = msgMatch ? msgMatch[1].substring(0, 300) : '';
                    extensionErrors.push(entry);
                } else if (line.includes('ResourceDisk') || line.includes('resource disk')) {
                    const msgMatch = line.match(/(?:ERROR \S+ \S+ )(.+)/);
                    entry.message = msgMatch ? msgMatch[1].substring(0, 300) : line.substring(0, 300);
                    resourceDiskErrors.push(entry);
                } else {
                    otherErrors.push(entry);
                }
            }
            // ── WARNING lines ──
            else if (line.includes(' WARNING ')) {
                const entry = { timestamp: timestamp, line: line.substring(0, 500), lineNumber: i + 1 };

                if (line.includes('IMDS_CONNECTION_ERROR')) {
                    imdsErrors.push(entry);
                } else if (line.includes('no status file was reported') || line.includes('incorrect format')) {
                    const extMatch = line.match(/extension (\S+)/);
                    entry.extensionName = extMatch ? extMatch[1].replace(/:$/, '') : 'unknown';
                    statusFileWarnings.push(entry);
                } else if (line.includes('ResourceDisk') || line.includes('resource disk')) {
                    const msgMatch = line.match(/(?:WARNING \S+ \S+ )(.+)/);
                    entry.message = msgMatch ? msgMatch[1].substring(0, 300) : line.substring(0, 300);
                    resourceDiskErrors.push(entry);
                } else {
                    otherWarnings.push(entry);
                }
            }
        }

        // Build extension status summary from the last "Extension status:" line
        let extensionStatusSummary = null;
        for (let i = lines.length - 1; i >= 0; i--) {
            if (lines[i].includes('Extension status:')) {
                // Parse: [("ext1", "status1"), ("ext2", "status2")]
                const statusMatch = lines[i].match(/Extension status:\s*\[(.+)\]/);
                if (statusMatch) {
                    const entries = [];
                    const pairRegex = /\("([^"]+)",\s*"([^"]+)"\)|^\(\\?"([^"\\]+)\\?",\s*\\?"([^"\\]+)\\?"\)/g;
                    // Handle both escaped and non-escaped quotes
                    const raw = statusMatch[1];
                    const tupleRegex = /\(\\?"([^"\\]+)\\?",\s*\\?"([^"\\]+)\\?"\)/g;
                    let m;
                    while ((m = tupleRegex.exec(raw)) !== null) {
                        entries.push({ name: m[1], status: m[2] });
                    }
                    if (entries.length > 0) {
                        extensionStatusSummary = entries;
                    }
                }
                break;
            }
        }

        const totalErrors = goalStateErrors.length + extensionErrors.length +
            resourceDiskErrors.length + otherErrors.length;
        const totalWarnings = imdsErrors.length + statusFileWarnings.length + otherWarnings.length;

        debugLog('[waagentLog parser] Version:', currentVersion,
            '| Errors:', totalErrors, '| Warnings:', totalWarnings,
            '| GoalState:', goalStateErrors.length,
            '| Extensions:', extensionErrors.length,
            '| ResourceDisk:', resourceDiskErrors.length,
            '| IMDS:', imdsErrors.length);

        return {
            found: true,
            agentVersion: currentVersion,
            agentVersionHistory: versionHistory,
            goalStateErrors: goalStateErrors,
            extensionErrors: extensionErrors,
            resourceDiskErrors: resourceDiskErrors,
            imdsErrors: imdsErrors,
            statusFileWarnings: statusFileWarnings,
            otherErrors: otherErrors,
            otherWarnings: otherWarnings,
            extensionStatusSummary: extensionStatusSummary,
            totalErrors: totalErrors,
            totalWarnings: totalWarnings,
            hasErrors: totalErrors > 0,
            hasWarnings: totalWarnings > 0
        };
    }
};
