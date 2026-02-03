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

/**
 * Process an archive file and run all parsers on its contents (streaming)
 * @param {string} archivePath - Path to the archive file
 * @param {object} options - Processing options
 * @returns {Promise<object>} - Analysis results
 */
export async function processArchive(archivePath, options = {}) {
    const { debug, parserFilter } = options;
    
    const results = {
        fileCount: 0,
        directories: [],
        files: [],
        fileTypes: {}
    };
    
    // Parser results storage
    const analysisResults = {};
    
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
    
    const isXz = ext === '.xz' || basename.endsWith('.tar.xz');
    const isGz = ext === '.gz' || basename.endsWith('.tar.gz') || basename.endsWith('.tgz');
    
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
            
            // Find matching parsers for this file
            const matchingParsers = parsersToUse.filter(([name, parser]) => 
                parser.filePattern.test(filename)
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
                const content = Buffer.concat(chunks).toString('utf8');
                
                debugLog(`Processing: ${filename} (${content.length} bytes) with ${matchingParsers.length} parsers`);
                
                // Run each matching parser
                for (const [parserName, parser] of matchingParsers) {
                    try {
                        const result = parser.parse(content, filename);
                        
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
                    } catch (error) {
                        debugLog(`Parser ${parserName} error on ${filename}: ${error.message}`);
                    }
                }
                
                next();
            });
            stream.on('error', next);
        });
        
        extract.on('finish', () => {
            debugLog(`Finished processing ${results.fileCount} files`);
            
            // Post-processing: correlate fstab with block devices
            correlateFstabWithBlockDevices(analysisResults);
            
            resolve({
                ...results,
                ...analysisResults
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

export default { processArchive };
