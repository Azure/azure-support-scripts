mod components;
mod types;
mod worker_bridge;

use leptos::prelude::*;
use web_sys::DragEvent;

use components::analysis_view::AnalysisView;
use components::drop_zone::{handle_file_list, DropZone};
use components::progress_bar::ProgressBar;
use components::theme_toggle::{Theme, ThemeToggle};
use worker_bridge::{console_dbg, FileFormat, ProgressState, WorkerResult};

fn main() {
    // Initialise console_log so `log::info!()` etc. go to the browser console
    console_log::init_with_level(log::Level::Debug).ok();
    console_dbg!("[Leptos] Mounting app");

    leptos::mount::mount_to_body(App);
}

#[component]
fn App() -> impl IntoView {
    // ── Theme ───────────────────────────────────────────────────────

    let (theme, set_theme) = signal(Theme::from_storage());

    // Apply theme class to <body>
    Effect::new(move || {
        let doc = web_sys::window().unwrap().document().unwrap();
        let body = doc.body().unwrap();
        body.set_class_name(theme.get().class_name());
    });

    // ── Debug mode (toggle mirrors original "?debug" query param) ───

    let debug_mode = {
        let loc = web_sys::window().unwrap().location();
        let search = loc.search().unwrap_or_default();
        if search.contains("debug") {
            "true"
        } else {
            "false"
        }
    };

    // ── Worker signals ──────────────────────────────────────────────

    let (progress, set_progress) = signal(ProgressState::default());
    let (result, set_result) = signal(WorkerResult::InProgress);
    let (analysing, set_analysing) = signal(false);
    let (filename, set_filename) = signal(String::new());
    let (page_dragging, set_page_dragging) = signal(false);
    let (drag_depth, set_drag_depth) = signal(0_u32);

    // ── File callback ───────────────────────────────────────────────

    let on_file = {
        let debug_mode = debug_mode.to_string();
        Callback::new(move |(name, buffer, fmt): (String, js_sys::ArrayBuffer, FileFormat)| {
            console_dbg!(
                "[Leptos] File received: {name} ({} bytes, {fmt})",
                buffer.byte_length()
            );

            if fmt == FileFormat::Unknown {
                set_result.set(WorkerResult::Error(format!(
                    "Unsupported file format for \"{name}\""
                )));
                return;
            }

            set_filename.set(name.clone());
            set_analysing.set(true);
            set_progress.set(ProgressState::default());
            set_result.set(WorkerResult::InProgress);

            worker_bridge::launch_worker(
                buffer,
                name,
                fmt,
                debug_mode.clone(),
                set_progress,
                set_result,
            );
        })
    };

    let on_page_dragenter = move |ev: DragEvent| {
        ev.prevent_default();
        let next = drag_depth.get_untracked().saturating_add(1);
        set_drag_depth.set(next);
        set_page_dragging.set(true);
    };

    let on_page_dragover = move |ev: DragEvent| {
        ev.prevent_default();
        set_page_dragging.set(true);
    };

    let on_page_dragleave = move |ev: DragEvent| {
        ev.prevent_default();
        let next = drag_depth.get_untracked().saturating_sub(1);
        set_drag_depth.set(next);
        if next == 0 {
            set_page_dragging.set(false);
        }
    };

    let on_page_drop = {
        let on_file = on_file.clone();
        move |ev: DragEvent| {
            ev.prevent_default();
            set_drag_depth.set(0);
            set_page_dragging.set(false);

            if let Some(files) = ev.data_transfer().and_then(|dt| dt.files()) {
                handle_file_list(files, on_file.clone());
            }
        }
    };

    // Derived: are we done?
    let is_done = move || !matches!(result.get(), WorkerResult::InProgress);

    view! {
        <div
            class=move || {
                if page_dragging.get() {
                    "page-drop-target page-drop-target--active"
                } else {
                    "page-drop-target"
                }
            }
            on:dragenter=on_page_dragenter
            on:dragover=on_page_dragover
            on:dragleave=on_page_dragleave
            on:drop=on_page_drop
        >
            <div class="container">
                <header class="header">
                    <h1>"RCA Tool"</h1>
                    <ThemeToggle theme=theme set_theme=set_theme/>
                </header>

                <main class="main-content">
                    // Show drop-zone when idle
                    {move || {
                        if !analysing.get() {
                            Some(view! { <DropZone on_file=on_file.clone() dragging=page_dragging/> })
                        } else {
                            None
                        }
                    }}

                    <div id="output" role="region" aria-live="polite" aria-label="Analysis results" tabindex="-1">
                        // Show progress while analysing
                        {move || {
                            if analysing.get() && !is_done() {
                                Some(view! {
                                    <div class="analysis-header">
                                        <h2>"Analysing " <code>{filename.get()}</code> " …"</h2>
                                    </div>
                                    <ProgressBar progress=progress/>
                                })
                            } else {
                                None
                            }
                        }}

                        // Show results or error
                        {move || {
                            if is_done() {
                                Some(view! {
                                    <div class="analysis-header">
                                        <h2>{filename.get()}</h2>
                                        <button
                                            class="btn btn-secondary"
                                            on:click=move |_| {
                                                set_analysing.set(false);
                                                set_result.set(WorkerResult::InProgress);
                                            }
                                        >
                                            "Analyse another file"
                                        </button>
                                    </div>
                                    <AnalysisView result=result/>
                                })
                            } else {
                                None
                            }
                        }}
                    </div>
                </main>

                <footer class="footer">
                    <p>"RCA Tool — Leptos 0.8 CSR • Pure WASM, no server required"</p>
                </footer>
            </div>
        </div>
    }
}
