//! Pure-Rust streaming XZ decoder for the RCA Tool worker.
//!
//! Mirrors the worker-facing `xz_stream_*` API previously provided by the
//! C-based liblzma wrapper so the JS worker can drive the Rust backend
//! directly.
//!
//! This implementation is backed by `github.com/fede2cr/lzma-rs`
//! (`streaming` branch), which adds a push-based [`XzStream<W>`] decoder.
//! Each `process` call feeds input directly into the decoder and returns any
//! newly produced output.

use std::cell::RefCell;
use std::collections::HashMap;
use std::io::Write;

use lzma_rs::decompress::XzStream;
use wasm_bindgen::prelude::*;

const STATUS_NEED_MORE: i32 = 0;
const STATUS_FINISHED: i32 = 1;
const STATUS_INVALID_HANDLE: i32 = -1;
const STATUS_ALREADY_FINISHED: i32 = 1;
const STATUS_ALREADY_ERROR: i32 = -2;
const STATUS_DECODE_ERROR: i32 = -3;

#[wasm_bindgen(start)]
pub fn start() {
    console_error_panic_hook::set_once();
}

#[derive(Default)]
struct VecSink {
    buf: Vec<u8>,
}

impl Write for VecSink {
    fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
        self.buf.extend_from_slice(data);
        Ok(data.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

struct StreamState {
    decoder: Option<XzStream<VecSink>>,
    finished: bool,
    error: Option<String>,
}

thread_local! {
    static STREAMS: RefCell<HashMap<u32, StreamState>> = RefCell::new(HashMap::new());
    static NEXT_ID: RefCell<u32> = RefCell::new(1);
}

#[wasm_bindgen]
pub struct ProcessResult {
    output: Vec<u8>,
    status: i32,
}

#[wasm_bindgen]
impl ProcessResult {
    #[wasm_bindgen(getter)]
    pub fn output(self) -> Vec<u8> {
        self.output
    }

    #[wasm_bindgen(getter)]
    pub fn status(&self) -> i32 {
        self.status
    }
}

#[wasm_bindgen(js_name = xzStreamInit)]
pub fn xz_stream_init() -> u32 {
    let id = NEXT_ID.with(|next_id| {
        let id = *next_id.borrow();
        *next_id.borrow_mut() = id.wrapping_add(1).max(1);
        id
    });

    STREAMS.with(|streams| {
        streams.borrow_mut().insert(
            id,
            StreamState {
                decoder: Some(XzStream::new(VecSink::default())),
                finished: false,
                error: None,
            },
        );
    });

    id
}

#[wasm_bindgen(js_name = xzStreamProcess)]
pub fn xz_stream_process(handle: u32, input: &[u8]) -> ProcessResult {
    STREAMS.with(|streams| {
        let mut streams = streams.borrow_mut();
        let state = match streams.get_mut(&handle) {
            Some(state) => state,
            None => {
                return ProcessResult {
                    output: Vec::new(),
                    status: STATUS_INVALID_HANDLE,
                };
            }
        };

        if state.error.is_some() {
            return ProcessResult {
                output: Vec::new(),
                status: STATUS_ALREADY_ERROR,
            };
        }
        if state.finished {
            return ProcessResult {
                output: Vec::new(),
                status: STATUS_ALREADY_FINISHED,
            };
        }

        if input.is_empty() {
            let decoder = match state.decoder.take() {
                Some(decoder) => decoder,
                None => {
                    state.error = Some("decoder already consumed".to_string());
                    return ProcessResult {
                        output: Vec::new(),
                        status: STATUS_DECODE_ERROR,
                    };
                }
            };

            match decoder.finish() {
                Ok(sink) => {
                    state.finished = true;
                    ProcessResult {
                        output: sink.buf,
                        status: STATUS_FINISHED,
                    }
                }
                Err(error) => {
                    state.error = Some(format!("{:?}", error));
                    ProcessResult {
                        output: Vec::new(),
                        status: STATUS_DECODE_ERROR,
                    }
                }
            }
        } else {
            let decoder = match state.decoder.as_mut() {
                Some(decoder) => decoder,
                None => {
                    state.error = Some("decoder already consumed".to_string());
                    return ProcessResult {
                        output: Vec::new(),
                        status: STATUS_DECODE_ERROR,
                    };
                }
            };

            if let Err(error) = decoder.write_all(input) {
                state.error = Some(error.to_string());
                return ProcessResult {
                    output: Vec::new(),
                    status: STATUS_DECODE_ERROR,
                };
            }

            let sink = decoder
                .get_sink_mut()
                .expect("XzStream sink unavailable after successful write");

            ProcessResult {
                output: std::mem::take(&mut sink.buf),
                status: STATUS_NEED_MORE,
            }
        }
    })
}

#[wasm_bindgen(js_name = xzStreamError)]
pub fn xz_stream_error(handle: u32) -> String {
    STREAMS.with(|streams| match streams.borrow().get(&handle) {
        Some(state) => state
            .error
            .clone()
            .unwrap_or_else(|| "no error".to_string()),
        None => "invalid handle".to_string(),
    })
}

#[wasm_bindgen(js_name = xzStreamFree)]
pub fn xz_stream_free(handle: u32) {
    STREAMS.with(|streams| {
        streams.borrow_mut().remove(&handle);
    });
}
