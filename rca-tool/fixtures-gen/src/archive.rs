//! Deterministic archive writers for the test fixtures.
//!
//! Only `.zip` is needed for the HANA proof-of-concept; a `.tar.xz` writer can
//! be added here (using the `tar` + `liblzma` crates already vendored by
//! `supportfile`) when the scc-style fixtures are ported off `create-fixtures.sh`.

use std::collections::BTreeSet;
use std::io::Write;
use std::path::Path;

use zip::write::SimpleFileOptions;

pub type BoxError = Box<dyn std::error::Error>;

/// Fixed archive timestamp so generated fixtures are byte-stable across runs
/// and machines (archive formats embed mtimes, which otherwise churn).
fn fixed_mtime() -> zip::DateTime {
    zip::DateTime::from_date_and_time(2026, 1, 1, 0, 0, 0).expect("valid fixed DOS timestamp")
}

/// Write `entries` (`archive-path -> bytes`) into a deflate `.zip` at `out_path`,
/// emitting an explicit directory entry for every parent folder so the layout
/// matches how real HANA log bundles are shipped (`T31 HANA Logs/`).
pub fn write_zip(out_path: &Path, entries: &[(&str, &[u8])]) -> Result<(), BoxError> {
    if let Some(parent) = out_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let opts = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .last_modified_time(fixed_mtime())
        .unix_permissions(0o644);

    let mut dirs: BTreeSet<String> = BTreeSet::new();
    for (name, _) in entries {
        if let Some(idx) = name.rfind('/') {
            dirs.insert(name[..idx].to_string());
        }
    }

    let file = std::fs::File::create(out_path)?;
    let mut zip = zip::ZipWriter::new(file);

    for dir in &dirs {
        zip.add_directory(dir.clone(), opts)?;
    }
    for (name, data) in entries {
        zip.start_file((*name).to_string(), opts)?;
        zip.write_all(data)?;
    }
    zip.finish()?;
    Ok(())
}
