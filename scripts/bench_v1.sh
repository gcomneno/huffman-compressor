#!/usr/bin/env bash
set -euo pipefail

# Directory di questo script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Root del repo = cartella padre di scripts/
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PYTHON="python3"
SCRIPT="$ROOT_DIR/src/python/gcc_huffman.py"

echo "=== huffman-compressor v1 benchmark ==="
echo "Using: $PYTHON $SCRIPT"
echo

FILES=(
  "$ROOT_DIR/tests/data/small.txt"
  "$ROOT_DIR/tests/data/medium.txt"
  "$ROOT_DIR/tests/data/large.txt"
)

for INPUT in "${FILES[@]}"; do
  if [[ ! -f "$INPUT" ]]; then
    echo "[WARN] Skipping missing file: $INPUT"
    echo
    continue
  fi

  OUT="${INPUT}.v1.bench.gcc"

  ORIG_SIZE=$(stat -c%s "$INPUT")
  REL_PATH="${INPUT#$ROOT_DIR/}"
  echo "--- File: $REL_PATH ($ORIG_SIZE bytes) ---"

  # comprime con v1 (silenziamo l'output, teniamo solo le nostre stats)
  $PYTHON "$SCRIPT" c1 "$INPUT" "$OUT" >/dev/null

  COMP_SIZE=$(stat -c%s "$OUT")
  RATIO=$(awk "BEGIN { if ($ORIG_SIZE > 0) printf \"%.3f\", $COMP_SIZE / $ORIG_SIZE; else print \"0\" }")

  echo "Compressed: ${OUT#$ROOT_DIR/} ($COMP_SIZE bytes)"
  echo "Ratio     : $RATIO (1.0 = no compression)"
  echo

done

echo "=== Done v1 benchmark ==="
