# Developer documentation

How to build and contribute to rca-tool.

## Functionality

Currently, the tool manages:

|Function|Description|Mature code?|crm/hb|scc|sos|console /messages / syslog / plain text files|inspect|
|--------|-----------|------|------|---|---|-----------|-------|
|Azure vm size|Extract Azure VM Size, from wireserver metadata|🗸|n.a.|🗸|🗸|||
|Azure BYOS/PAYG|Licensing source for Azure, from wireserver metadata.|𐄂|n.a.|🗸|🗸|||
|Distro detection|It finds distribution mayor and minor version from OS files or wireserver metadata|🗸|🗸|🗸|🗸||🗸|
|Cluster node detection and validation|Detects if a node name is declared in both cluster config and hosts file|🗸|🗸|🗸|🗸||🗸|
|Corosync configuration and validation|Azure best practices are compared. Needs improvement for non-Suse|𐄂|🗸|🗸|🗸||🗸|
|Cluster resource extraction|List resources, active node for each. Adding constains would be useful.|🗸|🗸|🗸|🗸|||
|Corosync runtime status|Details which nodes are active, which is localhost|🗸|🗸|🗸|🗸|||
|Fencing detection|Azure fencing or SDB. Needs warning if two are active at the same time.|🗸|🗸|🗸|🗸|||
|Cluster events|Migrations are detected and listed|🗸|🗸|🗸|🗸||🗸|
|Live migration|Azure Live Migrations are detected and listed|🗸|🗸|🗸|🗸|🗸|🗸|
|Kernel reboot events|Shutdown, reboots and kernel starts are listed. Shows kernel version when boots|🗸|🗸|🗸|🗸|🗸|🗸|
|Out of memory/oomk events|If the system cannot allocate memory for processes or has out of memory events, they are detected and listed.|🗸|n.a.|🗸|🗸|🗸|🗸|
|Cluster packages|Validation of packages install in specific version ranges. Needs improvement for non-Suse.|||||||
|AV Detection|MS Defender, Cloudstrike Falcon, Illumio, Trend Micro, Guardicore|🗸|n.a.|🗸|🗸|||
|DLM Service Detection|Detects if DLM (Distributed Lock Manager) service is enabled and alerts|🗸|n.a.|🗸|🗸|||
|Kernel parameters and validation|It grabs kernel parameters (sysctl) and displays them raw. If SAP Hana is found, it also validates best practices.|🗸|||🗸|||
|Huge Pages Detection|Detects static huge pages and Transparent Huge Pages (THP) configuration. Shows warnings for unused pages and recommendations for SAP HANA.|🗸|n.a.|🗸|🗸|||
|Raw fstab|It grab the raw fstab.|🗸|n.a.|🗸|🗸||🗸|
|Azure Site Recovery|It detects if the involflt_start service is enabled.|🗸|n.a.|🗸||||
|XFS corruption|If we see a message about xfs corruption, it is listed as an event.|🗸||🗸|🗸||🗸|
|XFS duplicate UUID|If the is a kernel message about a duplicate UUID XFS mount, it is listed as an event.|🗸||🗸|🗸|🗸|🗸|
|Emergency mode|Detects when system entered emergency mode from log messages|🗸|n.a.|🗸|🗸||🗸|
|NVME Detection|If NVME disks are found, they are listed.|🗸|n.a.||🗸|||
|Network Kernel Parameters|Recommended and optional kernel parameters for network are verified on the collected sysctl.|🗸|n.a.|🗸|🗸|||
|Raw list of distro packages|Shows a raw list of packages from dpkg -l, dnf list, yum list and rpm.txt|🗸|n.a.|🗸|🗸|||
|Azure Storage Type Detection|Standard SSD, Premium SSDv2, Ultradisk, etc.|🗸|n.a.|n.a.|🗸|||
|SSH error detection|Failed to start and permission errors|𐄂|n.a.|🗸|🗸|🗸||
|Network Interfaces|Detects interfaces, DHCP/static, drivers, accelerated networking from ifcfg/netplan files|🗸|n.a.|🗸|🗸||🗸|
|Firewall Rules|Detects firewall technology (firewalld, nftables, iptables) and configuration|🗸|n.a.|🗸|🗸||🗸|
|InspectIaaSDisk results|Parses disk inspection diagnostics: request info, filesystem status, OS metadata, mount points, and mount failures with warnings|🗸|n.a.|n.a.|n.a.|n.a.|🗸|
|Azure Linux Agent config|Parses /etc/waagent.conf: extensions, firewall, swap, FIPS, auto-update, SCSI timeout. Flags risky settings.|🗸|n.a.|🗸|🗸||🗸|
|(WIP)||𐄂|n.a.|🗸|🗸|||


