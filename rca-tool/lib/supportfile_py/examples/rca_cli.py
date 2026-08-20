#!/usr/bin/env python3
"""rca_cli.py - Python port of the RCA Tool CLI.

Analyses ``.tar.xz`` / ``.tar.gz`` / ``.tar`` support bundles (the same
fixtures the JavaScript CLI consumes, including those produced by
``rca-tool/tests/create-fixtures.sh``) by streaming them through the
``supportfile`` Rust extension exposed by ``rca-tool/lib/supportfile_py``.

Usage:
    python rca_cli.py <archive> [--json] [--parser NAME] [--list-parsers]
                                [--extract DIR] [--debug]
"""

from __future__ import annotations

import argparse
import gzip
import json
import lzma
import os
import re
import sys
import tarfile
import zipfile
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Pattern, Tuple

try:
    import supportfile
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(
        "ERROR: the 'supportfile' native module is not installed.\n"
        "       From rca-tool/lib, run:\n"
        "         python3 -m venv .venv && . .venv/bin/activate\n"
        "         pip install ./supportfile_py\n"
    )
    raise SystemExit(1) from exc


# ---------------------------------------------------------------------------
# Parser registry
# ---------------------------------------------------------------------------
#
# Each entry maps a Python parser callable to:
#   - file_pattern: regex applied to the (full) archive member path. A parser
#     runs on every file whose path matches.
#   - multi_file: when True, results from successive files are merged. When
#     False, the last successful (``found`` truthy) result wins.
#
# The patterns mirror the JS parsers in rca-tool/lib/parsers/*.js so that the
# same fixtures yield equivalent coverage.

@dataclass
class ParserSpec:
    name: str                            # output key in the results dict
    func: Callable[[str], str]           # supportfile.parse_* function
    file_pattern: Pattern[str]
    multi_file: bool = False             # if True, merge results across files


def _re(pattern: str) -> Pattern[str]:
    return re.compile(pattern)


