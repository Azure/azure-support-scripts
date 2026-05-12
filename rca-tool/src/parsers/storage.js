/**
 * @module parsers/storage
 * @description Storage parsers — partial migration to WASM thin shims.
 *
 * Migrated to thin shims (delegated to `supportfile_core` Rust):
 *   - `lvmConfigParser`     → `parseLvmConfig`
 *   - `raidConfigParser`    → `parseRaidConfig`
 *   - `fstabAnalysisParser` → `parseFstabAnalysis`
 *   - `dfOutputParser`      → `parseDfOutput`
 *   - `mtabAnalysisParser`  → `parseMtabAnalysis`
 *
 * Still legacy thick JS (Rust port has feature gaps — see TODO blocks below):
 *   - `btrfsConfigParser`   — Rust `BtrfsFilesystem` is missing `deviceCount`,
 *                              device entries, and `BtrfsSubvolume` is missing
 *                              `parent`/`topLevel` fields that the Leptos UI
 *                              renders.
 *   - `blockDevicesParser`  — Rust `BlockDevicesResult` does not expose the
 *                              per-device `deviceMap` that
 *                              `worker.correlateFstabWithBlockDevices()`
 *                              relies on for UUID/fstype lookups.
 *
 * SCC fs-diskio.txt section extraction (fstab / df / mount) stays in JS for
 * now — the Rust parsers expect already-extracted content.  This avoids
 * duplicating section-marker logic in two languages.
 */

function storageDebugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.storage) {
        console.log('[storage.js]', ...args);
    }
}

function _storageWasmCall(fnName, content, filename, fallback) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
        storageDebugLog('WASM not ready -- returning fallback for', fnName, filename);
        return fallback;
    }
    try {
        return WASM_BRIDGE.parseJson(fnName, content, filename || '');
    } catch (err) {
        console.error('[storage.js]', fnName, 'WASM call failed:', err);
        return fallback;
    }
}

// ===========================================================================
// lvmConfig — thin shim
// ===========================================================================
//
// The Rust `parseLvmConfig` parses any LVM content (aggregated lvm.txt,
// individual pvs/vgs/lvs/pvdisplay/etc.) line-by-line and emits the same
// PV/VG/LV columns as the legacy JS.  The shim is responsible for:
//   1. Filtering supportconfig markers / lvm preamble (so that the
//      `rawOutput.{pvs,vgs,lvs}` panes shown by the Leptos UI stay clean).
//   2. Routing the cleaned content into the right `rawOutput` slot based
//      on the filename.
//   3. Re-aliasing `pvCount`/`lvCount` (mechanical camelCase from
//      `pv_count`/`lv_count`) back to snake_case, because the Leptos LVM
//      table currently reads `vg.pv_count` / `vg.lv_count`.
//
// `mergeResults` is preserved so the worker can accumulate sosreport's
// separate `pvs.txt`, `vgs.txt`, and `lvs.txt` files into one result.

const LVM_VG_ALIASES = {
    pvCount: 'pv_count',
    lvCount: 'lv_count',
};

function _cleanLvmOutput(content) {
    return content
        .split('\n')
        .filter(line => {
            const t = line.trim();
            return !t.startsWith('#==')
                && !t.startsWith('WARNING:')
                && !t.startsWith('Reloading')
                && !t.startsWith('Loading config')
                && !t.startsWith('devices/');
        })
        .join('\n');
}

