# supportfile

Shared Rust core for parsing and analyzing Linux support bundles
(supportconfig, sosreport, and ad‑hoc text dumps). It is the single
source of truth for parser logic that is reused across the
[`rca-tool`](../../README.md) frontends:

- the Leptos web UI (compiled to WebAssembly)
- the [`supportfile`](../supportfile_py) Python extension (via PyO3)
- the [`supportfile_wasm`](../supportfile_wasm) browser bindings
- the `rca_cli` example binary in this crate

## Scope

The crate exposes a collection of parser modules under
[`src/parsers`](src/parsers), each focused on a specific area of a
support bundle:

| Module               | Purpose                                              |
| -------------------- | ---------------------------------------------------- |
| `automation`         | Cloud‑init / Azure Linux agent automation logs       |
| `azure`              | Azure guest metadata and platform fingerprints       |
| `cluster`            | Pacemaker / Corosync state and high‑CPU events       |
| `debugfs`            | `debugfs` / kernel debug captures                    |
| `events`             | Generic timestamped event extraction                 |
| `network_interfaces` | NIC inventory, addressing, link state                |
| `networking`         | Routing, firewall, name resolution                   |
| `packages`           | Installed package inventory (rpm/dpkg)               |
| `services`           | systemd unit and service state                       |
| `storage`            | Block devices, filesystems, multipath                |
| `unix`               | Generic Unix host facts (uname, uptime, sysctl, …)   |
| `vmcore`             | Kernel crash / vmcore artifacts                      |

All parser entry points are re‑exported at the crate root, so most
callers only need:

```rust
use supportfile::*;
```

## Building

```bash
cargo build --release
cargo test
```

The crate is built and tested as a regular `rlib`. WebAssembly and
Python bindings live in sibling crates and depend on this one.

## Example: `rca_cli`

A reference command‑line analyzer is included as an example. It can
ingest plain directories or compressed bundles
(`.tar`, `.tar.gz` / `.tgz`, `.tar.xz` / `.txz`, `.zip`) and print
the results as JSON.

```bash
cargo run --release --example rca_cli -- /path/to/supportbundle.tar.xz
```

`.tar.xz` decompression uses the multi‑threaded `liblzma` decoder for
faster ingestion of large bundles.

## Dependencies

Runtime:

- `regex` — pattern matching across log lines
- `serde` / `serde_json` — structured output for all parsers

Dev / example only:

- `tar`, `flate2`, `zip`, `liblzma` — archive handling for `rca_cli`

## Layout

```
supportfile_core/
├── Cargo.toml
├── src/
│   ├── lib.rs           # re‑exports every parser module
│   └── parsers/         # one file per parser domain
└── examples/
    └── rca_cli.rs       # reference CLI driver
```

## Versioning and publishing

Version is tracked in [`Cargo.toml`](Cargo.toml). Release packaging,
crates.io publishing, and the matching Python wheel build are wired
into the repository CI workflow at
`.github/workflows/rust-python-packages.yml`.

## License

MIT — see [`LICENSE.txt`](../LICENSE.txt).
