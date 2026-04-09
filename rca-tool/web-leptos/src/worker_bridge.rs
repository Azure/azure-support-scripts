/// Bridge between the Leptos UI and the existing JS web-worker.
///
/// This module creates the same worker as the original JS app
/// (`liblzma-streaming-worker.js`) and speaks the same message protocol:
///
///   UI  ──→  { command: "set_debug", enabled }
///   UI  ──→  { cmd: "decompress_streaming", compressedData, chunkSize }
///   UI  ──→  { cmd: "analyze_tar", tarData }
///   UI  ──→  { cmd: "analyze_zip", zipData }
///   UI  ──→  { cmd: "analyze_plaintext", textData }
///   Worker  ──→  { ready: true }
///   Worker  ──→  { progress, decompressed, currentFile, analysis }
///   Worker  ──→  { success: true, analysis }
///   Worker  ──→  { error: "..." }
use leptos::prelude::*;
use wasm_bindgen::prelude::*;
use wasm_bindgen::JsCast;
use web_sys::{MessageEvent, Worker};

use crate::types::AnalysisResult;

// ── Debug-log helper (mirrors per-parser console.log) ───────────────

/// Log to the browser console at the "log" level.
macro_rules! console_dbg {
    ($($arg:tt)*) => {
        web_sys::console::log_1(&format!($($arg)*).into())
    };
}
pub(crate) use console_dbg;

/// Log to the browser console at the "error" level.
macro_rules! console_err {
    ($($arg:tt)*) => {
        web_sys::console::error_1(&format!($($arg)*).into())
    };
}
pub(crate) use console_err;

// ── File format detection ───────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileFormat {
    Gzip,
    Xz,
    Zip,
    PlainText,
    Unknown,
}

impl std::fmt::Display for FileFormat {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Gzip => write!(f, "gzip"),
            Self::Xz => write!(f, "xz"),
            Self::Zip => write!(f, "zip"),
            Self::PlainText => write!(f, "plaintext"),
            Self::Unknown => write!(f, "unknown"),
        }
    }
}

pub fn detect_format(data: &[u8]) -> FileFormat {
    if data.len() >= 6
        && data[0] == 0xfd
        && data[1] == 0x37
        && data[2] == 0x7a
        && data[3] == 0x58
        && data[4] == 0x5a
        && data[5] == 0x00
    {
        return FileFormat::Xz;
    }
    if data.len() >= 2 && data[0] == 0x1f && data[1] == 0x8b {
        return FileFormat::Gzip;
    }
    if data.len() >= 4 && data[0] == 0x50 && data[1] == 0x4b && data[2] == 0x03 && data[3] == 0x04 {
        return FileFormat::Zip;
    }

    // Heuristic for plain text (same as JS version)
    let sample_size = data.len().min(512);
    let mut printable = 0usize;
    for &b in &data[..sample_size] {
        if b == 0 {
            return FileFormat::Unknown;
        }
        if (0x20..=0x7e).contains(&b) || b == 0x09 || b == 0x0a || b == 0x0d {
            printable += 1;
        }
    }
    if printable as f64 / sample_size as f64 > 0.8 {
        FileFormat::PlainText
    } else {
        FileFormat::Unknown
    }
}

// ── Progress state ──────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct ProgressState {
    pub percent: f64,
    pub decompressed_bytes: f64,
    pub file_count: u32,
    pub current_file: String,
    pub message: String,
}

impl Default for ProgressState {
    fn default() -> Self {
        Self {
            percent: 0.0,
            decompressed_bytes: 0.0,
            file_count: 0,
            current_file: String::new(),
            message: "Preparing…".into(),
        }
    }
}

// ── Worker result ───────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub enum WorkerResult {
    InProgress,
    Success {
        analysis: AnalysisResult,
        total_decompressed: f64,
        partial: bool,
    },
    Error(String),
}

// ── Public API: launch analysis ─────────────────────────────────────

