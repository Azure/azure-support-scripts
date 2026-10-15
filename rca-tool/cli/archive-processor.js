/**
 * Archive Processor for CLI
 * 
 * Handles streaming decompression and processing of .tar.xz, .tar.gz, and .tar files.
 * Single-pass streaming approach - processes files as they are extracted.
 */

import fs from 'fs';
import path from 'path';
import { createReadStream } from 'fs';
import { createGunzip } from 'zlib';
import tar from 'tar-stream';
import lzma from 'lzma-native';
import { SCC_RULES } from './parser-loader.js';
import { PerformanceTracker } from './performance-loader.js';

const PLAINTEXT_EXTS = new Set(['.log', '.txt', '.out']);
const GZIP_MAGIC = Buffer.from([0x1f, 0x8b]);
const XZ_MAGIC = Buffer.from([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00]);
const ZIP_MAGIC = Buffer.from([0x50, 0x4b, 0x03, 0x04]);

/**
 * Detect a bare plaintext log file (not an archive container).
 * Recognises common log extensions and falls back to magic-byte sniffing.
 */
function isPlaintextLog(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    if (PLAINTEXT_EXTS.has(ext)) return true;
    let head;
    try {
        const fd = fs.openSync(filePath, 'r');
        head = Buffer.alloc(512);
        const n = fs.readSync(fd, head, 0, 512, 0);
        fs.closeSync(fd);
        head = head.subarray(0, n);
    } catch {
        return false;
    }
    if (head.length === 0) return false;
    if (head.subarray(0, 2).equals(GZIP_MAGIC)) return false;
    if (head.subarray(0, 6).equals(XZ_MAGIC)) return false;
    if (head.subarray(0, 4).equals(ZIP_MAGIC)) return false;
    // Tar magic "ustar" lives at offset 257
    if (head.length >= 263 && head.subarray(257, 262).toString('ascii') === 'ustar') {
        return false;
    }
    let printable = 0;
    for (const b of head) {
        if (b === 9 || b === 10 || b === 13 || (b >= 32 && b < 127)) printable++;
    }
    return printable / head.length > 0.85;
}

/**
 * Process an archive file and run all parsers on its contents (streaming)
 * @param {string} archivePath - Path to the archive file
 * @param {object} options - Processing options
 * @returns {Promise<object>} - Analysis results
 */
