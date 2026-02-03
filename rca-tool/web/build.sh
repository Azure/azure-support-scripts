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

# Copy parsers directory
echo "Copying parsers..."
mkdir -p public/parsers
cp -r ../src/parsers/*.js public/parsers/

# Copy WASM files
echo "Copying WASM modules..."
cp -r liblzma-wasm public/

# Run Vite build
echo "Running Vite build..."
npx vite build

echo "Build complete! Output in dist/"
echo "Run 'npm run preview' to test the build"
