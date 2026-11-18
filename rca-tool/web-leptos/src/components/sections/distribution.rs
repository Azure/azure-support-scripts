use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section 8 – Distribution (RHUI, FIPS, Leapp, Packages).
#[component]
pub fn DistributionSection(data: Value) -> impl IntoView {
    let rhui = data.get("rhuiConfig").cloned().unwrap_or(Value::Null);
    let eus = data.get("eusVersionLock").cloned().unwrap_or(Value::Null);
    let rhel_rhui = data.get("rhelRhuiCheck").cloned().unwrap_or(Value::Null);
    let crypto = data.get("cryptoPolicies").cloned().unwrap_or(Value::Null);
    let rhui_err = data.get("rhuiErrors").cloned().unwrap_or(Value::Null);
    let fips_setup = data.get("fipsModeSetup").cloned().unwrap_or(Value::Null);
    let kcmd = data.get("kernelCmdline").cloned().unwrap_or(Value::Null);
    let ktune = data.get("kernelTuning").cloned().unwrap_or(Value::Null);
    let waagent = data.get("waagentConfig").cloned().unwrap_or(Value::Null);
    let distro_pkgs = data.get("distroPackages").cloned().unwrap_or(Value::Null);
    let leapp_report = data.get("leappReport").cloned().unwrap_or(Value::Null);
    let leapp_log = data.get("leappLog").cloned().unwrap_or(Value::Null);

    let has_rhui = json_bool(&rhui, "found")
        || json_bool(&eus, "found")
        || json_bool(&rhel_rhui, "found")
        || json_bool(&crypto, "found")
        || json_bool(&rhui_err, "found");
    let has_fips = json_bool(&fips_setup, "found")
        || json_bool(&kcmd, "found")
        || (json_bool(&ktune, "found") && ktune.get("fipsEnabled").is_some())
        || json_bool(&crypto, "found");
    let has_leapp = json_bool(&leapp_report, "found") || json_bool(&leapp_log, "found");
    let has_pkgs = json_bool(&distro_pkgs, "found");

    if !has_rhui && !has_fips && !has_leapp && !has_pkgs {
        return view! {}.into_any();
    }

    let warnings = collect_warnings(&[
        &rhui,
        &eus,
        &rhel_rhui,
        &crypto,
        &rhui_err,
        &leapp_report,
        &leapp_log,
    ]);
    let section_class = if warnings.is_empty() {
        "content-details"
    } else {
        "warning-block"
    };

    view! {
        <Section title="Distribution" class=section_class open=true>
            {has_rhui.then(|| render_rhui_section(&rhui, &eus, &rhel_rhui, &crypto, &rhui_err, warnings.clone()))}
            {has_fips.then(|| render_fips_section(&fips_setup, &kcmd, &ktune, &crypto, &waagent, &distro_pkgs))}
            {has_leapp.then(|| render_leapp_section(&leapp_report, &leapp_log))}
            {has_pkgs.then(|| render_packages_section(&distro_pkgs))}
        </Section>
    }
    .into_any()
}

