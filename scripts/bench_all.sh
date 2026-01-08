#!/usr/bin/env bash
set -euo pipefail

# Directory di questo script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Root del repo = cartella padre di scripts/
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PYTHON="python3"
DRIVER="$ROOT_DIR/src/python/gcc_huffman.py"

echo "=== huffman-compressor benchmark (v1–v4) ==="
echo "Using: $PYTHON $DRIVER"
echo

# NB: qui uso tests/data/ perché è quello che ti stampa già bench_v1.sh.
# Se nel tuo repo è tests/testdata/, basta cambiare qui.
FILES=(
  "$ROOT_DIR/tests/data/small.txt"
  "$ROOT_DIR/tests/data/medium.txt"
  "$ROOT_DIR/tests/data/large.txt"
)

# step:mode:etichetta
STEPS=(
  "1:c1:Step1 (bytes)"
  "2:c2:Step2 (V/C/O)"
  "3:c3:Step3 (sillabe)"
  "4:c4:Step4 (parole)"
)

for INPUT in "${FILES[@]}"; do
  if [[ ! -f "$INPUT" ]]; then
    echo "[WARN] Skipping missing file: $INPUT"
    echo
    continue
  fi

  ORIG_SIZE=$(stat -c%s "$INPUT")
  REL_PATH="${INPUT#$ROOT_DIR/}"
  echo "--- File: $REL_PATH ($ORIG_SIZE bytes) ---"

  for ENTRY in "${STEPS[@]}"; do
    IFS=: read -r STEP MODE LABEL <<< "$ENTRY"

    OUT="${INPUT}.v${STEP}.bench.gcc"

    echo "  [$LABEL]"

    # Provo la compressione; se fallisce, stampo FAIL ma non interrompo il loop
    if $PYTHON "$DRIVER" "$MODE" "$INPUT" "$OUT" >/dev/null 2>&1; then
      COMP_SIZE=$(stat -c%s "$OUT")
      RATIO=$(awk "BEGIN { if ($ORIG_SIZE > 0) printf \"%.3f\", $COMP_SIZE / $ORIG_SIZE; else print \"0\" }")
      echo "    OK   size=$COMP_SIZE  ratio=$RATIO (1.0 = no compression)"
    else
      echo "    FAIL (compression error, probabilmente VOCAB limit o altra constraint)"
    fi
  done

  echo
done

echo "=== Done benchmark v1–v4 ==="