PARSERS: List[ParserSpec] = [
    # ----- Cluster ---------------------------------------------------------
    ParserSpec(
        "highCpuEvents", supportfile.parse_high_cpu_events,
        _re(r"/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|localmessages|journalctl[^/]*)"
            r"(?:[.-]\d+)?(?:\.txt)?(?:\.gz)?$|/ha\.txt$"),
        multi_file=True,
    ),
    ParserSpec(
        "clusterEvents", supportfile.parse_cluster_events,
        _re(r"/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|journalctl[^/]*)"
            r"(?:[.-]\d+)?(?:\.txt)?(?:\.gz)?$|/ha\.txt$"),
        multi_file=True,
    ),
    ParserSpec(
        "clusterStatus", supportfile.parse_cluster_status,
        _re(r"cib\.xml$|/crm_mon.*\.txt$|/crm_mon.*\.xml$|/ha\.txt$|/pcs_status"),
    ),
    ParserSpec(
        "corosyncConfig", supportfile.parse_corosync_config,
        _re(r"/(ha\.txt|corosync\.conf)$"),
    ),
    ParserSpec(
        "clusterMaintenanceMode", supportfile.parse_cluster_maintenance_mode,
        _re(r"cib\.xml$|/crm_mon.*\.txt$|/ha\.txt$"),
    ),

    # ----- Automation ------------------------------------------------------
    ParserSpec(
        "automationEvents", supportfile.parse_automation_events,
        _re(r"/(messages|localmessages|syslog|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$"),
        multi_file=True,
    ),

    # ----- Azure -----------------------------------------------------------
    ParserSpec(
        "azureVMProperties", supportfile.parse_azure_vm_properties,
        _re(r"(?:instance_metadata\.json|public_cloud/metadata\.txt)$"),
    ),
    ParserSpec(
        "suseCloudRegister", supportfile.parse_suse_cloud_register,
        _re(r"public_cloud/cloudregister\.txt$"),
    ),
    ParserSpec(
        "waagentConfig", supportfile.parse_waagent_config,
        _re(r"/etc/waagent\.conf$"),
    ),
    ParserSpec(
        "waagentLog", supportfile.parse_waagent_log,
        _re(r"/waagent\.log$"),
    ),
    ParserSpec(
        "azureExtensions", supportfile.parse_azure_extensions,
        _re(r"var/lib/waagent/[^/]+/config/HandlerStatus$"),
        multi_file=True,
    ),

    # ----- Debugfs ---------------------------------------------------------
    ParserSpec(
        "hvBalloon", supportfile.parse_hv_balloon,
        _re(r"sys/kernel/debug/hv[-_]balloon$"),
    ),
    ParserSpec(
        "extfrag", supportfile.parse_extfrag,
        _re(r"sys/kernel/debug/extfrag/(extfrag_index|unusable_index)$"),
        multi_file=True,
    ),

    # ----- System events ---------------------------------------------------
    ParserSpec(
        "emergencyMode", supportfile.parse_emergency_mode,
        _re(r"/(messages|localmessages|journalctl[^/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$"),
        multi_file=True,
    ),
    ParserSpec(
        "kernelReboots", supportfile.parse_kernel_reboots,
        _re(r"/(messages|localmessages|ha-log|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$"),
        multi_file=True,
    ),
    ParserSpec(
        "oomKiller", supportfile.parse_oom_killer,
        _re(r"/(messages|localmessages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$"),
        multi_file=True,
    ),
    ParserSpec(
        "xfsErrors", supportfile.parse_xfs_errors,
        _re(r"/(messages|localmessages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$"),
        multi_file=True,
    ),

    # ----- Networking ------------------------------------------------------
    ParserSpec(
        "firewallRules", supportfile.parse_firewall_rules,
        _re(r"network\.txt$|sos_commands/firewalld/|sos_commands/firewall_tables/|"
            r"etc/sysconfig/(?:iptables-config|ebtables-config|nftables\.conf|firewalld)$|"
            r"etc/firewalld/firewalld\.conf$"),
        multi_file=True,
    ),
    ParserSpec(
        "networkInterfaces", supportfile.parse_network_interfaces,
        _re(r"network\.txt$|sos_commands/networking/ip_-o_addr$|"
            r"sos_commands/networking/ip_-s_-d_link$|"
            r"sos_commands/networking/ethtool_-i_\w+|"
            r"sos_commands/networkmanager/nmcli_con_show_id_|"
            r"etc/sysconfig/network-scripts/ifcfg-|"
            r"etc/sysconfig/network/(?:network/)?ifcfg-|"
            r"etc/netplan/|var/log/cloud-init-output\.log$|(?:^|/)messages$"),
        multi_file=True,
    ),

    # ----- Packages --------------------------------------------------------
    ParserSpec(
        "distroPackages", supportfile.parse_distro_packages,
        _re(r"/(rpm\.txt|installed-rpms|package-data|dpkg_-l|"
            r"dnf[_-]list[_-]installed|yum[_-]list[_-]installed|"
            r"var/log/zypp/history|var/log/(?:dnf|yum)\.log)$"),
    ),

    # ----- Services --------------------------------------------------------
    ParserSpec(
        "sshServiceIssues", supportfile.parse_ssh_service_issues,
        _re(r"/(messages|localmessages|syslog|journalctl[^/]*|console.*\.log)"
            r"(?:[.-]\d+)?(?:\.txt)?$"),
        multi_file=True,
    ),
    ParserSpec(
        "dlmService", supportfile.parse_dlm_service,
        _re(r"sos_commands/systemd/systemctl_list-unit-files$"),
    ),
    ParserSpec(
        "azureSiteRecovery", supportfile.parse_azure_site_recovery,
        _re(r"(?:sos_commands/systemd/systemctl_list-unit-files|systemd-status\.txt)$"),
    ),
    ParserSpec(
        "guardicoreAgent", supportfile.parse_guardicore_agent,
        _re(r"(?:sos_commands/systemd/systemctl_list-unit-files|systemd-status\.txt)$"),
    ),
    ParserSpec(
        "illumio", supportfile.parse_illumio,
        _re(r"sos_commands/systemd/systemctl_list-units_--all$"),
    ),
    ParserSpec(
        "trendMicro", supportfile.parse_trend_micro,
        _re(r"sos_commands/systemd/systemctl_list-units_--all$"),
    ),
    ParserSpec(
        "falconSensor", supportfile.parse_falcon_sensor,
        _re(r"/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$"),
    ),
    ParserSpec(
        "falconSensorConfig", supportfile.parse_falcon_sensor_config,
        _re(r"/(falconctl|CrowdStrike.*config|falcon.*conf)$", ),
    ),
    ParserSpec(
        "msDefender", supportfile.parse_ms_defender,
        _re(r"/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$"),
    ),
    ParserSpec(
        "msDefenderConfig", supportfile.parse_ms_defender_config,
        _re(r"/(mdatp.*|defender.*config)$"),
    ),
    ParserSpec(
        "involfltVersion", supportfile.parse_involflt_version,
        _re(r"modules\.txt$"),
    ),
    ParserSpec(
        "involfltKernelVersion", supportfile.parse_involflt_kernel_version,
        _re(r"/(messages|boot)(?:[.-]\d+)?(?:\.txt)?$"),
    ),

    # ----- Storage ---------------------------------------------------------
    ParserSpec(
        "lvmConfig", supportfile.parse_lvm_config,
        _re(r"/(lvm\.txt|pvs\.txt|vgs\.txt|lvs\.txt|pvdisplay|vgdisplay|lvdisplay)$|"
            r"/lvm2/pvs_|/lvm2/vgs_|/lvm2/lvs_"),
    ),
    ParserSpec(
        "raidConfig", supportfile.parse_raid_config,
        _re(r"/(mdstat|md-arrays\.txt|mdadm\.txt|proc/mdstat)$"),
    ),
    ParserSpec(
        "btrfsConfig", supportfile.parse_btrfs_config,
        _re(r"/(btrfs\.txt|fs-btrfs\.txt|btrfs-filesystem-show\.txt|btrfs-subvolume-list\.txt)$"),
    ),
    ParserSpec(
        "blockDevices", supportfile.parse_block_devices,
        _re(r"/sos_commands/block/(lsblk|lsblk_-f_-a_-l|blkid_-c_\.dev\.null)$|(?:^|/)results\.txt$"),
        multi_file=True,
    ),
    ParserSpec(
        "fstabAnalysis", supportfile.parse_fstab_analysis,
        _re(r"/etc/fstab$|/fs-diskio\.txt$"),
    ),
    ParserSpec(
        "dfOutput", supportfile.parse_df_output,
        _re(r"/df$|/df_-aliT|/df_-al_|/fs-diskio\.txt$"),
    ),
    ParserSpec(
        "mtabAnalysis", supportfile.parse_mtab_analysis,
        _re(r"/etc/mtab$|/proc/mounts$|/proc/self/mounts$|/fs-diskio\.txt$|/mount_-l$|/mount$"),
    ),

    # ----- OS / filesystem -------------------------------------------------
    ParserSpec(
        "basicEnvironment", supportfile.parse_basic_environment,
        _re(r"basic-environment\.txt$"),
    ),
    ParserSpec(
        "osRelease", supportfile.parse_os_release,
        _re(r"/usr/lib/os-release$|/etc/os-release$|/sysinfo\.txt$|"
            r"/basic-environment\.txt$|/etc/(redhat|centos|SuSE|system)-release$"),
    ),
    ParserSpec(
        "fstab", supportfile.parse_fstab,
        _re(r"/etc/fstab$|/fs-diskio\.txt$"),
    ),
    ParserSpec(
        "inspectDiskResults", supportfile.parse_inspect_disk_results,
        _re(r"(?:^|/)results\.txt$"),
    ),

    # ----- Kernel tuning ---------------------------------------------------
    ParserSpec(
        "kernelTuning", supportfile.parse_kernel_tuning,
        _re(r"sos_commands/kernel/sysctl_-a$|/env\.txt$|/etc/sysctl\.conf$|"
            r"/sysctl\.d/[^/]*\.conf$"),
    ),
    ParserSpec(
        "hugePages", supportfile.parse_huge_pages,
        _re(r"/proc/meminfo$"),
    ),

    # ----- Time sync (Azure PTP) -------------------------------------------
    ParserSpec(
        "timeSync", supportfile.parse_time_sync,
        _re(r"sos_commands/kernel/lsmod$|/modules\.txt$"),
    ),
    ParserSpec(
        "ptpClockSource", supportfile.parse_ptp_clock_source,
        _re(r"sos_commands/chrony/chronyc_sources$|/etc/chrony\.conf$|"
            r"/etc/chrony/chrony\.conf$|/ntp\.txt$"),
    ),
    ParserSpec(
        "timeSyncService", supportfile.parse_time_sync_service,
        _re(r"sos_commands/systemd/systemctl_list-unit-files$|"
            r"/systemd-status\.txt$|/ntp\.txt$"),
    ),
    ParserSpec(
        "timedatectl", supportfile.parse_timedatectl,
        _re(r"sos_commands/systemd/timedatectl$|/ntp\.txt$"),
    ),
    ParserSpec(
        "ptpDevice", supportfile.parse_ptp_device,
        _re(r"sos_commands/block/ls_-lanR_\.dev$|/udev\.txt$"),
    ),
    ParserSpec(
        "chronyTracking", supportfile.parse_chrony_tracking,
        _re(r"sos_commands/chrony/chronyc_tracking$|/ntp\.txt$"),
    ),
    ParserSpec(
        "chronyMakestep", supportfile.parse_chrony_makestep,
        _re(r"/etc/chrony\.conf$|/etc/chrony/chrony\.conf$|/ntp\.txt$"),
    ),

    # ----- RHUI ------------------------------------------------------------
    ParserSpec(
        "rhuiConfig", supportfile.parse_rhui_config,
        _re(r"/(rh-cloud.*\.repo|rhui-.*\.repo|yum\.repos\.d\.txt|"
            r"dnf\.repos\.d\.txt|yum\.repos\.d/.*\.repo)$"),
    ),
    ParserSpec(
        "eusVersionLock", supportfile.parse_eus_version_lock,
        _re(r"/(releasever|yum-vars\.txt|dnf-vars\.txt|etc/yum/vars|"
            r"etc/dnf/vars|dnf/vars/releasever|yum/vars/releasever)$"),
    ),
    ParserSpec(
        "rhelRhuiCheck", supportfile.parse_rhel_rhui_check,
        _re(r"/(installed-rpms|rpm-qa\.txt|rpm_-qa|package-data)$"),
    ),
    ParserSpec(
        "rhuiErrors", supportfile.parse_rhui_errors,
        _re(r"/(dnf\.log|yum\.log|rhsm\.log)(\.\d+)?$"),
        multi_file=True,
    ),

    # ----- Security --------------------------------------------------------
    ParserSpec(
        "cryptoPolicies", supportfile.parse_crypto_policies,
        _re(r"/crypto-policies/(config|state/current)$"),
    ),
    ParserSpec(
        "fipsModeSetup", supportfile.parse_fips_mode_setup,
        _re(r"sos_commands/crypto/fips-mode-setup"),
    ),
    ParserSpec(
        "kernelCmdline", supportfile.parse_kernel_cmdline,
        _re(r"/proc/cmdline$|/boot\.txt$"),
    ),

    # ----- Leapp -----------------------------------------------------------
    ParserSpec(
        "leappReport", supportfile.parse_leapp_report,
        _re(r"var/log/leapp/leapp-report\.(txt|json)$"),
    ),
    ParserSpec(
        "leappLog", supportfile.parse_leapp_log,
        _re(r"var/log/leapp/leapp-(preupgrade|upgrade)\.log$"),
    ),

    # ----- vmcore / kdump --------------------------------------------------
    ParserSpec(
        "vmcoreDmesg", supportfile.parse_vmcore_dmesg,
        _re(r"var/crash/[^/]+/vmcore-dmesg\.txt$"),
        multi_file=True,
    ),
    ParserSpec(
        "kdumpStatus", supportfile.parse_kdump_status,
        _re(r"sos_commands/kdump/kdumpctl_status$"),
    ),
    ParserSpec(
        "crashListing", supportfile.parse_crash_listing,
        _re(r"sos_commands/kdump/ls_-alZR_\.var\.crash$"),
    ),
    ParserSpec(
        "kdumpConf", supportfile.parse_kdump_conf,
        _re(r"etc/kdump\.conf$"),
    ),
]


