use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section 12 – Azure Services / Antivirus.
#[component]
pub fn ServicesAntivirusSection(data: Value) -> impl IntoView {
    let antivirus = data.get("antivirus").cloned().unwrap_or(Value::Null);
    let involflt_version = data.get("involfltVersion").cloned().unwrap_or(Value::Null);
    let involflt_kernel_version = data
        .get("involfltKernelVersion")
        .cloned()
        .unwrap_or(Value::Null);

    let sap_detected = detect_sap_workload(&data);
    let has_antivirus = json_bool(&antivirus, "anyDetected")
        || json_bool(&involflt_version, "found")
        || json_bool(&involflt_kernel_version, "found");
    let has_exceptions =
        json_bool(&antivirus, "allHaveExceptions") && has_antivirus && sap_detected;

    let (block_class, status_text) = if !has_antivirus {
        ("info-block", "Azure Services or Antivirus".to_string())
    } else if !sap_detected {
        (
            "info-block",
            "Azure Services or Antivirus Detected".to_string(),
        )
    } else if has_exceptions {
        (
            "success-block",
            "[OK] Azure Services or Antivirus Detected with SAP Exceptions".to_string(),
        )
    } else {
        (
            "danger-block",
            "[WARNING] Antivirus Detected - SAP Exceptions Required".to_string(),
        )
    };

    let falcon = antivirus
        .get("falconSensor")
        .cloned()
        .unwrap_or(Value::Null);
    let defender = antivirus.get("msDefender").cloned().unwrap_or(Value::Null);
    let illumio = antivirus.get("illumio").cloned().unwrap_or(Value::Null);
    let trend_micro = antivirus.get("trendMicro").cloned().unwrap_or(Value::Null);
    let guardicore = antivirus
        .get("guardicoreAgent")
        .cloned()
        .unwrap_or(Value::Null);
    let puppet = antivirus.get("puppetAgent").cloned().unwrap_or(Value::Null);
    let chef = antivirus.get("chefClient").cloned().unwrap_or(Value::Null);
    let asr = antivirus
        .get("azureSiteRecovery")
        .cloned()
        .unwrap_or(Value::Null);

    view! {
        <details class=block_class>
            <summary>{status_text}</summary>

            <div class="section-body">
                {(!has_antivirus).then(|| view! {
                    <>
                        <p class="text-muted">
                            <em>
                                "No Azure services, antivirus or security software was detected in the analyzed files."
                            </em>
                        </p>
                        <p class="text-muted">
                            <em>
                                "Checked for: Azure Site Recovery, CrowdStrike Falcon Sensor, Microsoft Defender for Endpoint (mdatp), Illumio, Trend Micro Deep Security, Guardicore Agent, Puppet Agent, Chef Client"
                            </em>
                        </p>
                    </>
                })}

                {render_falcon_section(&falcon, sap_detected)}
                {render_defender_section(&defender, sap_detected)}
                {render_basic_detection_section(
                    &illumio,
                    "Illumio",
                    sap_detected,
                    "Please verify that SAP paths are excluded in Illumio policy configuration: /usr/sap, /hana/shared, /hana/data, /hana/log, /sapmnt",
                )}
                {render_basic_detection_section(
                    &trend_micro,
                    "Trend Micro Deep Security",
                    sap_detected,
                    "Please verify that SAP paths are excluded in Deep Security Manager: /usr/sap, /hana/shared, /hana/data, /hana/log, /sapmnt",
                )}
                {render_detected_with_source(
                    &guardicore,
                    "Guardicore Agent",
                    "warning-block",
                    "text-warning",
                    sap_detected,
                    Some("Please verify that SAP paths are excluded in Guardicore policy configuration: /usr/sap, /hana/shared, /hana/data, /hana/log, /sapmnt"),
                )}
                {render_detected_with_source(
                    &puppet,
                    "Puppet Agent",
                    "info-block",
                    "text-info",
                    false,
                    None,
                )}
                {render_detected_with_source(
                    &chef,
                    "Chef Client",
                    "info-block",
                    "text-info",
                    false,
                    None,
                )}
                {render_asr_section(&asr, &involflt_version, &involflt_kernel_version)}

                {(sap_detected && has_antivirus).then(|| view! {
                    <div class="warning-block">
                        <p class="text-warning">
                            <strong>"Important:"</strong>
                            " When running SAP on Azure, antivirus software must exclude SAP directories to prevent performance issues and potential data corruption."
                        </p>
                        <p class="text-warning">
                            "Recommended exclusions: /usr/sap, /hana/shared, /hana/data, /hana/log, /sapmnt, /usr/sap/*/SYS/exe"
                        </p>
                    </div>
                })}
            </div>
        </details>
    }
    .into_any()
}

