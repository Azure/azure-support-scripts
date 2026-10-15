/// Rust mirror of the analysis result object returned by the JS worker.
///
/// Fields are kept as `serde_json::Value` for now: the JS parsers evolve
/// frequently and encoding every nested struct would couple the Leptos UI
/// to parser internals. Individual components pull what they need via
/// helper methods on [`AnalysisResult`].

// ── Analysis result (flat bag of optional sections) ─────────────────

/// The big analysis object.  Every field is optional because the worker
/// The analysis result is kept as a plain `serde_json::Value` map.
///
/// The JS worker's output evolves frequently; trying to enumerate every
/// field in a Rust struct is fragile (e.g. `files` can be `[string]` or
/// `[{name,size}]`).  Sections pull what they need via JSON helpers.
pub type AnalysisResult = serde_json::Value;