Note: "n.a." in this table, means that some data is not present on all type of debug files.

## Architecture overview

The detectors live in the **Rust crate `supportfile`** (`rca-tool/lib/supportfile_core`).
Two thin bindings expose the same functions to other ecosystems:

- **`supportfile-wasm`** — `wasm-bindgen` build consumed by the Leptos web UI
  (`rca-tool/web-leptos`) and by the legacy JS worker.
- **`supportfile_py`** — PyO3 / maturin build published to PyPI as
  [`supportfile`](https://pypi.org/project/supportfile/).

Both bindings re-export the same `parse_*_json` functions, so a detector
written once in Rust is automatically available from Python, JavaScript, and
the browser.

## Using the published Rust crate

The Rust crate is published to crates.io as
[`supportfile`](https://crates.io/crates/supportfile).

```toml
# Cargo.toml
[dependencies]
supportfile = "0.1"
```

Minimal example — pass a tiny string straight to a detector and inspect the
typed result:

```rust
use supportfile::parse_secure_boot;

fn main() {
    // Positive detection: SecureBoot is present and disabled.
    let r = parse_secure_boot("SecureBoot disabled\n", "");
    assert!(r.found);
    assert_eq!(r.enabled, Some(false));
    assert!(r.supported);
    println!("{:?}", r);
    // SecureBootResult { found: true, enabled: Some(false),
    //                    supported: true, state_text: "SecureBoot disabled",
    //                    source_path: "", source_line: Some(1) }
}
```

Every detector also has a `parse_<name>_json` variant that returns a JSON
string — that is the form the WASM and Python bindings call.

## Using the published Python package

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install supportfile
```

Minimal example — pass a tiny string and parse the returned JSON:

```python
import json
import supportfile

result = json.loads(supportfile.parse_secure_boot("SecureBoot disabled\n", ""))
assert result["found"] is True
assert result["enabled"] is False        # positive detection
assert result["supported"] is True
print(result)
# {'found': True, 'enabled': False, 'supported': True,
#  'state_text': 'SecureBoot disabled', 'source_path': '', 'source_line': 1}
```

## Command-line tools

Both bindings ship an example CLI that walks an SCC / sosreport archive
(`.tar`, `.tar.gz`, `.tar.xz`) and runs every registered parser.

### Rust CLI (`rca_cli`)

`rca_cli` is built as a binary under the `cli` feature of `supportfile`:

```bash
cd rca-tool/lib/supportfile_core

# Human-readable summary
cargo run --release --features cli --bin rca_cli -- \
    ../../tests/fixtures/scc_test-secureboot-disabled.tar.xz

# Raw JSON (one object per parser)
cargo run --release --features cli --bin rca_cli -- \
    ../../tests/fixtures/scc_test-secureboot-disabled.tar.xz --json

# List every parser that ships with the binary
cargo run --release --features cli --bin rca_cli -- --list-parsers
```

### Python CLI (`examples/rca_cli.py`)

After `pip install supportfile`, run the Python mirror of the same CLI:

```bash
cd rca-tool/lib/supportfile_py

python examples/rca_cli.py tests/fixtures/scc_test-secureboot-disabled.tar.xz
python examples/rca_cli.py tests/fixtures/scc_test-secureboot-disabled.tar.xz --json
python examples/rca_cli.py --list-parsers

# Run a single parser
python examples/rca_cli.py archive.tar.xz --parser secureBoot
```

## MCP server (`supportfile_mcp`)

`supportfile_mcp` (`rca-tool/lib/supportfile_mcp`) is a
[Model Context Protocol](https://modelcontextprotocol.io) server that exposes
the analyzer as MCP **tools**, so AI agents (GitHub Copilot custom agents /
Agency, Claude Desktop, or any MCP client) can triage support archives without
shelling out by hand.

It is a thin adapter: it runs the compiled `rca_cli` binary under the hood and
reshapes its JSON for agent consumption. Because it reuses `rca_cli`, the
archive walk, parallel parser dispatch, and multi-file merge are exactly the
same as the CLI — there is no second copy of the analysis logic.

It speaks MCP over **stdio** (newline-delimited JSON-RPC 2.0 on
stdin/stdout). The process stays alive until its stdin is closed.

### Install

Install both binaries with `cargo install`; they land in `~/.cargo/bin`, which
is normally on your `PATH`.

From crates.io:

```bash
# The CLI the server shells out to. The `cli` feature pulls in the
# archive/parallelism stack and builds the `rca_cli` binary.
cargo install supportfile --features cli

# The MCP server itself.
cargo install supportfile_mcp
```

From a local checkout (handy while developing):

```bash
cargo install --path rca-tool/lib/supportfile_core --features cli
cargo install --path rca-tool/lib/supportfile_mcp
```

Both binaries (`rca_cli` and `supportfile_mcp`) end up in `~/.cargo/bin`, so the
server finds `rca_cli` automatically — no extra configuration needed.

### Binary resolution (`RCA_CLI_BIN`)

The server locates `rca_cli` via the `RCA_CLI_BIN` environment variable, and
falls back to `rca_cli` on `PATH`. After `cargo install` (above) `rca_cli` is
already on `PATH`, so you can just run:

```bash
supportfile_mcp
```

Set `RCA_CLI_BIN` only when `rca_cli` lives somewhere off `PATH` — for example a
`target/release` directory from a plain `cargo build`:

```bash
export RCA_CLI_BIN=/abs/path/to/rca-tool/lib/supportfile_core/target/release/rca_cli
supportfile_mcp
```

If `rca_cli` cannot be spawned, every tool call returns an MCP error telling you
to set `RCA_CLI_BIN`.

### Tools exposed

| Tool | Parameters | Maps to | Returns |
|------|-----------|---------|---------|
| `list_parsers` | _(none)_ | `rca_cli --list-parsers` | JSON array of `{ "name", "pattern" }` — every detector and the file-path regex it runs on |
| `analyze_archive` | `archive_path` (string, required), `parser` (string, optional) | `rca_cli <path> --json [--parser NAME]` | The full merged JSON findings (`fileCount`, `matchedFiles`, `fileTypes`, plus one key per parser) |
| `summarize_findings` | `archive_path` (string, required) | `rca_cli <path> --json` (filtered) | Compact JSON: `{ "fileCount", "matchedFiles", "firedCount", "findings" }`, where `findings` holds **only the detectors that fired** (`found=true` or `count>0`) |

`archive_path` accepts the same inputs as the CLI: a `.tar`, `.tar.gz`,
`.tar.xz`, or `.zip` archive, or a bare plaintext log file.

`summarize_findings` is the recommended starting point for an agent: it strips
out detectors that found nothing, so the result is small enough to ground a
model without flooding it with empty sections. Use `analyze_archive` (optionally
with `parser`) to drill into a specific detector once you know what fired.

### Driving it manually over stdio

The server is a normal MCP stdio server, so you can exercise it by piping
JSON-RPC frames to its stdin (one JSON object per line). The sequence below
initializes the session, lists the tools, and summarizes an archive:

```bash
cd rca-tool   # so the fixture path below resolves

{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"manual","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"summarize_findings","arguments":{"archive_path":"tests/fixtures/scc_test-automation.tar.xz"}}}'
} | supportfile_mcp
```

Each request line produces one JSON-RPC response line on stdout. Calling a tool
uses `tools/call` with `params.name` set to the tool and `params.arguments`
holding its parameters, e.g. to run a single parser:

```json
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"analyze_archive","arguments":{"archive_path":"archive.tar.xz","parser":"sshServiceIssues"}}}
```

> The `rca_cli` binary writes its `Analyzing: <file>` progress line to **stderr**,
> so the JSON on stdout that the server parses stays clean.

### Using it from a GitHub Copilot / Agency custom agent

Custom agents declare MCP servers in their Markdown front matter. A ready-to-use
sample lives at [`.github/agents/rca-triage.md`](../.github/agents/rca-triage.md);
its front matter wires up this server:

```yaml
---
name: rca-triage
description: Triages Linux support archives (sosreport / supportconfig) for Azure VMs using the rca-tool analyzer.
mcp-servers:
  rca-tool:
    type: local
    command: supportfile_mcp   # must be on PATH, or use an absolute path
    args: []
    tools: ["*"]               # expose all three tools
