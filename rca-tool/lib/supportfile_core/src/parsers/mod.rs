pub mod automation;
pub mod azure;
pub mod cluster;
pub mod debugfs;
pub mod events;
pub mod network_interfaces;
pub mod networking;
pub mod packages;
pub mod services;
pub mod storage;
pub mod unix;
pub mod vmcore;

/// Recursively set the `source_path` field on every JSON object inside `value`
/// to `source_path` whenever the object already has the field present and it
/// is currently an empty string. Used by parser `_json` wrappers so that nested
/// records (warnings, sub-records, etc.) inherit the wrapper's source path
/// without each parser having to stamp them inline.
pub(crate) fn fill_source_path(value: &mut serde_json::Value, source_path: &str) {
    match value {
        serde_json::Value::Object(map) => {
            if let Some(serde_json::Value::String(s)) = map.get("source_path") {
                if s.is_empty() {
                    map.insert(
                        "source_path".to_string(),
                        serde_json::Value::String(source_path.to_string()),
                    );
                }
            }
            for (_, v) in map.iter_mut() {
                fill_source_path(v, source_path);
            }
        }
        serde_json::Value::Array(arr) => {
            for v in arr.iter_mut() {
                fill_source_path(v, source_path);
            }
        }
        _ => {}
    }
}