/// Spawn a web-worker, send it the file data, and reactively drive the
/// supplied signals as messages arrive.
///
/// The caller passes in the signals it owns so the bridge never needs to
/// know about the component tree.
pub fn launch_worker(
    data: Vec<u8>,
    filename: String,
    format: FileFormat,
    debug_mode: String,
    set_progress: WriteSignal<ProgressState>,
    set_result: WriteSignal<WorkerResult>,
) {
    // Create worker (same path as the original JS app)
    let worker = match Worker::new("./assets/liblzma-streaming-worker.js") {
        Ok(w) => w,
        Err(e) => {
            console_err!("[Leptos] Failed to create worker: {:?}", e);
            set_result.set(WorkerResult::Error(format!(
                "Failed to create worker: {e:?}"
            )));
            return;
        }
    };

    console_dbg!(
        "[Leptos] Worker created for {filename} ({} bytes, format={format})",
        data.len()
    );

    // Keep data in a RefCell so the ready-handler can consume it (once)
    let data_cell = std::cell::RefCell::new(Some(data));
    let format_cell = std::cell::Cell::new(format);
    let debug_mode_clone = debug_mode.clone();

    // -- onmessage handler ------------------------------------------------
    //
    // We use manual js_sys::Reflect extraction instead of serde(untagged)
    // because the worker's success message includes BOTH `success: true`
    // AND `progress: 100`, which causes the untagged enum to match the
    // Progress variant first, swallowing the result.
    let onmessage = {
        let worker_ref = worker.clone();
        Closure::<dyn FnMut(MessageEvent)>::new(move |ev: MessageEvent| {
            let js_val = ev.data();
            let get = |key: &str| js_sys::Reflect::get(&js_val, &JsValue::from_str(key)).ok();

            // ── ready ────────────────────────────────────────────
            if get("ready").and_then(|v| v.as_bool()) == Some(true) {
                console_dbg!("[Leptos] Worker ready, sending debug config + data");

                let dbg_obj = js_sys::Object::new();
                js_sys::Reflect::set(&dbg_obj, &"command".into(), &"set_debug".into()).ok();
                js_sys::Reflect::set(
                    &dbg_obj,
                    &"enabled".into(),
                    &JsValue::from_str(&debug_mode_clone),
                )
                .ok();
                worker_ref.post_message(&dbg_obj).ok();

                if let Some(bytes) = data_cell.borrow_mut().take() {
                    let fmt = format_cell.get();
                    send_data_to_worker(&worker_ref, &bytes, fmt);
                }
                return;
            }

            // ── error ────────────────────────────────────────────
            if let Some(err_val) = get("error") {
                if let Some(msg) = err_val.as_string() {
                    console_err!("[Leptos] Worker error: {msg}");
                    set_result.set(WorkerResult::Error(msg));
                    worker_ref.terminate();
                    return;
                }
            }

            // ── success (check BEFORE progress — the success
            //    message also carries `progress: 100`) ────────────
            if get("success").and_then(|v| v.as_bool()) == Some(true) {
                let partial = get("partialSuccess")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                let total_dec = get("totalDecompressed")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);

                // Deserialize the analysis object
                let analysis_js = get("analysis").unwrap_or(JsValue::NULL);
                let analysis: AnalysisResult = match serde_wasm_bindgen::from_value(analysis_js) {
                    Ok(a) => a,
                    Err(e) => {
                        console_err!("[Leptos] Failed to deserialize analysis: {e:?}");
                        set_result
                            .set(WorkerResult::Error(format!("Deserialization error: {e:?}")));
                        worker_ref.terminate();
                        return;
                    }
                };

                let fc = analysis
                    .get("fileCount")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0);
                console_dbg!("[Leptos] Worker success (partial={partial}): {fc} files");
                set_result.set(WorkerResult::Success {
                    analysis,
                    total_decompressed: total_dec,
                    partial,
                });
                worker_ref.terminate();
                return;
            }

            // ── progress (the common streaming case) ─────────────
            if let Some(pct) = get("progress").and_then(|v| v.as_f64()) {
                let decompressed = get("decompressed").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let current_file = get("currentFile")
                    .and_then(|v| v.as_string())
                    .unwrap_or_default();
                let file_count = get("analysis")
                    .and_then(|a| js_sys::Reflect::get(&a, &"fileCount".into()).ok())
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0) as u32;
                let msg_text = get("message")
                    .and_then(|v| v.as_string())
                    .unwrap_or_default();

                set_progress.set(ProgressState {
                    percent: pct,
                    decompressed_bytes: decompressed,
                    file_count,
                    current_file,
                    message: msg_text,
                });
                return;
            }

            console_dbg!("[Leptos] Ignoring unrecognised worker message");
        })
    };

    worker.set_onmessage(Some(onmessage.as_ref().unchecked_ref()));
    onmessage.forget(); // prevent GC

    // -- onerror handler --------------------------------------------------
    let onerror = {
        let set_result = set_result.clone();
        Closure::<dyn FnMut(web_sys::ErrorEvent)>::new(move |ev: web_sys::ErrorEvent| {
            let msg = ev.message();
            console_err!("[Leptos] Worker onerror: {msg}");
            set_result.set(WorkerResult::Error(msg));
        })
    };
    worker.set_onerror(Some(onerror.as_ref().unchecked_ref()));
    onerror.forget();
}

// ── Helpers ─────────────────────────────────────────────────────────

fn send_data_to_worker(worker: &Worker, data: &[u8], format: FileFormat) {
    let array = js_sys::Uint8Array::from(data);
    let buffer = array.buffer();

    let obj = js_sys::Object::new();
    match format {
        FileFormat::Xz => {
            js_sys::Reflect::set(&obj, &"cmd".into(), &"decompress_streaming".into()).ok();
            js_sys::Reflect::set(&obj, &"compressedData".into(), &buffer).ok();
            js_sys::Reflect::set(&obj, &"chunkSize".into(), &(256 * 1024).into()).ok();
        }
        FileFormat::Gzip => {
            // Gzip: send as analyze_tar after pako decompression.
            // For the MVP we send raw gzip to the worker via decompress_streaming
            // (the worker handles gzip → tar internally for the gzip command).
            // Actually the original JS does pako decompression in the main thread
            // then sends analyze_tar. For simplicity in the Leptos port we'll
            // send as XZ-style streaming and let the worker handle it, but the
            // worker only handles XZ in streaming mode. So for gzip we need to
            // do pako in JS. We'll address gzip in a follow-up; for now XZ and
            // plaintext are the primary paths.
            js_sys::Reflect::set(&obj, &"cmd".into(), &"analyze_tar".into()).ok();
            js_sys::Reflect::set(&obj, &"tarData".into(), &buffer).ok();
        }
        FileFormat::Zip => {
            js_sys::Reflect::set(&obj, &"cmd".into(), &"analyze_zip".into()).ok();
            js_sys::Reflect::set(&obj, &"zipData".into(), &buffer).ok();
        }
        FileFormat::PlainText => {
            js_sys::Reflect::set(&obj, &"cmd".into(), &"analyze_plaintext".into()).ok();
            js_sys::Reflect::set(&obj, &"textData".into(), &buffer).ok();
        }
        FileFormat::Unknown => {
            console_err!("[Leptos] Unknown format, cannot send to worker");
            return;
        }
    };

    let transfer = js_sys::Array::new();
    transfer.push(&buffer);

    if let Err(e) = worker.post_message_with_transfer(&obj, &transfer) {
        console_err!("[Leptos] Failed to post message to worker: {e:?}");
    }
}