# ---------------------------------------------------------------------------
# Result merging
# ---------------------------------------------------------------------------

def _merge(existing: Any, new: Any) -> Any:
    """Best-effort recursive merge for multi-file parser results.

    Lists are concatenated, dicts are merged key-by-key, ``found``-style
    booleans are OR'ed, ``count``-style integers are summed, scalars take
    the last non-empty value. This mirrors what the JS CLI does for its
    multi-file parsers without having to special-case every parser shape.
    """
    if existing is None:
        return new
    if new is None:
        return existing
    if isinstance(existing, dict) and isinstance(new, dict):
        merged = dict(existing)
        for key, val in new.items():
            if key in merged:
                if key == "found":
                    merged[key] = bool(merged[key]) or bool(val)
                elif key == "count" and isinstance(merged[key], int) and isinstance(val, int):
                    merged[key] = merged[key] + val
                else:
                    merged[key] = _merge(merged[key], val)
            else:
                merged[key] = val
        return merged
    if isinstance(existing, list) and isinstance(new, list):
        return existing + new
    # Scalars: keep the existing value unless it's empty/falsy.
    return existing if existing not in (None, "", 0, False) else new


# ---------------------------------------------------------------------------
# Archive processing
# ---------------------------------------------------------------------------

@dataclass
class ArchiveResults:
    file_count: int = 0
    matched_files: int = 0
    parser_results: Dict[str, Any] = field(default_factory=dict)
    file_types: Dict[str, int] = field(default_factory=dict)


