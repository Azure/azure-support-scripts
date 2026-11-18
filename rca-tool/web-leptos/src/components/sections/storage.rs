use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section 3 – InspectIaaSDisk Results.
#[component]
pub fn InspectDiskSection(data: Value) -> impl IntoView {
    let inspect = data
        .get("inspectDiskResults")
        .cloned()
        .unwrap_or(Value::Null);

    if !json_bool(&inspect, "found") || !json_bool(&inspect, "isInspectDisk") {
        return view! {}.into_any();
    }

    let request_info = inspect.get("requestInfo").cloned().unwrap_or(Value::Null);
    let metadata = inspect
        .get("inspectionMetadata")
        .cloned()
        .unwrap_or(Value::Null);
    let filesystem_status = json_array(&inspect, "filesystemStatus");
    let mount_results = json_array(&inspect, "mountResults");
    let warnings = json_array(&inspect, "warnings");

    let failed_mounts = mount_results
        .iter()
        .filter(|entry| json_str(entry, "status") == "FAILED")
        .count();
    let block_class = if failed_mounts > 0 {
        "danger-block"
    } else {
        "success-block"
    };

    let has_request_info = request_info
        .as_object()
        .map(|obj| !obj.is_empty())
        .unwrap_or(false);
    let has_metadata = metadata
        .as_object()
        .map(|obj| !obj.is_empty())
        .unwrap_or(false);

    view! {
        <details class=block_class open=true>
            <summary>
                "InspectIaaSDisk Results"
                {(failed_mounts > 0).then(|| view! {
                    <span class="badge badge-danger">
                        {format!(
                            "{failed_mounts} mount failure{}",
                            if failed_mounts == 1 { "" } else { "s" },
                        )}
                    </span>
                })}
            </summary>

            <div class="section-body">
                {has_request_info.then(|| view! {
                    <div class="subsection">
                        <p><strong>"Request Info:"</strong></p>
                        <KvTable>
                            <KvRow label="Storage Account" value=json_str(&request_info, "storageAccount")/>
                            <KvRow label="Container/VHD" value=json_str(&request_info, "containerVhd")/>
                            <KvRow label="Manifest" value=json_str(&request_info, "manifest")/>
                            <KvRow label="Operational ID" value=json_str(&request_info, "operationalId")/>
                            <KvRow label="Guestfish" value=json_str(&request_info, "guestfishVersion")/>
                        </KvTable>
                    </div>
                })}

                {has_metadata.then(|| view! {
                    <div class="subsection">
                        <p><strong>"Disk Inspection:"</strong></p>
                        <KvTable>
                            <KvRow label="Product" value=json_str(&metadata, "productName")/>
                            <KvRow label="Distribution" value=json_str(&metadata, "distribution")/>
                            <KvRow label="Type" value=json_str(&metadata, "type")/>
                        </KvTable>
                    </div>
                })}

                {(!filesystem_status.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Filesystem Status ({} devices)", filesystem_status.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Device"</th>
                                    <th>"Type"</th>
                                    <th>"UUID"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {filesystem_status
                                    .into_iter()
                                    .map(|fs| {
                                        let device = json_str(&fs, "device");
                                        let fs_type = json_str(&fs, "type");
                                        let uuid = json_str(&fs, "uuid");
                                        view! {
                                            <tr>
                                                <td><code>{device}</code></td>
                                                <td>{fs_type}</td>
                                                <td><code>{if uuid.is_empty() { "-".to_string() } else { uuid }}</code></td>
                                            </tr>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </details>
                })}

                {(!mount_results.is_empty()).then(|| view! {
                    <details class="content-details" open=failed_mounts > 0>
                        <summary>{format!("Mount Results ({} mounts)", mount_results.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Device"</th>
                                    <th>"Mount Point"</th>
                                    <th>"Status"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {mount_results
                                    .into_iter()
                                    .map(|mount| {
                                        let device = json_str(&mount, "device");
                                        let mount_point = json_str(&mount, "mountPoint");
                                        let status = json_str(&mount, "status");
                                        let status_class = if status == "SUCCEEDED" { "text-success" } else { "text-danger" };
                                        let status_text = if status == "SUCCEEDED" {
                                            format!("✓ {status}")
                                        } else {
                                            format!("✗ {status}")
                                        };
                                        view! {
                                            <tr>
                                                <td><code>{device}</code></td>
                                                <td><code>{mount_point}</code></td>
                                                <td class=status_class>{status_text}</td>
                                            </tr>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </details>
                })}

                {warnings
                    .into_iter()
                    .map(|warning| {
                        let severity = json_str(&warning, "severity");
                        let message = json_str(&warning, "message");
                        let recommendation = json_str(&warning, "recommendation");
                        let class = if severity == "error" { "danger-block" } else { "warning-block" };
                        let heading = if severity == "error" { "Error" } else { "Warning" };
                        view! {
                            <div class=class>
                                <p>
                                    <strong>{format!("{heading}:")}</strong>
                                    " "
                                    {message}
                                </p>
                                {(!recommendation.is_empty()).then(|| view! { <p>{recommendation}</p> })}
                            </div>
                        }
                    })
                    .collect::<Vec<_>>()}
            </div>
        </details>
    }
    .into_any()
}

/// Section 15 – Storage (LVM, RAID, BTRFS, block devices, fstab).
#[component]
pub fn StorageSection(data: Value) -> impl IntoView {
    let lvm = data.get("lvmConfig").cloned().unwrap_or(Value::Null);
    let raid = data.get("raidConfig").cloned().unwrap_or(Value::Null);
    let btrfs = data.get("btrfsConfig").cloned().unwrap_or(Value::Null);
    let fstab = data.get("fstab").cloned().unwrap_or(Value::Null);
    let fstab_analysis = data.get("fstabAnalysis").cloned().unwrap_or(Value::Null);
    let block = data.get("blockDevices").cloned().unwrap_or(Value::Null);
    let correlation = data
        .get("storageCorrelation")
        .cloned()
        .unwrap_or(Value::Null);
    let df = data.get("dfOutput").cloned().unwrap_or(Value::Null);
    let mtab = data.get("mtabAnalysis").cloned().unwrap_or(Value::Null);
    let nvme = data.get("nvmeList").cloned().unwrap_or(Value::Null);
    let nfs = data.get("nfsMounts").cloned().unwrap_or(Value::Null);

    let has_any = json_bool(&lvm, "found")
        || json_bool(&raid, "found")
        || json_bool(&btrfs, "found")
        || json_bool(&fstab, "found")
        || json_bool(&fstab_analysis, "found")
        || json_bool(&block, "found")
        || json_bool(&correlation, "found")
        || json_bool(&mtab, "found")
        || json_bool(&nfs, "found")
        || json_bool(&nvme, "hasNVMe");

    if !has_any {
        return view! {}.into_any();
    }

    let error_count = json_array(&correlation, "errors").len();
    let warning_count = json_array(&correlation, "warnings").len();
    let class = if error_count > 0 {
        "danger-block"
    } else if warning_count > 0 {
        "warning-block"
    } else {
        "content-details"
    };

    view! {
        <Section title="Storage" class=class>
            {render_lvm_section(&lvm)}
            {render_raid_section(&raid)}
            {render_btrfs_section(&btrfs)}
            {render_block_devices_section(&block)}
            {render_storage_correlation(&correlation)}
            {render_fstab_section(&fstab, &fstab_analysis, &df)}
            {render_mtab_section(&mtab)}
            {render_nfs_section(&nfs)}
            {render_nvme_section(&nvme)}
        </Section>
    }
    .into_any()
}

fn render_lvm_section(lvm: &Value) -> Option<AnyView> {
    if !json_bool(lvm, "found") {
        return None;
    }

    let warnings = json_array(lvm, "warnings");
    let pvs = json_array(lvm, "pvs");
    let vgs = json_array(lvm, "vgs");
    let lvs = json_array(lvm, "lvs");
    let raw_output = lvm.get("rawOutput").cloned().unwrap_or(Value::Null);

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"LVM Configuration:"</p>

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Warnings ({})", warnings.len())}</strong></p>
                        <ul class="disk-list">
                            {warnings
                                .iter()
                                .map(|warning| {
                                    let warning_type = json_text(warning, "type");
                                    let message = json_text(warning, "message");
                                    let details = json_text(warning, "details");
                                    view! {
                                        <li>
                                            <strong>{if warning_type.is_empty() {
                                                "Warning".to_string()
                                            } else {
                                                format!("{}:", warning_type)
                                            }}</strong>
                                            " "
                                            {message}
                                            {(!details.is_empty()).then(|| view! {
                                                <div class="text-muted">{details}</div>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!pvs.is_empty()).then(|| view! {
                    <details class="content-details" open=true>
                        <summary>{format!("Physical Volumes ({})", pvs.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Device"</th>
                                    <th>"Volume Group"</th>
                                    <th>"Size"</th>
                                    <th>"Free"</th>
                                    <th>"Attributes"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {pvs
                                    .iter()
                                    .map(|pv| view! {
                                        <tr>
                                            <td><code>{json_text(pv, "device")}</code></td>
                                            <td><code>{empty_dash(json_text(pv, "vg"))}</code></td>
                                            <td><code>{empty_dash(json_text(pv, "size"))}</code></td>
                                            <td><code>{empty_dash(json_text(pv, "free"))}</code></td>
                                            <td><code>{empty_dash(json_text(pv, "attr"))}</code></td>
                                        </tr>
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                        {render_raw_output_details("Raw pvs output", json_text(&raw_output, "pvs"))}
                    </details>
                })}

                {(!vgs.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Volume Groups ({})", vgs.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Volume Group"</th>
                                    <th>"PVs"</th>
                                    <th>"LVs"</th>
                                    <th>"Size"</th>
                                    <th>"Free"</th>
                                    <th>"Attributes"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {vgs
                                    .iter()
                                    .map(|vg| view! {
                                        <tr>
                                            <td><code>{json_text(vg, "name")}</code></td>
                                            <td><code>{empty_dash(json_text(vg, "pv_count"))}</code></td>
                                            <td><code>{empty_dash(json_text(vg, "lv_count"))}</code></td>
                                            <td><code>{empty_dash(json_text(vg, "size"))}</code></td>
                                            <td><code>{empty_dash(json_text(vg, "free"))}</code></td>
                                            <td><code>{empty_dash(json_text(vg, "attr"))}</code></td>
                                        </tr>
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                        {render_raw_output_details("Raw vgs output", json_text(&raw_output, "vgs"))}
                    </details>
                })}

                {(!lvs.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Logical Volumes ({})", lvs.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Logical Volume"</th>
                                    <th>"Volume Group"</th>
                                    <th>"Size"</th>
                                    <th>"Pool"</th>
                                    <th>"Attributes"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {lvs
                                    .iter()
                                    .map(|lv| view! {
                                        <tr>
                                            <td><code>{json_text(lv, "name")}</code></td>
                                            <td><code>{empty_dash(json_text(lv, "vg"))}</code></td>
                                            <td><code>{empty_dash(json_text(lv, "size"))}</code></td>
                                            <td><code>{empty_dash(json_text(lv, "pool"))}</code></td>
                                            <td><code>{empty_dash(json_text(lv, "attr"))}</code></td>
                                        </tr>
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                        {render_raw_output_details("Raw lvs output", json_text(&raw_output, "lvs"))}
                    </details>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_raid_section(raid: &Value) -> Option<AnyView> {
    if !json_bool(raid, "found") {
        return None;
    }

    let arrays = json_array(raid, "arrays");
    let warnings = json_array(raid, "warnings");
    let raw_output = raid.get("rawOutput").cloned().unwrap_or(Value::Null);

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"RAID Configuration:"</p>

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Warnings ({})", warnings.len())}</strong></p>
                        <ul class="disk-list">
                            {warnings
                                .iter()
                                .map(|warning| {
                                    let warning_type = json_text(warning, "type");
                                    let message = json_text(warning, "message");
                                    let details = json_text(warning, "details");
                                    view! {
                                        <li>
                                            <strong>{if warning_type.is_empty() {
                                                "Warning".to_string()
                                            } else {
                                                format!("{}:", warning_type)
                                            }}</strong>
                                            " "
                                            {message}
                                            {(!details.is_empty()).then(|| view! { <div class="text-muted">{details}</div> })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!arrays.is_empty()).then(|| view! {
                    <details class="content-details" open=true>
                        <summary>{format!("RAID Arrays ({})", arrays.len())}</summary>
                        {arrays
                            .iter()
                            .map(|array| {
                                let device = json_text(array, "device");
                                let state = json_text(array, "state");
                                let level = json_text(array, "level");
                                let size = json_text(array, "size");
                                let devices = json_array(array, "devices");
                                let sync_status = array.get("syncStatus").cloned().unwrap_or(Value::Null);
                                let badge_class = match state.as_str() {
                                    "active" => "badge badge-success",
                                    "degraded" => "badge badge-warning",
                                    _ => "badge badge-danger",
                                };
                                view! {
                                    <div class="vm-note info">
                                        <p>
                                            <strong><code>{device.clone()}</code></strong>
                                            " "
                                            <span class=badge_class>{state.to_uppercase()}</span>
                                            {(!level.is_empty()).then(|| view! {
                                                <span class="text-muted">{format!(" — Level: {}", level.clone())}</span>
                                            })}
                                        </p>
                                        {(!size.is_empty()).then(|| view! {
                                            <p><strong>"Size:"</strong> " " {size.clone()}</p>
                                        })}
                                        {(!devices.is_empty()).then(|| view! {
                                            <>
                                                <p><strong>"Devices:"</strong></p>
                                                <ul class="disk-list">
                                                    {devices
                                                        .iter()
                                                        .map(|dev| {
                                                            let name = json_text(dev, "device");
                                                            let state = json_text(dev, "state");
                                                            view! { <li><code>{name}</code>{format!(" - {}", state)}</li> }
                                                        })
                                                        .collect::<Vec<_>>()}
                                                </ul>
                                            </>
                                        })}
                                        {sync_status.as_object().map(|obj| !obj.is_empty()).unwrap_or(false).then(|| view! {
                                            <div class="info-block">
                                                <p>
                                                    <strong>{format!("{} in progress", json_text(&sync_status, "operation").to_uppercase())}</strong>
                                                </p>
                                                <p>
                                                    {format!(
                                                        "Progress: {}%{}{}",
                                                        empty_dash(json_text(&sync_status, "percentage")),
                                                        if json_text(&sync_status, "finish").is_empty() {
                                                            String::new()
                                                        } else {
                                                            format!(", finish {}", json_text(&sync_status, "finish"))
                                                        },
                                                        if json_text(&sync_status, "speed").is_empty() {
                                                            String::new()
                                                        } else {
                                                            format!(", speed {}", json_text(&sync_status, "speed"))
                                                        },
                                                    )}
                                                </p>
                                            </div>
                                        })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                        {render_raw_output_details("Raw /proc/mdstat", json_text(&raw_output, "mdstat"))}
                    </details>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_btrfs_section(btrfs: &Value) -> Option<AnyView> {
    if !json_bool(btrfs, "found") {
        return None;
    }

    let filesystems = json_array(btrfs, "filesystems");
    let subvolumes = json_array(btrfs, "subvolumes");
    let raw_output = btrfs.get("rawOutput").cloned().unwrap_or(Value::Null);

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"BTRFS Configuration:"</p>

                {(!filesystems.is_empty()).then(|| view! {
                    <details class="content-details" open=true>
                        <summary>{format!("BTRFS Filesystems ({})", filesystems.len())}</summary>
                        {filesystems
                            .iter()
                            .map(|fs| {
                                let label = json_text(fs, "label");
                                let uuid = json_text(fs, "uuid");
                                let total_size = json_text(fs, "totalSize");
                                let device_count = json_text(fs, "deviceCount");
                                let devices = json_array(fs, "devices");
                                view! {
                                    <div class="vm-note info">
                                        <p><strong>"Label:"</strong> " " {empty_dash(label.clone())}</p>
                                        {(!uuid.is_empty()).then(|| view! {
                                            <p><strong>"UUID:"</strong> " " <code>{uuid.clone()}</code></p>
                                        })}
                                        {(!device_count.is_empty() || !total_size.is_empty()).then(|| view! {
                                            <p>
                                                {(!device_count.is_empty()).then(|| view! {
                                                    <span><strong>"Devices:"</strong> " " {device_count.clone()}</span>
                                                })}
                                                {(!device_count.is_empty() && !total_size.is_empty()).then(|| view! { <span>" | "</span> })}
                                                {(!total_size.is_empty()).then(|| view! {
                                                    <span><strong>"Used:"</strong> " " {total_size.clone()}</span>
                                                })}
                                            </p>
                                        })}
                                        {(!devices.is_empty()).then(|| view! {
                                            <table class="data-table">
                                                <thead>
                                                    <tr>
                                                        <th>"Device"</th>
                                                        <th>"Size"</th>
                                                        <th>"Used"</th>
                                                    </tr>
                                                </thead>
                                                <tbody>
                                                    {devices
                                                        .iter()
                                                        .map(|dev| view! {
                                                            <tr>
                                                                <td><code>{json_text(dev, "path")}</code></td>
                                                                <td>{empty_dash(json_text(dev, "size"))}</td>
                                                                <td>{empty_dash(json_text(dev, "used"))}</td>
                                                            </tr>
                                                        })
                                                        .collect::<Vec<_>>()}
                                                </tbody>
                                            </table>
                                        })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                        {render_raw_output_details(
                            "Raw btrfs filesystem show",
                            json_text(&raw_output, "filesystems"),
                        )}
                    </details>
                })}

                {(!subvolumes.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("BTRFS Subvolumes ({})", subvolumes.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"ID"</th>
                                    <th>"Path"</th>
                                    <th>"Parent"</th>
                                    <th>"Top Level"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {subvolumes
                                    .iter()
                                    .map(|subvol| view! {
                                        <tr>
                                            <td><code>{json_text(subvol, "id")}</code></td>
                                            <td><code>{json_text(subvol, "path")}</code></td>
                                            <td><code>{empty_dash(json_text(subvol, "parent"))}</code></td>
                                            <td><code>{empty_dash(json_text(subvol, "topLevel"))}</code></td>
                                        </tr>
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                        {render_raw_output_details(
                            "Raw btrfs subvolume list",
                            json_text(&raw_output, "subvolumes"),
                        )}
                    </details>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_block_devices_section(block: &Value) -> Option<AnyView> {
    if !json_bool(block, "found") {
        return None;
    }

    let disks = json_array(block, "disks");
    let partitions = json_array(block, "partitions");

    if disks.is_empty() && partitions.is_empty() {
        return None;
    }

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Block Devices:"</p>

                {(!disks.is_empty()).then(|| view! {
                    <details class="content-details" open=true>
                        <summary>{format!("Disks ({})", disks.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Device"</th>
                                    <th>"Size"</th>
                                    <th>"Type"</th>
                                    <th>"Mount"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {disks
                                    .iter()
                                    .map(|disk| view! {
                                        <tr>
                                            <td><code>{json_text(disk, "device")}</code></td>
                                            <td>{empty_dash(json_text(disk, "size"))}</td>
                                            <td>{empty_dash(json_text(disk, "type"))}</td>
                                            <td><code>{empty_dash(json_text(disk, "mountpoint"))}</code></td>
                                        </tr>
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </details>
                })}

                {(!partitions.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Partitions ({})", partitions.len())}</summary>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Device"</th>
                                    <th>"Size"</th>
                                    <th>"Filesystem"</th>
                                    <th>"UUID"</th>
                                    <th>"Mount"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {partitions
                                    .iter()
                                    .map(|part| view! {
                                        <tr>
                                            <td><code>{json_text(part, "device")}</code></td>
                                            <td>{empty_dash(json_text(part, "size"))}</td>
                                            <td>{empty_dash(json_text(part, "fstype"))}</td>
                                            <td><code>{empty_dash(json_text(part, "uuid"))}</code></td>
                                            <td><code>{empty_dash(json_text(part, "mountpoint"))}</code></td>
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

fn render_storage_correlation(correlation: &Value) -> Option<AnyView> {
    if !json_bool(correlation, "found") {
        return None;
    }

    let errors = json_array(correlation, "errors");
    let warnings = json_array(correlation, "warnings");

    if errors.is_empty() && warnings.is_empty() {
        return None;
    }

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Fstab / UUID Correlation:"</p>

                {(!errors.is_empty()).then(|| view! {
                    <div class="danger-block">
                        <p><strong>{format!("UUID Errors ({})", errors.len())}</strong></p>
                        <ul class="disk-list">
                            {errors
                                .iter()
                                .map(|err| {
                                    let mountpoint = json_text(err, "mountpoint");
                                    let uuid = json_text(err, "uuid");
                                    let message = json_text(err, "message");
                                    view! {
                                        <li>
                                            <strong>{mountpoint}</strong>
                                            ": UUID "
                                            <code>{uuid}</code>
                                            " not found on any device."
                                            {(!message.is_empty()).then(|| view! {
                                                <div class="text-muted">{message}</div>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Filesystem Warnings ({})", warnings.len())}</strong></p>
                        <ul class="disk-list">
                            {warnings
                                .iter()
                                .map(|warning| {
                                    let mountpoint = json_text(warning, "mountpoint");
                                    let message = json_text(warning, "message");
                                    view! {
                                        <li>
                                            {if mountpoint.is_empty() {
                                                message.clone()
                                            } else {
                                                format!("{}: {}", mountpoint, message)
                                            }}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_fstab_section(fstab: &Value, fstab_analysis: &Value, df: &Value) -> Option<AnyView> {
    let raw_content = {
        let from_fstab = json_text(fstab, "content");
        if from_fstab.is_empty() {
            json_text(fstab_analysis, "rawContent")
        } else {
            from_fstab
        }
    };
    let entries = json_array(fstab_analysis, "entries");
    let nofail_warnings = json_array(fstab_analysis, "warnings")
        .into_iter()
        .filter(|warning| json_text(warning, "type") == "missing_nofail")
        .collect::<Vec<_>>();

    if entries.is_empty() && raw_content.is_empty() {
        return None;
    }

    Some(
        view! {
            <details class="content-details" open=!nofail_warnings.is_empty()>
                <summary>
                    "Filesystem Table (/etc/fstab)"
                    {(!nofail_warnings.is_empty()).then(|| view! {
                        <span class="badge badge-warning">
                            {format!(
                                "{} missing nofail",
                                nofail_warnings.len(),
                            )}
                        </span>
                    })}
                </summary>

                {(!nofail_warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>"Non-OS partitions missing 'nofail' option"</strong></p>
                        <p>
                            "These mount points may prevent the system from booting if the storage becomes unavailable:"
                        </p>
                        <ul class="disk-list">
                            {nofail_warnings
                                .iter()
                                .map(|warning| {
                                    let mountpoint = json_text(warning, "mountpoint");
                                    let fstype = json_text(warning, "fstype");
                                    let source = json_text(warning, "source");
                                    view! {
                                        <li>
                                            <code>{mountpoint}</code>
                                            {format!(" ({}) - source: {}", fstype, source)}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                        <p>
                            <strong>"Recommendation:"</strong>
                            " Add "
                            <code>"nofail"</code>
                            " to these entries in /etc/fstab."
                        </p>
                        <p>
                            <a
                                href="https://learn.microsoft.com/en-us/azure/virtual-machines/linux/fstab-device-names"
                                target="_blank"
                                rel="noopener noreferrer"
                                class="text-info"
                            >
                                "Azure fstab best practices"
                            </a>
                        </p>
                    </div>
                })}

                {(!entries.is_empty()).then(|| view! {
                    <div class="section-body">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Mount Point"</th>
                                    <th>"Source"</th>
                                    <th>"Type"</th>
                                    <th>"Size"</th>
                                    <th>"Used"</th>
                                    <th>"Use%"</th>
                                    <th>"Options"</th>
                                    <th>"Status"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {entries
                                    .iter()
                                    .map(|entry| {
                                        let mountpoint = json_text(entry, "mountpoint");
                                        let source = json_text(entry, "source");
                                        let fstype = json_text(entry, "fstype");
                                        let options = json_text(entry, "options");
                                        let usage = df
                                            .get("mountToUsage")
                                            .and_then(|usage| usage.get(&mountpoint))
                                            .cloned()
                                            .unwrap_or(Value::Null);
                                        let size = format_df_size(&json_text(&usage, "size"));
                                        let used = format_df_size(&json_text(&usage, "used"));
                                        let use_percent = json_text(&usage, "usePercentStr");
                                        let needs_nofail = entry
                                            .get("needsNofail")
                                            .and_then(|value| value.as_bool())
                                            .unwrap_or(false);
                                        let is_virtual = entry
                                            .get("isVirtualFs")
                                            .and_then(|value| value.as_bool())
                                            .unwrap_or(false);
                                        let is_os = entry
                                            .get("isOsPartition")
                                            .and_then(|value| value.as_bool())
                                            .unwrap_or(false);
                                        let has_nofail = entry
                                            .get("hasNofail")
                                            .and_then(|value| value.as_bool())
                                            .unwrap_or(false);
                                        view! {
                                            <tr>
                                                <td><code>{mountpoint.clone()}</code></td>
                                                <td><code>{source.clone()}</code></td>
                                                <td>{fstype.clone()}</td>
                                                <td>{empty_dash(size)}</td>
                                                <td>{empty_dash(used)}</td>
                                                <td>{empty_dash(use_percent.clone())}</td>
                                                <td>{options.clone()}</td>
                                                <td>
                                                    {if needs_nofail {
                                                        view! { <span class="badge badge-warning">"nofail"</span> }
                                                            .into_any()
                                                    } else if is_virtual {
                                                        view! { <span class="text-muted">"virtual"</span> }.into_any()
                                                    } else if is_os {
                                                        view! { <span class="text-success">"OS"</span> }.into_any()
                                                    } else if has_nofail {
                                                        view! { <span class="text-muted">"Data disk"</span> }.into_any()
                                                    } else {
                                                        view! { <span class="text-muted">"-"</span> }.into_any()
                                                    }}
                                                </td>
                                            </tr>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </div>
                })}

                {render_raw_output_details("Show raw /etc/fstab", raw_content)}
            </details>
        }
        .into_any(),
    )
}

fn render_mtab_section(mtab: &Value) -> Option<AnyView> {
    if !json_bool(mtab, "found") {
        return None;
    }

    let entries = json_array(mtab, "entries");
    let extra_mounts = json_array(mtab, "extraMounts");
    let raw_content = json_text(mtab, "rawContent");
    let real_mounts = mtab
        .get("realMounts")
        .and_then(|value| value.as_u64())
        .unwrap_or_else(|| {
            entries
                .iter()
                .filter(|entry| {
                    !entry
                        .get("isVirtualFs")
                        .and_then(|value| value.as_bool())
                        .unwrap_or(false)
                })
                .count() as u64
        });

    if entries.is_empty() && extra_mounts.is_empty() && raw_content.is_empty() {
        return None;
    }

    Some(
        view! {
            <details class="content-details" open=!extra_mounts.is_empty()>
                <summary>
                    {format!("Mounted Filesystems ({} real mount{})", real_mounts, if real_mounts == 1 { "" } else { "s" })}
                    {(!extra_mounts.is_empty()).then(|| view! {
                        <span class="badge badge-warning">
                            {format!(
                                "{} mount{} not in fstab",
                                extra_mounts.len(),
                                if extra_mounts.len() == 1 { "" } else { "s" },
                            )}
                        </span>
                    })}
                </summary>

                {(!extra_mounts.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>"Mounts not defined in /etc/fstab"</strong></p>
                        <p>
                            "These filesystems are currently mounted but have no entry in /etc/fstab. They may have been mounted manually or by a cluster resource agent."
                        </p>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Mount Point"</th>
                                    <th>"Source"</th>
                                    <th>"Type"</th>
                                    <th>"Options"</th>
                                    <th>"Likely Origin"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {extra_mounts
                                    .iter()
                                    .map(|mount| {
                                        let mountpoint = json_text(mount, "mountpoint");
                                        let source = json_text(mount, "source");
                                        let fstype = json_text(mount, "fstype");
                                        let options = json_text(mount, "options");
                                        let source_type = json_text(mount, "sourceType");
                                        let origin = if source_type == "network" {
                                            "Network mount (NFS/CIFS)".to_string()
                                        } else if mountpoint.contains("/hana/")
                                            || mountpoint.contains("/sapmnt")
                                            || mountpoint.contains("/usr/sap")
                                        {
                                            "SAP/HANA (likely cluster-managed)".to_string()
                                        } else if fstype == "ocfs2" || fstype == "gfs2" {
                                            "Cluster filesystem".to_string()
                                        } else {
                                            "Hand-mounted".to_string()
                                        };
                                        view! {
                                            <tr>
                                                <td><code>{mountpoint}</code></td>
                                                <td><code>{source}</code></td>
                                                <td>{fstype}</td>
                                                <td>{options}</td>
                                                <td>{origin}</td>
                                            </tr>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </div>
                })}

                {render_raw_output_details("Show raw /etc/mtab", raw_content)}
            </details>
        }
        .into_any(),
    )
}

fn render_nfs_section(nfs: &Value) -> Option<AnyView> {
    if !json_bool(nfs, "found") {
        return None;
    }

    let mounts = json_array(nfs, "mounts");
    let warnings = json_array(nfs, "warnings");

    if mounts.is_empty() && warnings.is_empty() {
        return None;
    }

    let opt_num = |mount: &Value, key: &str| -> String {
        mount
            .get(key)
            .and_then(|v| v.as_i64())
            .map(|n| n.to_string())
            .unwrap_or_else(|| "—".to_string())
    };

    let has_warnings = !warnings.is_empty();
    let block_class = if warnings
        .iter()
        .any(|w| json_str(w, "severity") == "error")
    {
        "danger-block"
    } else if has_warnings {
        "warning-block"
    } else {
        "content-details"
    };

    Some(
        view! {
            <details class=block_class open=has_warnings>
                <summary>
                    {format!(
                        "NFS Mounts ({} mount{})",
                        mounts.len(),
                        if mounts.len() == 1 { "" } else { "s" },
                    )}
                    {has_warnings.then(|| view! {
                        <span class="badge badge-warning">
                            {format!(
                                "{} issue{}",
                                warnings.len(),
                                if warnings.len() == 1 { "" } else { "s" },
                            )}
                        </span>
                    })}
                </summary>

                <table class="data-table">
                    <thead>
                        <tr>
                            <th>"Mount Point"</th>
                            <th>"Source"</th>
                            <th>"Type"</th>
                            <th>"Version"</th>
                            <th>"rsize"</th>
                            <th>"wsize"</th>
                            <th>"hard/soft"</th>
                            <th>"nconnect"</th>
                        </tr>
                    </thead>
                    <tbody>
                        {mounts
                            .iter()
                            .map(|mount| {
                                let mountpoint = json_text(mount, "mountpoint");
                                let source = json_text(mount, "source");
                                let fstype = json_text(mount, "fstype");
                                let vers = {
                                    let v = json_text(mount, "vers");
                                    if v.is_empty() { "—".to_string() } else { v }
                                };
                                let rsize = opt_num(mount, "rsize");
                                let wsize = opt_num(mount, "wsize");
                                let has_hard = json_bool(mount, "has_hard");
                                let has_soft = json_bool(mount, "has_soft");
                                let hardsoft = if has_soft {
                                    "soft".to_string()
                                } else if has_hard {
                                    "hard".to_string()
                                } else {
                                    "default".to_string()
                                };
                                let nconnect = opt_num(mount, "nconnect");
                                view! {
                                    <tr>
                                        <td><code>{mountpoint}</code></td>
                                        <td><code>{source}</code></td>
                                        <td>{fstype}</td>
                                        <td>{vers}</td>
                                        <td>{rsize}</td>
                                        <td>{wsize}</td>
                                        <td>{hardsoft}</td>
                                        <td>{nconnect}</td>
                                    </tr>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </tbody>
                </table>

                {warnings
                    .into_iter()
                    .map(|warning| {
                        let severity = json_str(&warning, "severity");
                        let message = json_str(&warning, "message");
                        let recommendation = json_str(&warning, "recommendation");
                        let class = if severity == "error" {
                            "danger-block"
                        } else if severity == "warning" {
                            "warning-block"
                        } else {
                            "info-block"
                        };
                        let heading = if severity == "error" {
                            "Error"
                        } else if severity == "warning" {
                            "Warning"
                        } else {
                            "Info"
                        };
                        view! {
                            <div class=class>
                                <p>
                                    <strong>{format!("{heading}:")}</strong>
                                    " "
                                    {message}
                                </p>
                                {(!recommendation.is_empty()).then(|| view! { <p>{recommendation}</p> })}
                            </div>
                        }
                    })
                    .collect::<Vec<_>>()}
            </details>
        }
        .into_any(),
    )
}

fn render_nvme_section(nvme: &Value) -> Option<AnyView> {
    if !json_bool(nvme, "hasNVMe") {
        return None;
    }

    let drive_count = nvme
        .get("driveCount")
        .and_then(|value| value.as_u64())
        .unwrap_or(0);
    let content = json_text(nvme, "content");

    Some(
        view! {
            <details class="content-details">
                <summary>{format!("NVMe Drives ({} detected)", drive_count)}</summary>
                <pre class="json-dump">{content}</pre>
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
                    v.to_string()
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

fn format_df_size(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() || trimmed == "-" {
        return "-".to_string();
    }

    if trimmed.chars().all(|ch| ch.is_ascii_digit() || ch == '.') {
        if let Ok(mut size) = trimmed.parse::<f64>() {
            let units = ["B", "KB", "MB", "GB", "TB", "PB"];
            let mut unit_index = 0usize;

            if size > 1024.0 {
                size *= 1024.0; // df often reports 1K blocks
            }

            while size >= 1024.0 && unit_index < units.len() - 1 {
                size /= 1024.0;
                unit_index += 1;
            }

            if unit_index == 0 {
                format!("{size:.0} {}", units[unit_index])
            } else if size >= 100.0 {
                format!("{size:.0} {}", units[unit_index])
            } else if size >= 10.0 {
                format!("{size:.1} {}", units[unit_index])
            } else {
                format!("{size:.2} {}", units[unit_index])
            }
        } else {
            trimmed.to_string()
        }
    } else {
        trimmed.to_string()
    }
}
