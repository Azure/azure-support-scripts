/**
 * @module parsers/storage
 * @description Storage parser shims delegated to `supportfile_core` Rust.
 *
 * This file intentionally does not implement storage parsing logic in JS.
 * Each parser calls `WASM_BRIDGE.parseJson(...)` and only performs minimal
 * compatibility shaping for current Leptos consumers (raw panes, field aliases,
 * and multi-file result merges).
 *
 * Rust-backed parser entrypoints used here:
 *   - `parseLvmConfig`
 *   - `parseRaidConfig`
 *   - `parseFstabAnalysis`
 *   - `parseDfOutput`
 *   - `parseMtabAnalysis`
 *   - `parseBtrfsConfig`
 *   - `parseBlockDevices`
 *
 * SCC `fs-diskio.txt` extraction (fstab / df / mount sections) remains as
 * lightweight pre-processing in JS before invoking Rust.
 */

function _storageWasmCall(fnName, content, filename, fallback) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
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
//   3. Keeping raw panes mapped by filename so the Leptos LVM
//      table and diagnostics stay coherent across split files.
//
// `mergeResults` is preserved so the worker can accumulate sosreport's
// separate `pvs.txt`, `vgs.txt`, and `lvs.txt` files into one result.

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
        const result = _storageWasmCall('parseRaidConfig', content, filename, null);
        if (!result) {
            return { found: false, arrays: [], warnings: [], rawOutput: { mdstat: content } };
        }
        if (!result.rawOutput || typeof result.rawOutput !== 'object') {
            result.rawOutput = {};
        }
        result.rawOutput.mdstat = content;
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
        let fstabContent = content;
        if ((filename || '').includes('fs-diskio.txt')) {
            fstabContent = _extractFstabFromSCC(content);
            if (!fstabContent) {
                return { found: false, entries: [], warnings: [] };
            }
        }

        const result = _storageWasmCall('parseFstabAnalysis', fstabContent, filename, null);
        if (!result) {
            return { found: false, entries: [], warnings: [], rawContent: fstabContent };
        }
        result.rawContent = fstabContent;
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
        return result;
    },
};

// ===========================================================================
// btrfsConfig — thin shim
// ===========================================================================
// Rust now provides the parser. Keep a tiny compatibility projection so the
// Leptos renderer can keep reading legacy fields while we finish UI cleanup.

const btrfsConfigParser = {
    filePattern: /\/(btrfs\.txt|fs-btrfs\.txt|btrfs-filesystem-show\.txt|btrfs-subvolume-list\.txt)$/,

    parse: function(content, filename, _lines) {
        const result = _storageWasmCall('parseBtrfsConfig', content, filename, null);
        if (!result) {
            return { found: false, filesystems: [], subvolumes: [], warnings: [], rawOutput: {} };
        }

        if (!Array.isArray(result.filesystems)) result.filesystems = [];
        if (!Array.isArray(result.subvolumes)) result.subvolumes = [];
        if (!Array.isArray(result.warnings)) result.warnings = [];
        if (!result.rawOutput || typeof result.rawOutput !== 'object') {
            result.rawOutput = {};
        }

        // Compatibility projection for legacy Leptos rendering.
        for (const fs of result.filesystems) {
            if (!Array.isArray(fs.devices)) fs.devices = [];
            if (fs.deviceCount == null) fs.deviceCount = String(fs.devices.length);
            fs.devices = fs.devices.map((dev, idx) => {
                if (typeof dev === 'string') {
                    return {
                        devid: String(idx + 1),
                        size: '-',
                        used: '-',
                        path: dev,
                    };
                }
                return dev;
            });
        }

        for (const subvol of result.subvolumes) {
            if (subvol.parent == null) subvol.parent = '-';
            if (subvol.topLevel == null) subvol.topLevel = '-';
        }

        const basename = (filename || '').split('/').pop() || '';
        if (basename.includes('filesystem-show')) result.rawOutput.filesystems = content;
        if (basename.includes('subvolume-list')) result.rawOutput.subvolumes = content;
        if (basename === 'btrfs.txt') {
            result.rawOutput.filesystems = result.rawOutput.filesystems || content;
            result.rawOutput.subvolumes = result.rawOutput.subvolumes || content;
        }

        return result;
    }
};

// ===========================================================================
// blockDevices — thin shim
// ===========================================================================

const blockDevicesParser = {
    filePattern: /\/sos_commands\/block\/(lsblk|lsblk_-f_-a_-l|blkid_-c_.dev.null)$|^results\.txt$/,
    multiFile: true,

    parse: function(content, filename, _lines) {
        const result = _storageWasmCall('parseBlockDevices', content, filename, null);
        if (!result) {
            return {
                found: false,
                disks: [],
                partitions: [],
                uuidMap: {},
                deviceMap: {},
                mountPoints: {},
                warnings: [],
                rawOutput: {},
            };
        }

        if (!result.uuidMap || typeof result.uuidMap !== 'object') result.uuidMap = {};
        if (!result.deviceMap || typeof result.deviceMap !== 'object') result.deviceMap = {};
        if (!result.mountPoints || typeof result.mountPoints !== 'object') result.mountPoints = {};
        if (!Array.isArray(result.disks)) result.disks = [];
        if (!Array.isArray(result.partitions)) result.partitions = [];
        if (!Array.isArray(result.warnings)) result.warnings = [];
        if (!result.rawOutput || typeof result.rawOutput !== 'object') result.rawOutput = {};

        // Preserve raw panes for troubleshooting/debug UI.
        const basename = (filename || '').split('/').pop() || '';
        if (basename === 'lsblk') result.rawOutput.lsblk = content;
        else if (basename.includes('lsblk_-f_-a_-l')) result.rawOutput.lsblkFull = content;
        else if (basename.includes('blkid')) result.rawOutput.blkid = content;
        else if (basename === 'results.txt') result.rawOutput.inspectDisk = content;

        return result;
    }
};

const nvmeListParser = {
    filePattern: /sos_commands\/nvme\/nvme_list$/,

    parse: function(content, filename, _lines) {
        const result = _storageWasmCall('parseNvmeList', content, filename, null);
        if (!result) {
            return {
                found: false,
                hasNVMe: false,
                driveCount: 0,
                content: null,
                filename: filename,
            };
        }

        // Rust emits snake_case; normalize keys expected by the UI.
        if (typeof result.hasNVMe === 'undefined' && typeof result.hasNvme !== 'undefined') {
            result.hasNVMe = result.hasNvme;
        }
        if (typeof result.driveCount !== 'number') {
            result.driveCount = 0;
        }
        return result;
    }
};