def _open_archive(path: str) -> tarfile.TarFile:
    # tarfile auto-detects gz/xz/bz2 from "r:*"
    return tarfile.open(path, mode="r:*")


def _is_zip(path: str) -> bool:
    return path.lower().endswith(".zip") and zipfile.is_zipfile(path)


_PLAINTEXT_EXTS = (".log", ".txt", ".out")
_GZIP_MAGIC = b"\x1f\x8b"
_XZ_MAGIC = b"\xfd7zXZ\x00"


def _is_plaintext(path: str) -> bool:
    """Detect a plaintext log file (no archive container).

    Recognises common log extensions and falls back to magic-byte sniffing:
    if the file is not gzip/xz/zip and not a tar, treat it as plaintext.
    """
    lower = path.lower()
    # Strip a trailing ".log" duplication like ".log.log"
    if lower.endswith(_PLAINTEXT_EXTS):
        return True
    try:
        with open(path, "rb") as fobj:
            head = fobj.read(512)
    except OSError:
        return False
    if head.startswith(_GZIP_MAGIC) or head.startswith(_XZ_MAGIC):
        return False
    if head.startswith(b"PK\x03\x04"):
        return False
    if tarfile.is_tarfile(path):
        return False
    # Heuristic: mostly printable ASCII / UTF-8 in the first chunk.
    if not head:
        return False
    printable = sum(1 for b in head if b == 9 or b == 10 or b == 13 or 32 <= b < 127)
    return printable / len(head) > 0.85


def _maybe_decompress_inner(name: str, data: bytes, debug: bool) -> Tuple[str, bytes]:
    """Decompress an archive member that is itself gzip/xz compressed.

    Mirrors ``maybe_decompress_inner`` in the Rust CLI: SOS reports often
    contain ``syslog-*.gz`` / ``kern.log-*.gz`` inside an outer ``.tar.xz``,
    which would otherwise be passed as binary garbage to text parsers.
    """
    try:
        if data.startswith(_GZIP_MAGIC):
            decoded = gzip.decompress(data)
            new_name = name[:-3] if name.lower().endswith(".gz") else name
            if debug:
                sys.stderr.write(
                    f"[debug] inner gzip: {name} -> {new_name} "
                    f"({len(data)} -> {len(decoded)} bytes)\n"
                )
            return new_name, decoded
        if data.startswith(_XZ_MAGIC):
            decoded = lzma.decompress(data)
            new_name = name[:-3] if name.lower().endswith(".xz") else name
            if debug:
                sys.stderr.write(
                    f"[debug] inner xz: {name} -> {new_name} "
                    f"({len(data)} -> {len(decoded)} bytes)\n"
                )
            return new_name, decoded
    except (OSError, EOFError, lzma.LZMAError) as exc:
        if debug:
            sys.stderr.write(f"[debug] inner decompress failed for {name}: {exc}\n")
    return name, data


def _process_one(
    member_path: str,
    content: str,
    active: List[ParserSpec],
    results: "ArchiveResults",
    debug: bool,
) -> None:
    results.file_count += 1
    ext = os.path.splitext(member_path)[1] or "(none)"
    results.file_types[ext] = results.file_types.get(ext, 0) + 1

    matching = [p for p in active if p.file_pattern.search("/" + member_path)]
    if not matching:
        return

    results.matched_files += 1
    if debug:
        sys.stderr.write(
            f"[debug] {member_path} ({len(content)} chars) -> "
            f"{', '.join(p.name for p in matching)}\n"
        )

    for spec in matching:
        try:
            raw = spec.func(content)
            parsed = json.loads(raw)
        except (ValueError, OSError) as exc:
            if debug:
                sys.stderr.write(
                    f"[debug] parser '{spec.name}' failed on "
                    f"{member_path}: {exc}\n"
                )
            continue

        prev = results.parser_results.get(spec.name)
        if spec.multi_file:
            results.parser_results[spec.name] = _merge(prev, parsed)
        else:
            is_empty = (
                isinstance(parsed, dict) and not parsed.get("found")
            ) or (isinstance(parsed, list) and not parsed)
            if prev is None or not is_empty:
                results.parser_results[spec.name] = parsed


