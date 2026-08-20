use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section 1 – Azure VM Properties + OS Release + Waagent Config.
#[component]
pub fn AzureVmSection(data: Value) -> impl IntoView {
    let vm = data
        .get("azureVMProperties")
        .cloned()
        .unwrap_or(Value::Null);
    let os = data.get("osRelease").cloned().unwrap_or(Value::Null);
    let wa = data.get("waagentConfig").cloned().unwrap_or(Value::Null);

    let has_vm = json_bool(&vm, "found");
    let has_os = json_bool(&os, "found");
    let has_wa = json_bool(&wa, "found");

    if !has_vm && !has_os && !has_wa {
        return view! {}.into_any();
    }

    let vm_name = json_str(&vm, "vmName");
    let vm_size = json_str(&vm, "vmSize");
    let location = json_str(&vm, "location");
    let publisher = json_str(&vm, "publisher");
    let offer = json_str(&vm, "offer");
    let sku = json_str(&vm, "sku");
    let version = json_str(&vm, "version");
    let billing_code = json_str(&vm, "billingCode");
    let billing_model = json_str(&vm, "billingModel");
    let detection_method = json_str(&vm, "detectionMethod");
    let license_type = json_str(&vm, "licenseType");
    let registration_server = {
        let direct = json_str(&vm, "registrationServer");
        if direct.is_empty() {
            json_str(&vm, "suseRegistrationServer")
        } else {
            direct
        }
    };
    let registration_type = {
        let direct = json_str(&vm, "registrationType");
        if direct.is_empty() {
            json_str(&vm, "suseRegistrationType")
        } else {
            direct
        }
    };
    let alternative_billing_model = json_str(&vm, "alternativeBillingModel");
    let alternative_detection_method = json_str(&vm, "alternativeDetectionMethod");
    let os_disk_type = json_str(&vm, "osDiskType");
    let data_disks = json_array(&vm, "dataDisks");

    let pretty_name = {
        let pretty = json_str(&os, "prettyName");
        if !pretty.is_empty() {
            pretty
        } else {
            let distro = json_str(&os, "distribution");
            if !distro.is_empty() {
                distro
            } else {
                json_str(&os, "name")
            }
        }
    };
    let os_version = {
        let version_id = json_str(&os, "versionId");
        if !version_id.is_empty() {
            version_id
        } else {
            let major = json_str(&os, "majorVersion");
            let minor = json_str(&os, "minorVersion");
            if !major.is_empty() && !minor.is_empty() {
                format!("{major}.{minor}")
            } else if !major.is_empty() {
                major
            } else {
                minor
            }
        }
    };
    let os_warnings = json_array(&os, "warnings");

    let wa_summary = wa.get("summary").cloned().unwrap_or(Value::Null);
    let wa_warnings = json_array(&wa, "warnings");
    let extensions_enabled = wa_summary
        .get("extensionsEnabled")
        .and_then(|v| v.as_bool());
    let provisioning_agent = json_str(&wa_summary, "provisioningAgent");
    let enable_firewall = wa_summary.get("enableFirewall").and_then(|v| v.as_bool());
    let resource_disk_enable_swap = wa_summary
        .get("resourceDiskEnableSwap")
        .and_then(|v| v.as_bool());
    let resource_disk_swap_size_mb = wa_summary
        .get("resourceDiskSwapSizeMB")
        .and_then(|v| v.as_i64());
    let resource_disk_format = wa_summary
        .get("resourceDiskFormat")
        .and_then(|v| v.as_bool());
    let resource_disk_mount_point = json_str(&wa_summary, "resourceDiskMountPoint");
    let root_device_scsi_timeout = wa_summary
        .get("rootDeviceScsiTimeout")
        .and_then(|v| v.as_i64());
    let auto_update_enabled = wa_summary.get("autoUpdateEnabled").and_then(|v| v.as_bool());
    let auto_update_ga_family = json_str(&wa_summary, "autoUpdateGAFamily");

    let billing_badge_class = match billing_model.as_str() {
        "BYOS" => "badge badge-warning",
        "PAYG" => "badge badge-info",
        _ => "badge",
    };

    view! {
        <Section title="Azure VM Properties" class="success-block" open=true>
            <div class="vm-properties">
                {(!vm_size.is_empty()).then(|| view! {
                    <p class="vm-inline-row">
                        <strong>"VM Size:"</strong>
                        " "
                        <code>{vm_size.clone()}</code>
                    </p>
                })}
                {(!vm_name.is_empty()).then(|| view! {
                    <p class="vm-inline-row">
                        <strong>"VM Name:"</strong>
                        " "
                        <code>{vm_name.clone()}</code>
                    </p>
                })}
                {(!location.is_empty()).then(|| view! {
                    <p class="vm-inline-row"><strong>"Location:"</strong> " " <code>{location.clone()}</code></p>
                })}
                {(!publisher.is_empty()).then(|| view! {
                    <p class="vm-inline-row"><strong>"Publisher:"</strong> " " <code>{publisher.clone()}</code></p>
                })}
                {(!offer.is_empty()).then(|| view! {
                    <p class="vm-inline-row"><strong>"Offer:"</strong> " " <code>{offer.clone()}</code></p>
                })}
                {(!sku.is_empty()).then(|| view! {
                    <p class="vm-inline-row"><strong>"SKU:"</strong> " " <code>{sku.clone()}</code></p>
                })}
                {(!version.is_empty()).then(|| view! {
                    <p class="vm-inline-row"><strong>"Version:"</strong> " " <code>{version.clone()}</code></p>
                })}
                {(!billing_code.is_empty()).then(|| view! {
                    <p class="vm-inline-row"><strong>"Billing Code:"</strong> " " <code>{billing_code.clone()}</code></p>
                })}

                {has_vm.then(|| view! {
                    <div class="subsection">
                        <p class="subsection-title">"Billing Model:"</p>
                        {if billing_model.is_empty() {
                            view! {
                                <p class="text-muted"><em>"Unable to determine billing model"</em></p>
                            }.into_any()
                        } else {
                            view! {
                                <p class="vm-inline-row">
                                    <strong>"Type:"</strong>
                                    " "
                                    <span class=billing_badge_class>{billing_model.clone()}</span>
                                </p>
                                {(!detection_method.is_empty()).then(|| view! {
                                    <p class="text-muted"><em>{format!("Detected via: {detection_method}")}</em></p>
                                })}
                                {((!registration_server.is_empty()) || (!registration_type.is_empty()) || (!alternative_billing_model.is_empty())).then(|| view! {
                                    <div class="vm-note info">
                                        <p class="subsection-title">"SUSE Registration:"</p>
                                        {(!registration_type.is_empty()).then(|| view! {
                                            <p class="vm-inline-row"><strong>"Type:"</strong> " " {registration_type.clone()}</p>
                                        })}
                                        {(!registration_server.is_empty()).then(|| view! {
                                            <p class="vm-inline-row"><strong>"Server:"</strong> " " <code>{registration_server.clone()}</code></p>
                                        })}
                                        {(!alternative_billing_model.is_empty()).then(|| view! {
                                            <p class="text-warning-dark">
                                                <em>{format!("[!] Alternative detection suggests: {}", alternative_billing_model.clone())}</em>
                                            </p>
                                        })}
                                        {(!alternative_detection_method.is_empty()).then(|| view! {
                                            <p class="text-muted"><em>{alternative_detection_method.clone()}</em></p>
                                        })}
                                    </div>
                                })}
                            }
                            .into_any()
                        }}
                        {(!license_type.is_empty()).then(|| view! {
                            <p class="vm-inline-row"><strong>"License Type:"</strong> " " <code>{license_type.clone()}</code></p>
                        })}
                    </div>
                })}

                {(has_vm && (!os_disk_type.is_empty() || !data_disks.is_empty())).then(|| view! {
                    <div class="subsection">
                        <p class="subsection-title">"Storage:"</p>
                        {(!os_disk_type.is_empty()).then(|| view! {
                            <p class="vm-inline-row">
                                <strong>"OS Disk:"</strong>
                                " "
                                <span class=disk_badge_class(&os_disk_type)>{display_disk_type(&os_disk_type)}</span>
                            </p>
                        })}
                        {(!data_disks.is_empty()).then(|| view! {
                            <>
                                <p class="vm-inline-row">
                                    <strong>"Data Disks:"</strong>
                                    " "
                                    {format!("{} disk(s)", data_disks.len())}
                                </p>
                                <ul class="disk-list">
                                    {data_disks
                                        .iter()
                                        .map(|disk| {
                                            let lun = disk
                                                .get("lun")
                                                .or_else(|| disk.get("LUN"))
                                                .and_then(value_as_text)
                                                .unwrap_or_else(|| "?".to_string());
                                            let size = disk
                                                .get("diskSizeGB")
                                                .or_else(|| disk.get("diskSizeGb"))
                                                .or_else(|| disk.get("sizeGB"))
                                                .and_then(value_as_text)
                                                .map(|v| format!(" ({v} GB)"))
                                                .unwrap_or_default();
                                            let disk_type = json_str(disk, "storageAccountType");
                                            view! {
                                                <li>
                                                    {format!("LUN {lun}{size}: ")}
                                                    <span class=disk_badge_class(&disk_type)>{display_disk_type(&disk_type)}</span>
                                                </li>
                                            }
                                        })
                                        .collect::<Vec<_>>()}
                                </ul>
                            </>
                        })}
                    </div>
                })}

                {has_os.then(|| view! {
                    <div class="subsection">
                        <p class="subsection-title">"Operating System:"</p>
                        {(!pretty_name.is_empty()).then(|| view! {
                            <p class="vm-inline-row"><strong>"Distribution:"</strong> " " <code>{pretty_name.clone()}</code></p>
                        })}
                        {(!os_version.is_empty()).then(|| view! {
                            <p class="vm-inline-row"><strong>"Version:"</strong> " " <code>{os_version.clone()}</code></p>
                        })}
                        {os_warnings
                            .into_iter()
                            .map(|warning| {
                                let message = json_str(&warning, "message");
                                let recommendation = json_str(&warning, "recommendation");
                                view! {
                                    <div class="vm-note warning">
                                        <p><strong>{format!("[!] {message}")}</strong></p>
                                        {(!recommendation.is_empty()).then(|| view! {
                                            <p>{recommendation}</p>
                                        })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </div>
                })}

                {has_wa.then(|| view! {
                    <div class="subsection">
                        <p class="subsection-title">"Azure Linux Agent Configuration:"</p>
                        <div class="property-grid">
                            {extensions_enabled.map(|enabled| view! {
                                <>
                                    <span class="property-label">"Extensions:"</span>
                                    <span class=if enabled { "badge badge-success" } else { "badge badge-danger" }>
                                        {if enabled { "Enabled" } else { "Disabled" }}
                                    </span>
                                </>
                            })}
                            {(!provisioning_agent.is_empty()).then(|| view! {
                                <>
                                    <span class="property-label">"Provisioning Agent:"</span>
                                    <code class="property-value">{provisioning_agent.clone()}</code>
                                </>
                            })}
                            {enable_firewall.map(|enabled| view! {
                                <>
                                    <span class="property-label">"OS Firewall:"</span>
                                    <span class=if enabled { "badge badge-success" } else { "badge badge-warning" }>
                                        {if enabled { "Enabled" } else { "Disabled" }}
                                    </span>
                                </>
                            })}
                            {resource_disk_enable_swap.map(|enabled| {
                                let label = if enabled {
                                    if let Some(size) = resource_disk_swap_size_mb {
                                        format!("Enabled ({size} MB)")
                                    } else {
                                        "Enabled".to_string()
                                    }
                                } else {
                                    "Disabled".to_string()
                                };
                                view! {
                                    <>
                                        <span class="property-label">"Resource Disk Swap:"</span>
                                        <span class=if enabled { "badge badge-info" } else { "badge badge-success" }>{label}</span>
                                    </>
                                }
                            })}
                            {resource_disk_format.map(|enabled| view! {
                                <>
                                    <span class="property-label">"Resource Disk Format:"</span>
                                    <span class="property-value">{if enabled { "Yes" } else { "No" }}</span>
                                </>
                            })}
                            {(!resource_disk_mount_point.is_empty()).then(|| view! {
                                <>
                                    <span class="property-label">"Resource Disk Mount:"</span>
                                    <code class="property-value">{resource_disk_mount_point.clone()}</code>
                                </>
                            })}
                            {root_device_scsi_timeout.map(|timeout| view! {
                                <>
                                    <span class="property-label">"SCSI Timeout:"</span>
                                    <span class="property-value">{format!("{timeout}s")}</span>
                                </>
                            })}
                            {auto_update_enabled.map(|enabled| {
                                let label = if auto_update_ga_family.is_empty() {
                                    if enabled {
                                        "Enabled".to_string()
                                    } else {
                                        "Disabled".to_string()
                                    }
                                } else if enabled {
                                    format!("Enabled ({})", auto_update_ga_family.clone())
                                } else {
                                    format!("Disabled ({})", auto_update_ga_family.clone())
                                };
                                view! {
                                    <>
                                        <span class="property-label">"Auto-Update:"</span>
                                        <span class=if enabled { "badge badge-success" } else { "badge badge-info" }>{label}</span>
                                    </>
                                }
                            })}
                        </div>

                        {(!wa_warnings.is_empty()).then(|| view! {
                            <div class="vm-notes">
                                {wa_warnings
                                    .into_iter()
                                    .map(|warning| {
                                        let severity = json_str(&warning, "severity");
                                        let setting = json_str(&warning, "setting");
                                        let value = json_str(&warning, "value");
                                        let message = json_str(&warning, "message");
                                        let note_class = match severity.as_str() {
                                            "warning" => "vm-note warning",
                                            "info" => "vm-note info",
                                            _ => "vm-note",
                                        };
                                        view! {
                                            <div class=note_class>
                                                <p>
                                                    <strong>
                                                        {if setting.is_empty() {
                                                            message.clone()
                                                        } else if value.is_empty() {
                                                            setting.clone()
                                                        } else {
                                                            format!("{setting}={value}")
                                                        }}
                                                    </strong>
                                                    {if !message.is_empty() && !setting.is_empty() {
                                                        format!(" — {message}")
                                                    } else {
                                                        String::new()
                                                    }}
                                                </p>
                                            </div>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </div>
                        })}
                    </div>
                })}
            </div>
        </Section>
    }
    .into_any()
}

/// Section 2 – Azure Linux Agent Log.
#[component]
pub fn WaagentLogSection(data: Value) -> impl IntoView {
    let wa_log = data.get("waagentLog").cloned().unwrap_or(Value::Null);
    if !json_bool(&wa_log, "found") {
        return view! {}.into_any();
    }

    let total_errors = wa_log
        .get("totalErrors")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as usize;
    let total_warnings = wa_log
        .get("totalWarnings")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as usize;
    let has_issues = json_bool(&wa_log, "hasErrors") || json_bool(&wa_log, "hasWarnings");
    let block_class = if has_issues {
        "danger-block"
    } else {
        "success-block"
    };

    let agent_version = json_str(&wa_log, "agentVersion");
    let version_history = json_array(&wa_log, "agentVersionHistory");
    let extension_status = json_array(&wa_log, "extensionStatusSummary");
    let goal_state_errors = json_array(&wa_log, "goalStateErrors");
    let extension_errors = json_array(&wa_log, "extensionErrors");
    let resource_disk_errors = json_array(&wa_log, "resourceDiskErrors");
    let imds_errors = json_array(&wa_log, "imdsErrors");
    let status_file_warnings = json_array(&wa_log, "statusFileWarnings");
    let other_errors = json_array(&wa_log, "otherErrors");
    let other_warnings = json_array(&wa_log, "otherWarnings");

    view! {
        <details class=block_class open=has_issues>
            <summary>
                "Azure Linux Agent Log"
                {(!agent_version.is_empty()).then(|| view! {
                    <span class="badge badge-info">{format!("v{agent_version}")}</span>
                })}
                {(total_errors > 0).then(|| view! {
                    <span class="badge badge-danger">
                        {format!(
                            "{total_errors} error{}",
                            if total_errors == 1 { "" } else { "s" },
                        )}
                    </span>
                })}
                {(total_warnings > 0).then(|| view! {
                    <span class="badge badge-warning">
                        {format!(
                            "{total_warnings} warning{}",
                            if total_warnings == 1 { "" } else { "s" },
                        )}
                    </span>
                })}
                {(!has_issues).then(|| view! {
                    <span class="badge badge-success">"No issues found"</span>
                })}
            </summary>

            <div class="section-body">
                {(!version_history.is_empty()).then(|| {
                    if version_history.len() == 1 {
                        let version = json_str(&version_history[0], "version");
                        let first_seen = json_str(&version_history[0], "firstSeen");
                        view! {
                            <div class="subsection">
                                <p><strong>"Agent Version History:"</strong></p>
                                <p>
                                    "WALinuxAgent "
                                    <strong>{version}</strong>
                                    {(!first_seen.is_empty()).then(|| view! {
                                        <span>{format!(" (since {first_seen})")}</span>
                                    })}
                                </p>
                            </div>
                        }
                        .into_any()
                    } else {
                        view! {
                            <div class="subsection">
                                <p><strong>"Agent Version History:"</strong></p>
                                <table class="data-table">
                                    <thead>
                                        <tr>
                                            <th>"Version"</th>
                                            <th>"First Seen"</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {version_history
                                            .into_iter()
                                            .map(|entry| {
                                                let version = json_str(&entry, "version");
                                                let first_seen = json_str(&entry, "firstSeen");
                                                view! {
                                                    <tr>
                                                        <td><code>{version}</code></td>
                                                        <td>{if first_seen.is_empty() {
                                                            "N/A".to_string()
                                                        } else {
                                                            first_seen
                                                        }}</td>
                                                    </tr>
                                                }
                                            })
                                            .collect::<Vec<_>>()}
                                    </tbody>
                                </table>
                            </div>
                        }
                        .into_any()
                    }
                })}

                {(!extension_status.is_empty()).then(|| view! {
                    <div class="subsection">
                        <p><strong>"Extension Status (last reported):"</strong></p>
                        <table class="data-table">
                            <tbody>
                                {extension_status
                                    .into_iter()
                                    .map(|ext| {
                                        let name = json_str(&ext, "name");
                                        let status = json_str(&ext, "status");
                                        let badge_class = match status.as_str() {
                                            "Ready" => "badge badge-success",
                                            "NotReady" => "badge badge-danger",
                                            _ => "badge badge-warning",
                                        };
                                        view! {
                                            <tr>
                                                <td><code>{name}</code></td>
                                                <td><span class=badge_class>{status}</span></td>
                                            </tr>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </div>
                })}

                {render_waagent_issue_group("Goal State Errors", goal_state_errors, false)}
                {render_waagent_issue_group("Extension Errors", extension_errors, false)}
                {render_waagent_issue_group("Resource Disk Errors", resource_disk_errors, false)}
                {render_waagent_issue_group("IMDS Connectivity Errors", imds_errors, false)}
                {render_waagent_issue_group("Status File Warnings", status_file_warnings, true)}
                {render_waagent_issue_group("Other Warnings", other_warnings, true)}

                {(!other_errors.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Other Errors ({})", other_errors.len())}</summary>
                        <ul>
                            {other_errors
                                .iter()
                                .take(20)
                                .map(|entry| {
                                    let timestamp = json_str(entry, "timestamp");
                                    let line = json_str(entry, "line");
                                    view! {
                                        <li>
                                            {(!timestamp.is_empty()).then(|| view! {
                                                <span class="text-muted">{format!("{timestamp} ")}</span>
                                            })}
                                            <code>{line.chars().take(200).collect::<String>()}</code>
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                            {(other_errors.len() > 20).then(|| view! {
                                <li class="text-muted">
                                    {format!("...and {} more", other_errors.len() - 20)}
                                </li>
                            })}
                        </ul>
                    </details>
                })}
            </div>
        </details>
    }
    .into_any()
}

/// Section 13 – Azure VM Extensions.
#[component]
pub fn AzureExtensionsSection(data: Value) -> impl IntoView {
    let ext = data.get("azureExtensions").cloned().unwrap_or(Value::Null);
    if !json_bool(&ext, "found") {
        return view! {}.into_any();
    }

    let mut extensions = json_array(&ext, "events");
    if extensions.is_empty() {
        extensions = json_array(&ext, "extensions");
    }
    if extensions.is_empty() {
        return view! {}.into_any();
    }

    extensions.sort_by(|a, b| {
        let a_healthy = a
            .get("healthy")
            .and_then(|v| v.as_bool())
            .unwrap_or_else(|| json_str(a, "status") == "Ready");
        let b_healthy = b
            .get("healthy")
            .and_then(|v| v.as_bool())
            .unwrap_or_else(|| json_str(b, "status") == "Ready");

        let a_label = json_str(a, "label");
        let b_label = json_str(b, "label");

        a_healthy
            .cmp(&b_healthy)
            .then_with(|| a_label.to_lowercase().cmp(&b_label.to_lowercase()))
    });

    let unhealthy_count = extensions
        .iter()
        .filter(|ext| {
            !ext.get("healthy")
                .and_then(|v| v.as_bool())
                .unwrap_or_else(|| json_str(ext, "status") == "Ready")
        })
        .count();

    let block_class = if unhealthy_count > 0 {
        "danger-block"
    } else {
        "info-block"
    };

    view! {
        <details class=block_class>
            <summary>
                {if unhealthy_count > 0 {
                    format!(
                        "Azure VM Extensions ({}) – {} not ready",
                        extensions.len(),
                        unhealthy_count,
                    )
                } else {
                    format!("Azure VM Extensions ({})", extensions.len())
                }}
            </summary>

            <div class="section-body">
                {extensions
                    .into_iter()
                    .map(|extension| {
                        let name = json_str(&extension, "name");
                        let label = {
                            let label = json_str(&extension, "label");
                            if label.is_empty() { name.clone() } else { label }
                        };
                        let version = json_str(&extension, "version");
                        let status = json_str(&extension, "status");
                        let message = json_str(&extension, "message");
                        let healthy = extension
                            .get("healthy")
                            .and_then(|v| v.as_bool())
                            .unwrap_or(status == "Ready");
                        let badge_class = if healthy {
                            "badge badge-success"
                        } else {
                            "badge badge-danger"
                        };
                        let text_class = if healthy { "text-success" } else { "text-danger" };

                        view! {
                            <div class="subsection">
                                <p class=text_class>
                                    <strong>{label.clone()}</strong>
                                </p>
                                <p>
                                    "Version: " <code>{version}</code>
                                    <span class=badge_class>{if status.is_empty() {
                                        if healthy {
                                            "Ready".to_string()
                                        } else {
                                            "NotReady".to_string()
                                        }
                                    } else {
                                        status.clone()
                                    }}</span>
                                </p>
                                {(!message.is_empty() && !healthy).then(|| view! {
                                    <p class="text-danger">
                                        <strong>"Error:"</strong>
                                        " "
                                        <code>{message}</code>
                                    </p>
                                })}
                                {(name != label && !name.is_empty()).then(|| view! {
                                    <p class="text-muted">{name}</p>
                                })}
                            </div>
                        }
                    })
                    .collect::<Vec<_>>()}
            </div>
        </details>
    }
    .into_any()
}

fn render_waagent_issue_group(
    title: &'static str,
    items: Vec<Value>,
    is_warning: bool,
) -> Option<AnyView> {
    if items.is_empty() {
        return None;
    }

    let class = if is_warning {
        "warning-block"
    } else {
        "danger-block"
    };
    let len = items.len();

    Some(
        view! {
            <div class=class>
                <p><strong>{format!("{title} ({len})")}</strong></p>
                <ul>
                    {items
                        .into_iter()
                        .take(10)
                        .map(|item| {
                            let timestamp = json_str(&item, "timestamp");
                            let description = describe_waagent_item(&item);
                            view! {
                                <li>
                                    {(!timestamp.is_empty()).then(|| view! {
                                        <span class="text-muted">{format!("{timestamp} ")}</span>
                                    })}
                                    {description}
                                </li>
                            }
                        })
                        .collect::<Vec<_>>()}
                    {(len > 10).then(|| view! {
                        <li class="text-muted">{format!("...and {} more", len - 10)}</li>
                    })}
                </ul>
            </div>
        }
        .into_any(),
    )
}

fn describe_waagent_item(item: &Value) -> String {
    let extension_name = json_str(item, "extensionName");
    let operation = json_str(item, "operation");
    let message = json_str(item, "message");

    if !extension_name.is_empty() && !operation.is_empty() {
        if message.is_empty() {
            format!("{extension_name} ({operation})")
        } else {
            format!("{extension_name} ({operation}): {message}")
        }
    } else if !message.is_empty() {
        message
    } else {
        let line = json_str(item, "line");
        if line.is_empty() {
            "Unknown issue".to_string()
        } else {
            line.chars().take(200).collect()
        }
    }
}

fn display_disk_type(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return "Unknown".to_string();
    }

    let display = trimmed.replace("_LRS", "").replace("_ZRS", " (ZRS)");

    match display.as_str() {
        "PremiumV2" => "Premium SSD v2".to_string(),
        "UltraSSD" => "Ultra Disk".to_string(),
        "Premium" => "Premium SSD".to_string(),
        "StandardSSD" => "Standard SSD".to_string(),
        "Standard" => "Standard HDD".to_string(),
        _ => display,
    }
}

fn value_as_text(value: &Value) -> Option<String> {
    value
        .as_str()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .or_else(|| value.as_i64().map(|v| v.to_string()))
        .or_else(|| value.as_u64().map(|v| v.to_string()))
        .or_else(|| {
            value.as_f64().map(|v| {
                if v.fract() == 0.0 {
                    format!("{v:.0}")
                } else {
                    v.to_string()
                }
            })
        })
}

fn disk_badge_class(raw: &str) -> &'static str {
    match raw {
        "PremiumV2_LRS" | "UltraSSD_LRS" => "badge badge-success",
        "Premium_LRS" | "Premium_ZRS" | "StandardSSD_LRS" | "StandardSSD_ZRS" => "badge badge-info",
        _ => "badge",
    }
}

/// SecureBoot status section. Only available from sosreport archives
/// (`sos_commands/boot/mokutil_--sb-state`). Renders a single info/warning
/// block depending on enabled/disabled/unsupported state.
#[component]
pub fn SecureBootSection(data: Value) -> impl IntoView {
    let sb = data.get("secureBoot").cloned().unwrap_or(Value::Null);
    if !json_bool(&sb, "found") {
        return view! {}.into_any();
    }

    let supported = sb
        .get("supported")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let enabled = sb.get("enabled").and_then(|v| v.as_bool());
    let state_text = json_str(&sb, "stateText");
    let source_path = json_str(&sb, "sourcePath");

    let (block_class, badge_class, status_label, summary_text) = if !supported {
        (
            "warning-block",
            "badge badge-warning",
            "Not supported".to_string(),
            "SecureBoot: Not supported (no EFI variables)".to_string(),
        )
    } else {
        match enabled {
            Some(true) => (
                "info-block",
                "badge badge-success",
                "Enabled".to_string(),
                "SecureBoot: Enabled".to_string(),
            ),
            Some(false) => (
                "warning-block",
                "badge badge-warning",
                "Disabled".to_string(),
                "SecureBoot: Disabled".to_string(),
            ),
            None => (
                "info-block",
                "badge",
                "Unknown".to_string(),
                "SecureBoot: Unknown".to_string(),
            ),
        }
    };

    view! {
        <details class=block_class open=true>
            <summary>{summary_text}</summary>
            <div class="section-body">
                <p>
                    "Status: "
                    <span class=badge_class>{status_label}</span>
                </p>
                {(!state_text.is_empty()).then(|| view! {
                    <p>"Raw state: " <code>{state_text}</code></p>
                })}
                {(!source_path.is_empty()).then(|| view! {
                    <p class="text-muted"><small>"Source: " <code>{source_path}</code></small></p>
                })}
            </div>
        </details>
    }
    .into_any()
}
