/**
 * @module parsers/azure
 * @description Azure VM metadata and billing model detection.
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
    
    parse: function(content, filename) {
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
            console.error('[azureVMProperties parser] Failed to parse JSON:', e);
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
    
    parse: function(content, filename) {
        console.log('[suseCloudRegister] *** PARSING ***', filename);
        console.log('[suseCloudRegister] Content length:', content.length);
        debugLog('[suseCloudRegister parser] Analyzing SUSE cloud registration in:', filename);
        
        let billingModel = null;
        let detectionMethod = null;
        let registrationServer = null;
        let registrationType = null;
        
        // Performance optimization: cloudregister.txt can be huge (1GB+)
        // Only read first 100KB which should contain registration info
        const maxChars = 100 * 1024; // 100 KB
        const truncatedContent = content.length > maxChars ? content.substring(0, maxChars) : content;
        console.log('[suseCloudRegister] Truncated length:', truncatedContent.length);
        
        // Parse cloudregister.txt to extract registration information
        const lines = truncatedContent.split('\n');
        console.log('[suseCloudRegister] Number of lines:', lines.length);
        
        // Show first few lines for debugging
        console.log('[suseCloudRegister] First 3 lines:', lines.slice(0, 3));
        
        // Limit search to first 1000 lines for performance
        const searchLimit = Math.min(1000, lines.length);
        console.log('[suseCloudRegister] Searching first', searchLimit, 'lines');
        
        for (let i = 0; i < searchLimit; i++) {
            const line = lines[i].trim();
            
            // Pattern 1: Log format: "Registration: /usr/sbin/SUSEConnect --url https://..."
            const connectMatch = line.match(/SUSEConnect\s+--url\s+(https?:\/\/[^\s]+)/i);
            if (connectMatch) {
                registrationServer = connectMatch[1].trim();
                console.log('[suseCloudRegister] *** FOUND on line', i, '***:', registrationServer);
                debugLog('[suseCloudRegister parser] Found registration server (SUSEConnect):', registrationServer);
                break; // Found it, no need to continue
            }
            
            // Pattern 2: Simple key=value format: "url = https://..."
            if (line.match(/url/i) && line.includes('=')) {
                const urlMatch = line.match(/url\s*=\s*(.+)/i);
                if (urlMatch) {
                    registrationServer = urlMatch[1].trim();
                    console.log('[suseCloudRegister] *** FOUND (url=) on line', i, '***:', registrationServer);
                    debugLog('[suseCloudRegister parser] Found registration server (url=):', registrationServer);
                    break;
                }
            }
            
            // Pattern 3: Simple key=value format: "server = https://..."
            if (line.match(/server/i) && line.includes('=')) {
                const serverMatch = line.match(/server\s*=\s*(.+)/i);
                if (serverMatch && !registrationServer) {
                    registrationServer = serverMatch[1].trim();
                    console.log('[suseCloudRegister] *** FOUND (server=) on line', i, '***:', registrationServer);
                    debugLog('[suseCloudRegister parser] Found registration server (server=):', registrationServer);
                    break;
                }
            }
        }
        
        console.log('[suseCloudRegister] Final registrationServer:', registrationServer);
        
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