def process_archive(
    path: str,
    *,
    parser_filter: Optional[str] = None,
    debug: bool = False,
) -> ArchiveResults:
    """Stream every file in *path* through any matching parser.

    Supports tar (`.tar`, `.tar.gz`, `.tar.xz`, `.tgz`) and `.zip` archives.
    """
    if parser_filter:
        active = [p for p in PARSERS if p.name == parser_filter]
        if not active:
            raise ValueError(
                f"Unknown parser '{parser_filter}'. "
                f"Use --list-parsers to see available names."
            )
    else:
        active = list(PARSERS)

    results = ArchiveResults()

    if _is_plaintext(path):
        try:
            with open(path, "rb") as fobj:
                data = fobj.read()
        except OSError as exc:
            if debug:
                sys.stderr.write(f"[debug] read error {path}: {exc}\n")
            return results
        # Use a synthetic path so message-style parsers (which match on
        # /messages, /syslog, etc.) actually fire on a bare .log file.
        synthetic = os.path.basename(path) + "/messages"
        content = data.decode("utf-8", errors="replace")
        _process_one(synthetic, content, active, results, debug)
        return results

    if _is_zip(path):
        with zipfile.ZipFile(path) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                try:
                    with zf.open(info) as fobj:
                        data = fobj.read()
                except (OSError, RuntimeError) as exc:
                    if debug:
                        sys.stderr.write(f"[debug] read error {info.filename}: {exc}\n")
                    continue
                name, data = _maybe_decompress_inner(info.filename, data, debug)
                content = data.decode("utf-8", errors="replace")
                _process_one(name, content, active, results, debug)
        return results

    with _open_archive(path) as archive:
        for member in archive:
            if not member.isfile():
                continue
            try:
                fobj = archive.extractfile(member)
                if fobj is None:
                    continue
                data = fobj.read()
            except (OSError, KeyError) as exc:
                if debug:
                    sys.stderr.write(f"[debug] read error {member.name}: {exc}\n")
                continue
            name, data = _maybe_decompress_inner(member.name, data, debug)
            content = data.decode("utf-8", errors="replace")
            _process_one(name, content, active, results, debug)

    return results


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

SEP = "=" * 70
SUB = "-" * 70


def _section(title: str) -> str:
    return f"\n{SUB}\n{title}\n{SUB}\n"


def _list_warnings(items: Any, indent: str = "    ") -> str:
    out = ""
    if not isinstance(items, list):
        return out
    for w in items:
        if isinstance(w, dict):
            severity = (w.get("severity") or "warn").upper()
            msg = w.get("message") or w.get("type") or json.dumps(w)
            out += f"{indent}[{severity}] {msg}\n"
            if w.get("recommendation"):
                out += f"{indent}        Recommendation: {w['recommendation']}\n"
        else:
            out += f"{indent}[WARN] {w}\n"
    return out


def _has_data(value: Any) -> bool:
    """A parser result counts as having data if it explicitly says so via
    ``found``/``count`` or carries any non-default scalar / non-empty
    container value. Used to decide whether to print a section.
    """
    if value is None:
        return False
    if isinstance(value, list):
        return len(value) > 0
    if not isinstance(value, dict):
        return bool(value)
    if value.get("found"):
        return True
    if isinstance(value.get("count"), int) and value["count"] > 0:
        return True
    # No explicit found; treat as data if any non-trivial field is set.
    for k, v in value.items():
        if k in ("found", "count", "warnings", "errors"):
            continue
        if v in (None, "", 0, False, [], {}):
            continue
        return True
    return False