const lvmConfigParser = {
    filePattern: /\/(lvm\.txt|pvs\.txt|vgs\.txt|lvs\.txt|pvdisplay|vgdisplay|lvdisplay)$|\/lvm2\/pvs_|\/lvm2\/vgs_|\/lvm2\/lvs_/,

    parse: function(content, filename, _lines) {
        storageDebugLog('[LVM parser] Analyzing:', filename);

        const result = _storageWasmCall('parseLvmConfig', content, filename, null);
        if (!result) {
            return { found: false, pvs: [], vgs: [], lvs: [], warnings: [], rawOutput: {} };
        }
        if (!result.rawOutput || typeof result.rawOutput !== 'object') {
            result.rawOutput = {};
        }

        // Route raw content into the right pane.  For aggregated lvm.txt,
        // we don't try to split here — Leptos shows whatever section keys
        // are present, and the structured pvs/vgs/lvs arrays already carry
        // the parsed data.
        const basename = (filename || '').split('/').pop();
        const cleanContent = _cleanLvmOutput(content);
        if (basename === 'lvm.txt') {
            result.rawOutput.pvs = cleanContent;
            result.rawOutput.vgs = cleanContent;
            result.rawOutput.lvs = cleanContent;
        } else if (basename.startsWith('pvs') || basename === 'pvdisplay') {
            result.rawOutput.pvs = cleanContent;
        } else if (basename.startsWith('vgs') || basename === 'vgdisplay') {
            result.rawOutput.vgs = cleanContent;
        } else if (basename.startsWith('lvs') || basename === 'lvdisplay') {
            result.rawOutput.lvs = cleanContent;
        }

        WASM_BRIDGE.aliasKeys(result, LVM_VG_ALIASES);

        storageDebugLog('[LVM parser] Found:', {
            found: result.found,
            pvs: result.pvs?.length || 0,
            vgs: result.vgs?.length || 0,
            lvs: result.lvs?.length || 0,
        });
        return result;
    },

    /**
     * Merge results from multiple LVM files (sosreport ships pvs/vgs/lvs as
     * separate files).  Same contract as the legacy JS implementation:
     * push arrays, OR `found` flags, and shallow-merge `rawOutput`.
     */
    mergeResults: function(existing, newResult) {
        if (newResult.pvs && newResult.pvs.length > 0) existing.pvs.push(...newResult.pvs);
        if (newResult.vgs && newResult.vgs.length > 0) existing.vgs.push(...newResult.vgs);
        if (newResult.lvs && newResult.lvs.length > 0) existing.lvs.push(...newResult.lvs);
        if (newResult.warnings && newResult.warnings.length > 0) {
            existing.warnings.push(...newResult.warnings);
        }
        if (newResult.rawOutput) {
            if (!existing.rawOutput) existing.rawOutput = {};
            Object.assign(existing.rawOutput, newResult.rawOutput);
        }
        if ((newResult.pvs?.length || 0) > 0
            || (newResult.vgs?.length || 0) > 0
            || (newResult.lvs?.length || 0) > 0) {
            existing.found = true;
        }
    },
};

// ===========================================================================
// raidConfig — thin shim
// ===========================================================================

const raidConfigParser = {
    filePattern: /\/(mdstat|md-arrays\.txt|mdadm\.txt|proc\/mdstat)$/,

    parse: function(content, filename, _lines) {
        storageDebugLog('[RAID parser] Analyzing:', filename);
        const result = _storageWasmCall('parseRaidConfig', content, filename, null);
        if (!result) {
            return { found: false, arrays: [], warnings: [], rawOutput: { mdstat: content } };
        }
        if (!result.rawOutput || typeof result.rawOutput !== 'object') {
            result.rawOutput = {};
        }
        result.rawOutput.mdstat = content;
        storageDebugLog('[RAID parser] Found:', result.arrays?.length || 0, 'arrays');
        return result;
    },
};

// ===========================================================================
// fstabAnalysis — thin shim (with SCC section extraction kept in JS)
// ===========================================================================