fn render_falcon_section(data: &Value, sap_detected: bool) -> Option<AnyView> {
    if !json_bool(data, "detected") {
        return None;
    }

    let version = json_str(data, "version");
    let running = json_bool(data, "runningProcess");
    let message = json_str(data, "message");
    let has_exclusions = json_bool(data, "sapExceptions");
    let exclusions = string_array(data, "exclusionPaths");
    let text_class = if sap_detected && !has_exclusions {
        "text-danger"
    } else {
        "text-success"
    };

    Some(
        view! {
            <div class="subsection">
                <p class=text_class><strong>"CrowdStrike Falcon Sensor"</strong></p>
                {(!version.is_empty()).then(|| view! {
                    <p>
                        <strong>"Version:"</strong>
                        " "
                        <code>{version.clone()}</code>
                    </p>
                })}
                {running.then(|| view! {
                    <p><span class="badge badge-success">"Running"</span></p>
                })}

                {if sap_detected {
                    if has_exclusions && !exclusions.is_empty() {
                        view! {
                            <div class="success-block">
                                <p class="text-success"><strong>"SAP Exclusions Configured:"</strong></p>
                                <ul>
                                    {exclusions
                                        .into_iter()
                                        .map(|path| view! { <li><code>{path}</code></li> })
                                        .collect::<Vec<_>>()}
                                </ul>
                            </div>
                        }
                        .into_any()
                    } else {
                        view! {
                            <div class="danger-block">
                                <p class="text-danger"><strong>"[!] SAP exclusions not detected."</strong></p>
                                <p class="text-muted">
                                    "Required SAP paths should be excluded: /usr/sap, /hana/shared, /hana/data, /hana/log, /sapmnt"
                                </p>
                                <p>
                                    <a
                                        href="https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker"
                                        target="_blank"
                                        rel="noopener noreferrer"
                                        class="text-info"
                                    >
                                        "View SAP on Azure Documentation"
                                    </a>
                                </p>
                            </div>
                        }
                        .into_any()
                    }
                } else {
                    view! {
                        <p class="text-muted">
                            {format!(
                                "Detected CrowdStrike Falcon Sensor{}.",
                                if version.is_empty() {
                                    "".to_string()
                                } else {
                                    format!(" - version {version}")
                                },
                            )}
                        </p>
                    }
                    .into_any()
                }}

                {(!message.is_empty()).then(|| view! {
                    <p class="text-muted"><em>{message}</em></p>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_defender_section(data: &Value, sap_detected: bool) -> Option<AnyView> {
    if !json_bool(data, "detected") {
        return None;
    }

    let version = json_str(data, "version");
    let running = json_bool(data, "runningProcess");
    let message = json_str(data, "message");
    let has_exclusions = json_bool(data, "sapExceptions");
    let exclusions = string_array(data, "exclusionPaths");
    let text_class = if sap_detected && !has_exclusions {
        "text-warning"
    } else {
        "text-success"
    };

    Some(
        view! {
            <div class="subsection">
                <p class=text_class><strong>"Microsoft Defender for Endpoint"</strong></p>
                {(!version.is_empty()).then(|| view! {
                    <p>
                        <strong>"Version:"</strong>
                        " "
                        <code>{version.clone()}</code>
                    </p>
                })}
                {running.then(|| view! {
                    <p><span class="badge badge-success">"Running"</span></p>
                })}

                {if sap_detected {
                    if has_exclusions && !exclusions.is_empty() {
                        view! {
                            <div class="success-block">
                                <p class="text-success"><strong>"SAP Exclusions Configured:"</strong></p>
                                <ul>
                                    {exclusions
                                        .into_iter()
                                        .map(|path| view! { <li><code>{path}</code></li> })
                                        .collect::<Vec<_>>()}
                                </ul>
                            </div>
                        }
                        .into_any()
                    } else {
                        view! {
                            <div class="warning-block">
                                <p class="text-warning"><strong>"[!] SAP exclusions need verification"</strong></p>
                                <p class="text-muted">
                                    "The exclusion configuration file was not found in the analyzed files. Please verify that the following SAP paths are excluded: /usr/sap, /hana/shared, /hana/data, /hana/log, /sapmnt"
                                </p>
                                <p>
                                    <a
                                        href="https://learn.microsoft.com/en-us/defender-endpoint/mde-linux-deployment-on-sap"
                                        target="_blank"
                                        rel="noopener noreferrer"
                                        class="text-info"
                                    >
                                        "Configure Defender Exclusions on Linux"
                                    </a>
                                </p>
                            </div>
                        }
                        .into_any()
                    }
                } else {
                    view! {
                        <p class="text-muted">
                            {format!(
                                "Detected Microsoft Defender{}.",
                                if version.is_empty() {
                                    "".to_string()
                                } else {
                                    format!(" - version {version}")
                                },
                            )}
                        </p>
                    }
                    .into_any()
                }}

                {(!message.is_empty()).then(|| view! {
                    <p class="text-muted"><em>{message}</em></p>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_basic_detection_section(
    data: &Value,
    label: &'static str,
    sap_detected: bool,
    sap_guidance: &'static str,
) -> Option<AnyView> {
    if !json_bool(data, "detected") {
        return None;
    }

    let message = json_str(data, "message");

    Some(
        view! {
            <div class="subsection">
                <p class="text-warning"><strong>{label}</strong></p>
                {sap_detected.then(|| view! {
                    <div class="warning-block">
                        <p class="text-warning"><strong>"[!] SAP exclusions need verification"</strong></p>
                        <p class="text-muted">{sap_guidance}</p>
                    </div>
                })}
                {(!sap_detected).then(|| view! {
                    <p class="text-muted">{format!("Detected {label}.")}</p>
                })}
                {(!message.is_empty()).then(|| view! {
                    <p class="text-muted"><em>{message}</em></p>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_detected_with_source(
    data: &Value,
    label: &'static str,
    block_class: &'static str,
    text_class: &'static str,
    sap_detected: bool,
    sap_guidance: Option<&'static str>,
) -> Option<AnyView> {
    if !json_bool(data, "detected") {
        return None;
    }

    let message = json_str(data, "message");
    let detection_file = json_str(data, "detectionFile");
    let detection_line = data
        .get("detectionLine")
        .and_then(|value| value.as_i64())
        .map(|value| value.to_string())
        .unwrap_or_default();
    let detection_content = json_str(data, "detectionContent");

    Some(
        view! {
            <div class=block_class>
                <p class=text_class><strong>{label}</strong></p>
                {(!message.is_empty()).then(|| view! {
                    <p>{message.clone()}</p>
                })}
                {(sap_detected && sap_guidance.is_some()).then(|| view! {
                    <p class="text-muted">{sap_guidance.unwrap_or_default()}</p>
                })}
                {(!detection_file.is_empty()).then(|| view! {
                    <p class="text-muted">
                        <strong>"Detected in:"</strong>
                        " "
                        <code>
                            {if detection_line.is_empty() {
                                detection_file.clone()
                            } else {
                                format!("{} at line {}", detection_file, detection_line)
                            }}
                        </code>
                    </p>
                })}
                {(!detection_content.is_empty()).then(|| view! {
                    <p class="text-muted"><code>{detection_content}</code></p>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_asr_section(
    asr: &Value,
    involflt_version: &Value,
    involflt_kernel_version: &Value,
) -> Option<AnyView> {
    let has_asr = json_bool(asr, "detected");
    let has_involflt =
        json_bool(involflt_version, "found") || json_bool(involflt_kernel_version, "found");

    if !has_asr && !has_involflt {
        return None;
    }

    let message = json_str(asr, "message");
    let detection_file = json_str(asr, "detectionFile");
    let detection_line = asr
        .get("detectionLine")
        .and_then(|value| value.as_i64())
        .map(|value| value.to_string())
        .unwrap_or_default();
    let detection_content = json_str(asr, "detectionContent");
    let runtime_version = json_str(involflt_kernel_version, "version");
    let build_version = json_str(involflt_version, "version");
    let build_date = json_str(involflt_version, "buildDate");
    let filename = json_str(involflt_version, "filename");
    let loaded = json_bool(involflt_version, "loaded");

    Some(
        view! {
            <div class="subsection">
                <p class="text-info"><strong>"Azure Site Recovery"</strong></p>
                {(has_asr && !message.is_empty()).then(|| view! {
                    <p>{message}</p>
                })}
                {(has_asr && !detection_file.is_empty()).then(|| view! {
                    <p class="text-muted">
                        <strong>"Detected in:"</strong>
                        " "
                        <code>
                            {if detection_line.is_empty() {
                                detection_file.clone()
                            } else {
                                format!("{} at line {}", detection_file, detection_line)
                            }}
                        </code>
                    </p>
                })}
                {(has_asr && !detection_content.is_empty()).then(|| view! {
                    <p class="text-muted"><code>{detection_content}</code></p>
                })}

                {has_involflt.then(|| view! {
                    <div class="info-block">
                        <p><strong>"InMage Filter Driver (involflt):"</strong></p>
                        {json_bool(involflt_version, "found").then(|| view! {
                            <p>
                                <span class=if loaded {
                                    "badge badge-success"
                                } else {
                                    "badge badge-warning"
                                }>
                                    {if loaded { "Loaded" } else { "Not Loaded" }}
                                </span>
                            </p>
                        })}
                        {(!runtime_version.is_empty()).then(|| view! {
                            <p>
                                <strong>"Runtime Version:"</strong>
                                " "
                                <code>{runtime_version}</code>
                            </p>
                        })}
                        {(!build_version.is_empty()).then(|| view! {
                            <p>
                                <strong>"Build Version:"</strong>
                                " "
                                <code>{build_version}</code>
                            </p>
                        })}
                        {(!build_date.is_empty()).then(|| view! {
                            <p>
                                <strong>"Build Date:"</strong>
                                " "
                                <code>{build_date}</code>
                            </p>
                        })}
                        {(!filename.is_empty()).then(|| view! {
                            <p class="text-muted">
                                <strong>"Location:"</strong>
                                " "
                                <code>{filename}</code>
                            </p>
                        })}
                    </div>
                })}
            </div>
        }
        .into_any(),
    )
}

fn detect_sap_workload(data: &Value) -> bool {
    let basic_environment = data.get("basicEnvironment").cloned().unwrap_or(Value::Null);

    if json_bool(&basic_environment, "sapProductDetected")
        || json_str(&basic_environment, "product")
            .to_ascii_lowercase()
            .contains("sap")
        || json_str(&basic_environment, "prettyName")
            .to_ascii_lowercase()
            .contains("sap")
        || json_str(&basic_environment, "name")
            .to_ascii_lowercase()
            .contains("sap")
        || json_bool(
            &data
                .get("sapInstanceConfig")
                .cloned()
                .unwrap_or(Value::Null),
            "found",
        )
    {
        return true;
    }

    let path_match = |path: &str| {
        let lower = path.to_ascii_lowercase();
        lower.contains("usr/sap")
            || lower.contains("sapmnt")
            || lower.contains("hana/shared")
            || lower.contains("hana/data")
            || lower.contains("hana/log")
            || lower.contains("sapstartsrv")
    };

    if json_array(data, "directories")
        .iter()
        .filter_map(value_name)
        .any(|entry| path_match(&entry))
        || json_array(data, "files")
            .iter()
            .filter_map(value_name)
            .any(|entry| path_match(&entry))
    {
        return true;
    }

    let pacemaker = data
        .get("pacemakerResources")
        .cloned()
        .unwrap_or(Value::Null);
    if json_array(&pacemaker, "resources").iter().any(|resource| {
        let haystack = format!(
            "{} {} {}",
            json_str(resource, "name").to_ascii_lowercase(),
            json_str(resource, "type").to_ascii_lowercase(),
            json_str(resource, "provider").to_ascii_lowercase(),
        );
        haystack.contains("sap") || haystack.contains("hana") || haystack.contains("hdb")
    }) {
        return true;
    }

    !collect_packages(
        &data.get("distroPackages").cloned().unwrap_or(Value::Null),
        &["sap", "hana", "hdb", "saptune"],
    )
    .is_empty()
}

fn value_name(value: &Value) -> Option<String> {
    value.as_str().map(|name| name.to_string()).or_else(|| {
        value
            .get("name")
            .and_then(|name| name.as_str())
            .map(|name| name.to_string())
    })
}

fn collect_packages(packages_value: &Value, patterns: &[&str]) -> Vec<String> {
    packages_value
        .get("packages")
        .and_then(|packages| packages.as_object())
        .map(|packages| {
            packages
                .iter()
                .filter_map(|(name, version)| {
                    let lower_name = name.to_ascii_lowercase();
                    if patterns.iter().any(|pattern| lower_name.contains(pattern)) {
                        let version = version.as_str().unwrap_or("");
                        if version.is_empty() {
                            Some(name.clone())
                        } else {
                            Some(format!("{name}-{version}"))
                        }
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn string_array(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(|items| items.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(|s| s.to_string()))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}
