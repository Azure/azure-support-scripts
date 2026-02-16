/**
 * @module parsers/storage
 * @description Storage Parsers for RCA Tool
 *
 * Provides six independent parsers covering LVM, RAID, BTRFS, block devices,
 * fstab analysis, and disk usage.  Each parser targets a specific set of
 * files from SCC (supportconfig) or SOS (sosreport) archives.
 *
 * ### Parser Inventory
 *
 * | Parser | File Patterns | Purpose |
 * |--------|---------------|---------|
 * | `lvmConfigParser` | `lvm.txt`, `pvs.txt`, `vgs.txt`, `lvs.txt`, `pvdisplay`, `vgdisplay`, `lvdisplay` | Parses Physical Volumes, Volume Groups, and Logical Volumes; validates PV-to-VG membership |
 * | `raidConfigParser` | `mdstat`, `md-arrays.txt`, `mdadm.txt`, `proc/mdstat` | Parses `/proc/mdstat` RAID arrays; detects degraded state, faulty devices, rebuild progress |
 * | `btrfsConfigParser` | `btrfs.txt`, `fs-btrfs.txt`, `btrfs-filesystem-show.txt`, `btrfs-subvolume-list.txt` | Extracts BTRFS filesystem inventory (label, UUID, devices) and subvolume list |
 * | `blockDevicesParser` | `lsblk`, `lsblk_-f_-a_-l`, `blkid_-c_.dev.null` | Builds disk/partition inventory with UUID, filesystem type, and mount point maps (multi-file) |
 * | `fstabAnalysisParser` | `/etc/fstab`, `fs-diskio.txt` | Parses fstab entries; classifies source type (UUID/device/label/network); flags missing `nofail` on non-OS mounts |
 * | `dfOutputParser` | `df`, `df_-aliT`, `df_-al_`, `fs-diskio.txt` | Parses `df` output for filesystem usage; builds mountpoint-to-usage lookup |
 *
 * ### Return Shapes
 *
 * **lvmConfigParser:**
 * ```
 * { found, pvs[], vgs[], lvs[], warnings[], rawOutput }
 * ```
 * Warnings include "Missing VG" (PV references unknown VG) and "PV Count
 * Mismatch" (VG expects more PVs than found).
 *
 * **raidConfigParser:**
 * ```
 * { found, arrays[{ device, state, level, devices[], syncStatus }], warnings[], rawOutput }
 * ```
 * Warnings include "Faulty Device" and "Degraded Array".
 *
 * **btrfsConfigParser:**
 * ```
 * { found, filesystems[{ label, uuid, devices[], totalSize }], subvolumes[], warnings[], rawOutput }
 * ```
 *
 * **blockDevicesParser (multi-file):**
 * ```
 * { found, disks[], partitions[], uuidMap, deviceMap, mountPoints, warnings[], rawOutput }
 * ```
 *
 * **fstabAnalysisParser:**
 * ```
 * { found, entries[], uuidEntries[], deviceEntries[], labelEntries[], warnings[] }
 * ```
 * Each entry carries `sourceType` (uuid/device/label/network), `hasNofail`,
 * `isOsPartition`, `isVirtualFs`, and `needsNofail` flags.
 * Missing-nofail warnings link to the Azure fstab best-practices doc.
 *
 * **dfOutputParser:**
 * ```
 * { found, filesystems[], mountToUsage }
 * ```
 *
 * ### Key Helper Methods
 *
 * | Parser | Method | Purpose |
 * |--------|--------|---------|
 * | lvmConfig | `parsePVs`, `parseVGs`, `parseLVs` | Column-based parsing of pvs/vgs/lvs command output |
 * | lvmConfig | `validatePVsInVGs` | Cross-validates PV VG references against the VG list |
 * | btrfsConfig | `parseFilesystems`, `parseSubvolumes` | Parses `btrfs filesystem show` and `btrfs subvolume list` output |
 * | blockDevices | `parseLsblkBasic`, `parseLsblkFull`, `parseBlkid` | Three lsblk/blkid output formats into a unified device map |
 * | fstabAnalysis | `extractFstabFromSCC` | Extracts the fstab section from the aggregated `fs-diskio.txt` |
 * | dfOutput | `extractDfFromSCC` | Extracts the df section from the aggregated `fs-diskio.txt` |
 */

const storageDebugLog = console.log.bind(console, '[STORAGE]');

/**
 * Parser: lvmConfig
 * Parses LVM configuration from various supportconfig/sosreport files
 */
