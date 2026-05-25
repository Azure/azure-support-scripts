//! WASM bindings for the supportfile parser library.
//!
//! Exposes every `parse_*_json` function from `supportfile` as a wasm-bindgen
//! export with a camelCase `js_name`. Each export returns a JSON string that
//! the JS layer can `JSON.parse` and pass through a snake_case → camelCase
//! converter to match the legacy JS parser output shape.
//!
//! Generated mechanically from the parser fns in `supportfile_core/src/parsers/`.

use supportfile as sf;
use wasm_bindgen::prelude::*;

/// Initialize panic-to-console hook so Rust panics surface as readable
/// browser console errors instead of opaque "unreachable" traps.
#[wasm_bindgen(start)]
pub fn start() {
    #[cfg(feature = "console_error_panic_hook")]
    console_error_panic_hook::set_once();
}

/// Returns the supportfile crate version compiled into this WASM module.
#[wasm_bindgen(js_name = supportfileVersion)]
pub fn supportfile_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[wasm_bindgen(js_name = parseAutomationEvents)]
pub fn parse_automation_events_json(content: &str, source_path: &str) -> String {
    sf::parse_automation_events_json(content, source_path)
}

#[wasm_bindgen(js_name = parseAzureExtensions)]
pub fn parse_azure_extensions_json(content: &str, source_path: &str) -> String {
    sf::parse_azure_extensions_json(content, source_path)
}

#[wasm_bindgen(js_name = parseAzureSiteRecovery)]
pub fn parse_azure_site_recovery_json(content: &str, source_path: &str) -> String {
    sf::parse_azure_site_recovery_json(content, source_path)
}

#[wasm_bindgen(js_name = parseAzureVmProperties)]
pub fn parse_azure_vm_properties_json(content: &str, source_path: &str) -> String {
    sf::parse_azure_vm_properties_json(content, source_path)
}

#[wasm_bindgen(js_name = parseBasicEnvironment)]
pub fn parse_basic_environment_json(content: &str, source_path: &str) -> String {
    sf::parse_basic_environment_json(content, source_path)
}

#[wasm_bindgen(js_name = parseBlockDevices)]
pub fn parse_block_devices_json(content: &str, source_path: &str) -> String {
    sf::parse_block_devices_json(content, source_path)
}

#[wasm_bindgen(js_name = parseBtrfsConfig)]
pub fn parse_btrfs_config_json(content: &str, source_path: &str) -> String {
    sf::parse_btrfs_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseChronyMakestep)]
pub fn parse_chrony_makestep_json(content: &str, source_path: &str) -> String {
    sf::parse_chrony_makestep_json(content, source_path)
}

#[wasm_bindgen(js_name = parseChronyTracking)]
pub fn parse_chrony_tracking_json(content: &str, source_path: &str) -> String {
    sf::parse_chrony_tracking_json(content, source_path)
}

#[wasm_bindgen(js_name = parseClusterEvents)]
pub fn parse_cluster_events_json(content: &str, source_path: &str) -> String {
    sf::parse_cluster_events_json(content, source_path)
}

#[wasm_bindgen(js_name = parseClusterMaintenanceMode)]
pub fn parse_cluster_maintenance_mode_json(content: &str, source_path: &str) -> String {
    sf::parse_cluster_maintenance_mode_json(content, source_path)
}

#[wasm_bindgen(js_name = parseClusterStatus)]
pub fn parse_cluster_status_json(content: &str, source_path: &str) -> String {
    sf::parse_cluster_status_json(content, source_path)
}

#[wasm_bindgen(js_name = parseCorosyncConfig)]
pub fn parse_corosync_config_json(content: &str, source_path: &str) -> String {
    sf::parse_corosync_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseClusterDaemonStatus)]
pub fn parse_cluster_daemon_status_json(content: &str, source_path: &str) -> String {
    sf::parse_cluster_daemon_status_json(content, source_path)
}

#[wasm_bindgen(js_name = parseCorosyncStatus)]
pub fn parse_corosync_status_json(content: &str, source_path: &str) -> String {
    sf::parse_corosync_status_json(content, source_path)
}

#[wasm_bindgen(js_name = parseHostsFile)]
pub fn parse_hosts_file_json(content: &str, source_path: &str) -> String {
    sf::parse_hosts_file_json(content, source_path)
}

#[wasm_bindgen(js_name = parseSbdConfig)]
pub fn parse_sbd_config_json(content: &str, source_path: &str) -> String {
    sf::parse_sbd_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseAzureFenceAuth)]
