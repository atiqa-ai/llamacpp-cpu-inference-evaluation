#!/usr/bin/env bash
# Full per-file benchmark pipeline: bench + ppl + eval suite.
# Usage: run_file.sh <tag> <model_path> [full|half]
#   full -> bench + ppl + eval   (default)
#   half -> bench + eval, no ppl
set -euo pipefail

[ "$#" -ge 2 ] || { echo "usage: $(basename "$0") <tag> <model_path> [full|half]" >&2; exit 2; }

TAG="$1"; MODEL="$2"; MODE="${3:-full}"
case "$MODE" in
  full|half) ;;
  *) echo "error: unknown mode '$MODE' (expected: full, half)" >&2; exit 2 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$T/../.." && pwd)"
BIN="${LLAMA_BIN:-$ROOT/llama.cpp/build/bin}"
OUT="$T/results"

[ -x "$BIN/llama-bench" ] || { echo "error: $BIN/llama-bench not found — run ./scripts/setup.sh" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "error: model not found: $MODEL" >&2; exit 1; }

mkdir -p "$OUT"
log(){ echo "[$(date +%T)] $*" | tee -a "$OUT/master.log"; }

# Run one stage, mirroring its output into master.log. A failing stage is
# recorded as a WARNING and the remaining stages still run — a benchmark
# campaign wants every artifact it can get — but the failure is now visible in
# master.log instead of being masked by tee's exit status.
run_stage(){
  local label="$1"; shift
  local rc=0
  echo "[$(date +%T)] --- $label ---" | tee -a "$OUT/master.log"
  "$@" 2>&1 | tee -a "$OUT/master.log" || rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    echo "[$(date +%T)] WARNING: $label exited $rc — see output above" | tee -a "$OUT/master.log"
  fi
  return 0
}

log "=== BEGIN $TAG ($MODE) ==="
run_stage bench bash "$HERE/run_bench.sh" "$TAG" "$MODEL" "$OUT" "$BIN"
if [ "$MODE" = "full" ]; then
  run_stage ppl  bash "$HERE/run_ppl.sh"  "$TAG" "$MODEL" "$OUT" "$BIN"
fi
run_stage eval bash "$HERE/run_eval.sh" "$TAG" "$MODEL" "$OUT" "$BIN"
log "=== END $TAG ==="