const lvmConfigParser = {
    filePattern: /\/(lvm\.txt|pvs\.txt|vgs\.txt|lvs\.txt|pvdisplay|vgdisplay|lvdisplay)$/,
    
    parse: function(content, filename) {
        storageDebugLog('[LVM parser] Analyzing:', filename);
        
        const result = {
            found: false,
            pvs: [],
            vgs: [],
            lvs: [],
            warnings: [],
            rawOutput: {}
        };
        
        // Check if this is an lvm.txt aggregated file or individual command output
        if (filename.includes('lvm.txt')) {
            storageDebugLog('Processing aggregated lvm.txt file');
            
            // Parse aggregated lvm.txt file with multiple command outputs
            // Supportconfig format uses: # /sbin/pvs or #==[ Command ]====/sbin/pvs
            const pvsMatch = content.match(/# \/(?:usr\/)?sbin\/pvs[^\n]*\n([\s\S]*?)(?=\n# |$)/);
            const vgsMatch = content.match(/# \/(?:usr\/)?sbin\/vgs[^\n]*\n([\s\S]*?)(?=\n# |$)/);
            const lvsMatch = content.match(/# \/(?:usr\/)?sbin\/lvs[^\n]*\n([\s\S]*?)(?=\n# |$)/);
            
            if (pvsMatch) {
                storageDebugLog('Found pvs section, length:', pvsMatch[1].length);
                this.parsePVs(pvsMatch[1], result);
            }
            if (vgsMatch) {
                storageDebugLog('Found vgs section, length:', vgsMatch[1].length);
                this.parseVGs(vgsMatch[1], result);
            }
            if (lvsMatch) {
                storageDebugLog('Found lvs section, length:', lvsMatch[1].length);
                this.parseLVs(lvsMatch[1], result);
            }
        } else if (filename.includes('pvs') || filename.includes('pvdisplay')) {
            this.parsePVs(content, result);
        } else if (filename.includes('vgs') || filename.includes('vgdisplay')) {
            this.parseVGs(content, result);
        } else if (filename.includes('lvs') || filename.includes('lvdisplay')) {
            this.parseLVs(content, result);
        }
        
        // Validate PVs are present in VGs
        if (result.vgs.length > 0 && result.pvs.length > 0) {
            this.validatePVsInVGs(result);
        }
        
        if (result.pvs.length > 0 || result.vgs.length > 0 || result.lvs.length > 0) {
            result.found = true;
        }
        
        storageDebugLog('[LVM parser] Found:', result);
        return result;
    },
    
    parsePVs: function(content, result) {
        storageDebugLog('Parsing PVs, content length:', content.length);
        
        // Clean content from supportconfig markers
        const cleanContent = content
            .split('\n')
            .filter(line => !line.trim().startsWith('#=='))
            .join('\n');
        
        result.rawOutput.pvs = cleanContent;
        
        // Parse pvs command output (column format)
        const lines = cleanContent.split('\n');
        storageDebugLog('PVs: Processing', lines.length, 'lines');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('PV ') || trimmed.startsWith('#') || trimmed.startsWith('---')) continue;
            
            // Match lines with /dev/ devices - must have at least a VG name and format (lvm2)
            // Expected format: /dev/sda2  vg_name  lvm2  a--  <size>  <free>
            if (trimmed.startsWith('/dev/')) {
                const parts = trimmed.split(/\s+/);
                // Must have at least device, vg, and format columns
                if (parts.length >= 3 && parts[2] === 'lvm2') {
                    storageDebugLog('PVs: Found device line:', trimmed);
                    result.pvs.push({
                        device: parts[0],
                        vg: parts[1] !== '' ? parts[1] : '-',
                        attr: parts[3] || '-',
                        size: parts[4] || '-',
                        free: parts[5] || '-'
                    });
                    storageDebugLog('PVs: Added PV:', parts[0], 'VG:', parts[1]);
                } else {
                    storageDebugLog('PVs: Skipping line (not pvs format):', trimmed.substring(0, 80));
                }
            }
        }
        storageDebugLog('PVs: Total parsed:', result.pvs.length);
    },
    
    parseVGs: function(content, result) {
        storageDebugLog('VGs: Parsing VGs, content length:', content.length);
        
        // Clean content from supportconfig markers
        const cleanContent = content
            .split('\n')
            .filter(line => !line.trim().startsWith('#=='))
            .join('\n');
        
        result.rawOutput.vgs = cleanContent;
        
        // Parse vgs command output
        const lines = cleanContent.split('\n');
        storageDebugLog('VGs: Processing', lines.length, 'lines');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('VG ') || trimmed.startsWith('#')) continue;
            
            // Look for VG names (not starting with /)
            const parts = trimmed.split(/\s+/);
            if (parts.length >= 2 && !parts[0].startsWith('/') && !parts[0].startsWith('-')) {
                // First column should be VG name, second should be a number (PV count)
                if (/^\d+$/.test(parts[1])) {
                    storageDebugLog('VGs: Found VG line:', trimmed);
                    result.vgs.push({
                        name: parts[0],
                        pv_count: parts[1],
                        lv_count: parts[2] || '-',
                        attr: parts[4] || '-',
                        size: parts[5] || '-',
                        free: parts[6] || '-'
                    });
                    storageDebugLog('VGs: Added VG:', parts[0]);
                }
            }
        }
        storageDebugLog('VGs: Total parsed:', result.vgs.length);
    },
    
    parseLVs: function(content, result) {
        storageDebugLog('LVs: Parsing LVs, content length:', content.length);
        
        // Clean content from supportconfig markers
        const cleanContent = content
            .split('\n')
            .filter(line => !line.trim().startsWith('#=='))
            .join('\n');
        
        result.rawOutput.lvs = cleanContent;
        
        // Parse lvs command output
        const lines = cleanContent.split('\n');
        storageDebugLog('LVs: Processing', lines.length, 'lines');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('LV ') || trimmed.startsWith('#')) continue;
            
            // Match lines like: root   vg00 -wi-ao---- <125.52g
            const match = trimmed.match(/^(\S+)\s+(\S+)\s+(\S+)\s+(<?\d+[\.\d]*[MGTKmgtk]?)/);
            if (match) {
                storageDebugLog('LVs: Found LV line:', trimmed);
                result.lvs.push({
                    name: match[1],
                    vg: match[2],
                    attr: match[3],
                    size: match[4],
                    pool: '-'
                });
                storageDebugLog('LVs: Added LV:', match[1]);
            }
        }
        storageDebugLog('LVs: Total parsed:', result.lvs.length);
    },
    
    validatePVsInVGs: function(result) {
        storageDebugLog('[LVM parser] Validating PVs in VGs');
        
        // Get list of VG names from VGs
        const vgNames = new Set(result.vgs.map(vg => vg.name));
        
        // Check each PV's VG
        for (const pv of result.pvs) {
            if (pv.vg && pv.vg !== '--' && !vgNames.has(pv.vg)) {
                result.warnings.push({
                    type: 'Missing VG',
                    message: `Physical Volume ${pv.device} references Volume Group "${pv.vg}" which is not present`,
                    details: 'This may indicate a missing or corrupted Volume Group'
                });
            }
        }
        
        // Check each VG has expected number of PVs
        for (const vg of result.vgs) {
            const pvsInVg = result.pvs.filter(pv => pv.vg === vg.name);
            const expectedPVs = parseInt(vg.pv_count, 10);
            if (pvsInVg.length !== expectedPVs) {
                result.warnings.push({
                    type: 'PV Count Mismatch',
                    message: `Volume Group "${vg.name}" expects ${expectedPVs} PVs but only ${pvsInVg.length} were found`,
                    details: 'Missing PVs: ' + (expectedPVs - pvsInVg.length)
                });
            }
        }
    }
};
/**
 * Parser: raidConfig
 * Parses RAID configuration from /proc/mdstat and mdadm outputs
 */
