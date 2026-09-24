#!/usr/bin/env bash
# Builds dist/<name>_<version>.zip with a top-level <name>_<version>/ folder, as Factorio expects.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
name="$(jq -r .name "$root/cashflow/info.json")"
version="$(jq -r .version "$root/cashflow/info.json")"
folder="${name}_${version}"
out="$root/dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R "$root/cashflow" "$stage/$folder"
mkdir -p "$out"
rm -f "$out/$folder.zip"
(cd "$stage" && zip -rq "$out/$folder.zip" "$folder" -x '*.DS_Store')
echo "$out/$folder.zip"
