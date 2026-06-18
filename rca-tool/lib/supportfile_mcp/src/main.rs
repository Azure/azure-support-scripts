//! `supportfile_mcp` — a Model Context Protocol (MCP) server that exposes the
//! rca-tool support-file analyzer to MCP clients (e.g. Agency / Copilot custom
//! agents).
//!
//! Design (Direction B1): this server is a thin adapter that shells out to the
//! pure-Rust `rca_cli` binary (built from `lib/supportfile_core` with the
//! `cli` feature). It does not link the parser library directly, so the
//! already-tested archive walk, parallel parser dispatch, and multi-file merge
//! logic are reused as-is.
//!
//! Binary resolution: the `rca_cli` executable is located via the
//! `RCA_CLI_BIN` environment variable, falling back to `rca_cli` on `PATH`.
//!
//! Tools exposed:
//!   - `list_parsers`        -> `rca_cli --list-parsers` (parsed into JSON)
//!   - `analyze_archive`     -> `rca_cli <path> --json [--parser NAME]`
//!   - `summarize_findings`  -> `rca_cli <path> --json`, filtered to detectors
//!                              that fired (found=true or count>0)

use std::process::Stdio;

use rmcp::{
    handler::server::wrapper::Parameters,
    model::{ServerCapabilities, ServerInfo},
    schemars, tool, tool_handler, tool_router,
    transport::stdio,
    ErrorData as McpError, ServerHandler, ServiceExt,
};
use serde::Deserialize;
use serde_json::{Map, Value};
use tokio::process::Command;

const DEFAULT_BIN: &str = "rca_cli";

/// Resolve the `rca_cli` binary path: `RCA_CLI_BIN` env var, else `rca_cli`.
fn rca_cli_bin() -> String {
    std::env::var("RCA_CLI_BIN").unwrap_or_else(|_| DEFAULT_BIN.to_string())
}

#[derive(Clone)]
struct RcaServer;

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct AnalyzeParams {
    /// Path to the support archive (.tar.xz / .tar.gz / .tar / .zip) or a bare
    /// plaintext log file to analyze.
    archive_path: String,
    /// Optional: run only the parser with this name (see `list_parsers`).
    #[serde(default)]
    parser: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct SummarizeParams {
    /// Path to the support archive or plaintext log file to analyze.
    archive_path: String,
}

/// Spawn `rca_cli` with the given arguments and capture stdout.
async fn run_cli(args: &[String]) -> Result<String, McpError> {
    let bin = rca_cli_bin();
    let output = Command::new(&bin)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .await
        .map_err(|e| {
            McpError::internal_error(
                format!(
                    "failed to spawn rca_cli ('{bin}'): {e}. \
                     Set RCA_CLI_BIN to the compiled binary path."
                ),
                None,
            )
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(McpError::internal_error(
            format!("rca_cli exited with {}: {}", output.status, stderr.trim()),
            None,
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// Whether a parser result value represents a detector that "fired".
fn fired(value: &Value) -> bool {
    match value {
        Value::Object(o) => {
            o.get("found").and_then(Value::as_bool).unwrap_or(false)
                || o.get("count")
                    .and_then(Value::as_i64)
                    .map(|c| c > 0)
                    .unwrap_or(false)
        }
        Value::Array(a) => !a.is_empty(),
        _ => false,
    }
}

#[tool_router]
impl RcaServer {
    #[tool(
        description = "List all available RCA detectors (parser name + the file-path regex each runs on)."
    )]
    async fn list_parsers(&self) -> Result<String, McpError> {
        let text = run_cli(&["--list-parsers".to_string()]).await?;
        let mut parsers = Vec::new();
        for line in text.lines() {
            if let Some((name, pattern)) = line.split_once(" -> ") {
                parsers.push(serde_json::json!({
                    "name": name.trim(),
                    "pattern": pattern.trim(),
                }));
            }
        }
        serde_json::to_string_pretty(&Value::Array(parsers))
            .map_err(|e| McpError::internal_error(format!("encode error: {e}"), None))
    }

    #[tool(
        description = "Analyze a support archive (sosreport/supportconfig) and return the full structured findings as JSON. Optionally restrict the run to a single parser by name."
    )]
    async fn analyze_archive(
        &self,
        Parameters(AnalyzeParams {
            archive_path,
            parser,
        }): Parameters<AnalyzeParams>,
    ) -> Result<String, McpError> {
        let mut args = vec![archive_path, "--json".to_string()];
        if let Some(p) = parser {
            args.push("--parser".to_string());
            args.push(p);
        }
        run_cli(&args).await
    }

    #[tool(
        description = "Analyze a support archive and return only the detectors that fired (found=true or count>0), as a compact JSON summary suitable for grounding an agent."
    )]
    async fn summarize_findings(
        &self,
        Parameters(SummarizeParams { archive_path }): Parameters<SummarizeParams>,
    ) -> Result<String, McpError> {
        let raw = run_cli(&[archive_path, "--json".to_string()]).await?;
        let parsed: Value = serde_json::from_str(&raw).map_err(|e| {
            McpError::internal_error(format!("rca_cli did not return valid JSON: {e}"), None)
        })?;
        let obj = parsed
            .as_object()
            .ok_or_else(|| McpError::internal_error("expected a JSON object from rca_cli", None))?;

        let mut findings = Map::new();
        for (k, v) in obj {
            if matches!(k.as_str(), "fileCount" | "matchedFiles" | "fileTypes") {
                continue;
            }
            if fired(v) {
                findings.insert(k.clone(), v.clone());
            }
        }

        let summary = serde_json::json!({
            "fileCount": obj.get("fileCount").cloned().unwrap_or(Value::Null),
            "matchedFiles": obj.get("matchedFiles").cloned().unwrap_or(Value::Null),
            "firedCount": findings.len(),
            "findings": Value::Object(findings),
        });
        serde_json::to_string_pretty(&summary)
            .map_err(|e| McpError::internal_error(format!("encode error: {e}"), None))
    }
}

#[tool_handler]
impl ServerHandler for RcaServer {
    fn get_info(&self) -> ServerInfo {
        let mut info = ServerInfo::default();
        info.instructions = Some(
            "RCA tool MCP server. Use list_parsers to discover detectors, \
             analyze_archive for the full JSON findings of a support archive, \
             and summarize_findings for a compact view of only the detectors \
             that fired."
                .to_string(),
        );
        info.capabilities = ServerCapabilities::builder().enable_tools().build();
        info
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let service = RcaServer.serve(stdio()).await?;
    service.waiting().await?;
    Ok(())
}