fn render_rhui_section(
    rhui: &Value,
    eus: &Value,
    rhel_rhui: &Value,
    crypto: &Value,
    rhui_err: &Value,
    warnings: Vec<Value>,
) -> AnyView {
    let rhui = rhui.clone();
    let eus = eus.clone();
    let rhel_rhui = rhel_rhui.clone();
    let crypto = crypto.clone();
    let rhui_err = rhui_err.clone();

    let repo_values = json_array(&rhui, "repos");
    let repo_list = repo_values
        .iter()
        .filter(|repo| json_bool(repo, "isMicrosoft") || json_bool(repo, "isEus"))
        .cloned()
        .collect::<Vec<_>>();
    let enabled_repo_count = repo_list
        .iter()
        .filter(|repo| json_bool(repo, "enabled"))
        .count();

    let connectivity =
        if json_bool(&rhui_err, "hasCertExpiration") || json_bool(&rhui_err, "hasHttp403") {
            "Certificate Issue Detected"
        } else if json_bool(&rhui_err, "hasHttp400") {
            "EUS Version Issue Detected"
        } else if json_bool(&rhui_err, "hasConnectionError") {
            "Connection Error"
        } else {
            "Issues Detected"
        };
    let rhui_found = json_bool(&rhui_err, "found");

    view! {
        <details class="content-details" open=true>
            <summary>"RHUI Configuration"</summary>
            <div class="section-body">
                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p class="text-warning"><strong>{format!("RHUI Warnings ({}):", warnings.len())}</strong></p>
                        <ul>
                            {warnings
                                .into_iter()
                                .map(|warning| {
                                    let warning_type = json_str(&warning, "type");
                                    let message = json_str(&warning, "message");
                                    let recommendation = json_str(&warning, "recommendation");
                                    let docs = json_str(&warning, "documentationUrl");
                                    view! {
                                        <li>
                                            <strong>{if warning_type.is_empty() { "warning".to_string() } else { warning_type }}</strong>
                                            ": "
                                            {message}
                                            {(!recommendation.is_empty()).then(|| view! {
                                                <div class="text-muted">{format!("Recommendation: {recommendation}")}</div>
                                            })}
                                            {(!docs.is_empty()).then(|| view! {
                                                <div>
                                                    <a href=docs.clone() target="_blank" rel="noopener noreferrer" class="text-info">"[docs]"</a>
                                                </div>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                <KvTable>
                    {json_bool(&rhel_rhui, "found").then(|| {
                        let has_pkg = json_bool(&rhel_rhui, "hasRhuiPackage");
                        let packages = string_array_from_key(&rhel_rhui, "rhuiPackages");
                        let rhui_type = json_str(&rhel_rhui, "rhuiType");
                        let value = if has_pkg {
                            if rhui_type.is_empty() {
                                packages.join(", ")
                            } else {
                                format!("{} ({})", packages.join(", "), rhui_type)
                            }
                        } else {
                            "Not found".to_string()
                        };
                        let class = if has_pkg {
                            "text-success".to_string()
                        } else {
                            "text-danger".to_string()
                        };
                        view! { <KvRow label="RHUI Package" value=value class=class/> }
                    })}
                    {json_bool(&eus, "found").then(|| {
                        let value = if json_bool(&eus, "hasReleaseverFile") {
                            let releasever = json_str(&eus, "releasever");
                            let source = json_str(&eus, "source");
                            if source.is_empty() {
                                releasever
                            } else {
                                format!("{} (from {})", releasever, source)
                            }
                        } else {
                            "Not locked".to_string()
                        };
                        view! { <KvRow label="EUS Version Lock" value=value/> }
                    })}
                    {json_bool(&crypto, "found").then(|| {
                        let policy = json_str(&crypto, "policy");
                        let is_default = crypto
                            .get("isDefault")
                            .and_then(|value| value.as_bool())
                            .unwrap_or(false);
                        let value = if policy.is_empty() {
                            "-".to_string()
                        } else if is_default {
                            policy
                        } else {
                            format!("{} (non-default)", policy)
                        };
                        let class = if is_default {
                            "text-success".to_string()
                        } else {
                            "text-warning".to_string()
                        };
                        view! { <KvRow label="Crypto Policy" value=value class=class/> }
                    })}
                    {rhui_found.then(|| {
                        let class = if connectivity.contains("Certificate") {
                            "text-danger".to_string()
                        } else {
                            "text-warning".to_string()
                        };
                        view! { <KvRow label="RHUI Connectivity" value=connectivity.to_string() class=class/> }
                    })}
                </KvTable>

                {(!repo_list.is_empty()).then(|| view! {
                    <div class="subsection">
                        <p><strong>"RHUI Repositories:"</strong> <span class="text-muted">{format!("({} enabled)", enabled_repo_count)}</span></p>
                        <ul>
                            {repo_list
                                .into_iter()
                                .map(|repo| {
                                    let name = json_str(&repo, "name");
                                    let enabled = json_bool(&repo, "enabled");
                                    let is_eus = json_bool(&repo, "isEus");
                                    let status = if enabled { "enabled" } else { "disabled" };
                                    let class = if enabled { "text-success" } else { "text-muted" };
                                    view! {
                                        <li>
                                            <code>{name}</code>
                                            {is_eus.then(|| view! { <span class="text-info">" [EUS]"</span> })}
                                            " - "
                                            <span class=class>{status}</span>
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {render_rhui_errors(&rhui_err)}
            </div>
        </details>
    }
    .into_any()
}

fn render_rhui_errors(rhui_err: &Value) -> Option<AnyView> {
    if !json_bool(rhui_err, "found") {
        return None;
    }

    let errors = json_array(rhui_err, "errors");
    let affected_repos = string_array_from_key(rhui_err, "affectedRepos");
    let has_errors = !errors.is_empty();
    let has_samples = errors.iter().any(|err| !json_str(err, "sample").is_empty());
    let errors_for_list = errors.clone();
    let errors_for_samples = errors.clone();

    Some(
        view! {
            <div class="subsection">
                {has_errors.then(|| view! {
                    <>
                        <p><strong>"Errors Found:"</strong></p>
                        <ul>
                            {errors_for_list
                                .iter()
                                .map(|err| {
                                    let repo = json_str(err, "repo");
                                    let message = json_str(err, "message");
                                    let kind = json_str(err, "type");
                                    let class = if kind == "certificate_expired" || kind == "http_403" {
                                        "text-danger"
                                    } else {
                                        "text-warning"
                                    };
                                    view! {
                                        <li>
                                            {(!repo.is_empty()).then(|| view! { <code>{format!("{}: ", repo)}</code> })}
                                            <span class=class>{message}</span>
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </>
                })}

                {has_samples.then(|| view! {
                    <details class="content-details">
                        <summary>"View Raw Log Details"</summary>
                        <ul>
                            {errors_for_samples
                                .clone()
                                .into_iter()
                                .filter_map(|err| {
                                    let sample = json_str(&err, "sample");
                                    if sample.is_empty() {
                                        None
                                    } else {
                                        Some(view! { <li><code>{sample}</code></li> })
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </details>
                })}

                {(!has_errors && !affected_repos.is_empty()).then(|| view! {
                    <>
                        <p><strong>"Affected Repositories:"</strong></p>
                        <ul>
                            {affected_repos
                                .into_iter()
                                .map(|repo| view! { <li><code>{repo}</code></li> })
                                .collect::<Vec<_>>()}
                        </ul>
                    </>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_fips_section(
    fips_setup: &Value,
    kcmd: &Value,
    ktune: &Value,
    crypto: &Value,
    waagent: &Value,
    distro_pkgs: &Value,
) -> AnyView {
    let fips_rows = build_fips_rows(fips_setup, kcmd, ktune, crypto, waagent, distro_pkgs);
    let mut present_signals: Vec<bool> = Vec::new();

    if json_bool(fips_setup, "found") {
        present_signals.push(
            fips_setup
                .get("fipsEnabled")
                .and_then(|value| value.as_bool())
                .unwrap_or(false),
        );
    }
    if json_bool(kcmd, "found") {
        present_signals.push(
            kcmd.get("fipsEnabled")
                .and_then(|value| value.as_bool())
                .unwrap_or(false),
        );
    }
    if let Some(enabled) = ktune.get("fipsEnabled").and_then(|value| value.as_bool()) {
        present_signals.push(enabled);
    }
    if json_bool(crypto, "found") {
        present_signals.push(json_str(crypto, "policy").to_ascii_uppercase().contains("FIPS"));
    }
    if json_bool(waagent, "found") {
        let waagent_enabled = matches!(
            waagent
                .get("summary")
                .and_then(|summary| summary.get("enableFIPS"))
                .map(value_to_inline_string)
                .unwrap_or_default()
                .to_ascii_lowercase()
                .as_str(),
            "y" | "yes" | "true"
        );
        present_signals.push(waagent_enabled);
    }
    let has_dracut = json_array(distro_pkgs, "fipsPackages").iter().any(|pkg| {
        let name = json_str(pkg, "name");
        name == "dracut-fips" || name.starts_with("dracut-fips-")
    }) || json_bool(distro_pkgs, "hasDracutFips");
    if has_dracut {
        present_signals.push(true);
    }

    let has_enabled = present_signals.iter().any(|flag| *flag);
    let has_disabled = present_signals.iter().any(|flag| !*flag);
    let inconsistent = json_bool(fips_setup, "inconsistentState") || (has_enabled && has_disabled);
    let overall_enabled = has_enabled && !has_disabled && !inconsistent;

    view! {
        <details class="content-details" open=true>
            <summary>
                "FIPS Status"
                {overall_enabled.then(|| view! { <span class="badge badge-success">"ENABLED"</span> })}
                {inconsistent.then(|| view! { <span class="badge badge-warning">"inconsistent"</span> })}
            </summary>
            {inconsistent.then(|| view! {
                <div class="warning-block">
                    <p><strong>"Inconsistent FIPS state"</strong></p>
                    <p>
                        "Some indicators report FIPS enabled while others remain disabled or not set. "
                        <code>"fips-mode-setup --enable"</code>
                    </p>
                </div>
            })}
            <table class="data-table">
                <thead>
                    <tr>
                        <th>"Source"</th>
                        <th>"Indicator"</th>
                        <th>"Status"</th>
                    </tr>
                </thead>
                <tbody>{fips_rows}</tbody>
            </table>
            {(!json_str(kcmd, "rawCmdline").is_empty()).then(|| view! {
                <details class="content-details">
                    <summary>"Kernel Command Line"</summary>
                    <pre class="json-dump">{json_str(kcmd, "rawCmdline")}</pre>
                </details>
            })}
        </details>
    }
    .into_any()
}

fn render_leapp_section(leapp_report: &Value, leapp_log: &Value) -> AnyView {
    let has_report = json_bool(leapp_report, "found");
    let has_log = json_bool(leapp_log, "found");
    let upgrade_blocked = leapp_report
        .get("upgradeBlocked")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
        || leapp_log
            .get("hasErrors")
            .and_then(|value| value.as_bool())
            .unwrap_or(false);
    let has_high_risk = leapp_report
        .get("hasHighRisk")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let block_class = if upgrade_blocked {
        "danger-block"
    } else if has_high_risk {
        "warning-block"
    } else {
        "content-details"
    };

    let report_error_count = leapp_report
        .get("errorCount")
        .and_then(|value| value.as_u64())
        .unwrap_or(0);
    let log_error_count = leapp_log
        .get("errorCount")
        .and_then(|value| value.as_u64())
        .unwrap_or(0);
    let high_risk_count = leapp_report
        .get("highRiskCount")
        .and_then(|value| value.as_u64())
        .unwrap_or(0);

    view! {
        <details class=block_class open=true>
            <summary>"Leapp Upgrade Analysis"</summary>
            <div class="section-body">
                <p>
                    {if upgrade_blocked {
                        view! {
                            <span class="text-danger">
                                <strong>"Upgrade Blocked:"</strong>
                                " "
                                {format!("{} error(s) must be resolved", report_error_count + log_error_count)}
                            </span>
                        }
                        .into_any()
                    } else if has_high_risk {
                        view! {
                            <span class="text-warning">
                                <strong>"Review Required:"</strong>
                                " "
                                {format!("{} high-risk warning(s) detected", high_risk_count)}
                            </span>
                        }
                        .into_any()
                    } else {
                        view! {
                            <span class="text-success">
                                <strong>"Upgrade Ready:"</strong>
                                " No blocking issues found"
                            </span>
                        }
                        .into_any()
                    }}
                </p>

                {render_leapp_log_errors(leapp_log)}

                {has_report.then(|| view! {
                    <>
                        <p class="text-muted">
                            {format!(
                                "Report: {} issue(s) - {} error(s), {} high, {} medium, {} info",
                                leapp_report.get("totalIssues").and_then(|value| value.as_u64()).unwrap_or(0),
                                report_error_count,
                                high_risk_count,
                                leapp_report.get("mediumRiskCount").and_then(|value| value.as_u64()).unwrap_or(0),
                                leapp_report.get("infoCount").and_then(|value| value.as_u64()).unwrap_or(0),
                            )}
                        </p>

                        {render_issue_group("Errors (Upgrade Blockers)", &json_array(leapp_report, "errors"), "danger-block")}
                        {render_issue_group(
                            &format!("High Risk Warnings ({})", high_risk_count),
                            &json_array(leapp_report, "highRisk"),
                            "warning-block",
                        )}

                        {(!json_array(leapp_report, "thirdPartyPackages").is_empty()).then(|| view! {
                            <details class="content-details">
                                <summary>{format!("Third-Party Packages ({})", json_array(leapp_report, "thirdPartyPackages").len())}</summary>
                                <p class="text-muted">"These packages are not signed by Red Hat and may need manual handling:"</p>
                                <ul>
                                    {json_array(leapp_report, "thirdPartyPackages")
                                        .into_iter()
                                        .filter_map(|pkg| pkg.as_str().map(|value| value.to_string()))
                                        .map(|pkg| view! { <li><code>{pkg}</code></li> })
                                        .collect::<Vec<_>>()}
                                </ul>
                            </details>
                        })}

                        {(!json_array(leapp_report, "info").is_empty()).then(|| view! {
                            <details class="content-details">
                                <summary>{format!("Informational Notes ({})", json_array(leapp_report, "info").len())}</summary>
                                <ul>
                                    {json_array(leapp_report, "info")
                                        .into_iter()
                                        .map(|issue| view! { <li>{json_str(&issue, "title")}</li> })
                                        .collect::<Vec<_>>()}
                                </ul>
                            </details>
                        })}
                    </>
                })}

                {(has_log && !json_array(leapp_log, "curlErrors").is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Connection Errors from Log ({})", json_array(leapp_log, "curlErrors").len())}</summary>
                        <div class="section-body">
                            {json_array(leapp_log, "curlErrors")
                                .into_iter()
                                .map(|err| {
                                    let message = json_str(&err, "message");
                                    let curl_code = err.get("curlCode").map(value_to_inline_string).unwrap_or_default();
                                    let url = json_str(&err, "url");
                                    view! {
                                        <div class="subsection">
                                            <code>{format!("Curl error ({}) {}", curl_code, message)}</code>
                                            {(!url.is_empty()).then(|| view! { <p class="text-muted"><code>{url}</code></p> })}
                                        </div>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </div>
                    </details>
                })}

                <p>
                    <a
                        href="https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/upgrading_from_rhel_8_to_rhel_9/index"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="text-info"
                    >
                        "Leapp Upgrade Documentation"
                    </a>
                </p>
            </div>
        </details>
    }
    .into_any()
}

fn render_leapp_log_errors(leapp_log: &Value) -> Option<AnyView> {
    let dns_errors = json_array(leapp_log, "dnsErrors");
    let rhui_errors = json_array(leapp_log, "rhuiErrors");
    let has_dns_errors = !dns_errors.is_empty();
    let has_rhui_errors = !rhui_errors.is_empty();
    let dns_errors_for_view = dns_errors.clone();
    let rhui_errors_for_view = rhui_errors.clone();

    if !has_dns_errors && !has_rhui_errors {
        return None;
    }

    Some(
        view! {
            <>
                {has_dns_errors.then(|| view! {
                    <div class="danger-block">
                        <p><strong>"DNS Resolution Errors (Root Cause):"</strong></p>
                        {dns_errors_for_view
                            .clone()
                            .into_iter()
                            .map(|err| {
                                let curl_code = err.get("curlCode").map(value_to_inline_string).unwrap_or_default();
                                let message = json_str(&err, "message");
                                let host = json_str(&err, "host");
                                let url = json_str(&err, "url");
                                view! {
                                    <div class="subsection">
                                        <p><strong>{format!("Curl error ({}) {}", curl_code, message)}</strong></p>
                                        {(!host.is_empty()).then(|| view! { <p><code>{format!("Host: {}", host)}</code></p> })}
                                        {(!url.is_empty()).then(|| view! { <p class="text-muted"><code>{url}</code></p> })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </div>
                })}

                {(!has_dns_errors && has_rhui_errors).then(|| view! {
                    <div class="danger-block">
                        <p><strong>"RHUI Connection Errors:"</strong></p>
                        {rhui_errors_for_view
                            .clone()
                            .into_iter()
                            .map(|err| {
                                let curl_code = err.get("curlCode").map(value_to_inline_string).unwrap_or_default();
                                let message = json_str(&err, "message");
                                let url = json_str(&err, "url");
                                view! {
                                    <div class="subsection">
                                        <p><strong>{format!("Curl error ({}) {}", curl_code, message)}</strong></p>
                                        {(!url.is_empty()).then(|| view! { <p class="text-muted"><code>{url}</code></p> })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </div>
                })}
            </>
        }
        .into_any(),
    )
}

fn render_issue_group(title: &str, issues: &[Value], class_name: &'static str) -> Option<AnyView> {
    if issues.is_empty() {
        return None;
    }

    Some(
        view! {
            <details class="content-details">
                <summary>{title.to_string()}</summary>
                <div class="section-body">
                    {issues
                        .iter()
                        .cloned()
                        .map(|issue| {
                            let item_title = json_str(&issue, "title");
                            let summary = json_str(&issue, "summary");
                            let remediation = json_str(&issue, "remediation");
                            view! {
                                <div class=class_name>
                                    <p><strong>{item_title}</strong></p>
                                    {(!summary.is_empty()).then(|| view! { <p>{summary}</p> })}
                                    {(!remediation.is_empty()).then(|| view! { <p class="text-muted"><em>{format!("Remediation: {remediation}")}</em></p> })}
                                </div>
                            }
                        })
                        .collect::<Vec<_>>()}
                </div>
            </details>
        }
        .into_any(),
    )
}

fn render_packages_section(distro_pkgs: &Value) -> AnyView {
    let is_dpkg = distro_pkgs
        .get("isDpkg")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let is_rpm_based = distro_pkgs
        .get("isRpmRaw")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
        || !is_dpkg;
    let raw_content = json_str(distro_pkgs, "rawContent");
    let package_entries = distro_pkgs
        .get("packages")
        .and_then(|value| value.as_object())
        .map(|packages| {
            let mut items = packages
                .iter()
                .map(|(name, value)| {
                    let version = value
                        .as_str()
                        .map(|item| item.to_string())
                        .or_else(|| {
                            value
                                .get("version")
                                .and_then(|item| item.as_str())
                                .map(|item| item.to_string())
                        })
                        .unwrap_or_default();
                    (name.clone(), version)
                })
                .collect::<Vec<_>>();
            items.sort_by(|a, b| a.0.cmp(&b.0));
            items
        })
        .unwrap_or_default();
    let package_count = distro_pkgs
        .get("packageCount")
        .and_then(|value| value.as_u64())
        .unwrap_or_else(|| {
            if !raw_content.is_empty() {
                raw_content.lines().filter(|line| !line.trim().is_empty()).count() as u64
            } else {
                package_entries.len() as u64
            }
        });
    let fips_packages = json_array(distro_pkgs, "fipsPackages");
    let warning_entries = json_array(distro_pkgs, "warnings");
    let summary = if is_dpkg {
        format!("Packages ({package_count} Debian/Ubuntu)")
    } else if is_rpm_based {
        format!("Packages ({package_count} RPM-based)")
    } else {
        format!("Packages ({package_count})")
    };

    view! {
        <details class="content-details">
            <summary>{summary}</summary>
            <div class="section-body">
                {(!warning_entries.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Azure package validation warnings ({})", warning_entries.len())}</strong></p>
                        <ul>
                            {warning_entries
                                .into_iter()
                                .map(|warning| {
                                    let package = json_str(&warning, "package");
                                    let expected = json_str(&warning, "expected");
                                    let actual = json_str(&warning, "actual");
                                    let message = json_str(&warning, "message");
                                    let docs = json_str(&warning, "documentationUrl");
                                    let source_path = json_str(&warning, "sourcePath");
                                    let source_line = warning
                                        .get("sourceLine")
                                        .and_then(|value| value.as_u64())
                                        .unwrap_or(0);
                                    view! {
                                        <li class="text-warning">
                                            <strong>{package.clone()}</strong>
                                            {if message.is_empty() {
                                                format!(": expected {expected}, found {actual}")
                                            } else {
                                                format!(": {message}")
                                            }}
                                            {(!expected.is_empty() || !actual.is_empty()).then(|| view! {
                                                <div class="text-muted">{format!(
                                                    "Expected: {} • Actual: {}",
                                                    if expected.is_empty() { "-".to_string() } else { expected.clone() },
                                                    if actual.is_empty() { "-".to_string() } else { actual.clone() },
                                                )}</div>
                                            })}
                                            {(!source_path.is_empty()).then(|| view! {
                                                <div class="text-muted">{format!("Source: {}", source_path)}</div>
                                            })}
                                            {(source_line > 0).then(|| view! {
                                                <div class="text-muted">{format!("Line: {}", source_line)}</div>
                                            })}
                                            {(!docs.is_empty()).then(|| view! {
                                                <div>
                                                    <a href=docs.clone() target="_blank" rel="noopener noreferrer" class="text-info">"[docs]"</a>
                                                </div>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!raw_content.is_empty()).then(|| view! {
                    <details class="content-details" open=true>
                        <summary>{if is_dpkg {
                            format!("Raw package list ({package_count} entries)")
                        } else {
                            format!("Raw RPM package list ({package_count} entries)")
                        }}</summary>
                        <pre class="json-dump">{raw_content.clone()}</pre>
                    </details>
                })}

                {(!fips_packages.is_empty()).then(|| view! {
                    <div class="subsection">
                        <p><strong>"FIPS-related packages:"</strong></p>
                        <ul>
                            {fips_packages
                                .into_iter()
                                .map(|pkg| {
                                    let name = json_str(&pkg, "name");
                                    let version = json_str(&pkg, "version");
                                    view! {
                                        <li>
                                            <code>{name}</code>
                                            {(!version.is_empty()).then(|| view! { <span class="text-muted">{format!(" {}", version)}</span> })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!package_entries.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Validated package inventory ({})", package_entries.len())}</summary>
                        <ul>
                            {package_entries
                                .into_iter()
                                .map(|(name, version)| view! {
                                    <li>
                                        <code>{name}</code>
                                        {(!version.is_empty()).then(|| view! { <span class="text-muted">{format!(" {}", version)}</span> })}
                                    </li>
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </details>
                })}
            </div>
        </details>
    }
    .into_any()
}

fn build_fips_rows(
    fips_setup: &Value,
    kcmd: &Value,
    ktune: &Value,
    crypto: &Value,
    waagent: &Value,
    distro_pkgs: &Value,
) -> Vec<AnyView> {
    let mut rows: Vec<AnyView> = Vec::new();

    if json_bool(fips_setup, "found") {
        let enabled = fips_setup
            .get("fipsEnabled")
            .and_then(|value| value.as_bool())
            .unwrap_or(false);
        let text = if enabled {
            "Enabled".to_string()
        } else {
            "Disabled / Not set".to_string()
        };
        let class = if enabled {
            "text-success".to_string()
        } else {
            "text-muted".to_string()
        };
        rows.push(
            view! {
                <tr>
                    <td>"fips-mode-setup --check"</td>
                    <td>"FIPS mode check"</td>
                    <td class=class>{text}</td>
                </tr>
            }
            .into_any(),
        );
    }

    if json_bool(kcmd, "found") {
        let has_fips = kcmd
            .get("fipsEnabled")
            .and_then(|value| value.as_bool())
            .unwrap_or(false);
        let (text, class) = if has_fips {
            ("Enabled".to_string(), "text-success".to_string())
        } else {
            ("Disabled / Not set".to_string(), "text-muted".to_string())
        };
        rows.push(
            view! {
                <tr>
                    <td>"Kernel cmdline (fips=1)"</td>
                    <td>"Boot parameter"</td>
                    <td class=class>{text}</td>
                </tr>
            }
            .into_any(),
        );
    }

    if json_bool(ktune, "found") {
        if let Some(val) = ktune.get("fipsEnabled") {
            let enabled = val.as_bool().unwrap_or(false);
            let (text, class) = if enabled {
                ("Enabled".to_string(), "text-success".to_string())
            } else {
                ("Disabled / Not set".to_string(), "text-muted".to_string())
            };
            rows.push(
                view! {
                    <tr>
                        <td>"sysctl crypto.fips_enabled"</td>
                        <td>"Kernel state"</td>
                        <td class=class>{text}</td>
                    </tr>
                }
                .into_any(),
            );
        }
    }

    if json_bool(crypto, "found") {
        let policy = json_str(crypto, "policy");
        let is_fips = policy.to_uppercase().contains("FIPS");
        let class = if is_fips {
            "text-success".to_string()
        } else {
            "text-muted".to_string()
        };
        let display = if is_fips {
            "Enabled (FIPS)".to_string()
        } else if policy.is_empty() {
            "Disabled / Not set".to_string()
        } else {
            format!("Disabled / Not set ({policy})")
        };
        rows.push(
            view! {
                <tr>
                    <td>"Crypto policy"</td>
                    <td>"Current policy"</td>
                    <td class=class>{display}</td>
                </tr>
            }
            .into_any(),
        );
    }

    if json_bool(waagent, "found") {
        let summary = waagent.get("summary").unwrap_or(&Value::Null);
        let enable_fips = summary
            .get("enableFIPS")
            .map(value_to_inline_string)
            .unwrap_or_else(|| "n/a".to_string());
        let enabled = matches!(
            enable_fips.to_ascii_lowercase().as_str(),
            "y" | "yes" | "true"
        );
        let class = if enabled {
            "text-success".to_string()
        } else {
            "text-muted".to_string()
        };
        rows.push(
            view! {
                <tr>
                    <td>"waagent.conf OS.EnableFIPS"</td>
                    <td>"Azure agent setting"</td>
                    <td class=class>{if enabled { "Enabled".to_string() } else { "Disabled / Not set".to_string() }}</td>
                </tr>
            }
            .into_any(),
        );
    }

    if json_bool(distro_pkgs, "found") {
        let fips_pkgs = json_array(distro_pkgs, "fipsPackages");
        let has_dracut = fips_pkgs.iter().any(|pkg| {
            let name = json_str(pkg, "name");
            name == "dracut-fips" || name.starts_with("dracut-fips-")
        }) || json_bool(distro_pkgs, "hasDracutFips");
        if has_dracut {
            rows.push(
                view! {
                    <tr>
                        <td>"dracut-fips package"</td>
                        <td>"Installed package"</td>
                        <td class="text-success">"Enabled"</td>
                    </tr>
                }
                .into_any(),
            );
        }
    }

    rows
}

fn collect_warnings(values: &[&Value]) -> Vec<Value> {
    values
        .iter()
        .flat_map(|value| json_array(value, "warnings"))
        .collect::<Vec<_>>()
}

fn string_array_from_key(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(|items| items.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(|entry| entry.to_string()))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn value_to_inline_string(value: &Value) -> String {
    if let Some(text) = value.as_str() {
        text.to_string()
    } else if let Some(number) = value.as_i64() {
        number.to_string()
    } else if let Some(number) = value.as_u64() {
        number.to_string()
    } else if let Some(number) = value.as_f64() {
        if number.fract() == 0.0 {
            (number as i64).to_string()
        } else {
            format!("{number:.2}")
        }
    } else if let Some(boolean) = value.as_bool() {
        if boolean {
            "true".to_string()
        } else {
            "false".to_string()
        }
    } else {
        "".to_string()
    }
}
