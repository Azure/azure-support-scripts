#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="$SCRIPT_DIR/.build-venv"
if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
fi

. "$VENV_DIR/bin/activate"
python -m pip install -q --upgrade pip maturin
rm -rf "$SCRIPT_DIR/dist"
maturin build --release --out dist

echo
find "$SCRIPT_DIR/dist" -maxdepth 1 -name '*.whl' -print | sort