pub fn parse_azure_fence_auth_json(content: &str, source_path: &str) -> String {
    sf::parse_azure_fence_auth_json(content, source_path)
}

#[wasm_bindgen(js_name = parseIscsiConfig)]
pub fn parse_iscsi_config_json(content: &str, source_path: &str) -> String {
    sf::parse_iscsi_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseLiveMigration)]
pub fn parse_live_migration_json(content: &str, source_path: &str) -> String {
    sf::parse_live_migration_json(content, source_path)
}

#[wasm_bindgen(js_name = parseSapInstanceErrors)]
pub fn parse_sap_instance_errors_json(content: &str, source_path: &str) -> String {
    sf::parse_sap_instance_errors_json(content, source_path)
}

#[wasm_bindgen(js_name = parseClusterNodes)]
pub fn parse_cluster_nodes_json(content: &str, source_path: &str) -> String {
    sf::parse_cluster_nodes_json(content, source_path)
}

#[wasm_bindgen(js_name = parseFencingConfig)]
pub fn parse_fencing_config_json(content: &str, source_path: &str) -> String {
    sf::parse_fencing_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseAzureScheduledEvents)]
pub fn parse_azure_scheduled_events_json(content: &str, source_path: &str) -> String {
    sf::parse_azure_scheduled_events_json(content, source_path)
}

#[wasm_bindgen(js_name = parseSapInstanceConfig)]
pub fn parse_sap_instance_config_json(content: &str, source_path: &str) -> String {
    sf::parse_sap_instance_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parsePacemakerResources)]
pub fn parse_pacemaker_resources_json(content: &str, source_path: &str) -> String {
    sf::parse_pacemaker_resources_json(content, source_path)
}

#[wasm_bindgen(js_name = parseCrashListing)]
pub fn parse_crash_listing_json(content: &str, source_path: &str) -> String {
    sf::parse_crash_listing_json(content, source_path)
}

#[wasm_bindgen(js_name = parseCryptoPolicies)]
pub fn parse_crypto_policies_json(content: &str, source_path: &str) -> String {
    sf::parse_crypto_policies_json(content, source_path)
}

#[wasm_bindgen(js_name = parseDfOutput)]
pub fn parse_df_output_json(content: &str, source_path: &str) -> String {
    sf::parse_df_output_json(content, source_path)
}

#[wasm_bindgen(js_name = parseDistroPackages)]
pub fn parse_distro_packages_json(content: &str, source_path: &str) -> String {
    sf::parse_distro_packages_json(content, source_path)
}

#[wasm_bindgen(js_name = parseDlmService)]
pub fn parse_dlm_service_json(content: &str, source_path: &str) -> String {
    sf::parse_dlm_service_json(content, source_path)
}

#[wasm_bindgen(js_name = parseEmergencyMode)]
pub fn parse_emergency_mode_json(content: &str, source_path: &str) -> String {
    sf::parse_emergency_mode_json(content, source_path)
}

#[wasm_bindgen(js_name = parseEusVersionLock)]
pub fn parse_eus_version_lock_json(content: &str, source_path: &str) -> String {
    sf::parse_eus_version_lock_json(content, source_path)
}

#[wasm_bindgen(js_name = parseExtfrag)]
pub fn parse_extfrag_json(content: &str, source_path: &str) -> String {
    sf::parse_extfrag_json(content, source_path)
}

#[wasm_bindgen(js_name = parseFalconSensorConfig)]
pub fn parse_falcon_sensor_config_json(content: &str, source_path: &str) -> String {
    sf::parse_falcon_sensor_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseFalconSensor)]
pub fn parse_falcon_sensor_json(content: &str, source_path: &str) -> String {
    sf::parse_falcon_sensor_json(content, source_path)
}

#[wasm_bindgen(js_name = parseFipsModeSetup)]
pub fn parse_fips_mode_setup_json(content: &str, source_path: &str) -> String {
    sf::parse_fips_mode_setup_json(content, source_path)
}

#[wasm_bindgen(js_name = parseFirewallRules)]
pub fn parse_firewall_rules_json(content: &str, source_path: &str) -> String {
    sf::parse_firewall_rules_json(content, source_path)
}

#[wasm_bindgen(js_name = parsePacketLoss)]
pub fn parse_packet_loss_json(content: &str, source_path: &str) -> String {
    sf::parse_packet_loss_json(content, source_path)
}

#[wasm_bindgen(js_name = parseRingBuffer)]
pub fn parse_ring_buffer_json(content: &str, source_path: &str) -> String {
    sf::parse_ring_buffer_json(content, source_path)
}