const raidConfigParser = {
    filePattern: /\/(mdstat|md-arrays\.txt|mdadm\.txt|proc\/mdstat)$/,
    parse: function(content, filename) {
        storageDebugLog('[RAID parser] Analyzing:', filename);
        const result = {
            found: false,
            arrays: [],
            warnings: [],
            rawOutput: {}
        };
        result.rawOutput.mdstat = content;
        const lines = content.split('\n');
        let currentArray = null;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const arrayMatch = line.match(/^(md\d+)\s*:\s*(\w+)\s+(\w+)\s+(.+)/);
            if (arrayMatch) {
                if (currentArray) {
                    result.arrays.push(currentArray);
                }
                currentArray = {
                    device: '/dev/' + arrayMatch[1],
                    state: arrayMatch[2],
                    level: arrayMatch[3],
                    devices: [],
                    syncStatus: null
                };
                const devicesStr = arrayMatch[4];
                const deviceMatches = devicesStr.matchAll(/(\w+)\[\d+\](?:\((\w+)\))?/g);
                for (const devMatch of deviceMatches) {
                    let deviceState = devMatch[2] || 'active';
                    if (deviceState === 'S') {
                        deviceState = 'spare';
                    }
                    currentArray.devices.push({
                        device: '/dev/' + devMatch[1],
                        state: deviceState
                    });
                }
                if (devicesStr.includes('(F)')) {
                    result.warnings.push({
                        type: 'Faulty Device',
                        message: `RAID array ${currentArray.device} has faulty devices`,
                        details: 'Check device status with mdadm'
                    });
                }
                continue;
            }
            if (currentArray && line.includes('blocks')) {
                const sizeMatch = line.match(/(\d+)\s+blocks/);
                if (sizeMatch) {
                    const blocks = parseInt(sizeMatch[1], 10);
                    const mb = (blocks / 1024).toFixed(2);
                    currentArray.size = mb + ' MB';
                }
                if (line.includes('[_')) {
                    currentArray.state = 'degraded';
                    result.warnings.push({
                        type: 'Degraded Array',
                        message: `RAID array ${currentArray.device} is degraded`,
                        details: 'One or more devices are missing or failed'
                    });
                }
            }
            if (currentArray && (line.includes('recovery') || line.includes('resync') || line.includes('reshape') || line.includes('check'))) {
                const syncMatch = line.match(/\[([\.><=]+)\]\s+(\w+)\s*=\s*([\d.]+)%/);
                if (syncMatch) {
                    const operation = syncMatch[2];
                    const percentage = syncMatch[3];
                    const finishMatch = line.match(/finish=([\d.]+)(\w+)/);
                    const speedMatch = line.match(/speed=([\d.]+[KMG])\/sec/);
                    currentArray.syncStatus = {
                        operation: operation,
                        percentage: percentage,
                        finish: finishMatch ? finishMatch[1] + finishMatch[2] : null,
                        speed: speedMatch ? speedMatch[1] + '/sec' : null,
                        progress: syncMatch[1]
                    };
                }
            }
        }
        if (currentArray) {
            result.arrays.push(currentArray);
        }
        if (result.arrays.length > 0) {
            result.found = true;
        }
        storageDebugLog('[RAID parser] Found:', result);
        return result;
    }
};
/**
 * Parser: btrfsConfig
 * Parses BTRFS filesystem configuration
 */
