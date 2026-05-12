#!/bin/bash
# Build script for RCA Tool Web Interface
# Copies necessary files to public directory and triggers Vite build

set -e

echo "Building RCA Tool Web Interface..."

# Clean and prepare directories
echo "Preparing directories..."
rm -rf public dist
mkdir -p public

# Copy worker and utility files to public (from shared src/ at rca-tool root)
echo "Copying worker files..."
cp ../src/worker.js public/liblzma-streaming-worker.js
cp ../src/utils.js public/utils.js
cp ../src/performance.js public/performance.js
cp ../src/wasm-bridge.js public/wasm-bridge.js

# Copy parsers directory
echo "Copying parsers..."
mkdir -p public/parsers
cp -r ../src/parsers/*.js public/parsers/

# Copy WASM files
echo "Copying WASM modules..."
cp -r liblzma-wasm public/

# Copy supportfile_core WASM package (produced by `wasm-pack build --target web`
# in ../lib/supportfile_wasm).  Worker.js loads supportfile-wasm/supportfile_wasm.js
# at runtime via importScripts.
echo "Copying supportfile WASM bundle..."
SUPPORTFILE_WASM_DIR="../lib/supportfile_wasm/pkg"
if [ -d "$SUPPORTFILE_WASM_DIR" ]; then
    mkdir -p public/supportfile-wasm
    cp "$SUPPORTFILE_WASM_DIR"/supportfile_wasm.js public/supportfile-wasm/
    cp "$SUPPORTFILE_WASM_DIR"/supportfile_wasm_bg.wasm public/supportfile-wasm/
else
    echo "ERROR: supportfile_wasm/pkg not found. Build it with:" >&2
    echo "  (cd ../lib/supportfile_wasm && wasm-pack build --target no-modules --release)" >&2
    exit 1
fi

# Run Vite build
echo "Running Vite build..."
npx vite build

echo "Build complete! Output in dist/"
echo "Run 'npm run preview' to test the build"