def format_text(results: ArchiveResults) -> str:  # noqa: C901 - long but linear
    r = results.parser_results
    out = f"\n{SEP}\n  RCA Analysis Results (python)\n{SEP}\n\n"
    out += f"Files processed: {results.file_count}\n"
    out += f"Files matched by parsers: {results.matched_files}\n\n"

    # ---- Azure VM properties / OS -----
    vm = r.get("azureVMProperties") or {}
    osrel = r.get("osRelease") or {}
    if _has_data(vm) or _has_data(osrel):
        out += _section("AZURE VM PROPERTIES")
        for label, key in (("VM Size", "vm_size"), ("Publisher", "publisher"),
                           ("Offer", "offer"), ("SKU", "sku"),
                           ("License Type", "license_type"),
                           ("Billing Model", "billing_model"),
                           ("Detection Method", "detection_method"),
                           ("OS Disk Type", "os_disk_type")):
            if vm.get(key):
                out += f"  {label}: {vm[key]}\n"
        if vm.get("data_disks"):
            out += f"  Data Disks: {len(vm['data_disks'])}\n"
        if _has_data(osrel):
            out += "  Operating System:\n"
            name = osrel.get("pretty_name") or osrel.get("name")
            if name:
                out += f"    Distribution: {name}\n"
            if osrel.get("version_id"):
                out += f"    Version: {osrel['version_id']}\n"
        out += "\n"

    # ---- Cluster -----
    cluster_keys = ("corosyncConfig", "clusterStatus", "clusterMaintenanceMode")
    if any(_has_data(r.get(k)) for k in cluster_keys):
        out += _section("CLUSTER")
        cc = r.get("corosyncConfig") or {}
        if _has_data(cc):
            out += "  Corosync:\n"
            for label, key in (("Token", "totem_token"),
                               ("Consensus", "totem_consensus"),
                               ("Transport", "totem_transport"),
                               ("Quorum provider", "quorum_provider"),
                               ("Expected votes", "quorum_expected_votes"),
                               ("Two-node mode", "quorum_two_node")):
                if cc.get(key) is not None:
                    out += f"    {label}: {cc[key]}\n"
            out += _list_warnings(cc.get("warnings"))
        cs = r.get("clusterStatus") or {}
        if _has_data(cs):
            out += "  Status:\n"
            for label, key in (("Cluster name", "cluster_name"),
                               ("DC node", "dc_node"),
                               ("Nodes configured", "nodes_configured"),
                               ("Resources configured", "resources_configured"),
                               ("Quorum status", "quorum_status")):
                if cs.get(key) is not None:
                    out += f"    {label}: {cs[key]}\n"
            for ns in cs.get("node_statuses", []):
                state = "online" if ns.get("online") else "offline"
                out += f"    - {ns.get('name')}: {state}\n"
        mm = r.get("clusterMaintenanceMode") or {}
        if _has_data(mm):
            mm_on = mm.get("maintenance_mode")
            out += f"  Maintenance Mode: {'YES' if mm_on else 'no'}\n"
            res = mm.get("resources_in_maintenance") or []
            if res:
                out += f"    Resources in maintenance: {len(res)}\n"
        out += "\n"

    # ---- Storage -----
    storage_keys = ("lvmConfig", "raidConfig", "btrfsConfig", "blockDevices",
                    "fstabAnalysis", "dfOutput", "mtabAnalysis")
    if any(_has_data(r.get(k)) for k in storage_keys):
        out += _section("STORAGE")
        bd = r.get("blockDevices") or {}
        if _has_data(bd):
            out += (f"  Block Devices: {len(bd.get('disks') or [])} disk(s), "
                    f"{len(bd.get('partitions') or [])} partition(s)\n")
        lvm = r.get("lvmConfig") or {}
        if _has_data(lvm):
            out += (f"  LVM: {len(lvm.get('pvs') or [])} PV(s), "
                    f"{len(lvm.get('vgs') or [])} VG(s), "
                    f"{len(lvm.get('lvs') or [])} LV(s)\n")
            out += _list_warnings(lvm.get("warnings"))
        raid = r.get("raidConfig") or {}
        if _has_data(raid) and raid.get("arrays"):
            out += f"  RAID Arrays: {len(raid['arrays'])}\n"
            out += _list_warnings(raid.get("warnings"))
        btrfs = r.get("btrfsConfig") or {}
        if _has_data(btrfs):
            out += (f"  BTRFS: {len(btrfs.get('filesystems') or [])} fs, "
                    f"{len(btrfs.get('subvolumes') or [])} subvol(s)\n")
        fa = r.get("fstabAnalysis") or {}
        if _has_data(fa):
            out += f"  Fstab entries: {len(fa.get('entries') or [])}\n"
            out += _list_warnings(fa.get("warnings"))
        df = r.get("dfOutput") or {}
        if _has_data(df):
            out += f"  df entries: {len(df.get('filesystems') or [])}\n"
        mt = r.get("mtabAnalysis") or {}
        if _has_data(mt):
            extras = mt.get("extra_mounts") or []
            out += f"  Mtab entries: {len(mt.get('entries') or [])}"
            if extras:
                out += f" ({len(extras)} not in fstab)"
            out += "\n"
        out += "\n"

    # ---- Networking -----
    net_keys = ("networkInterfaces", "firewallRules", "sshServiceIssues")
    if any(_has_data(r.get(k)) for k in net_keys):
        out += _section("NETWORKING")
        ni = r.get("networkInterfaces") or {}
        if _has_data(ni):
            ifaces = ni.get("interfaces") or {}
            real = [i for n, i in ifaces.items() if n != "lo"]
            accelnet = any(i.get("accel_net") for i in real)
            out += (f"  Network Interfaces: {len(real)} interface(s)"
                    f"{' [Accelerated Networking]' if accelnet else ''}\n")
            for i in real:
                ipv4 = ", ".join(
                    (a.get("address") or "") for a in (i.get("ipv4") or [])
                ) or "-"
                out += (f"    {i.get('name')}: {i.get('state') or '-'} | "
                        f"{ipv4} | MAC {i.get('mac') or '-'} | "
                        f"driver {i.get('driver') or '-'}\n")
        fw = r.get("firewallRules") or {}
        if _has_data(fw):
            out += f"  Firewall: active = {fw.get('active_firewall') or 'none'}\n"
            out += _list_warnings(fw.get("warnings"))
        ssh = r.get("sshServiceIssues") or {}
        if _has_data(ssh):
            out += f"  SSH issues: {ssh.get('count', 0)} event(s)\n"
        out += "\n"

    # ---- Events -----
    def _count(name: str) -> int:
        v = r.get(name)
        if isinstance(v, dict):
            return v.get("count") or len(v.get("events") or [])
        if isinstance(v, list):
            return len(v)
        return 0

    event_counts = {
        "High CPU": _count("highCpuEvents"),
        "Cluster": _count("clusterEvents"),
        "Kernel reboots": _count("kernelReboots"),
        "OOM killer": _count("oomKiller"),
        "XFS errors": _count("xfsErrors"),
        "Automation": _count("automationEvents"),
        "Emergency mode": _count("emergencyMode"),
    }
    if any(event_counts.values()):
        out += _section("EVENTS")
        for label, count in event_counts.items():
            if count:
                out += f"  {label}: {count} event(s)\n"
        out += "\n"

    # ---- Packages / RHUI -----
    pkg_keys = ("distroPackages", "rhuiConfig", "rhelRhuiCheck",
                "eusVersionLock", "rhuiErrors", "cryptoPolicies",
                "fipsModeSetup", "kernelCmdline", "kernelTuning",
                "hugePages")
    if any(_has_data(r.get(k)) for k in pkg_keys):
        out += _section("PACKAGES / DISTRIBUTION")
        dp = r.get("distroPackages") or {}
        if _has_data(dp):
            count = dp.get("package_count") or len(dp.get("packages") or {})
            out += f"  Packages: {count}\n"
            out += _list_warnings(dp.get("warnings"))
        rc = r.get("rhuiConfig") or {}
        if _has_data(rc) and rc.get("repos"):
            enabled = [x for x in rc["repos"] if x.get("enabled")]
            out += f"  RHUI Repositories: {len(enabled)} enabled\n"
        ev = r.get("eusVersionLock") or {}
        if _has_data(ev):
            out += f"  EUS releasever: {ev.get('releasever') or 'not locked'}\n"
        cp = r.get("cryptoPolicies") or {}
        if _has_data(cp):
            out += f"  Crypto Policy: {cp.get('policy')}\n"
        fp = r.get("fipsModeSetup") or {}
        if _has_data(fp):
            out += f"  FIPS Mode: {'enabled' if fp.get('fips_enabled') else 'disabled'}\n"
        kc = r.get("kernelCmdline") or {}
        if _has_data(kc) and kc.get("cmdline"):
            out += f"  Kernel cmdline: {kc['cmdline']}\n"
        re_ = r.get("rhuiErrors") or {}
        if _has_data(re_):
            out += f"  RHUI errors: {re_.get('count', 0)}\n"
        kt = r.get("kernelTuning") or {}
        if _has_data(kt):
            out += "  Kernel tuning:\n"
            for k in ("vm.swappiness", "vm.nr_hugepages",
                      "net.core.rmem_max", "net.core.wmem_max"):
                params = kt.get("parameters") or {}
                if k in params:
                    out += f"    {k} = {params[k]}\n"
            out += _list_warnings(kt.get("azure_network_warnings"))
        hp = r.get("hugePages") or {}
        if _has_data(hp):
            total = hp.get("total") or hp.get("nr_hugepages") or 0
            free = hp.get("free") or hp.get("free_hugepages")
            size = hp.get("size_kb") or hp.get("hugepagesize_kb")
            out += f"  HugePages: total={total}"
            if free is not None:
                out += f" free={free}"
            if size:
                out += f" size={size}KB"
            out += "\n"
        out += "\n"

    # ---- Azure agent / extensions -----
    az_keys = ("waagentConfig", "waagentLog", "azureExtensions",
               "suseCloudRegister")
    if any(_has_data(r.get(k)) for k in az_keys):
        out += _section("AZURE AGENT / EXTENSIONS")
        wc = r.get("waagentConfig") or {}
        if _has_data(wc):
            out += "  waagent.conf: parsed\n"
            out += _list_warnings(wc.get("warnings"))
        wl = r.get("waagentLog") or {}
        if _has_data(wl):
            out += f"  waagent.log: agent {wl.get('agent_version') or 'unknown'}\n"
            if wl.get("has_errors"):
                out += "    [WARN] errors detected\n"
        ax = r.get("azureExtensions") or {}
        if _has_data(ax) and ax.get("events"):
            out += f"  Extensions: {len(ax['events'])}\n"
            for ev in ax["events"]:
                marker = "OK " if ev.get("healthy") else "BAD"
                out += (f"    [{marker}] {ev.get('label')}"
                        f" v{ev.get('version')} -> {ev.get('status')}\n")
        sc = r.get("suseCloudRegister") or {}
        if _has_data(sc):
            out += (f"  SUSE Cloud Register: "
                    f"{sc.get('billing_model') or 'n/a'} via "
                    f"{sc.get('registration_server') or '-'}\n")
        out += "\n"

    # ---- Security software -----
    sec_keys = ("falconSensor", "msDefender", "trendMicro", "illumio",
                "guardicoreAgent")
    if any(_has_data(r.get(k)) for k in sec_keys):
        out += _section("SECURITY SOFTWARE")
        for key, label in (("falconSensor", "CrowdStrike Falcon"),
                           ("msDefender", "Microsoft Defender"),
                           ("trendMicro", "Trend Micro"),
                           ("illumio", "Illumio"),
                           ("guardicoreAgent", "Guardicore")):
            v = r.get(key) or {}
            if _has_data(v):
                msg = v.get("message") or ""
                out += f"  {label}: detected"
                if msg:
                    out += f" ({msg})"
                out += "\n"
        out += "\n"

    # ---- vmcore / kdump -----
    vm_keys = ("vmcoreDmesg", "kdumpStatus", "crashListing", "kdumpConf")
    if any(_has_data(r.get(k)) for k in vm_keys):
        out += _section("KERNEL CRASH DUMPS")
        ks = r.get("kdumpStatus") or {}
        if _has_data(ks):
            out += (f"  Kdump operational: "
                    f"{'yes' if ks.get('operational') else 'no'}\n")
        cl = r.get("crashListing") or {}
        if _has_data(cl):
            out += (f"  Crash entries: {cl.get('count', 0)}, "
                    f"{cl.get('total_gb', 0)} GB total\n")
            for entry in (cl.get("entries") or [])[:5]:
                out += (f"    - {entry.get('crash_date')}: "
                        f"{entry.get('size_mb')} MB\n")
        vd = r.get("vmcoreDmesg") or {}
        if _has_data(vd):
            # vmcoreDmesg is per-file; if multi-file merged, fields are scalars.
            out += "  Latest vmcore-dmesg:\n"
            if vd.get("panic_reason"):
                out += f"    Panic: {vd['panic_reason']}\n"
            if vd.get("kernel_version"):
                out += f"    Kernel: {vd['kernel_version']}\n"
            if vd.get("hardware"):
                out += f"    Hardware: {vd['hardware']}\n"
            ct = vd.get("call_trace") or []
            if ct:
                out += f"    Call trace ({len(ct)} frames, top 5):\n"
                for frame in ct[:5]:
                    out += f"      {frame}\n"
        kdc = r.get("kdumpConf") or {}
        if _has_data(kdc):
            out += "  /etc/kdump.conf:\n"
            for k in ("path", "core_collector", "default_action",
                      "failure_action"):
                if kdc.get(k):
                    out += f"    {k} = {kdc[k]}\n"
        out += "\n"

    # ---- Debugfs -----
    if _has_data(r.get("hvBalloon")) or _has_data(r.get("extfrag")):
        out += _section("DEBUGFS")
        hv = r.get("hvBalloon") or {}
        if _has_data(hv):
            out += (f"  Hyper-V balloon: committed "
                    f"{hv.get('committed_memory_gb')} GB / max "
                    f"{hv.get('max_dynamic_memory_gb')} GB\n")
            out += _list_warnings(hv.get("warnings"))
        ef = r.get("extfrag") or {}
        if _has_data(ef):
            out += (f"  Memory fragmentation zones: "
                    f"{len(ef.get('zones') or [])}\n")
            out += _list_warnings(ef.get("warnings"))
        out += "\n"

    out += SEP + "\n"
    return out


