#!/usr/bin/env bash
# Build the Leptos CSR web interface for RCA Tool.
#
# This script:
#   1. (Re)builds the supportfile WASM module from supportfile_wasm/
#      (skip with SKIP_WASM_BUILD=1 if pkg/ is already up to date)
#   2. Copies the JS worker, parsers, and WASM runtime into assets/
#   3. Runs `trunk build` to produce dist/
#
# The dist/ directory is fully self-contained and can be served from
# any static file server (or opened via file://).
set -euo pipefail
cd "$(dirname "$0")"

SUPPORTFILE_WASM_DIR="../lib/supportfile_wasm"
SUPPORTFILE_WASM_PKG="${SUPPORTFILE_WASM_DIR}/pkg"
LZMA_STREAM_WASM_DIR="../lib/lzma_stream_wasm"
LZMA_STREAM_WASM_PKG="${LZMA_STREAM_WASM_DIR}/pkg"

if [[ "${SKIP_WASM_BUILD:-0}" != "1" ]]; then
    echo "==> Building supportfile WASM (wasm-pack, target=no-modules, release)…"
    (cd "${SUPPORTFILE_WASM_DIR}" && wasm-pack build --target no-modules --release --out-dir pkg)
else
    echo "==> SKIP_WASM_BUILD=1 — using existing ${SUPPORTFILE_WASM_PKG}/"
fi

if [[ "${SKIP_LZMA_WASM_BUILD:-0}" != "1" ]]; then
    echo "==> Building Rust XZ streaming WASM (wasm-pack, target=no-modules, release)…"
    (cd "${LZMA_STREAM_WASM_DIR}" && wasm-pack build --target no-modules --release --out-dir pkg)
else
    echo "==> SKIP_LZMA_WASM_BUILD=1 — using existing ${LZMA_STREAM_WASM_PKG}/"
fi

# Avoid global name collisions between supportfile_wasm.js and lzma_stream_wasm.js
# (both are wasm-pack no-modules bundles that default to `wasm_bindgen`).
if grep -q '^let wasm_bindgen =' "${LZMA_STREAM_WASM_PKG}/lzma_stream_wasm.js"; then
    sed -i 's/^let wasm_bindgen =/let lzma_bindgen =/' "${LZMA_STREAM_WASM_PKG}/lzma_stream_wasm.js"
fi

echo "==> Building bundled worker asset…"
mkdir -p assets/lzma-stream-wasm assets/supportfile-wasm
cat \
    ../src/wasm-bridge.js \
    ../src/parsers/unix.js \
    ../src/parsers/services.js \
    ../src/parsers/events.js \
    ../src/parsers/azure.js \
    ../src/parsers/cluster.js \
    ../src/parsers/storage.js \
    ../src/parsers/hana.js \
    ../src/parsers/networking.js \
    ../src/parsers/network-interfaces.js \
    ../src/parsers/vmcore.js \
    ../src/parsers/debugfs.js \
    ../src/worker.js > assets/liblzma-streaming-worker.js

cp "${LZMA_STREAM_WASM_PKG}/lzma_stream_wasm.js"      assets/lzma-stream-wasm/
cp "${LZMA_STREAM_WASM_PKG}/lzma_stream_wasm_bg.wasm" assets/lzma-stream-wasm/
cp "${SUPPORTFILE_WASM_PKG}/supportfile_wasm.js"     assets/supportfile-wasm/
cp "${SUPPORTFILE_WASM_PKG}/supportfile_wasm_bg.wasm" assets/supportfile-wasm/

echo "==> Cleaning previous build output…"
rm -rf dist .stage

PUBLIC_URL="${PUBLIC_URL:-./}"
ASSET_VERSION="${ASSET_VERSION:-${GITHUB_SHA:-$(git rev-parse --short=12 HEAD 2>/dev/null || echo dev)}}"
export ASSET_VERSION

echo "==> Running trunk build (release, public URL: ${PUBLIC_URL}, asset version: ${ASSET_VERSION})…"
trunk build --release --public-url "$PUBLIC_URL" "$@"

echo "==> Done.  Output in dist/"
ls -lh dist/