---
```

For the agent to launch the server, install both binaries with `cargo install`
(see [Install](#install) above) so `supportfile_mcp` and `rca_cli` land on
`PATH`; otherwise replace `command` with the absolute path to the binary and set
`RCA_CLI_BIN`. Once configured, the agent can call `list_parsers`,
`summarize_findings`, and `analyze_archive` directly during a conversation.

### Using it from VS Code

VS Code (1.102+) has native MCP support for Copilot **agent mode**. You
register the server in an `mcp.json` file; VS Code launches it on demand and
exposes its three tools to the model.

First install both binaries (see [Install](#install) above):

```bash
cargo install supportfile --features cli
cargo install supportfile_mcp
```

**Workspace scope** (committed, shared with the repo) — create
`.vscode/mcp.json`. Because `cargo install` puts both binaries on `PATH`, the
command is just the binary name and no `env` is needed:

```jsonc
{
  "servers": {
    "rca-tool": {
      "type": "stdio",
      "command": "supportfile_mcp"
    }
  }
}
```

**User scope** (available in every workspace) — run **MCP: Open User
Configuration** from the Command Palette and use the same shape:

```jsonc
{
  "servers": {
    "rca-tool": {
      "type": "stdio",
      "command": "supportfile_mcp"
    }
  }
}
```

`type: "stdio"` matches how the server communicates (newline-delimited
JSON-RPC on stdin/stdout). If `~/.cargo/bin` is not on the `PATH` that VS Code
sees, set `"command"` to the absolute path (`~/.cargo/bin/supportfile_mcp`) and
add an `"env"` block with `RCA_CLI_BIN` pointing at `~/.cargo/bin/rca_cli`.

To start and use it:

1. Open `.vscode/mcp.json`. VS Code shows a **Start** CodeLens above the server
   entry — click it (or run **MCP: List Servers** and start it there).
2. Open the Chat view and switch to **Agent** mode.
3. Click the **Tools** icon; `list_parsers`, `analyze_archive`, and
   `summarize_findings` appear under `rca-tool`.
4. Prompt it, for example:
   > Summarize the findings in `rca-tool/tests/fixtures/scc_test-automation.tar.xz`

   The model calls `summarize_findings` first, then drills in with
   `analyze_archive` as needed.

To point the server at an `rca_cli` that is not on `PATH` (e.g. a
`target/release` build), set `RCA_CLI_BIN` via an `env` block, optionally
prompting for the path with an input:

```jsonc
{
  "inputs": [
    {
      "id": "rca_cli_path",
      "type": "promptString",
      "description": "Path to the rca_cli binary"
    }
  ],
  "servers": {
    "rca-tool": {
      "type": "stdio",
      "command": "supportfile_mcp",
      "env": { "RCA_CLI_BIN": "${input:rca_cli_path}" }
    }
  }
}
```

As with the manual stdio run, the server's `Analyzing: <file>` line goes to
stderr, so it never corrupts the JSON-RPC stream VS Code reads on stdout.

## Building and running the web interface

The browser UI is a client-side Leptos / WebAssembly app under
`rca-tool/web-leptos`.

Prerequisites:

```bash
rustup target add wasm32-unknown-unknown
cargo install trunk wasm-pack
```

Production build (also copies the JS worker and liblzma WASM assets):

```bash
cd rca-tool/web-leptos
./build.sh
# Output: dist/
```

Local development server with hot reload:

```bash
cd rca-tool/web-leptos
./build.sh            # one-time, to populate assets/
trunk serve --open    # http://localhost:8090
```

If you have already built the JS assets and only want to iterate on Rust
code, you can skip the heavy liblzma rebuild:

```bash
SKIP_LZMA_WASM_BUILD=1 ./build.sh
```

## Browser Compatibility

This project uses modern web APIs and requires a recent browser with:
- WebAssembly support
- File API support
- Drag and Drop API support

Currently all testing is done with MS Edge via Playwright.

## Adding rules

New detectors are added Rust-first in
`rca-tool/lib/supportfile_core/src/parsers/`. The
[SecureBoot detector](lib/supportfile_core/src/parsers/azure.rs) is a good
small reference.

Steps:

1. Add a `XxxResult` struct (`#[derive(Debug, Clone, Serialize)]`) and a
   `parse_xxx(content: &str, source_path: &str) -> XxxResult` function in the
   appropriate `parsers/*.rs` file. Add unit tests next to it.
