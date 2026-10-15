#!/usr/bin/env bash
# Bump the version of the supportfile Rust crates from the pushed git tag.
#
# Used by .github/workflows/rust-python-packages.yml when the workflow is
# triggered by a tag of the form `v<semver>` (e.g. `v0.1.2`). The leading
# `v` is stripped and the resulting version is written to all three crate
# Cargo.toml files so the published artifacts match the tag:
#
#   - rca-tool/lib/supportfile_core    (published to crates.io as `supportfile`)
#   - rca-tool/lib/supportfile_py      (built as a Python wheel)
#   - rca-tool/lib/supportfile_wasm    (used by the Leptos front-end build)
#
# After updating Cargo.toml files, the corresponding Cargo.lock entries
# are refreshed so subsequent `cargo --locked` invocations stay green.
#
# Environment:
#   GITHUB_REF_NAME — tag name as provided by GitHub Actions (e.g. `v0.1.2`).
#                      Falls back to parsing `GITHUB_REF` if unset.

set -euo pipefail

ref_name="${GITHUB_REF_NAME:-}"
if [[ -z "$ref_name" && -n "${GITHUB_REF:-}" ]]; then
    ref_name="${GITHUB_REF#refs/tags/}"
fi

if [[ -z "$ref_name" ]]; then
    echo "ERROR: neither GITHUB_REF_NAME nor GITHUB_REF is set" >&2
    exit 1
fi

if [[ ! "$ref_name" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]]; then
    echo "ERROR: tag '$ref_name' does not look like a semver tag (expected vX.Y.Z)" >&2
    exit 1
fi

version="${ref_name#v}"
echo "Setting supportfile crate versions to $version (from tag $ref_name)"

# Repo root is the working directory when invoked by Actions; resolve relative
# to this script so it can also be run locally from anywhere.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

declare -a crate_dirs=(
    "$repo_root/rca-tool/lib/supportfile_core"
    "$repo_root/rca-tool/lib/supportfile_py"
    "$repo_root/rca-tool/lib/supportfile_wasm"
)

for dir in "${crate_dirs[@]}"; do
    toml="$dir/Cargo.toml"
    if [[ ! -f "$toml" ]]; then
        echo "ERROR: $toml not found" >&2
        exit 1
    fi
    # Replace the FIRST `version = "..."` line only (package version, not
    # dependency versions). Cargo convention places it in the [package]
    # table at the top of the file.
    sed -i -E "0,/^version[[:space:]]*=[[:space:]]*\".*\"/ s//version = \"$version\"/" "$toml"
    echo "  updated $toml"
done

# Refresh Cargo.lock entries for the renamed packages so `cargo --locked`
# continues to work in subsequent build/test/publish steps. Each crate has
# its own lockfile; path dependencies don't hit the network.
declare -A lock_updates=(
    ["$repo_root/rca-tool/lib/supportfile_core"]="supportfile"
    ["$repo_root/rca-tool/lib/supportfile_py"]="supportfile_py supportfile"
    ["$repo_root/rca-tool/lib/supportfile_wasm"]="supportfile-wasm supportfile"
)

for dir in "${!lock_updates[@]}"; do
    pkgs="${lock_updates[$dir]}"
    if [[ -f "$dir/Cargo.lock" ]]; then
        args=()
        for p in $pkgs; do
            args+=(-p "$p")
        done
        echo "  refreshing $dir/Cargo.lock for: $pkgs"
        (cd "$dir" && cargo update "${args[@]}" --offline 2>/dev/null \
            || cd "$dir" && cargo update "${args[@]}")
    fi
done

echo "Done."
