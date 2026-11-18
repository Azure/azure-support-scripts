#!/bin/bash
# Generate Rust coverage for the supportfile_core library.
#
# This script intentionally does NOT instrument Node/JS worker files.
# It produces Rust coverage artifacts under tests/coverage-report-rust/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
CORE_LIB_DIR="$PROJECT_ROOT/lib/supportfile_core"
RUST_REPORT_DIR="$SCRIPT_DIR/coverage-report-rust"

if ! command -v cargo-llvm-cov >/dev/null 2>&1; then
  echo "cargo-llvm-cov is required but was not found in PATH."
  echo "Install it with: cargo install cargo-llvm-cov"
  exit 1
fi

echo "Generating Rust coverage for supportfile_core..."
mkdir -p "$RUST_REPORT_DIR"

cd "$CORE_LIB_DIR"

# Ensure stale profdata/profraw files do not pollute the report.
cargo llvm-cov clean --workspace

# Collect coverage once, then generate reports separately.
cargo llvm-cov \
  --lib \
  --tests \
  --no-report

cargo llvm-cov report \
  --html \
  --output-dir "$RUST_REPORT_DIR"

cargo llvm-cov report \
  --lcov \
  --output-path "$RUST_REPORT_DIR/lcov.info"

echo "Rust coverage complete."
echo "  HTML report: $RUST_REPORT_DIR/html/index.html"
echo "  LCOV report: $RUST_REPORT_DIR/lcov.info"
