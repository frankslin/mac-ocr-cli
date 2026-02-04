#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMMIT=$(git rev-parse --short HEAD 2>/dev/null || true)
if [[ -z "$COMMIT" ]]; then
  echo "Error: not a git repository or cannot read commit" >&2
  exit 1
fi
export COMMIT

tmp_base=$(mktemp -t ocr_buildXXXXXX)
tmp="${tmp_base}.swift"
trap 'rm -f "$tmp"' EXIT

# Replace placeholder and compile without modifying the working tree
python3 - <<'PY' > "$tmp"
import os

commit = os.environ.get("COMMIT", "")
if not commit:
    raise SystemExit("Error: COMMIT is empty")

with open("ocr.swift", "r", encoding="utf-8") as f:
    data = f.read()

data = data.replace("__GIT_COMMIT_VALUE__", commit, 1)
print(data, end="")
PY

swiftc "$tmp" -o ocr_tool

echo "Built ocr_tool with commit $COMMIT"