export async function processArchive(archivePath, options = {}) {
    const { debug, parserFilter, performance: perfMode } = options;
    
    const results = {
        fileCount: 0,
        directories: [],
        files: [],
        fileTypes: {}
    };
    
    // Parser results storage
    const analysisResults = {};
    
    // Performance tracking
    const pt = perfMode ? new PerformanceTracker() : null;
    
    // Get parsers to use
    const parsersToUse = Object.entries(SCC_RULES)
        .filter(([name, parser]) => {
            if (!parser.filePattern) return false;
            if (parserFilter && name !== parserFilter) return false;
            return true;
        });
    
    debugLog(`Using ${parsersToUse.length} parsers`);
    
    // Determine archive type
    const ext = path.extname(archivePath).toLowerCase();
    const basename = path.basename(archivePath).toLowerCase();
    
    // .txz is another common extension for .tar.xz (used by SUSE/openSUSE SCC reports)
    const isXz = ext === '.xz' || ext === '.txz' || basename.endsWith('.tar.xz');
    const isGz = ext === '.gz' || basename.endsWith('.tar.gz') || basename.endsWith('.tgz');
    const isPlaintext = !isXz && !isGz && isPlaintextLog(archivePath);
    if (isPlaintext) {
        debugLog(`Detected plaintext log file: ${archivePath}`);
    }
    
    return new Promise((resolve, reject) => {
        const extract = tar.extract();
        
        extract.on('entry', (header, stream, next) => {
            const filename = header.name;
            
            if (header.type === 'directory') {
                results.directories.push(filename);
                stream.resume();
                next();
                return;
            }
            
            // Track file info
            results.files.push({ name: filename, size: header.size });
            results.fileCount++;
            
            const fileExt = path.extname(filename) || '(no extension)';
            results.fileTypes[fileExt] = (results.fileTypes[fileExt] || 0) + 1;
            
            // Normalize sos_strings tailed file paths back to their original paths
            // sosreport stores large log files in sos_strings/<plugin>/var.log.<path>.<file>.tailed
            // and creates symlinks from the original paths (which are 0-byte in tar stream)
            let matchFilename = filename;
            const tailedMatch = filename.match(/sos_strings\/[^\/]+\/(.+)\.tailed$/);
            if (tailedMatch) {
                const dottedPath = tailedMatch[1];
                let originalPath;
                const extMatch = dottedPath.match(/^(.+)\.((log|conf|txt|xml)(?:[.-].+)?)$/);
                if (extMatch) {
                    const segments = extMatch[1].split('.');
                    const fileBase = segments.pop();
                    const dirPath = segments.join('/');
                    originalPath = dirPath + '/' + fileBase + '.' + extMatch[2];
                } else {
                    const segments = dottedPath.split('.');
                    const fileName = segments.pop();
                    const dirPath = segments.join('/');
                    originalPath = dirPath + '/' + fileName;
                }
                const reportPrefix = filename.substring(0, filename.indexOf('sos_strings'));
                matchFilename = reportPrefix + originalPath;
                debugLog(`Normalized sos_strings tailed path: ${filename} -> ${matchFilename}`);
            }
            
            // Find matching parsers for this file
            const matchingParsers = parsersToUse.filter(([name, parser]) => 
                parser.filePattern.test(matchFilename)
            );
            
            if (matchingParsers.length === 0) {
                // No parser matches this file, skip reading content
                stream.resume();
                next();
                return;
            }
            
            // Read file content for parsing
            const chunks = [];
            stream.on('data', chunk => chunks.push(chunk));
            stream.on('end', () => {
                const decodeStart = pt ? performance.now() : 0;
                const content = Buffer.concat(chunks).toString('utf8');
                const decodeMs = pt ? performance.now() - decodeStart : 0;
                
                if (pt) {
                    pt.startFile();
                    pt.recordDecode(decodeMs);
                }
                
                debugLog(`Processing: ${matchFilename} (${content.length} bytes) with ${matchingParsers.length} parsers`);
                
                // Split lines ONCE and share across all matching parsers
                // Avoids each parser re-splitting the same content (e.g. 10 parsers × 44MB = 10 redundant splits)
                const lines = content.split('\n');
                
                // Run each matching parser
                for (const [parserName, parser] of matchingParsers) {
                    try {
                        const parseStart = pt ? performance.now() : 0;
                        const result = parser.parse(content, matchFilename, lines);
                        const parseMs = pt ? performance.now() - parseStart : 0;
                        
                        // Handle multi-file parsers (like blockDevices that accumulate data)
                        if (parser.multiFile) {
                            if (!analysisResults[parserName]) {
                                analysisResults[parserName] = result;
                            } else {
                                // Merge result into existing
                                mergeMultiFileResult(analysisResults[parserName], result, parserName);
                            }
                        }
                        // Handle processAllRotations parsers (like log file parsers)
                        else if (parser.processAllRotations) {
                            if (!analysisResults[parserName]) {
                                // Initialize based on parser type
                                if (parserName === 'rhuiErrors') {
                                    analysisResults[parserName] = {
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
                                } else if (parserName === 'clusterEvents') {
                                    analysisResults[parserName] = {
                                        found: false,
                                        count: 0,
                                        resourceMigrations: [],
                                        fencingEvents: []
                                    };
                                } else {
                                    analysisResults[parserName] = {
                                        count: 0,
                                        events: []
                                    };
                                }
                            }
                            
                            // Merge results
                            if (parserName === 'rhuiErrors') {
                                analysisResults[parserName].found = analysisResults[parserName].found || result.found;
                                analysisResults[parserName].hasCertExpiration = analysisResults[parserName].hasCertExpiration || result.hasCertExpiration;
                                analysisResults[parserName].hasHttp403 = analysisResults[parserName].hasHttp403 || result.hasHttp403;
                                analysisResults[parserName].hasHttp400 = analysisResults[parserName].hasHttp400 || result.hasHttp400;
                                analysisResults[parserName].hasConnectionError = analysisResults[parserName].hasConnectionError || result.hasConnectionError;
                                
                                result.errors?.forEach(err => {
                                    analysisResults[parserName].errors.push({ ...err, sourceFile: filename });
                                });
                                result.affectedRepos?.forEach(repo => {
                                    if (!analysisResults[parserName].affectedRepos.includes(repo)) {
                                        analysisResults[parserName].affectedRepos.push(repo);
                                    }
                                });
                                result.warnings?.forEach(warning => {
                                    if (!analysisResults[parserName].warnings.find(w => w.type === warning.type)) {
                                        analysisResults[parserName].warnings.push(warning);
                                    }
                                });
                            } else if (parserName === 'clusterEvents') {
                                // clusterEvents returns { found, resourceMigrations, fencingEvents, totalEvents }
                                if (result.found) {
                                    analysisResults[parserName].found = true;
                                    result.resourceMigrations?.forEach(m => {
                                        analysisResults[parserName].resourceMigrations.push({ ...m, sourceFile: matchFilename });
                                    });
                                    result.fencingEvents?.forEach(f => {
                                        analysisResults[parserName].fencingEvents.push({ ...f, sourceFile: matchFilename });
                                    });
                                    analysisResults[parserName].count = 
                                        analysisResults[parserName].resourceMigrations.length + 
                                        analysisResults[parserName].fencingEvents.length;
                                }
                            } else if (result.count !== undefined && result.events) {
                                analysisResults[parserName].count += result.count;
                                analysisResults[parserName].events.push(...result.events.map(e => ({
                                    ...e,
                                    sourceFile: filename
                                })));
                            }
                        } else {
                            // Single file parser - just store result
                            if (!analysisResults[parserName] || result.found) {
                                analysisResults[parserName] = result;
                            }
                        }
                        
                        debugLog(`Parser ${parserName} result: found=${result.found}`);
                        
                        // Track per-parser performance
                        if (pt) {
                            pt.recordParser(matchFilename, parserName, parseMs, result, analysisResults[parserName]);
                        }
                    } catch (error) {
                        debugLog(`Parser ${parserName} error on ${filename}: ${error.message}`);
                    }
                }
                
                // Track per-file performance
                if (pt) {
                    pt.endFile(matchFilename, content.length, matchingParsers.length);
                }
                
                next();
            });
            stream.on('error', next);
        });
        
        extract.on('finish', () => {
            debugLog(`Finished processing ${results.fileCount} files`);
            
            // Post-processing: correlate fstab with block devices
            correlateFstabWithBlockDevices(analysisResults);
            
            // Post-processing: compare mtab with fstab
            compareMtabWithFstab(analysisResults);
            
            // Post-processing: distro-aware corosync warning filtering
            const osReleaseData = analysisResults.osRelease || analysisResults.sysinfo || analysisResults.basicEnvironment || null;
            const isSUSE = osReleaseData && osReleaseData.name && 
                          (osReleaseData.name.toLowerCase().includes('suse') || 
                           (osReleaseData.prettyName && osReleaseData.prettyName.toLowerCase().includes('suse')));
            const isRHEL = osReleaseData && osReleaseData.name &&
                          (osReleaseData.name.toLowerCase().includes('red hat') ||
                           osReleaseData.name.toLowerCase().includes('rhel') ||
                           (osReleaseData.prettyName && (osReleaseData.prettyName.toLowerCase().includes('red hat') || osReleaseData.prettyName.toLowerCase().includes('rhel'))));
            const distroFamily = isSUSE ? 'sles' : (isRHEL ? 'rhel' : 'unknown');
            
            if (analysisResults.corosyncConfig) {
                analysisResults.corosyncConfig.distroFamily = distroFamily;
                if (analysisResults.corosyncConfig.warnings) {
                    if (isRHEL) {
                        // RHEL guide recommends same totem values as SUSE, except transport should be 'knet'
                        // Reference: https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker
                        
                        // Remove the SUSE-specific transport warning (which expects 'udpu')
                        analysisResults.corosyncConfig.warnings = analysisResults.corosyncConfig.warnings.filter(w => 
                            w.parameter !== 'totem.transport'
                        );
                        
                        // Add RHEL-specific transport check: should be 'knet' for RHEL 8+
                        if (analysisResults.corosyncConfig.totemTransport !== null && analysisResults.corosyncConfig.totemTransport !== 'knet') {
                            analysisResults.corosyncConfig.warnings.push({
                                parameter: 'totem.transport',
                                expected: 'knet',
                                actual: analysisResults.corosyncConfig.totemTransport,
                                severity: 'warning',
                                message: `Totem transport value is '${analysisResults.corosyncConfig.totemTransport}', but should be 'knet' for RHEL 8+ Azure environments`,
                                documentationUrl: 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker'
                            });
                        }
                        
                        // Update documentation URLs to RHEL guide
                        analysisResults.corosyncConfig.warnings.forEach(w => {
                            w.documentationUrl = 'https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker';
                        });
                        
                        debugLog('Applied RHEL-specific corosync validation (transport: knet)');
                    } else if (!isSUSE) {
                        analysisResults.corosyncConfig.warnings = analysisResults.corosyncConfig.warnings.filter(w => 
                            w.parameter !== 'totem.transport'
                        );
                    }
                }
            }
            
            resolve({
                ...results,
                ...analysisResults,
                ...(pt ? { _performanceData: pt.getReport() } : {})
            });
        });
        
        extract.on('error', reject);
        
        // Create the decompression pipeline
        const fileStream = createReadStream(archivePath);
        
        if (isXz) {
            debugLog('Using LZMA decompression');
            const decompressor = lzma.createDecompressor();
            fileStream.pipe(decompressor).pipe(extract);
        } else if (isGz) {
            debugLog('Using Gzip decompression');
            fileStream.pipe(createGunzip()).pipe(extract);
        } else if (isPlaintext) {
            debugLog('Wrapping plaintext file as synthetic tar entry');
            // Wrap the plaintext file in a single-entry in-memory tar so the
            // existing entry handler (with all its merging/multi-file logic)
            // runs unchanged. The synthetic name <basename>/messages ensures
            // syslog-style file_pattern regexes match.
            const pack = tar.pack();
            const syntheticName = `${path.basename(archivePath)}/messages`;
            const stat = fs.statSync(archivePath);
            const entry = pack.entry({ name: syntheticName, size: stat.size }, err => {
                if (err) extract.emit('error', err);
                pack.finalize();
            });
            fileStream.pipe(entry);
            pack.pipe(extract);
        } else {
            debugLog('No decompression needed');
            fileStream.pipe(extract);
        }
    });
}

function debugLog(...args) {
    if (global.DEBUG_MODE) {
        console.error('[DEBUG]', ...args);
    }
}

/**
 * Merge results from multi-file parsers
 * These parsers accumulate data across multiple files
 */
function mergeMultiFileResult(existing, newResult, parserName) {
    // Merge found flag
    existing.found = existing.found || newResult.found;
    
    // Special handling for networkInterfaces (delegate to parser's mergeResults)
    if (parserName === 'networkInterfaces') {
        // networkInterfacesParser.mergeResults handles everything except found flag (already merged above)
        // Merge interfaces
        for (const [name, iface] of Object.entries(newResult.interfaces || {})) {
            if (!existing.interfaces[name]) {
                existing.interfaces[name] = iface;
            } else {
                const e = existing.interfaces[name];
                if (iface.state && !e.state) e.state = iface.state;
                if (iface.mac && !e.mac) e.mac = iface.mac;
                if (iface.mtu && !e.mtu) e.mtu = iface.mtu;
                if (iface.driver && !e.driver) e.driver = iface.driver;
                if (iface.driverInfo && !e.driverInfo) e.driverInfo = iface.driverInfo;
                if (iface.accelNet) e.accelNet = true;
                if (iface.bootproto && !e.bootproto) e.bootproto = iface.bootproto;
                if (iface.master && !e.master) e.master = iface.master;
                if (iface.type && !e.type) e.type = iface.type;
                if (iface.firmwareVersion && !e.firmwareVersion) e.firmwareVersion = iface.firmwareVersion;
                if (iface.busInfo && !e.busInfo) e.busInfo = iface.busInfo;
                for (const ip of (iface.ipv4 || [])) {
                    if (!e.ipv4.some(a => a.address === ip.address)) e.ipv4.push(ip);
                }
                for (const ip of (iface.ipv6 || [])) {
                    if (!e.ipv6.some(a => a.address === ip.address)) e.ipv6.push(ip);
                }
            }
        }
        Object.assign(existing.raw, newResult.raw || {});
        return;
    }

    // Special handling for firewallRules (deep merge of per-type fields)
    if (parserName === 'firewallRules') {
        // Merge firewalld
        existing.firewalld.detected = existing.firewalld.detected || newResult.firewalld.detected;
        existing.firewalld.running = existing.firewalld.running || newResult.firewalld.running;
        if (newResult.firewalld.config) existing.firewalld.config = newResult.firewalld.config;
        if (newResult.firewalld.zones) existing.firewalld.zones = newResult.firewalld.zones;
        if (newResult.firewalld.directRules) existing.firewalld.directRules = (existing.firewalld.directRules || '') + newResult.firewalld.directRules;
        if (newResult.firewalld.passthroughs) existing.firewalld.passthroughs = (existing.firewalld.passthroughs || '') + newResult.firewalld.passthroughs;
        if (newResult.firewalld.chains) existing.firewalld.chains = (existing.firewalld.chains || '') + newResult.firewalld.chains;
        if (newResult.firewalld.logDenied) existing.firewalld.logDenied = newResult.firewalld.logDenied;
        if (newResult.firewalld.backend) existing.firewalld.backend = newResult.firewalld.backend;
        // Merge iptables / ip6tables
        existing.iptables.detected = existing.iptables.detected || newResult.iptables.detected;
        existing.iptables.rules.push(...(newResult.iptables.rules || []));
        existing.iptables.modules.push(...(newResult.iptables.modules || []));
        existing.ip6tables.detected = existing.ip6tables.detected || newResult.ip6tables.detected;
        existing.ip6tables.rules.push(...(newResult.ip6tables.rules || []));
        existing.ip6tables.modules.push(...(newResult.ip6tables.modules || []));
        // Merge ebtables
        existing.ebtables.detected = existing.ebtables.detected || newResult.ebtables.detected;
        if (newResult.ebtables.config) existing.ebtables.config = newResult.ebtables.config;
        // Merge nftables
        existing.nftables.detected = existing.nftables.detected || newResult.nftables.detected;
        if (newResult.nftables.ruleset) existing.nftables.ruleset = newResult.nftables.ruleset;
        if (newResult.nftables.tables) existing.nftables.tables = newResult.nftables.tables;
        // Merge warnings and raw sections
        newResult.warnings?.forEach(w => { if (!existing.warnings.includes(w)) existing.warnings.push(w); });
        Object.assign(existing.rawSections, newResult.rawSections || {});
        // Re-determine active firewall using the parser's logic
        if (existing.firewalld.running) existing.activeFirewall = 'firewalld';
        else if (existing.nftables.ruleset && existing.nftables.ruleset !== '(empty)' && existing.nftables.ruleset.length > 10) existing.activeFirewall = 'nftables';
        else if (existing.iptables.rules.length > 0) existing.activeFirewall = 'iptables';
        else if (existing.ip6tables.rules.length > 0) existing.activeFirewall = 'ip6tables';
        else existing.activeFirewall = 'none';
        return;
    }
    
    // Special handling for clusterEvents (has resourceMigrations and fencingEvents arrays)
    if (parserName === 'clusterEvents') {
        if (newResult.resourceMigrations) {
            if (!existing.resourceMigrations) existing.resourceMigrations = [];
            existing.resourceMigrations.push(...newResult.resourceMigrations);
        }
        if (newResult.fencingEvents) {
            if (!existing.fencingEvents) existing.fencingEvents = [];
            existing.fencingEvents.push(...newResult.fencingEvents);
        }
        existing.count = (existing.resourceMigrations?.length || 0) + (existing.fencingEvents?.length || 0);
        return;
    }
    
    // Merge arrays (like disks, partitions)
    for (const key of ['disks', 'partitions', 'warnings']) {
        if (Array.isArray(newResult[key])) {
            if (!existing[key]) existing[key] = [];
            for (const item of newResult[key]) {
                // Avoid duplicates by checking for unique identifier
                const isDupe = existing[key].some(e => 
                    (e.name && e.name === item.name) || 
                    (e.device && e.device === item.device) ||
                    (JSON.stringify(e) === JSON.stringify(item))
                );
                if (!isDupe) {
                    existing[key].push(item);
                }
            }
        }
    }
    
    // Merge maps (like uuidMap, deviceMap, mountPoints)
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
function correlateFstabWithBlockDevices(results) {
    const fstab = results.fstabAnalysis;
    const blockDevices = results.blockDevices;
    
    if (!fstab?.found || !blockDevices?.found) {
        debugLog('Cannot correlate: fstab or blockDevices not found');
        return;
    }
    
    // Create a storage correlation result
    const correlation = {
        found: true,
        mountedVolumes: [],
        warnings: [],
        errors: []
    };
    
    for (const entry of fstab.entries) {
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
            const device = blockDevices.uuidMap[entry.uuid] || 
                          blockDevices.uuidMap[entry.uuid.toLowerCase()] ||
                          blockDevices.uuidMap[entry.uuid.toUpperCase()];
            
            if (device) {
                const deviceInfo = blockDevices.deviceMap[device];
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
                
                // Check if mount point matches
                if (deviceInfo?.mountpoint && deviceInfo.mountpoint !== entry.mountpoint) {
                    mountInfo.issues.push({
                        type: 'mountpoint_mismatch',
                        message: `Device mounted at '${deviceInfo.mountpoint}' but fstab expects '${entry.mountpoint}'`,
                        severity: 'info'
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
            const deviceInfo = blockDevices.deviceMap[entry.device];
            if (deviceInfo) {
                mountInfo.actualDevice = entry.device;
                mountInfo.actualUuid = deviceInfo.uuid;
                mountInfo.actualFstype = deviceInfo.fstype;
                mountInfo.status = 'found';
            } else {
                // Check if it's a symlink path like /dev/disk/cloud/azure_resource-part1
                // These won't be in deviceMap directly
                mountInfo.status = 'symlink';
                mountInfo.issues.push({
                    type: 'symlink_device',
                    message: `Device path '${entry.device}' is likely a symlink, actual device unknown`,
                    severity: 'info'
                });
            }
        }
        
        correlation.mountedVolumes.push(mountInfo);
    }
    
    // Add summary
    correlation.summary = {
        totalEntries: fstab.entries.length,
        foundDevices: correlation.mountedVolumes.filter(m => m.status === 'found').length,
        warnings: correlation.warnings.length,
        errors: correlation.errors.length
    };
    
    results.storageCorrelation = correlation;
    debugLog('Storage correlation complete:', correlation.summary);
}

/**
 * Compare mtab entries with fstab to find mounts not defined in fstab.
 * These are typically hand-mounted filesystems or cluster-managed resources.
 * Mutates results.mtabAnalysis to include extraMounts.
 */
function compareMtabWithFstab(results) {
    const mtab = results.mtabAnalysis;
    if (!mtab?.found) {
        debugLog('Cannot compare mtab: mtabAnalysis not found');
        return;
    }

    const fstab = results.fstabAnalysis;

    // Build a set of fstab mountpoints for fast lookup
    const fstabMountpoints = new Set();
    if (fstab?.found && fstab.entries) {
        for (const entry of fstab.entries) {
            fstabMountpoints.add(entry.mountpoint);
        }
    }

    // Count real vs virtual mounts
    let realMounts = 0;
    let virtualMounts = 0;
    const typeBreakdown = {};
    for (const entry of mtab.entries) {
        if (entry.isVirtualFs) {
            virtualMounts++;
        } else {
            realMounts++;
        }
        typeBreakdown[entry.fstype] = (typeBreakdown[entry.fstype] || 0) + 1;
    }

    // Find mounts in mtab that are NOT in fstab (excluding virtual filesystems)
    const extraMounts = [];
    for (const entry of mtab.entries) {
        if (entry.isVirtualFs) continue;
        if (!fstabMountpoints.has(entry.mountpoint)) {
            extraMounts.push({
                source: entry.source,
                mountpoint: entry.mountpoint,
                fstype: entry.fstype,
                options: entry.options,
                sourceType: entry.sourceType,
                reason: 'Not found in /etc/fstab - possibly hand-mounted or cluster-managed'
            });
        }
    }

    // Collect autofs entries separately for visibility
    const autofsMounts = mtab.entries.filter(e => e.fstype === 'autofs');

    mtab.realMounts = realMounts;
    mtab.virtualMounts = virtualMounts;
    mtab.typeBreakdown = typeBreakdown;
    mtab.extraMounts = extraMounts;
    mtab.autofsMounts = autofsMounts;
    debugLog('mtab vs fstab comparison complete:', extraMounts.length, 'extra mounts,', realMounts, 'real,', virtualMounts, 'virtual,', autofsMounts.length, 'autofs');
}

export default { processArchive };