function _extractFstabFromSCC(content) {
    // SCC's `fs-diskio.txt` is a multipart file with sections delimited by
    // lines starting with `#==[` (e.g. `#==[ Configuration File ]==`).
    // The fstab section begins with a `# /etc/fstab` header line and ends
    // at the next `#==` marker.  Blank lines and commented-out fstab entries
    // (e.g. `#/dev/system/swap` on SUSE12) are legitimate fstab content and
    // must NOT terminate the section.
    const headerRe = /^#\s*\/etc\/fstab\s*$/;
    const out = [];
    let inSection = false;
    for (const line of content.split('\n')) {
        if (!inSection) {
            if (headerRe.test(line)) inSection = true;
            continue;
        }
        if (line.startsWith('#==')) break;
        out.push(line);
    }
    // Strip leading/trailing blanks; preserve interior blanks (some fstabs
    // use blank lines as visual separators between mount groups).
    while (out.length && out[0].trim() === '') out.shift();
    while (out.length && out[out.length - 1].trim() === '') out.pop();
    return out.length > 0 ? out.join('\n') : null;
}

const fstabAnalysisParser = {
    filePattern: /\/etc\/fstab$|\/fs-diskio\.txt$/,

    parse: function(content, filename, _lines) {
        storageDebugLog('[fstabAnalysis parser] Analyzing:', filename);

        let fstabContent = content;
        if ((filename || '').includes('fs-diskio.txt')) {
            fstabContent = _extractFstabFromSCC(content);
            if (!fstabContent) {
                storageDebugLog('[fstabAnalysis parser] No fstab section in fs-diskio.txt');
                return { found: false, entries: [], warnings: [] };
            }
        }

        const result = _storageWasmCall('parseFstabAnalysis', fstabContent, filename, null);
        if (!result) {
            return { found: false, entries: [], warnings: [], rawContent: fstabContent };
        }
        result.rawContent = fstabContent;
        storageDebugLog('[fstabAnalysis parser] Found:', result.entries?.length || 0, 'entries');
        return result;
    },
};

// ===========================================================================
// dfOutput — thin shim (with SCC section extraction kept in JS)
// ===========================================================================

function _extractDfFromSCC(content) {
    const lines = content.split('\n');
    const out = [];
    let inSection = false;
    for (const line of lines) {
        if (line.includes('# /bin/df') || line.includes('# df ')) {
            inSection = true;
            continue;
        }
        if (inSection && (line.startsWith('#==') || (line.startsWith('# /') && !line.includes('df')))) {
            break;
        }
        if (inSection && line.trim()) out.push(line);
    }
    return out.length > 0 ? out.join('\n') : null;
}

const dfOutputParser = {
    filePattern: /\/df$|\/df_-aliT|\/df_-al_|\/fs-diskio\.txt$/,

    parse: function(content, filename, _lines) {
        storageDebugLog('[dfOutput parser] Analyzing:', filename);

        let dfContent = content;
        if ((filename || '').includes('fs-diskio.txt')) {
            dfContent = _extractDfFromSCC(content);
            if (!dfContent) {
                return { found: false, filesystems: [], mountToUsage: {} };
            }
        }

        const result = _storageWasmCall('parseDfOutput', dfContent, filename, null);
        if (!result) {
            return { found: false, filesystems: [], mountToUsage: {} };
        }
        storageDebugLog('[dfOutput parser] Found:', result.filesystems?.length || 0, 'filesystems');
        return result;
    },
};

// ===========================================================================
// mtabAnalysis — thin shim (with SCC section extraction kept in JS)
// ===========================================================================
//
// The Rust `parseMtabAnalysis` already handles the `device on mp type fs
// (opts)` mount-command format internally, so we don't need the legacy
// `convertMountToMtab` helper.  We still extract the mount section from
// SCC's `fs-diskio.txt` here in JS.
//
// Note: Rust pre-populates `extra_mounts` with all non-virtual entries.
// The worker's `compareMtabWithFstab()` re-derives `extraMounts` later by
// diffing against fstab, so the Rust default is harmless (it gets
// overwritten).

