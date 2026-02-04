#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMMIT=$(git rev-parse --short HEAD 2>/dev/null || true)
if [[ -z "$COMMIT" ]]; then
  echo "Error: not a git repository or cannot read commit" >&2
  exit 1
fi

tmp_base=$(mktemp -t ocr_buildXXXXXX)
tmp="${tmp_base}.swift"
trap 'rm -f "$tmp"' EXIT

# Replace placeholder and compile without modifying the working tree
sed "s/__GIT_COMMIT__/${COMMIT}/g" ocr.swift > "$tmp"

swiftc "$tmp" -o ocr_tool

echo "Built ocr_tool with commit $COMMIT"
