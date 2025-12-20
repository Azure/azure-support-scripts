#!/bin/bash
# Build script for RCA Tool
# Copies necessary files to public directory and triggers Vite build

set -e

echo "Building RCA Tool..."

# Clean and prepare directories
echo "Preparing directories..."
rm -rf public dist
mkdir -p public

# Copy worker and utility files to public
echo "Copying worker files..."
cp src/worker.js public/liblzma-streaming-worker.js
cp src/utils.js public/utils.js

# Copy parsers directory
echo "Copying parsers..."
mkdir -p public/parsers
cp -r src/parsers/*.js public/parsers/

# Create symlink for development (tests use http-server from root)
# This allows tests to access parsers via /dist/parsers/ path
if [ ! -L "parsers" ] && [ ! -d "parsers" ]; then
    ln -s dist/parsers parsers
    echo "Created symlink: parsers -> dist/parsers"
fi

# Copy WASM files
echo "Copying WASM modules..."
cp -r liblzma-wasm public/

# Run Vite build
echo "Running Vite build..."
npx vite build

echo "Build complete! Output in dist/"
echo "Run 'npm run preview' to test the build"
