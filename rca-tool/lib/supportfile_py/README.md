# Supportfile Python wrapper

This crate exposes the Supportfile library core as a native Python extension.

## Install for local development

From the lib folder:

- python3 -m venv .venv
- . .venv/bin/activate
- python -m pip install -e ./supportfile_py

## Build a wheel for distribution

From the wrapper folder:

- ./build-wheel.sh

The script creates a local build virtual environment automatically and writes the built wheel under the dist folder.

## GitHub publishing

The repository CI now builds the Rust crate and Python wheels for both amd64 and arm64, and publishes them on release tags.

Then import it normally in Python:

```python
import supportfile

result_json = supportfile.parse_high_cpu_events(log_text)
```

Current exported functions:

- parse_high_cpu_events
- parse_cluster_events
- parse_cluster_status
- parse_corosync_config
- parse_cluster_maintenance_mode
- parse_automation_events
- parse_azure_vm_properties
- parse_suse_cloud_register
- parse_waagent_config
- parse_waagent_log
- parse_hv_balloon
- parse_extfrag
- parse_emergency_mode
- parse_kernel_reboots
- parse_oom_killer
- parse_xfs_errors
- parse_firewall_rules
- parse_network_interfaces
- parse_distro_packages
- parse_ssh_service_issues
- parse_dlm_service
- parse_azure_site_recovery
- parse_guardicore_agent
- parse_illumio
- parse_trend_micro
- parse_falcon_sensor
- parse_falcon_sensor_config
- parse_ms_defender
- parse_ms_defender_config
- parse_involflt_version
- parse_involflt_kernel_version
- parse_azure_extensions
- parse_lvm_config
- parse_raid_config
- parse_btrfs_config
- parse_block_devices
- parse_fstab_analysis
- parse_df_output
- parse_mtab_analysis
- parse_basic_environment
- parse_os_release
- parse_fstab
- parse_inspect_disk_results
- parse_kernel_tuning
- parse_huge_pages
- parse_time_sync
- parse_ptp_clock_source
- parse_time_sync_service
- parse_timedatectl
- parse_ptp_device
- parse_chrony_tracking
- parse_chrony_makestep
- parse_rhui_config
- parse_eus_version_lock
- parse_rhel_rhui_check
- parse_crypto_policies
- parse_fips_mode_setup
- parse_kernel_cmdline
- parse_rhui_errors
- parse_leapp_report
- parse_leapp_log
- parse_vmcore_dmesg
- parse_kdump_status
- parse_crash_listing
- parse_kdump_conf
- parse_vmcore_summary

It depends on the shared parser implementation in the sibling supportfile_core crate.
