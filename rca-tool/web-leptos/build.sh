#!/usr/bin/env bash
# Build the Leptos CSR web interface for RCA Tool.
#
# This script:
#   1. Copies the JS worker, parsers, and WASM runtime into assets/
#   2. Runs `trunk build` to produce dist/
#
# The dist/ directory is fully self-contained and can be served from
# any static file server (or opened via file://).
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Copying JS assets…"
mkdir -p assets/parsers assets/liblzma-wasm/dist-streaming
cp ../src/worker.js           assets/liblzma-streaming-worker.js
cp ../src/parsers/*.js        assets/parsers/
cp ../src/utils.js            assets/
cp ../src/performance.js      assets/
cp -r ../web/liblzma-wasm/dist-streaming/* assets/liblzma-wasm/dist-streaming/

echo "==> Cleaning previous build output…"
rm -rf dist .stage

PUBLIC_URL="${PUBLIC_URL:-./}"

echo "==> Running trunk build (release, public URL: ${PUBLIC_URL})…"
trunk build --release --public-url "$PUBLIC_URL" "$@"

echo "==> Done.  Output in dist/"
ls -lh dist/