def extract_results(results: ArchiveResults, out_dir: str) -> int:
    os.makedirs(out_dir, exist_ok=True)
    count = 0
    index: Dict[str, str] = {}
    for name, value in results.parser_results.items():
        path = os.path.join(out_dir, f"{name}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(value, fh, indent=2)
        index[name] = f"{name}.json"
        count += 1
    summary = {
        "fileCount": results.file_count,
        "matchedFiles": results.matched_files,
        "fileTypes": results.file_types,
    }
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as fh:
        json.dump({"files": index}, fh, indent=2)
    return count


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def list_parsers() -> None:
    print("\nAvailable parsers:\n")
    for spec in sorted(PARSERS, key=lambda s: s.name):
        flag = "  [multi-file]" if spec.multi_file else ""
        print(f"  {spec.name}{flag}")
        print(f"    Pattern: {spec.file_pattern.pattern}")
    print(f"\nTotal: {len(PARSERS)} parsers\n")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="rca_cli.py",
        description=(
            "RCA CLI (Python). Analyses .tar.xz / .tar.gz / .tar support "
            "bundles using the supportfile native parser library."
        ),
    )
    parser.add_argument("file", nargs="?",
                        help="Path to .tar.xz, .tar.gz, or .tar archive")
    parser.add_argument("-j", "--json", action="store_true",
                        help="Emit results as JSON instead of text summary")
    parser.add_argument("-d", "--debug", action="store_true",
                        help="Enable verbose debug logging on stderr")
    parser.add_argument("-l", "--list-parsers", action="store_true",
                        help="List available parsers and exit")
    parser.add_argument("-p", "--parser", metavar="NAME",
                        help="Run only the named parser")
    parser.add_argument("-e", "--extract", metavar="DIR",
                        help="Write per-parser JSON files to DIR")
    args = parser.parse_args(argv)

    if args.list_parsers:
        list_parsers()
        return 0

    if not args.file:
        parser.error("missing archive path (or pass --list-parsers)")

    if not os.path.exists(args.file):
        sys.stderr.write(f"Error: file not found: {args.file}\n")
        return 2

    sys.stderr.write(f"\nAnalyzing: {args.file}\n")
    try:
        results = process_archive(args.file,
                                  parser_filter=args.parser,
                                  debug=args.debug)
    except (tarfile.TarError, ValueError, OSError) as exc:
        sys.stderr.write(f"Error processing {args.file}: {exc}\n")
        return 1

    if args.extract:
        n = extract_results(results, args.extract)
        sys.stderr.write(f"Extracted {n} parser result files to {args.extract}\n")

    if args.json:
        payload = {
            "fileCount": results.file_count,
            "matchedFiles": results.matched_files,
            "fileTypes": results.file_types,
            **results.parser_results,
        }
        json.dump(payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(format_text(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