#[wasm_bindgen(js_name = parseNetworkSysctl)]
pub fn parse_network_sysctl_json(content: &str, source_path: &str) -> String {
    sf::parse_network_sysctl_json(content, source_path)
}

#[wasm_bindgen(js_name = parseFstabAnalysis)]
pub fn parse_fstab_analysis_json(content: &str, source_path: &str) -> String {
    sf::parse_fstab_analysis_json(content, source_path)
}

#[wasm_bindgen(js_name = parseFstab)]
pub fn parse_fstab_json(content: &str, source_path: &str) -> String {
    sf::parse_fstab_json(content, source_path)
}

#[wasm_bindgen(js_name = parseGuardicoreAgent)]
pub fn parse_guardicore_agent_json(content: &str, source_path: &str) -> String {
    sf::parse_guardicore_agent_json(content, source_path)
}

#[wasm_bindgen(js_name = parseHugePages)]
pub fn parse_huge_pages_json(content: &str, source_path: &str) -> String {
    sf::parse_huge_pages_json(content, source_path)
}

#[wasm_bindgen(js_name = parseHvBalloon)]
pub fn parse_hv_balloon_json(content: &str, source_path: &str) -> String {
    sf::parse_hv_balloon_json(content, source_path)
}

#[wasm_bindgen(js_name = parseIllumio)]
pub fn parse_illumio_json(content: &str, source_path: &str) -> String {
    sf::parse_illumio_json(content, source_path)
}

#[wasm_bindgen(js_name = parseInspectDiskResults)]
pub fn parse_inspect_disk_results_json(content: &str, source_path: &str) -> String {
    sf::parse_inspect_disk_results_json(content, source_path)
}

#[wasm_bindgen(js_name = parseInvolfltKernelVersion)]
pub fn parse_involflt_kernel_version_json(content: &str, source_path: &str) -> String {
    sf::parse_involflt_kernel_version_json(content, source_path)
}

#[wasm_bindgen(js_name = parseInvolfltVersion)]
pub fn parse_involflt_version_json(content: &str, source_path: &str) -> String {
    sf::parse_involflt_version_json(content, source_path)
}

#[wasm_bindgen(js_name = parseKdumpConf)]
pub fn parse_kdump_conf_json(content: &str, source_path: &str) -> String {
    sf::parse_kdump_conf_json(content, source_path)
}

#[wasm_bindgen(js_name = parseKdumpStatus)]
pub fn parse_kdump_status_json(content: &str, source_path: &str) -> String {
    sf::parse_kdump_status_json(content, source_path)
}

#[wasm_bindgen(js_name = parseKernelCmdline)]
pub fn parse_kernel_cmdline_json(content: &str, source_path: &str) -> String {
    sf::parse_kernel_cmdline_json(content, source_path)
}

#[wasm_bindgen(js_name = parseKernelReboots)]
pub fn parse_kernel_reboots_json(content: &str, source_path: &str) -> String {
    sf::parse_kernel_reboots_json(content, source_path)
}

#[wasm_bindgen(js_name = parseKernelTuning)]
pub fn parse_kernel_tuning_json(content: &str, source_path: &str) -> String {
    sf::parse_kernel_tuning_json(content, source_path)
}

#[wasm_bindgen(js_name = parseLeappLog)]
pub fn parse_leapp_log_json(content: &str, source_path: &str) -> String {
    sf::parse_leapp_log_json(content, source_path)
}

#[wasm_bindgen(js_name = parseLeappReport)]
pub fn parse_leapp_report_json(content: &str, source_path: &str) -> String {
    sf::parse_leapp_report_json(content, source_path)
}

#[wasm_bindgen(js_name = parseLvmConfig)]
pub fn parse_lvm_config_json(content: &str, source_path: &str) -> String {
    sf::parse_lvm_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseMsDefenderConfig)]
pub fn parse_ms_defender_config_json(content: &str, source_path: &str) -> String {
    sf::parse_ms_defender_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseMsDefender)]
pub fn parse_ms_defender_json(content: &str, source_path: &str) -> String {
    sf::parse_ms_defender_json(content, source_path)
}

#[wasm_bindgen(js_name = parseMtabAnalysis)]
pub fn parse_mtab_analysis_json(content: &str, source_path: &str) -> String {
    sf::parse_mtab_analysis_json(content, source_path)
}

