use leptos::prelude::*;

use crate::worker_bridge::WorkerResult;

use super::sections::archive::ArchiveSection;
use super::sections::azure_vm::{
    AzureExtensionsSection, AzureVmSection, SecureBootSection, WaagentLogSection,
};
use super::sections::cluster::{ApplicationsSection, ClusterSection, SapInstanceSection};
use super::sections::deadlocks::DeadlocksSection;
use super::sections::distribution::DistributionSection;
use super::sections::events::EventsSection;
use super::sections::hana::HanaSection;
use super::sections::kernel::{KernelCrashSection, KernelSection};
use super::sections::merge_errors::MergeErrorsSection;
use super::sections::networking::NetworkingSection;
use super::sections::oom::OomSection;
use super::sections::os_tuning::OsTuningSection;
use super::sections::services::ServicesAntivirusSection;
use super::sections::storage::{InspectDiskSection, StorageSection};

fn format_bytes(bytes: f64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut value = bytes.max(0.0);
    let mut unit = 0usize;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{value:.0} {}", UNITS[unit])
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

/// Renders the full analysis once the worker is done.
#[component]
pub fn AnalysisView(result: ReadSignal<WorkerResult>) -> impl IntoView {
    move || match result.get() {
        WorkerResult::InProgress => view! {}.into_any(),

        WorkerResult::Error(msg) => view! {
            <div class="error-banner">
                <h2>"Analysis Error"</h2>
                <p>{msg}</p>
            </div>
        }
        .into_any(),

        WorkerResult::Success {
            analysis,
            total_decompressed,
            partial,
        } => {
            let json = analysis;

            let partial_banner = partial.then(|| {
                let msg = json
                    .get("corruptionMessage")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Archive may be partially corrupted.")
                    .to_string();
                let progress_summary = if total_decompressed > 0.0 {
                    format!(
                        "Processed {} of decompressed data before corruption was detected.",
                        format_bytes(total_decompressed)
                    )
                } else {
                    "Processed a partial amount of decompressed data before corruption was detected."
                        .to_string()
                };
                view! {
                    <div class="warning-banner">
                        <strong>"⚠ Partial Analysis — "</strong>{msg}
                        <div><small>{progress_summary}</small></div>
                    </div>
                }
            });

            view! {
                <div class="analysis-results">
                    {partial_banner}

                    // Sections in the same order as the original HTML
                    <AzureVmSection data=json.clone()/>
                    <SecureBootSection data=json.clone()/>
                    <WaagentLogSection data=json.clone()/>
                    <InspectDiskSection data=json.clone()/>
                    <ClusterSection data=json.clone()/>
                    <ApplicationsSection data=json.clone()/>
                    <SapInstanceSection data=json.clone()/>
                    <DistributionSection data=json.clone()/>
                    <EventsSection data=json.clone()/>
                    <KernelCrashSection data=json.clone()/>
                    <NetworkingSection data=json.clone()/>
                    <ServicesAntivirusSection data=json.clone()/>
                    <AzureExtensionsSection data=json.clone()/>
                    <KernelSection data=json.clone()/>
                    <OsTuningSection data=json.clone()/>
                    <StorageSection data=json.clone()/>
                    <HanaSection data=json.clone()/>
                    <DeadlocksSection data=json.clone()/>
                    <OomSection data=json.clone()/>
                    <MergeErrorsSection data=json.clone()/>
                    <ArchiveSection data=json.clone()/>
                </div>
            }
            .into_any()
        }
    }
}
