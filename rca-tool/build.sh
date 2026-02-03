#!/bin/bash
# Build script for RCA Tool
# Delegates to web/ directory for the actual build

set -e

echo "Building RCA Tool..."

cd web
bash build.sh

echo ""
echo "Web build complete! Output in web/dist/"
