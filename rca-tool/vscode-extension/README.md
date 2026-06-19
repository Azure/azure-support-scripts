# RCA Tool

Analyze Linux support archives (`sosreport` / `supportconfig`) for Azure VMs
directly from VS Code Chat. This extension bundles the **RCA Tool** MCP server
(`supportfile_mcp`) and the `rca_cli` analyzer and registers them with VS Code's
Model Context Protocol integration, so the tools appear automatically in
**Agent mode**.

## What you get

Once installed, the server `rca-tool` is contributed automatically. In the Chat
view (Agent mode), the following tools become available under **rca-tool**:

- `list_parsers` — list the available detectors/parsers
- `analyze_archive` — run the analyzer over a support archive
- `summarize_findings` — produce a high-level summary of detected issues

Example prompt:

> Summarize the findings in `path/to/sosreport.tar.xz`

## How it works

The extension ships a platform-specific build of two native binaries under
`bin/`:

- `supportfile_mcp` — the stdio MCP server
- `rca_cli` — the analyzer the server shells out to

On activation the extension registers an `McpServerDefinitionProvider` that
launches `supportfile_mcp` over stdio and points it at the bundled `rca_cli`
via the `RCA_CLI_BIN` environment variable.

## Settings

| Setting | Description |
| --- | --- |
| `rcaTool.mcpServerPath` | Absolute path to a `supportfile_mcp` binary to use instead of the bundled one. |
| `rcaTool.rcaCliPath` | Absolute path to an `rca_cli` binary to use instead of the bundled one. |

Leave both empty to use the binaries shipped with the extension.

## Platform support

Platform-specific VSIX packages are published for:

- `linux-x64`, `linux-arm64`
- `darwin-arm64`
- `win32-x64`

The Marketplace serves the package matching your OS and architecture
automatically.

## License

MIT — see [LICENSE.txt](LICENSE.txt).