2. Add a `parse_xxx_json(content: &str, source_path: &str) -> String` wrapper
   and re-export both from `lib.rs`.
3. Expose to JS / WASM in
   [`lib/supportfile_wasm/src/lib.rs`](lib/supportfile_wasm/src/lib.rs) with
   `#[wasm_bindgen(js_name = parseXxx)]`.
4. Expose to Python in
   [`lib/supportfile_py/src/lib.rs`](lib/supportfile_py/src/lib.rs) via
   `wrap_pyfunction!`.
5. Register the file pattern in the JS worker
   ([`src/parsers/*.js`](src/parsers/) + [`src/worker.js`](src/worker.js)) so
   the browser worker dispatches the right files to the new parser.
6. Render the result in a Leptos section under
   [`web-leptos/src/components/sections/`](web-leptos/src/components/sections/)
   and wire it into [`analysis_view.rs`](web-leptos/src/components/analysis_view.rs).
7. Add a fixture in [`tests/create-fixtures.sh`](tests/create-fixtures.sh) and
   a Playwright test in the matching `tests/*.spec.js` file.

## Debug mode

For reviewing the rules, you can run the web page with the following query
parameter so the browser worker logs verbose per-parser output to the
DevTools console:

```
http://localhost:8090/?debug=cluster
```

