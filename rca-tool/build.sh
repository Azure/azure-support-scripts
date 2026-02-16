#!/bin/bash
# Build script for RCA Tool
# Delegates to web/ directory for the actual build

set -e

echo "Building RCA Tool..."

# Generate static HTML documentation from JSDoc comments
echo "Generating API documentation..."
rm -rf docs
npx jsdoc -c jsdoc.json

cd web
bash build.sh

# Copy API docs into the web dist so they're served at /docs/
echo "Copying API documentation into dist..."
cp -r ../docs dist/docs

echo ""
echo "Web build complete! Output in web/dist/"
