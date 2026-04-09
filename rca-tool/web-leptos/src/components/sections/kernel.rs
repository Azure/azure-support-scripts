use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section 10 – Kernel Crash Dumps (vmcore).
#[component]
pub fn KernelCrashSection(data: Value) -> impl IntoView {
    let vmcore = data.get("vmcore").cloned().unwrap_or(Value::Null);
    let crashes = json_array(&vmcore, "crashes");

    if !json_bool(&vmcore, "found") || crashes.is_empty() {
        return view! {}.into_any();
    }

    let crash_count = crashes.len();
    let kdump_status = vmcore.get("kdumpStatus").cloned().unwrap_or(Value::Null);
    let crash_listing = vmcore.get("crashListing").cloned().unwrap_or(Value::Null);
    let listing_entries = json_array(&crash_listing, "entries");
    let kdump_conf = vmcore.get("kdumpConf").cloned().unwrap_or(Value::Null);
    let total_usage = crash_listing
        .get("totalBytes")
        .and_then(|value| value.as_f64())
        .map(format_bytes)
        .unwrap_or_else(|| {
            let total_gb = json_str(&crash_listing, "totalGB");
            if total_gb.is_empty() {
                "-".to_string()
            } else {
                format!("{total_gb} GB")
            }
        });
    let total_count = crash_listing
        .get("count")
        .and_then(|value| value.as_u64())
        .unwrap_or(crash_count as u64);

    view! {
        <details class="danger-block" open=true>
            <summary>
                "Kernel Crash Dumps "
                <span class="badge badge-danger">
                    {format!("{} vmcore{}", crash_count, if crash_count == 1 { "" } else { "s" })}
                </span>
            </summary>

            <div class="section-body">
                {kdump_status
                    .get("raw")
                    .and_then(|value| value.as_str())
                    .map(|raw| {
                        let status_class = if json_bool(&kdump_status, "operational") {
                            "text-success"
                        } else {
                            "text-danger"
                        };
                        let status_icon = if json_bool(&kdump_status, "operational") {
                            "[OK]"
                        } else {
                            "[!]"
                        };
                        view! {
                            <p>
                                <strong>"Kdump Status:"</strong>
                                " "
                                <span class=status_class>{format!("{status_icon} {raw}")}</span>
                            </p>
                        }
                    })}

                <table class="kv-table">
                    <thead>
                        <tr>
                            <th class="kv-label">"Date"</th>
                            <th class="kv-label">"Panic Reason"</th>
                            <th class="kv-label">"Kernel"</th>
                            <th class="kv-label">"Process"</th>
                            <th class="kv-label">"Vmcore Size"</th>
                        </tr>
                    </thead>
                    <tbody>
                        {crashes
                            .into_iter()
                            .map(|crash| {
                                let date = json_str(&crash, "date");
                                let panic_reason = json_str(&crash, "panicReason");
                                let kernel_version = json_str(&crash, "kernelVersion");
                                let comm = json_str(&crash, "comm");
                                let pid = crash
                                    .get("pid")
                                    .and_then(|value| value.as_i64())
                                    .map(|value| value.to_string())
                                    .unwrap_or_default();
                                let process = if comm.is_empty() {
                                    "-".to_string()
                                } else if pid.is_empty() {
                                    comm.clone()
                                } else {
                                    format!("{comm} (PID {pid})")
                                };
                                let size = vmcore_size_for_date(&listing_entries, &date);
                                let call_trace = json_array(&crash, "callTrace");

                                view! {
                                    <>
                                        <tr>
                                            <td class="kv-value"><code>{if date.is_empty() { "-".to_string() } else { date }}</code></td>
                                            <td class="kv-value text-danger">
                                                <strong>
                                                    {if panic_reason.is_empty() {
                                                        "-".to_string()
                                                    } else {
                                                        panic_reason
                                                    }}
                                                </strong>
                                            </td>
                                            <td class="kv-value"><code>{if kernel_version.is_empty() { "-".to_string() } else { kernel_version }}</code></td>
                                            <td class="kv-value">{process}</td>
                                            <td class="kv-value"><code>{size}</code></td>
                                        </tr>
                                        {(!call_trace.is_empty()).then(|| view! {
                                            <tr>
                                                <td colspan="5" class="kv-value">
                                                    <details class="content-details">
                                                        <summary>{format!("Call Trace ({} frames)", call_trace.len())}</summary>
                                                        <pre class="json-dump">
                                                            {call_trace
                                                                .into_iter()
                                                                .filter_map(|frame| frame.as_str().map(|value| value.to_string()))
                                                                .collect::<Vec<_>>()
                                                                .join("\n")}
                                                        </pre>
                                                    </details>
                                                </td>
                                            </tr>
                                        })}
                                    </>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </tbody>
                </table>

                {(total_usage != "-").then(|| view! {
                    <p class="text-muted">
                        <strong>"Total vmcore disk usage:"</strong>
                        " "
                        {format!(
                            "{} across {} dump{}",
                            total_usage,
                            total_count,
                            if total_count == 1 { "" } else { "s" },
                        )}
                    </p>
                })}

                {(json_bool(&kdump_conf, "found") || !json_str(&kdump_conf, "path").is_empty())
                    .then(|| view! {
                        <details class="content-details">
                            <summary>"Kdump Configuration"</summary>
                            <KvTable>
                                <KvRow label="Dump path" value={json_str(&kdump_conf, "path")}/>
                                {(!json_str(&kdump_conf, "coreCollector").is_empty()).then(|| view! {
                                    <KvRow
                                        label="Core collector"
                                        value={json_str(&kdump_conf, "coreCollector")}
                                    />
                                })}
                                {(!json_str(&kdump_conf, "defaultAction").is_empty()).then(|| view! {
                                    <KvRow
                                        label="Failure action"
                                        value={json_str(&kdump_conf, "defaultAction")}
                                    />
                                })}
                            </KvTable>
                        </details>
                    })}

                <p>
                    <a
                        href="https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/troubleshoot-kdump"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="text-info"
                    >
                        "Kdump Documentation"
                    </a>
                </p>
            </div>
        </details>
    }
    .into_any()
}

/// Sections 14 + 16 – Kernel / System Parameters + Debugfs.
#[component]
pub fn KernelSection(data: Value) -> impl IntoView {
    let ktune = data.get("kernelTuning").cloned().unwrap_or(Value::Null);
    let hpages = data.get("hugePages").cloned().unwrap_or(Value::Null);
    let time_sync = data.get("timeSync").cloned().unwrap_or(Value::Null);
    let ptp_clock_source = data.get("ptpClockSource").cloned().unwrap_or(Value::Null);
    let time_sync_service = data.get("timeSyncService").cloned().unwrap_or(Value::Null);
    let timedatectl = data.get("timedatectl").cloned().unwrap_or(Value::Null);
    let ptp_device = data.get("ptpDevice").cloned().unwrap_or(Value::Null);
    let chrony_tracking = data.get("chronyTracking").cloned().unwrap_or(Value::Null);
    let chrony_makestep = data.get("chronyMakestep").cloned().unwrap_or(Value::Null);
    let hv_balloon = data.get("hvBalloon").cloned().unwrap_or(Value::Null);
    let extfrag = data.get("extfrag").cloned().unwrap_or(Value::Null);

    let has_kernel = json_bool(&ktune, "found")
        || json_bool(&hpages, "found")
        || json_bool(&time_sync, "found")
        || json_bool(&ptp_clock_source, "found")
        || json_bool(&time_sync_service, "found")
        || json_bool(&timedatectl, "found")
        || json_bool(&ptp_device, "found")
        || json_bool(&chrony_tracking, "found")
        || json_bool(&chrony_makestep, "found");
    let has_debugfs = json_bool(&hv_balloon, "found") || json_bool(&extfrag, "found");

    if !has_kernel && !has_debugfs {
        return view! {}.into_any();
    }

    let has_warnings = json_bool(&ktune, "hasWarnings")
        || json_bool(&ktune, "hasAzureNetworkWarnings")
        || json_bool(&hpages, "hasWarnings")
        || json_bool(&hpages, "hasRecommendations")
        || json_bool(&time_sync, "hasWarnings")
        || json_bool(&time_sync, "hasErrors")
        || !json_array(&hv_balloon, "warnings").is_empty()
        || !json_array(&extfrag, "warnings").is_empty();

    view! {
        {has_kernel.then(|| view! {
            <Section
                title="Kernel and System Parameters"
                class=if has_warnings { "warning-block" } else { "content-details" }
            >
                {render_kernel_tuning_section(&ktune)}
                {render_huge_pages_section(&hpages)}
                {render_time_sync_section(
                    &time_sync,
                    &ptp_clock_source,
                    &time_sync_service,
                    &timedatectl,
                    &ptp_device,
                    &chrony_tracking,
                    &chrony_makestep,
                )}
            </Section>
        })}
        {has_debugfs.then(|| view! {
            <Section title="Debugfs (Advanced)" class="warning-block">
                {render_hv_balloon_section(&hv_balloon)}
                {render_extfrag_section(&extfrag)}
            </Section>
        })}
    }
    .into_any()
}

fn render_kernel_tuning_section(tuning: &Value) -> Option<AnyView> {
    if !json_bool(tuning, "found") {
        return None;
    }

    let warnings = json_array(tuning, "warnings");
    let azure_warnings = json_array(tuning, "azureNetworkWarnings");
    let optional_info = json_array(tuning, "optionalNetworkInfo");
    let mut parameters = tuning
        .get("parameters")
        .and_then(|value| value.as_object())
        .map(|map| {
            map.iter()
                .map(|(key, value)| {
                    (
                        key.clone(),
                        value_as_text(value).unwrap_or_else(|| value.to_string()),
                    )
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    parameters.sort_by(|left, right| left.0.cmp(&right.0));

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Kernel Tuning:"</p>

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Kernel Parameter Warnings ({})", warnings.len())}</strong></p>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Parameter"</th>
                                    <th>"Expected"</th>
                                    <th>"Found"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {warnings
                                    .iter()
                                    .map(|warning| view! {
                                        <tr>
                                            <td><code>{json_text(warning, "parameter")}</code></td>
                                            <td><code>{json_text(warning, "expected")}</code></td>
                                            <td><code>{json_text(warning, "actual")}</code></td>
                                        </tr>
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </div>
                })}

                {tuning
                    .get("azureNetworkTuned")
                    .and_then(|value| value.as_bool())
                    .unwrap_or(false)
                    .then(|| view! {
                        <div class="info-block">
                            <p><strong>"[OK] Kernel parameters tuned for Azure Network"</strong></p>
                            <p>
                                <a
                                    href="https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-optimize-network-bandwidth#linux-virtual-machines"
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    class="text-info"
                                >
                                    "View Documentation"
                                </a>
                            </p>
                        </div>
                    })}

                {(!azure_warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p>
                            <strong>"[!] Azure Network Optimization - Parameters Need Adjustment"</strong>
                            " "
                            <span class="badge badge-warning">"Network tuning"</span>
                        </p>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Parameter"</th>
                                    <th>"Expected"</th>
                                    <th>"Found"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {azure_warnings
                                    .iter()
                                    .map(|warning| view! {
                                        <tr>
                                            <td><code>{json_text(warning, "parameter")}</code></td>
                                            <td><code>{json_text(warning, "expected")}</code></td>
                                            <td><code>{json_text(warning, "actual")}</code></td>
                                        </tr>
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                        <p>
                            <a
                                href="https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-optimize-network-bandwidth#linux-virtual-machines"
                                target="_blank"
                                rel="noopener noreferrer"
                                class="text-info"
                            >
                                "View Documentation"
                            </a>
                        </p>
                    </div>
                })}

                {tuning
                    .get("fipsEnabled")
                    .and_then(|value| value.as_bool())
                    .unwrap_or(false)
                    .then(|| view! {
                        <div class="info-block">
                            <p><strong>"FIPS mode is enabled in the kernel."</strong></p>
                        </div>
                    })}

                {(!optional_info.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>"Optional Network Tuning (informational only)"</summary>
                        <p class="text-muted">
                            "These are optional recommendations and do not indicate configuration issues; they are informational only."
                        </p>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Status"</th>
                                    <th>"Parameter"</th>
                                    <th>"Recommended"</th>
                                    <th>"Current"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {optional_info
                                    .iter()
                                    .map(|item| {
                                        let matches = item
                                            .get("matches")
                                            .and_then(|value| value.as_bool())
                                            .unwrap_or(false);
                                        view! {
                                            <tr>
                                                <td>{if matches { "[OK]" } else { "[i]" }}</td>
                                                <td><code>{json_text(item, "parameter")}</code></td>
                                                <td><code>{json_text(item, "expected")}</code></td>
                                                <td><code>{json_text(item, "actual")}</code></td>
                                            </tr>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                        <p>
                            <a
                                href="https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-optimize-network-bandwidth#linux-virtual-machines"
                                target="_blank"
                                rel="noopener noreferrer"
                                class="text-info"
                            >
                                "View Documentation"
                            </a>
                        </p>
                    </details>
                })}

                {(!parameters.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("All Kernel Parameters ({})", parameters.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Parameter"</th>
                                    <th>"Value"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {parameters
                                    .iter()
                                    .map(|(key, value)| view! {
                                        <tr>
                                            <td><code>{key.clone()}</code></td>
                                            <td><code>{value.clone()}</code></td>
                                        </tr>
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </details>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_huge_pages_section(huge: &Value) -> Option<AnyView> {
    if !json_bool(huge, "found") {
        return None;
    }

    let warnings = json_array(huge, "warnings");
    let recommendations = json_array(huge, "recommendations");
    let static_hp = huge.get("staticHugePages").cloned().unwrap_or(Value::Null);
    let thp = huge
        .get("transparentHugePages")
        .cloned()
        .unwrap_or(Value::Null);
    let sysctl = huge.get("sysctlParams").cloned().unwrap_or(Value::Null);

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Huge Pages Configuration:"</p>

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Huge Pages Warnings ({})", warnings.len())}</strong></p>
                        <ul class="disk-list">
                            {warnings
                                .iter()
                                .map(|warning| view! { <li>{json_text(warning, "message")}</li> })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!recommendations.is_empty()).then(|| view! {
                    <div class="info-block">
                        <p><strong>"Recommendations"</strong></p>
                        <ul class="disk-list">
                            {recommendations
                                .iter()
                                .map(|rec| {
                                    let message = json_text(rec, "message");
                                    let doc = json_text(rec, "documentationUrl");
                                    view! {
                                        <li>
                                            {message}
                                            {(!doc.is_empty()).then(|| view! {
                                                <div>
                                                    <a
                                                        href=doc.clone()
                                                        target="_blank"
                                                        rel="noopener noreferrer"
                                                        class="text-info"
                                                    >
                                                        "View Documentation"
                                                    </a>
                                                </div>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                <details class="content-details" open=true>
                    <summary>"Static Huge Pages"</summary>
                    <KvTable>
                        <KvRow
                            label="Total Pages"
                            value=empty_dash(json_text(&static_hp, "total"))
                        />
                        <KvRow
                            label="Free Pages"
                            value=empty_dash(json_text(&static_hp, "free"))
                        />
                        <KvRow
                            label="Reserved Pages"
                            value=empty_dash(json_text(&static_hp, "rsvd"))
                        />
                        <KvRow
                            label="Surplus Pages"
                            value=empty_dash(json_text(&static_hp, "surp"))
                        />
                        <KvRow
                            label="Page Size"
                            value=if json_text(&static_hp, "pagesize_kb").is_empty() {
                                "-".to_string()
                            } else {
                                format!("{} kB", json_text(&static_hp, "pagesize_kb"))
                            }
                        />
                        <KvRow
                            label="Total Memory"
                            value=if json_text(&static_hp, "total_mb").is_empty() {
                                "-".to_string()
                            } else {
                                format!("{} MB", json_text(&static_hp, "total_mb"))
                            }
                        />
                    </KvTable>
                </details>

                <details class="content-details">
                    <summary>"Transparent Huge Pages (THP)"</summary>
                    <KvTable>
                        <KvRow
                            label="Anonymous Huge Pages"
                            value=if json_text(&thp, "anon_kb").is_empty() {
                                "-".to_string()
                            } else {
                                format!("{} kB", json_text(&thp, "anon_kb"))
                            }
                        />
                        <KvRow
                            label="THP In Use"
                            value=if json_text(&thp, "anon_mb").is_empty() {
                                "-".to_string()
                            } else {
                                format!("{} MB", json_text(&thp, "anon_mb"))
                            }
                        />
                        <KvRow
                            label="Shared Memory Huge Pages"
                            value=if json_text(&thp, "shmem_kb").is_empty() {
                                "-".to_string()
                            } else {
                                format!("{} kB", json_text(&thp, "shmem_kb"))
                            }
                        />
                        <KvRow
                            label="Shared PMD Mapped"
                            value=if json_text(&thp, "shmem_pmd_mapped_kb").is_empty() {
                                "-".to_string()
                            } else {
                                format!("{} kB", json_text(&thp, "shmem_pmd_mapped_kb"))
                            }
                        />
                    </KvTable>
                </details>

                {(sysctl.as_object().map(|obj| !obj.is_empty()).unwrap_or(false)).then(|| view! {
                    <details class="content-details">
                        <summary>"Huge Page Kernel Parameters (sysctl)"</summary>
                        <KvTable>
                            <KvRow
                                label="vm.nr_hugepages"
                                value=empty_dash(json_text(&sysctl, "nr_hugepages"))
                            />
                            <KvRow
                                label="vm.nr_overcommit_hugepages"
                                value=empty_dash(json_text(&sysctl, "nr_overcommit_hugepages"))
                            />
                            <KvRow
                                label="vm.hugetlb_shm_group"
                                value=empty_dash(json_text(&sysctl, "hugetlb_shm_group"))
                            />
                        </KvTable>
                    </details>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_time_sync_section(
    time_sync: &Value,
    ptp_clock_source: &Value,
    time_sync_service: &Value,
    timedatectl: &Value,
    ptp_device: &Value,
    chrony_tracking: &Value,
    chrony_makestep: &Value,
) -> Option<AnyView> {
    let has_any = json_bool(time_sync, "found")
        || json_bool(ptp_clock_source, "found")
        || json_bool(time_sync_service, "found")
        || json_bool(timedatectl, "found")
        || json_bool(ptp_device, "found")
        || json_bool(chrony_tracking, "found")
        || json_bool(chrony_makestep, "found");

    if !has_any {
        return None;
    }

    let mut issues = Vec::new();
    for source in [
        time_sync,
        ptp_clock_source,
        time_sync_service,
        timedatectl,
        ptp_device,
        chrony_tracking,
        chrony_makestep,
    ] {
        issues.extend(json_array(source, "warnings"));
    }

    let error_count = issues
        .iter()
        .filter(|issue| json_text(issue, "severity") == "error")
        .count();
    let warning_count = issues.len().saturating_sub(error_count);

    let hyperv_modules = string_array(time_sync, "hypervModules").join(", ");
    let hv_utils_loaded = time_sync
        .get("hvUtilsLoaded")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let detection_file = json_text(time_sync_service, "detectionFile");
    let service_details = if time_sync_service
        .get("chronyEnabled")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
    {
        format!(
            "chrony ({})",
            empty_dash(json_text(time_sync_service, "chronyStatus"))
        )
    } else if time_sync_service
        .get("ntpdEnabled")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
    {
        format!(
            "ntpd ({})",
            empty_dash(json_text(time_sync_service, "ntpdStatus"))
        )
    } else if time_sync_service
        .get("timesyncdEnabled")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
    {
        format!(
            "systemd-timesyncd ({})",
            empty_dash(json_text(time_sync_service, "timesyncdStatus")),
        )
    } else {
        "No active time sync service detected".to_string()
    };
    let ptp_source = if ptp_clock_source
        .get("hasPtpSource")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
    {
        empty_dash(json_text(ptp_clock_source, "ptpDevice"))
    } else if chrony_tracking
        .get("isPtpSource")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
    {
        empty_dash(json_text(chrony_tracking, "referenceName"))
    } else {
        "No PTP source configured".to_string()
    };
    let ntp_synchronized = timedatectl
        .get("ntpSynchronized")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let ptp_hyperv = ptp_device
        .get("hasPtpHypervSymlink")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let offset_ok = chrony_tracking
        .get("lastOffsetSeconds")
        .and_then(|value| value.as_f64())
        .map(|offset| offset.abs() < 0.1)
        .unwrap_or(true);
    let offset_details = chrony_tracking
        .get("lastOffsetSeconds")
        .and_then(|value| value.as_f64())
        .map(|offset| format!("{:.3} ms", offset * 1000.0))
        .unwrap_or_else(|| "No offset data".to_string());
    let makestep_details = if chrony_makestep
        .get("hasMakestep")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
    {
        format!(
            "{} {}",
            empty_dash(json_text(chrony_makestep, "makestepThreshold")),
            empty_dash(json_text(chrony_makestep, "makestepLimit")),
        )
    } else {
        "Not configured".to_string()
    };
    let timezone = empty_dash(json_text(timedatectl, "timezone"));
    let ptp_target = empty_dash(json_text(ptp_device, "ptpHypervTarget"));
    let chrony_sources = json_array(ptp_clock_source, "chronySources");
    let issues_class = if error_count > 0 {
        "warning-block"
    } else {
        "info-block"
    };

    Some(
        view! {
            <details class="content-details" open=error_count > 0 || warning_count > 0>
                <summary>
                    "Time Synchronization"
                    {(error_count > 0).then(|| view! {
                        <span class="badge badge-danger">{format!("{} error(s)", error_count)}</span>
                    })}
                    {(warning_count > 0).then(|| view! {
                        <span class="badge badge-warning">{format!("{} warning(s)", warning_count)}</span>
                    })}
                </summary>

                <p class="text-muted">
                    "Azure Linux VMs should use PTP from the host for accurate time synchronization."
                    " "
                    <a
                        href="https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="text-info"
                    >
                        "Documentation"
                    </a>
                </p>

                <KvTable>
                    <KvRow
                        label="hv_utils module"
                        value=if hyperv_modules.is_empty() {
                            if hv_utils_loaded {
                                "OK".to_string()
                            } else {
                                "ERROR — No Hyper-V modules listed".to_string()
                            }
                        } else if hv_utils_loaded {
                            format!("OK — {}", hyperv_modules)
                        } else {
                            format!("ERROR — {}", hyperv_modules)
                        }
                    />
                    <KvRow
                        label="Time sync service"
                        value=if service_details.starts_with("No active") {
                            if detection_file.is_empty() {
                                format!("ERROR — {}", service_details)
                            } else {
                                format!("ERROR — {} (from {})", service_details, detection_file)
                            }
                        } else if detection_file.is_empty() {
                            format!("OK — {}", service_details)
                        } else {
                            format!("OK — {} (from {})", service_details, detection_file)
                        }
                    />
                    <KvRow
                        label="PTP clock source"
                        value=if ptp_source.starts_with("No PTP") {
                            format!("WARN — {}", ptp_source)
                        } else {
                            format!("OK — {}", ptp_source)
                        }
                    />
                    <KvRow
                        label="Clock synchronized"
                        value=if ntp_synchronized {
                            "OK — NTP synchronized".to_string()
                        } else {
                            format!("WARN — {}", timezone.clone())
                        }
                    />
                    <KvRow
                        label="/dev/ptp_hyperv"
                        value=if ptp_hyperv {
                            format!("OK — {}", ptp_target.clone())
                        } else {
                            "WARN — Symlink not present".to_string()
                        }
                    />
                    <KvRow
                        label="Chrony offset"
                        value=if offset_ok {
                            format!("OK — {}", offset_details)
                        } else {
                            format!("WARN — {}", offset_details)
                        }
                    />
                    <KvRow
                        label="makestep"
                        value=if makestep_details == "Not configured" {
                            "Info — Not configured".to_string()
                        } else {
                            format!("OK — {}", makestep_details)
                        }
                    />
                </KvTable>

                {(!issues.is_empty()).then(|| view! {
                    <div class=issues_class>
                        <p><strong>"Issues Detected"</strong></p>
                        <ul class="disk-list">
                            {issues
                                .iter()
                                .map(|issue| {
                                    let message = json_text(issue, "message");
                                    let recommendation = json_text(issue, "recommendation");
                                    view! {
                                        <li>
                                            {message}
                                            {(!recommendation.is_empty()).then(|| view! {
                                                <div class="text-muted">{recommendation}</div>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!chrony_sources.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Chrony Sources ({})", chrony_sources.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Type"</th>
                                    <th>"Source"</th>
                                    <th>"Status"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {chrony_sources
                                    .iter()
                                    .map(|source| {
                                        let active = source
                                            .get("active")
                                            .and_then(|value| value.as_bool())
                                            .unwrap_or(false);
                                        view! {
                                            <tr>
                                                <td>{json_text(source, "type")}</td>
                                                <td><code>{json_text(source, "name")}</code></td>
                                                <td>{if active { "Active sync source" } else { "Available" }}</td>
                                            </tr>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </details>
                })}
            </details>
        }
        .into_any(),
    )
}

fn render_hv_balloon_section(hv_balloon: &Value) -> Option<AnyView> {
    if !json_bool(hv_balloon, "found") {
        return None;
    }

    let warnings = json_array(hv_balloon, "warnings");
    let raw_content = json_text(hv_balloon, "rawContent");
    let host_version = empty_dash(json_text(hv_balloon, "hostVersion"));
    let capabilities = empty_dash(json_text(hv_balloon, "capabilities"));
    let state_value = if json_text(hv_balloon, "stateText").is_empty() {
        empty_dash(json_text(hv_balloon, "state"))
    } else {
        format!(
            "{} ({})",
            empty_dash(json_text(hv_balloon, "state")),
            json_text(hv_balloon, "stateText"),
        )
    };
    let committed_memory = if json_text(hv_balloon, "committedMemoryGB").is_empty() {
        "-".to_string()
    } else {
        format!("{} GB", json_text(hv_balloon, "committedMemoryGB"))
    };
    let max_dynamic_memory = if json_text(hv_balloon, "maxDynamicMemoryGB").is_empty() {
        "-".to_string()
    } else {
        format!("{} GB", json_text(hv_balloon, "maxDynamicMemoryGB"))
    };
    let ballooned_memory = if json_text(hv_balloon, "balloonedMemoryMB").is_empty() {
        "-".to_string()
    } else {
        format!("{} MB", json_text(hv_balloon, "balloonedMemoryMB"))
    };
    let pages_added = empty_dash(json_text(hv_balloon, "pagesAdded"));
    let pages_onlined = empty_dash(json_text(hv_balloon, "pagesOnlined"));

    Some(
        view! {
            <details class="content-details" open=true>
                <summary>"Hyper-V Dynamic Memory (hv-balloon)"</summary>

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>"Warnings"</strong></p>
                        <ul class="disk-list">
                            {warnings
                                .iter()
                                .map(|warning| {
                                    let text = value_as_text(warning).unwrap_or_else(|| warning.to_string());
                                    view! { <li>{text}</li> }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                <KvTable>
                    <KvRow label="Host Version" value=host_version.clone() />
                    <KvRow label="Capabilities" value=capabilities.clone() />
                    <KvRow label="State" value=state_value.clone() />
                    <KvRow label="Committed Memory" value=committed_memory.clone() />
                    <KvRow label="Max Dynamic Memory" value=max_dynamic_memory.clone() />
                    <KvRow label="Ballooned Memory" value=ballooned_memory.clone() />
                    <KvRow label="Pages Added" value=pages_added.clone() />
                    <KvRow label="Pages Onlined" value=pages_onlined.clone() />
                </KvTable>

                {render_raw_output_details("Raw debugfs output", raw_content)}
            </details>
        }
        .into_any(),
    )
}

fn render_extfrag_section(extfrag: &Value) -> Option<AnyView> {
    if !json_bool(extfrag, "found") {
        return None;
    }

    let zones = json_array(extfrag, "zones");
    let warnings = json_array(extfrag, "warnings");
    let raw_content = json_text(extfrag, "rawContent");

    Some(
        view! {
            <details class="content-details" open=true>
                <summary>{format!("Memory Fragmentation Index ({} zone{})", zones.len(), if zones.len() == 1 { "" } else { "s" })}</summary>

                <p class="text-muted">
                    "Values are reported per buddy allocator order (4K through 4M). Higher orders map to larger contiguous allocations; order 9 corresponds to 2 MB huge pages."
                </p>

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Fragmentation warnings ({})", warnings.len())}</strong></p>
                        <ul class="disk-list">
                            {warnings
                                .iter()
                                .map(|warning| {
                                    let text = value_as_text(warning).unwrap_or_else(|| warning.to_string());
                                    view! { <li>{text}</li> }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {zones
                    .iter()
                    .map(|zone| {
                        let unusable = zone
                            .get("unusableIndex")
                            .and_then(|value| value.as_array())
                            .map(|items| {
                                items
                                    .iter()
                                    .filter_map(value_as_text)
                                    .collect::<Vec<_>>()
                                    .join(", ")
                            })
                            .unwrap_or_default();
                        let extfrag_index = zone
                            .get("extfragIndex")
                            .and_then(|value| value.as_array())
                            .map(|items| {
                                items
                                    .iter()
                                    .filter_map(value_as_text)
                                    .collect::<Vec<_>>()
                                    .join(", ")
                            })
                            .unwrap_or_default();
                        view! {
                            <div class="vm-note info">
                                <p>
                                    <strong>
                                        {format!(
                                            "Node {}, zone {}",
                                            json_text(zone, "node"),
                                            json_text(zone, "zone"),
                                        )}
                                    </strong>
                                </p>
                                {(!unusable.is_empty()).then(|| view! {
                                    <p>
                                        <strong>"Unusable Index:"</strong>
                                        " "
                                        <code>{unusable}</code>
                                    </p>
                                })}
                                {(!extfrag_index.is_empty()).then(|| view! {
                                    <p>
                                        <strong>"Extfrag Index:"</strong>
                                        " "
                                        <code>{extfrag_index}</code>
                                    </p>
                                })}
                            </div>
                        }
                    })
                    .collect::<Vec<_>>()}

                {render_raw_output_details("Raw extfrag output", raw_content)}
            </details>
        }
        .into_any(),
    )
}

fn render_raw_output_details(title: &str, content: String) -> Option<AnyView> {
    if content.trim().is_empty() {
        return None;
    }

    Some(
        view! {
            <details class="content-details">
                <summary>{title.to_string()}</summary>
                <pre class="json-dump">{content}</pre>
            </details>
        }
        .into_any(),
    )
}

fn string_array(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(|value| value.as_array())
        .map(|items| items.iter().filter_map(value_as_text).collect())
        .unwrap_or_default()
}

fn json_text(value: &Value, key: &str) -> String {
    value.get(key).and_then(value_as_text).unwrap_or_default()
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
                    format!("{v:.3}")
                }
            })
        })
}

fn empty_dash(value: String) -> String {
    if value.trim().is_empty() {
        "-".to_string()
    } else {
        value
    }
}

fn vmcore_size_for_date(entries: &[Value], crash_date: &str) -> String {
    entries
        .iter()
        .find(|entry| json_str(entry, "crashDate") == crash_date)
        .map(|entry| {
            entry
                .get("sizeBytes")
                .and_then(|value| value.as_f64())
                .map(format_bytes)
                .or_else(|| {
                    entry
                        .get("sizeMB")
                        .and_then(|value| value.as_u64())
                        .map(|value| format!("{value} MB"))
                })
                .unwrap_or_else(|| {
                    let size_gb = json_str(entry, "sizeGB");
                    if size_gb.is_empty() {
                        "-".to_string()
                    } else {
                        format!("{size_gb} GB")
                    }
                })
        })
        .unwrap_or_else(|| "-".to_string())
}