Useful modes are `cluster`, `app` and `all`.

## Testing

The Rust crates carry their own unit tests; run them from each crate
directory:

```bash
cd rca-tool/lib/supportfile_core
cargo test
```

End-to-end browser tests are driven by Playwright against the Leptos build:

```bash
cd rca-tool/tests
npm ci
bash create-fixtures.sh
npx playwright install --with-deps msedge

# Run the full Leptos suite
node_modules/.bin/playwright test \
    --config=playwright.leptos.config.js \
    --project=local-leptos

# Run a single spec, or filter by test name
node_modules/.bin/playwright test \
    --config=playwright.leptos.config.js \
    --project=local-leptos azure.spec.js

node_modules/.bin/playwright test \
    --config=playwright.leptos.config.js \
    --project=local-leptos -g "SecureBoot"

# Accessibility checks
node accessibility-check.js
```

The Playwright config automatically builds and serves the Leptos app, so the
first run takes longer while `./build.sh` populates `web-leptos/dist/`.

## TODO

If you want to contribute to the project, the current priority is not to add more functionality, but to have parity and testing of the 4 supported type of files, since they contain different information, packaged in different ways, it is possible that (as an example, this used to happen but is not fixed) you are able to find a kernel reboot on an sos report, but not on an scc file from the same server.

1. Parity for all types of files, with testing
2. Adding detection from cases or from cluster specialist's recommendations
3. Adding more detectors: automation platforms, better cluster resources and events, package history, others

If possible, moving the rules to a rust WASM code would make the analysis of the files even faster. (see Limitations)

## Limitations

Due to the need to run with streaming, we currently support only gzip and xz files, using a C library compiled for WASM.

If other mature libraries for compression can be compiled and used with streaming, it should be possible to support other types for files like ZIP, or zstd.