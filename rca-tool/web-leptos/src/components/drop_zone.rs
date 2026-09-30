use leptos::prelude::*;
use wasm_bindgen::prelude::*;
use wasm_bindgen::JsCast;
use web_sys::{Event, File, FileList, FileReader, HtmlInputElement};

use crate::worker_bridge::{console_dbg, detect_format, FileFormat};

/// Sniff the first bytes of an ArrayBuffer for format detection without
/// copying the entire file into wasm linear memory. We allocate at most
/// `SNIFF_BYTES` bytes inside wasm; the full ArrayBuffer stays in the JS
/// heap and is later transferred (zero-copy) to the worker.
const SNIFF_BYTES: u32 = 512;

fn detect_format_from_buffer(array_buf: &js_sys::ArrayBuffer) -> FileFormat {
    let total = array_buf.byte_length();
    let len = total.min(SNIFF_BYTES);
    let head = js_sys::Uint8Array::new_with_byte_offset_and_length(array_buf, 0, len);
    let mut buf = vec![0u8; len as usize];
    head.copy_to(&mut buf);
    detect_format(&buf)
}

fn read_file(file: File, on_file: Callback<(String, js_sys::ArrayBuffer, FileFormat)>) {
    let name = file.name();
    let reader = FileReader::new().unwrap();
    let reader_clone = reader.clone();

    let onload = Closure::<dyn FnMut(Event)>::new(move |_ev: Event| {
        let result = reader_clone.result().unwrap();
        let array_buf = result.dyn_into::<js_sys::ArrayBuffer>().unwrap();
        let fmt = detect_format_from_buffer(&array_buf);
        console_dbg!(
            "[Leptos] Loaded {} ({} bytes, format={fmt})",
            name,
            array_buf.byte_length()
        );
        on_file.run((name.clone(), array_buf, fmt));
    });

    reader.set_onload(Some(onload.as_ref().unchecked_ref()));
    onload.forget();
    reader.read_as_array_buffer(&file).unwrap();
}

pub fn handle_file_list(
    files: FileList,
    on_file: Callback<(String, js_sys::ArrayBuffer, FileFormat)>,
) -> bool {
    let count = files.length();

    if let Some(file) = files.item(0) {
        if count > 1 {
            console_dbg!(
                "[Leptos] {} files received; starting with the first one: {}",
                count,
                file.name()
            );
        }
        read_file(file, on_file);
        true
    } else {
        false
    }
}

/// File drop zone and file-input button.
///
/// When a file is loaded it calls `on_file` with `(filename, buffer, format)`.
/// `buffer` is a JS-heap `ArrayBuffer` that callers should transfer (not copy)
/// to a worker so that multi-GB files do not exhaust wasm linear memory.
#[component]
pub fn DropZone(
    #[prop(into)] on_file: Callback<(String, js_sys::ArrayBuffer, FileFormat)>,
    dragging: ReadSignal<bool>,
) -> impl IntoView {
    // -- file input change ------------------------------------------------

    let on_input_change = move |ev: Event| {
        let input: HtmlInputElement = ev.target().unwrap().dyn_into().unwrap();
        if let Some(files) = input.files() {
            handle_file_list(files, on_file.clone());
        }
    };

    view! {
        <div
            id="drop-zone"
            class=move || {
                if dragging.get() {
                    "drop-zone drop-zone--active"
                } else {
                    "drop-zone"
                }
            }
        >
            <h2>"Drag and Drop Support File"</h2>
            <p>
                "Choose a .tar.gz, .tar.xz, or .zip cluster file (hb_report, crm_report, supportconfig, or sosreport)"
            </p>
            <p>"Or a plain text console log file (.log)"</p>
            <p class="drop-zone__support-note">"Supports gzip, XZ, and ZIP compression"</p>
            <input
                id="file-input"
                type="file"
                accept=".txz,.tar.xz,.tar.gz,.tgz,.zip,.txt,.log"
                aria-label="Drag and drop support file (.tar.gz, .tar.xz, .zip, or .log)"
                on:change=on_input_change
                class="drop-zone__input"
            />
            <p id="detection-warning" class="detection-warning">
                "Detection is pattern-based and not exhaustive. Missing findings may reflect unimplemented detectors rather than absence of issues. Manual review of the source report (hb_report, SCC, sosreport) is recommended."
            </p>
        </div>
    }
}
