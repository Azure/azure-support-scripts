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

if [[ "${SKIP_WASM_BUILD:-0}" != "1" ]]; then
    echo "==> Building supportfile WASM (wasm-pack, target=no-modules, release)…"
    (cd "${SUPPORTFILE_WASM_DIR}" && wasm-pack build --target no-modules --release --out-dir pkg)
else
    echo "==> SKIP_WASM_BUILD=1 — using existing ${SUPPORTFILE_WASM_PKG}/"
fi

echo "==> Copying JS assets…"
mkdir -p assets/parsers assets/liblzma-wasm/dist-streaming assets/supportfile-wasm
cp ../src/worker.js           assets/liblzma-streaming-worker.js
cp ../src/parsers/*.js        assets/parsers/
cp ../src/utils.js            assets/
cp ../src/performance.js      assets/
cp ../src/wasm-bridge.js      assets/
# liblzma streaming WASM: produced by `../web/liblzma-wasm/build-liblzma-streaming.sh`
# (the only piece of the legacy web/ tree that web-leptos still consumes; move
# it out of web/ when the legacy interface is fully retired).
cp -r ../web/liblzma-wasm/dist-streaming/* assets/liblzma-wasm/dist-streaming/
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