const btrfsConfigParser = {
    filePattern: /\/(btrfs\.txt|fs-btrfs\.txt|btrfs-filesystem-show\.txt|btrfs-subvolume-list\.txt)$/,
    
    parse: function(content, filename) {
        storageDebugLog('[BTRFS parser] Analyzing:', filename);
        
        const result = {
            found: false,
            filesystems: [],
            subvolumes: [],
            warnings: [],
            rawOutput: {}
        };
        
        // Parse aggregated btrfs.txt file
        if (filename.includes('btrfs.txt')) {
            storageDebugLog('[BTRFS parser] Processing aggregated btrfs.txt file');
            
            // Parse "btrfs filesystem show" output
            // Match either direct command or after section marker
            const fsShowMatch = content.match(/(?:#==\[.*?\].*?\n)?# (?:\/usr)?\/sbin\/btrfs filesystem show[^\n]*\n([\s\S]*?)(?=\n#==\[|$)/);
            if (fsShowMatch) {
                storageDebugLog('Found btrfs filesystem show section, length:', fsShowMatch[1].length);
                this.parseFilesystems(fsShowMatch[1], result);
            } else {
                storageDebugLog('No btrfs filesystem show section found');
            }
            
            // Parse "btrfs subvolume list" output
            const subvolMatch = content.match(/(?:#==\[.*?\].*?\n)?# (?:\/usr)?\/sbin\/btrfs subvolume list[^\n]*\n([\s\S]*?)(?=\n#==\[|$)/);
            if (subvolMatch) {
                storageDebugLog('Found btrfs subvolume list section, length:', subvolMatch[1].length);
                this.parseSubvolumes(subvolMatch[1], result);
            } else {
                storageDebugLog('No btrfs subvolume list section found');
            }
        } else if (filename.includes('filesystem-show')) {
            this.parseFilesystems(content, result);
        } else if (filename.includes('subvolume-list')) {
            this.parseSubvolumes(content, result);
        }
        
        if (result.filesystems.length > 0 || result.subvolumes.length > 0) {
            result.found = true;
        }
        
        storageDebugLog('[BTRFS parser] Result:', {
            found: result.found,
            filesystems: result.filesystems.length,
            subvolumes: result.subvolumes.length,
            filesystemsData: result.filesystems,
            subvolumesData: result.subvolumes
        });
        return result;
    },
    
    parseFilesystems: function(content, result) {
        storageDebugLog('Parsing BTRFS filesystems, content length:', content.length);
        
        // Clean content from supportconfig markers
        const cleanContent = content
            .split('\n')
            .filter(line => !line.trim().startsWith('#=='))
            .join('\n');
        
        result.rawOutput.filesystems = cleanContent;
        
        const lines = cleanContent.split('\n');
        let currentFs = null;
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            
            // Match: Label: 'root'  uuid: 550e8400-e29b-41d4-a716-446655440000
            // or: Label: none  uuid: ...
            const labelMatch = trimmed.match(/Label:\s*(?:'([^']+)'|(\w+))\s+uuid:\s+([0-9a-f\-]+)/i);
            if (labelMatch) {
                if (currentFs) {
                    result.filesystems.push(currentFs);
                }
                currentFs = {
                    label: labelMatch[1] || labelMatch[2] || 'none',
                    uuid: labelMatch[3],
                    devices: [],
                    totalSize: '-'
                };
                storageDebugLog('BTRFS: Found filesystem:', currentFs.label);
                continue;
            }
            
            // Match: Total devices 2 FS bytes used 28.00GiB
            const totalMatch = trimmed.match(/Total devices\s+(\d+)\s+FS bytes used\s+([\d\.]+\w+)/i);
            if (currentFs && totalMatch) {
                currentFs.deviceCount = totalMatch[1];
                currentFs.totalSize = totalMatch[2];
                continue;
            }
            
            // Match device lines: devid    1 size 50.00GiB used 30.00GiB path /dev/sda1
            const deviceMatch = trimmed.match(/devid\s+(\d+)\s+size\s+([\d\.]+\w+)\s+used\s+([\d\.]+\w+)\s+path\s+(\/dev\/\S+)/i);
            if (currentFs && deviceMatch) {
                currentFs.devices.push({
                    devid: deviceMatch[1],
                    size: deviceMatch[2],
                    used: deviceMatch[3],
                    path: deviceMatch[4]
                });
                storageDebugLog('BTRFS: Added device:', deviceMatch[4]);
            }
        }
        
        // Add last filesystem
        if (currentFs) {
            result.filesystems.push(currentFs);
        }
        
        storageDebugLog('BTRFS: Total filesystems parsed:', result.filesystems.length);
    },
    
    parseSubvolumes: function(content, result) {
        storageDebugLog('Parsing BTRFS subvolumes, content length:', content.length);
        
        // Clean content from supportconfig markers
        const cleanContent = content
            .split('\n')
            .filter(line => !line.trim().startsWith('#=='))
            .join('\n');
        
        result.rawOutput.subvolumes = cleanContent;
        
        const lines = cleanContent.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            
            // Match: ID 256 gen 123 top level 5 path @rootfs
            // or: ID 257 gen 124 parent 256 top level 5 path @home
            const match = trimmed.match(/ID\s+(\d+)\s+gen\s+(\d+)(?:\s+parent\s+(\d+))?\s+top level\s+(\d+)\s+path\s+(.+)/);
            if (match) {
                result.subvolumes.push({
                    id: match[1],
                    gen: match[2],
                    parent: match[3] || '-',
                    topLevel: match[4],
                    path: match[5]
                });
                storageDebugLog('BTRFS: Added subvolume:', match[5]);
            }
        }
        
        storageDebugLog('BTRFS: Total subvolumes parsed:', result.subvolumes.length);
    }
};

/**
 * Parser: blockDevices
 * Parses block device information from lsblk and blkid outputs
 * Correlates with fstab to detect UUID mismatches or mount issues
 */
const blockDevicesParser = {
    filePattern: /\/sos_commands\/block\/(lsblk|lsblk_-f_-a_-l|blkid_-c_.dev.null)$/,
    
    // This parser accumulates data from multiple files
    multiFile: true,
    
    parse: function(content, filename) {
        storageDebugLog('[blockDevices parser] Analyzing:', filename);
        
        const result = {
            found: false,
            disks: [],
            partitions: [],
            uuidMap: {},       // UUID -> device mapping
            deviceMap: {},     // device -> info mapping
            mountPoints: {},   // mountpoint -> device mapping
            warnings: [],
            rawOutput: {}
        };
        
        if (filename.includes('lsblk_-f_-a_-l')) {
            // Parse lsblk -f -a -l output (includes filesystem, UUID, mount info)
            this.parseLsblkFull(content, result);
        } else if (filename.endsWith('/lsblk')) {
            // Parse basic lsblk output
            this.parseLsblkBasic(content, result);
        } else if (filename.includes('blkid')) {
            // Parse blkid output for complete UUID info
            this.parseBlkid(content, result);
        }
        
        if (result.disks.length > 0 || result.partitions.length > 0 || Object.keys(result.uuidMap).length > 0) {
            result.found = true;
        }
        
        storageDebugLog('[blockDevices parser] Found:', result.disks.length, 'disks,', result.partitions.length, 'partitions');
        return result;
    },
    
    parseLsblkBasic: function(content, result) {
        storageDebugLog('Parsing basic lsblk output');
        result.rawOutput.lsblk = content;
        
        const lines = content.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('NAME')) continue;
            
            // Clean tree characters: ├─, └─, │, `, -
            const cleanLine = trimmed.replace(/^[├└│`\-\s]+/, '');
            
            // Match: sda       8:0    0  300G  0 disk
            // or:    sda1      8:1    0  300G  0 part /mnt
            const match = cleanLine.match(/^(\S+)\s+(\d+:\d+)\s+(\d+)\s+([\d\.]+\w?)\s+(\d+)\s+(disk|part|lvm|raid\d*|loop|rom|crypt)\s*(.*)?$/);
            if (match) {
                const [, name, majMin, rm, size, ro, type, mountpoint] = match;
                const deviceInfo = {
                    name: name,
                    device: `/dev/${name}`,
                    majMin: majMin,
                    removable: rm === '1',
                    size: size,
                    readOnly: ro === '1',
                    type: type,
                    mountpoint: mountpoint?.trim() || null
                };
                
                if (type === 'disk') {
                    result.disks.push(deviceInfo);
                } else {
                    result.partitions.push(deviceInfo);
                }
                
                result.deviceMap[`/dev/${name}`] = deviceInfo;
                if (deviceInfo.mountpoint) {
                    result.mountPoints[deviceInfo.mountpoint] = `/dev/${name}`;
                }
            }
        }
    },
    
    parseLsblkFull: function(content, result) {
        storageDebugLog('Parsing lsblk -f -a -l output');
        result.rawOutput.lsblkFull = content;
        
        const lines = content.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('NAME')) continue;
            
            // Match: sda1  ext4   1.0         748dadf8-ba52-4bb3-b3ce-1ef8e8a2412f  279.2G     0% /mnt
            // Columns: NAME FSTYPE FSVER LABEL UUID FSAVAIL FSUSE% MOUNTPOINTS
            // Some fields may be empty
            const parts = trimmed.split(/\s+/);
            if (parts.length < 1) continue;
            
            const name = parts[0];
            // Skip loop devices without filesystem
            if (name.startsWith('loop') && parts.length < 3) continue;
            
            // Parse based on known column structure
            // NAME FSTYPE FSVER LABEL UUID FSAVAIL FSUSE% MOUNTPOINTS
            let fstype = null, uuid = null, mountpoint = null, fsavail = null, fsuse = null;
            
            // Try to identify UUID (looks like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx or short like B8C6-B076)
            for (let i = 1; i < parts.length; i++) {
                const part = parts[i];
                if (part.match(/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/) ||
                    part.match(/^[0-9a-fA-F]{4}-[0-9a-fA-F]{4}$/)) {
                    uuid = part;
                } else if (part.match(/^(ext[234]|xfs|btrfs|vfat|ntfs|swap|iso9660|squashfs)$/i)) {
                    fstype = part;
                } else if (part.startsWith('/')) {
                    mountpoint = part;
                } else if (part.match(/^\d+(\.\d+)?[KMGTP]?$/i) && !fsavail) {
                    fsavail = part;
                } else if (part.match(/^\d+%$/)) {
                    fsuse = part;
                }
            }
            
            // Update existing device info or create new
            const devicePath = `/dev/${name}`;
            if (!result.deviceMap[devicePath]) {
                result.deviceMap[devicePath] = {
                    name: name,
                    device: devicePath,
                    type: name.match(/^[a-z]+$/) ? 'disk' : 'part'
                };
                if (name.match(/^[a-z]+$/)) {
                    result.disks.push(result.deviceMap[devicePath]);
                } else if (!name.startsWith('loop')) {
                    result.partitions.push(result.deviceMap[devicePath]);
                }
            }
            
            const deviceInfo = result.deviceMap[devicePath];
            if (fstype) deviceInfo.fstype = fstype;
            if (uuid) {
                deviceInfo.uuid = uuid;
                result.uuidMap[uuid] = devicePath;
                result.uuidMap[uuid.toLowerCase()] = devicePath;
                result.uuidMap[uuid.toUpperCase()] = devicePath;
            }
            if (mountpoint) {
                deviceInfo.mountpoint = mountpoint;
                result.mountPoints[mountpoint] = devicePath;
            }
            if (fsavail) deviceInfo.fsavail = fsavail;
            if (fsuse) deviceInfo.fsuse = fsuse;
        }
    },
    
    parseBlkid: function(content, result) {
        storageDebugLog('Parsing blkid output');
        result.rawOutput.blkid = content;
        
        const lines = content.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            
            // Match: /dev/sda1: UUID="748dadf8-..." BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="..."
            const deviceMatch = trimmed.match(/^(\/dev\/\S+):\s*(.*)/);
            if (!deviceMatch) continue;
            
            const device = deviceMatch[1];
            const attrs = deviceMatch[2];
            
            // Extract attributes
            const uuid = attrs.match(/\bUUID="([^"]+)"/)?.[1];
            const type = attrs.match(/\bTYPE="([^"]+)"/)?.[1];
            const partuuid = attrs.match(/\bPARTUUID="([^"]+)"/)?.[1];
            const label = attrs.match(/\bLABEL="([^"]+)"/)?.[1];
            const blockSize = attrs.match(/\bBLOCK_SIZE="([^"]+)"/)?.[1];
            
            // Update device map
            if (!result.deviceMap[device]) {
                result.deviceMap[device] = {
                    name: device.replace('/dev/', ''),
                    device: device,
                    type: 'part'
                };
                result.partitions.push(result.deviceMap[device]);
            }
            
            const deviceInfo = result.deviceMap[device];
            if (uuid) {
                deviceInfo.uuid = uuid;
                result.uuidMap[uuid] = device;
                result.uuidMap[uuid.toLowerCase()] = device;
                result.uuidMap[uuid.toUpperCase()] = device;
            }
            if (type) deviceInfo.fstype = type;
            if (partuuid) deviceInfo.partuuid = partuuid;
            if (label) deviceInfo.label = label;
            if (blockSize) deviceInfo.blockSize = blockSize;
        }
    }
};

/**
 * Parser: fstabAnalysis
 * Enhanced fstab parser that correlates with block device information
 * to detect UUID mismatches and mount issues
 */
const fstabAnalysisParser = {
    filePattern: /\/etc\/fstab$|\/fs-diskio\.txt$/,
    
    parse: function(content, filename) {
        storageDebugLog('[fstabAnalysis parser] Analyzing:', filename);
        
        // If this is SCC's fs-diskio.txt, extract just the fstab section
        let fstabContent = content;
        if (filename.includes('fs-diskio.txt')) {
            fstabContent = this.extractFstabFromSCC(content);
            if (!fstabContent) {
                storageDebugLog('[fstabAnalysis parser] No fstab section found in fs-diskio.txt');
                return { found: false, entries: [], warnings: [] };
            }
        }
        
        const result = {
            found: false,
            entries: [],
            uuidEntries: [],      // Entries using UUID=
            deviceEntries: [],    // Entries using /dev/
            labelEntries: [],     // Entries using LABEL=
            warnings: [],
            rawContent: fstabContent
        };
        
        const lines = fstabContent.split('\n');
        
        // OS-critical mount points that don't need nofail (exact match only)
        // Subdirectories like /var/crash or /home/user should still get nofail
        const osMountPoints = ['/', '/boot', '/boot/efi', '/usr', '/var', '/tmp', '/home', '/opt'];
        // Virtual/pseudo filesystems that don't need nofail
        const virtualFsTypes = ['tmpfs', 'devtmpfs', 'sysfs', 'proc', 'cgroup', 'cgroup2', 'securityfs', 
                                'devpts', 'hugetlbfs', 'mqueue', 'debugfs', 'tracefs', 'fusectl', 
                                'configfs', 'pstore', 'efivarfs', 'bpf', 'binfmt_misc', 'autofs', 'sunrpc'];
        
        for (const line of lines) {
            const trimmed = line.trim();
            // Skip comments and empty lines
            if (!trimmed || trimmed.startsWith('#')) continue;
            
            // Parse fstab entry: device mountpoint fstype options dump pass
            const parts = trimmed.split(/\s+/);
            if (parts.length < 4) continue;
            
            const [source, mountpoint, fstype, options, dump, pass] = parts;
            
            const entry = {
                source: source,
                mountpoint: mountpoint,
                fstype: fstype,
                options: options,
                dump: dump || '0',
                pass: pass || '0',
                sourceType: 'unknown',
                uuid: null,
                label: null,
                device: null,
                hasNofail: options.includes('nofail'),
                // Only exact matches are considered OS partitions
                isOsPartition: osMountPoints.includes(mountpoint),
                isVirtualFs: virtualFsTypes.includes(fstype) || fstype === 'none',
                needsNofail: false  // Will be set below
            };
            
            // Determine source type and extract identifier
            if (source.startsWith('UUID=')) {
                entry.sourceType = 'uuid';
                entry.uuid = source.replace('UUID=', '');
                result.uuidEntries.push(entry);
            } else if (source.startsWith('LABEL=')) {
                entry.sourceType = 'label';
                entry.label = source.replace('LABEL=', '');
                result.labelEntries.push(entry);
            } else if (source.startsWith('/dev/')) {
                entry.sourceType = 'device';
                entry.device = source;
                result.deviceEntries.push(entry);
            } else if (source.startsWith('//') || source.includes(':')) {
                // Network mounts (CIFS, NFS)
                entry.sourceType = 'network';
            }
            
            // Check if this non-OS partition needs nofail
            // Network mounts and non-OS local mounts should have nofail
            if (!entry.isOsPartition && !entry.isVirtualFs && !entry.hasNofail) {
                entry.needsNofail = true;
                result.warnings.push({
                    type: 'missing_nofail',
                    severity: 'warning',
                    mountpoint: mountpoint,
                    source: source,
                    fstype: fstype,
                    message: `Mount point "${mountpoint}" is missing the 'nofail' option`,
                    recommendation: 'Add nofail option to prevent boot failures if this mount becomes unavailable',
                    documentationUrl: 'https://learn.microsoft.com/en-us/azure/virtual-machines/linux/fstab-device-names'
                });
            }
            
            result.entries.push(entry);
        }
        
        if (result.entries.length > 0) {
            result.found = true;
        }
        
        storageDebugLog('[fstabAnalysis parser] Found:', result.entries.length, 'entries,', result.warnings.length, 'warnings');
        return result;
    },
    
    extractFstabFromSCC: function(content) {
        // Extract fstab section from SCC's fs-diskio.txt
        // Look for "# /etc/fstab" marker
        const lines = content.split('\n');
        const fstabLines = [];
        let inFstabSection = false;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Start of fstab section
            if (line.includes('# /etc/fstab') || line.match(/^#\s*\/etc\/fstab\s*$/)) {
                inFstabSection = true;
                continue;
            }
            
            // End of fstab section (next command section marker)
            if (inFstabSection && (line.startsWith('#==') || line.match(/^#\s*\//))) {
                break;
            }
            
            // Collect fstab lines
            if (inFstabSection) {
                fstabLines.push(line);
            }
        }
        
        return fstabLines.length > 0 ? fstabLines.join('\n') : null;
    }
};

/**
 * Parser: dfOutput
 * Parses df command output to get disk usage information
 * File patterns: 
 *   - /df (sosreport - symlink to actual file)
 *   - sos_commands/filesys/df_* (actual df output in sosreport)
 *   - fs-diskio.txt (SCC)
 */
const dfOutputParser = {
    filePattern: /\/df$|\/df_-aliT|\/df_-al_|\/fs-diskio\.txt$/,
    
    parse: function(content, filename) {
        storageDebugLog('[dfOutput parser] Analyzing:', filename);
        
        const result = {
            found: false,
            filesystems: [],
            mountToUsage: {}  // Map mountpoint -> usage info for quick lookup
        };
        
        let dfContent = content;
        
        // If this is SCC's fs-diskio.txt, extract the df section
        if (filename.includes('fs-diskio.txt')) {
            dfContent = this.extractDfFromSCC(content);
            if (!dfContent) {
                storageDebugLog('[dfOutput parser] No df section found in fs-diskio.txt');
                return result;
            }
        }
        
        const lines = dfContent.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            // Skip header lines and empty lines
            if (!trimmed || trimmed.startsWith('Filesystem') || trimmed.startsWith('#')) continue;
            
            // Parse df output - handle both formats:
            // Standard df: Filesystem 1K-blocks Used Available Use% Mounted on
            // df -Th:      Filesystem Type Size Used Avail Use% Mounted on
            
            // Check if this line has a Type column (df -Th format)
            const parts = trimmed.split(/\s+/);
            if (parts.length < 5) continue;
            
            let filesystem, fstype, size, used, avail, usePercent, mountpoint;
            
            // Detect format by checking if second column looks like a filesystem type
            const possibleType = parts[1];
            const isTypedFormat = /^(xfs|ext[234]|vfat|btrfs|nfs[34]?|cifs|tmpfs|devtmpfs|sysfs|proc|overlay|zfs|swap)$/i.test(possibleType);
            
            if (isTypedFormat && parts.length >= 7) {
                // df -Th format: Filesystem Type Size Used Avail Use% Mounted
                [filesystem, fstype, size, used, avail, usePercent, mountpoint] = parts;
            } else if (parts.length >= 6) {
                // Standard df format: Filesystem 1K-blocks Used Available Use% Mounted
                [filesystem, size, used, avail, usePercent, mountpoint] = parts;
                fstype = null;
            } else {
                continue;
            }
            
            // Clean up use percentage
            const usePct = parseInt(usePercent?.replace('%', '') || '0', 10);
            
            const entry = {
                filesystem: filesystem,
                fstype: fstype,
                size: size,
                used: used,
                available: avail,
                usePercent: usePct,
                usePercentStr: usePercent,
                mountpoint: mountpoint
            };
            
            result.filesystems.push(entry);
            result.mountToUsage[mountpoint] = entry;
        }
        
        if (result.filesystems.length > 0) {
            result.found = true;
        }
        
        storageDebugLog('[dfOutput parser] Found:', result.filesystems.length, 'filesystems');
        return result;
    },
    
    extractDfFromSCC: function(content) {
        // Extract df section from SCC's fs-diskio.txt
        // Look for "# /bin/df" marker
        const lines = content.split('\n');
        const dfLines = [];
        let inDfSection = false;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Start of df section
            if (line.includes('# /bin/df') || line.includes('# df ')) {
                inDfSection = true;
                continue;
            }
            
            // End of df section (next command section marker)
            if (inDfSection && (line.startsWith('#==') || (line.startsWith('# /') && !line.includes('df')))) {
                break;
            }
            
            // Collect df lines
            if (inDfSection && line.trim()) {
                dfLines.push(line);
            }
        }
        
        return dfLines.length > 0 ? dfLines.join('\n') : null;
    }
};