function _extractMountFromSCC(content) {
    const lines = content.split('\n');
    const out = [];
    let inSection = false;
    for (const line of lines) {
        if (/^#\s*\/bin\/mount\b/.test(line) || /^#\s*mount\s*$/.test(line)) {
            inSection = true;
            continue;
        }
        if (inSection && (line.startsWith('#==') || /^#\s*\//.test(line))) break;
        if (inSection && line.trim()) out.push(line);
    }
    return out.length > 0 ? out.join('\n') : null;
}

const mtabAnalysisParser = {
    filePattern: /\/etc\/mtab$|\/proc\/mounts$|\/proc\/self\/mounts$|\/fs-diskio\.txt$|\/mount_-l$|\/mount$/,

    parse: function(content, filename, _lines) {
        storageDebugLog('[mtabAnalysis parser] Analyzing:', filename);

        let mtabContent = content;
        if ((filename || '').includes('fs-diskio.txt')) {
            mtabContent = _extractMountFromSCC(content);
            if (!mtabContent) {
                return { found: false, entries: [], extraMounts: [], rawContent: '' };
            }
        }

        const result = _storageWasmCall('parseMtabAnalysis', mtabContent, filename, null);
        if (!result) {
            return { found: false, entries: [], extraMounts: [], rawContent: mtabContent };
        }
        result.rawContent = mtabContent;
        storageDebugLog('[mtabAnalysis parser] Found:', result.entries?.length || 0, 'entries');
        return result;
    },
};

// ===========================================================================
// btrfsConfig — LEGACY THICK JS (Rust port lacks deviceCount, devices[],
// parent, topLevel fields needed by the Leptos BTRFS section)
// ===========================================================================
// TODO: Once Rust BtrfsFilesystem gains a `device_count` field and
// `devices: Vec<BtrfsDeviceEntry { devid, size, used, path }>`, and
// BtrfsSubvolume gains `parent` + `top_level`, replace this with a thin
// shim mirroring `raidConfigParser` (with rawOutput.{filesystems,subvolumes}).

const btrfsConfigParser = {
    filePattern: /\/(btrfs\.txt|fs-btrfs\.txt|btrfs-filesystem-show\.txt|btrfs-subvolume-list\.txt)$/,

    parse: function(content, filename, _lines) {
        storageDebugLog('[BTRFS parser] Analyzing:', filename);

        const result = {
            found: false,
            filesystems: [],
            subvolumes: [],
            warnings: [],
            rawOutput: {}
        };

        if (filename.includes('btrfs.txt')) {
            const fsShowMatch = content.match(/(?:#==\[.*?\].*?\n)?# (?:\/usr)?\/sbin\/btrfs filesystem show[^\n]*\n([\s\S]*?)(?=\n#==\[|$)/);
            if (fsShowMatch) this._parseFilesystems(fsShowMatch[1], result);

            const subvolMatch = content.match(/(?:#==\[.*?\].*?\n)?# (?:\/usr)?\/sbin\/btrfs subvolume list[^\n]*\n([\s\S]*?)(?=\n#==\[|$)/);
            if (subvolMatch) this._parseSubvolumes(subvolMatch[1], result);
        } else if (filename.includes('filesystem-show')) {
            this._parseFilesystems(content, result);
        } else if (filename.includes('subvolume-list')) {
            this._parseSubvolumes(content, result);
        }

        if (result.filesystems.length > 0 || result.subvolumes.length > 0) {
            result.found = true;
        }
        return result;
    },

    _parseFilesystems: function(content, result) {
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

            const labelMatch = trimmed.match(/Label:\s*(?:'([^']+)'|(\w+))\s+uuid:\s+([0-9a-f\-]+)/i);
            if (labelMatch) {
                if (currentFs) result.filesystems.push(currentFs);
                currentFs = {
                    label: labelMatch[1] || labelMatch[2] || 'none',
                    uuid: labelMatch[3],
                    devices: [],
                    totalSize: '-'
                };
                continue;
            }

            const totalMatch = trimmed.match(/Total devices\s+(\d+)\s+FS bytes used\s+([\d\.]+\w+)/i);
            if (currentFs && totalMatch) {
                currentFs.deviceCount = totalMatch[1];
                currentFs.totalSize = totalMatch[2];
                continue;
            }

            const deviceMatch = trimmed.match(/devid\s+(\d+)\s+size\s+([\d\.]+\w+)\s+used\s+([\d\.]+\w+)\s+path\s+(\/dev\/\S+)/i);
            if (currentFs && deviceMatch) {
                currentFs.devices.push({
                    devid: deviceMatch[1],
                    size: deviceMatch[2],
                    used: deviceMatch[3],
                    path: deviceMatch[4]
                });
            }
        }
        if (currentFs) result.filesystems.push(currentFs);
    },

    _parseSubvolumes: function(content, result) {
        const cleanContent = content
            .split('\n')
            .filter(line => !line.trim().startsWith('#=='))
            .join('\n');
        result.rawOutput.subvolumes = cleanContent;

        const lines = cleanContent.split('\n');
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;

            const match = trimmed.match(/ID\s+(\d+)\s+gen\s+(\d+)(?:\s+parent\s+(\d+))?\s+top level\s+(\d+)\s+path\s+(.+)/);
            if (match) {
                result.subvolumes.push({
                    id: match[1],
                    gen: match[2],
                    parent: match[3] || '-',
                    topLevel: match[4],
                    path: match[5]
                });
            }
        }
    }
};

// ===========================================================================
// blockDevices — LEGACY THICK JS (Rust port lacks the per-device deviceMap
// that worker.correlateFstabWithBlockDevices() uses to look up uuid/fstype
// for each fstab UUID= entry)
// ===========================================================================
// TODO: Once Rust BlockDevicesResult exposes `device_map: BTreeMap<String,
// BlockDeviceInfo>` (it already maintains one internally), replace this
// with a thin shim like `lvmConfigParser` (with `mergeResults` for
// multi-file accumulation).

const blockDevicesParser = {
    filePattern: /\/sos_commands\/block\/(lsblk|lsblk_-f_-a_-l|blkid_-c_.dev.null)$|^results\.txt$/,
    multiFile: true,

    parse: function(content, filename, _lines) {
        storageDebugLog('[blockDevices parser] Analyzing:', filename);

        const result = {
            found: false,
            disks: [],
            partitions: [],
            uuidMap: {},
            deviceMap: {},
            mountPoints: {},
            warnings: [],
            rawOutput: {}
        };

        if (filename.includes('lsblk_-f_-a_-l')) {
            this._parseLsblkFull(content, result);
        } else if (filename.endsWith('/lsblk')) {
            this._parseLsblkBasic(content, result);
        } else if (filename.includes('blkid')) {
            this._parseBlkid(content, result);
        } else if (filename.endsWith('results.txt')) {
            this._parseInspectDiskFilesystems(content, result);
        }

        if (result.disks.length > 0 || result.partitions.length > 0
            || Object.keys(result.uuidMap).length > 0) {
            result.found = true;
        }
        return result;
    },

    _parseLsblkBasic: function(content, result) {
        result.rawOutput.lsblk = content;
        for (const line of content.split('\n')) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('NAME')) continue;
            const cleanLine = trimmed.replace(/^[├└│`\-\s]+/, '');
            const match = cleanLine.match(/^(\S+)\s+(\d+:\d+)\s+(\d+)\s+([\d\.]+\w?)\s+(\d+)\s+(disk|part|lvm|raid\d*|loop|rom|crypt)\s*(.*)?$/);
            if (!match) continue;
            const [, name, majMin, rm, size, ro, type, mountpoint] = match;
            const deviceInfo = {
                name, device: `/dev/${name}`, majMin,
                removable: rm === '1', size, readOnly: ro === '1', type,
                mountpoint: mountpoint?.trim() || null
            };
            if (type === 'disk') result.disks.push(deviceInfo);
            else result.partitions.push(deviceInfo);
            result.deviceMap[`/dev/${name}`] = deviceInfo;
            if (deviceInfo.mountpoint) {
                result.mountPoints[deviceInfo.mountpoint] = `/dev/${name}`;
            }
        }
    },

    _parseLsblkFull: function(content, result) {
        result.rawOutput.lsblkFull = content;
        for (const line of content.split('\n')) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('NAME')) continue;
            const parts = trimmed.split(/\s+/);
            if (parts.length < 1) continue;
            const name = parts[0];
            if (name.startsWith('loop') && parts.length < 3) continue;
            let fstype = null, uuid = null, mountpoint = null, fsavail = null, fsuse = null;
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
            const devicePath = `/dev/${name}`;
            if (!result.deviceMap[devicePath]) {
                result.deviceMap[devicePath] = {
                    name, device: devicePath,
                    type: name.match(/^[a-z]+$/) ? 'disk' : 'part'
                };
                if (name.match(/^[a-z]+$/)) result.disks.push(result.deviceMap[devicePath]);
                else if (!name.startsWith('loop')) result.partitions.push(result.deviceMap[devicePath]);
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

    _parseBlkid: function(content, result) {
        result.rawOutput.blkid = content;
        for (const line of content.split('\n')) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            const deviceMatch = trimmed.match(/^(\/dev\/\S+):\s*(.*)/);
            if (!deviceMatch) continue;
            const device = deviceMatch[1];
            const attrs = deviceMatch[2];
            const uuid = attrs.match(/\bUUID="([^"]+)"/)?.[1];
            const type = attrs.match(/\bTYPE="([^"]+)"/)?.[1];
            const partuuid = attrs.match(/\bPARTUUID="([^"]+)"/)?.[1];
            const label = attrs.match(/\bLABEL="([^"]+)"/)?.[1];
            const blockSize = attrs.match(/\bBLOCK_SIZE="([^"]+)"/)?.[1];
            if (!result.deviceMap[device]) {
                result.deviceMap[device] = {
                    name: device.replace('/dev/', ''),
                    device, type: 'part'
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
    },

    _parseInspectDiskFilesystems: function(content, result) {
        if (!content.includes('Filesystem Status:')) return;
        result.rawOutput.inspectDisk = content;

        const lines = content.split('\n');
        let inSection = false;
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed === 'Filesystem Status:') {
                inSection = true;
                continue;
            }
            if (inSection && (
                trimmed === ''
                || trimmed.startsWith('Inspection')
                || trimmed.startsWith('=====')
                || /^\d{2}:\d{2}:\d{2}\s+Executing/.test(trimmed)
            )) break;
            if (!inSection) continue;

            const fsMatch = trimmed.match(/^(\/dev\/\S+):\s+(\S+)\s+\[uuid=([^\]]*)\]/);
            if (!fsMatch) continue;
            const device = fsMatch[1];
            const fstype = fsMatch[2];
            const uuid = fsMatch[3] || null;
            if (fstype === 'unknown' && !uuid) continue;
            const isLvm = /^\/dev\/[^/]+\/[^/]+$/.test(device) && !device.match(/^\/dev\/sd[a-z]\d+$/);
            const type = isLvm ? 'lvm' : 'part';
            if (!result.deviceMap[device]) {
                const deviceInfo = {
                    name: device.replace('/dev/', ''),
                    device, type, source: 'InspectIaaSDisk'
                };
                result.deviceMap[device] = deviceInfo;
                result.partitions.push(deviceInfo);
            }
            const deviceInfo = result.deviceMap[device];
            if (fstype && fstype !== 'unknown') deviceInfo.fstype = fstype;
            if (uuid) {
                deviceInfo.uuid = uuid;
                result.uuidMap[uuid] = device;
                result.uuidMap[uuid.toLowerCase()] = device;
                result.uuidMap[uuid.toUpperCase()] = device;
            }
        }
    }
};