#[wasm_bindgen(js_name = parseNetworkInterfaces)]
pub fn parse_network_interfaces_json(content: &str, source_path: &str) -> String {
    sf::parse_network_interfaces_json(content, source_path)
}

#[wasm_bindgen(js_name = parseOomKiller)]
pub fn parse_oom_killer_json(content: &str, source_path: &str) -> String {
    sf::parse_oom_killer_json(content, source_path)
}

#[wasm_bindgen(js_name = parseOsRelease)]
pub fn parse_os_release_json(content: &str, source_path: &str) -> String {
    sf::parse_os_release_json(content, source_path)
}

#[wasm_bindgen(js_name = parsePacemakerHighCpu)]
pub fn parse_pacemaker_high_cpu_json(content: &str, source_path: &str) -> String {
    sf::parse_pacemaker_high_cpu_json(content, source_path)
}

#[wasm_bindgen(js_name = parsePtpClockSource)]
pub fn parse_ptp_clock_source_json(content: &str, source_path: &str) -> String {
    sf::parse_ptp_clock_source_json(content, source_path)
}

#[wasm_bindgen(js_name = parsePtpDevice)]
pub fn parse_ptp_device_json(content: &str, source_path: &str) -> String {
    sf::parse_ptp_device_json(content, source_path)
}

#[wasm_bindgen(js_name = parseRaidConfig)]
pub fn parse_raid_config_json(content: &str, source_path: &str) -> String {
    sf::parse_raid_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseRhelRhuiCheck)]
pub fn parse_rhel_rhui_check_json(content: &str, source_path: &str) -> String {
    sf::parse_rhel_rhui_check_json(content, source_path)
}

#[wasm_bindgen(js_name = parseRhuiConfig)]
pub fn parse_rhui_config_json(content: &str, source_path: &str) -> String {
    sf::parse_rhui_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseRhuiErrors)]
pub fn parse_rhui_errors_json(content: &str, source_path: &str) -> String {
    sf::parse_rhui_errors_json(content, source_path)
}

#[wasm_bindgen(js_name = parseSshServiceIssues)]
pub fn parse_ssh_service_issues_json(content: &str, source_path: &str) -> String {
    sf::parse_ssh_service_issues_json(content, source_path)
}

#[wasm_bindgen(js_name = parseSecureBoot)]
pub fn parse_secure_boot_json(content: &str, source_path: &str) -> String {
    sf::parse_secure_boot_json(content, source_path)
}

#[wasm_bindgen(js_name = parseSuseCloudRegister)]
pub fn parse_suse_cloud_register_json(content: &str, source_path: &str) -> String {
    sf::parse_suse_cloud_register_json(content, source_path)
}

#[wasm_bindgen(js_name = parseTimeSync)]
pub fn parse_time_sync_json(content: &str, source_path: &str) -> String {
    sf::parse_time_sync_json(content, source_path)
}

#[wasm_bindgen(js_name = parseTimeSyncService)]
pub fn parse_time_sync_service_json(content: &str, source_path: &str) -> String {
    sf::parse_time_sync_service_json(content, source_path)
}

#[wasm_bindgen(js_name = parseTimedatectl)]
pub fn parse_timedatectl_json(content: &str, source_path: &str) -> String {
    sf::parse_timedatectl_json(content, source_path)
}

#[wasm_bindgen(js_name = parseTrendMicro)]
pub fn parse_trend_micro_json(content: &str, source_path: &str) -> String {
    sf::parse_trend_micro_json(content, source_path)
}

#[wasm_bindgen(js_name = parseVmcoreDmesg)]
pub fn parse_vmcore_dmesg_json(content: &str, source_path: &str) -> String {
    sf::parse_vmcore_dmesg_json(content, source_path)
}

#[wasm_bindgen(js_name = parseVmcoreSummary)]
pub fn parse_vmcore_summary_json(content: &str, source_path: &str) -> String {
    sf::parse_vmcore_summary_json(content, source_path)
}

#[wasm_bindgen(js_name = parseWaagentConfig)]
pub fn parse_waagent_config_json(content: &str, source_path: &str) -> String {
    sf::parse_waagent_config_json(content, source_path)
}

#[wasm_bindgen(js_name = parseWaagentLog)]
pub fn parse_waagent_log_json(content: &str, source_path: &str) -> String {
    sf::parse_waagent_log_json(content, source_path)
}

#[wasm_bindgen(js_name = parseXfsErrors)]
pub fn parse_xfs_errors_json(content: &str, source_path: &str) -> String {
    sf::parse_xfs_errors_json(content, source_path)
}

