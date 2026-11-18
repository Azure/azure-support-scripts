//! `fixtures-gen` — deterministic builder for the RCA Tool Playwright fixtures.
//!
//! Proof-of-concept scope: builds the two SAP HANA `.zip` fixtures consumed by
//! `tests/hana.spec.js` and `tests/hana-trace-events.spec.js`. No archives or
//! binaries are committed — the `.zip` files are generated on demand into the
//! (gitignored) `tests/fixtures/` directory.
//!
//! Usage:
//!   fixtures-gen [--out <dir>] [--only <archive-name.zip>]
//!
//! Defaults `--out` to `tests/fixtures`.

mod archive;
mod hana;

use std::path::PathBuf;

/// Each fixture: output archive name + the in-archive trace content generator.
/// All HANA archives package a single `T31 HANA Logs/indexserver_test.trc`
/// (the path the JS router matches via `/(indexserver|nameserver).*\.trc$/`).
const FIXTURES: &[(&str, fn() -> String)] = &[
    ("hana_test-savepoints.zip", hana::savepoints_trace),
    ("hana_test-trace-events.zip", hana::trace_events_trace),
];

const TRACE_ARCNAME: &str = "T31 HANA Logs/indexserver_test.trc";

fn main() -> Result<(), archive::BoxError> {
    let mut out = PathBuf::from("tests/fixtures");
    let mut only: Option<String> = None;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--out" => {
                out = PathBuf::from(args.next().ok_or("--out requires a directory argument")?)
            }
            "--only" => only = Some(args.next().ok_or("--only requires an archive name")?),
            "-h" | "--help" => {
                println!("usage: fixtures-gen [--out <dir>] [--only <archive-name.zip>]");
                return Ok(());
            }
            other => return Err(format!("unknown argument: {other}").into()),
        }
    }

    std::fs::create_dir_all(&out)?;

    let mut built = 0usize;
    for (name, generate) in FIXTURES {
        if let Some(filter) = &only {
            if filter != name {
                continue;
            }
        }
        let content = generate();
        archive::write_zip(
            &out.join(name),
            &[(TRACE_ARCNAME, content.as_bytes())],
        )?;
        println!("[OK] {}", out.join(name).display());
        built += 1;
    }

    if built == 0 {
        return Err("no fixtures matched the requested filter".into());
    }
    Ok(())
}
