#!/usr/bin/env bash
# Full per-file pipeline: bench + ppl + eval suite (+ optional eval-only path)
# Usage: run_file.sh <tag> <model_path> [mode]
#   mode = full  -> bench + ppl + eval   (default)
#   mode = half  -> bench + eval, no ppl
set -u
TAG="$1"; MODEL="$2"; MODE="${3:-full}"
T=/home/devops/local-llm-llama-cpp/benchmarks/quantization-track
BIN=/home/devops/local-llm-llama-cpp/llama.cpp/build/bin
OUT=$T/results
mkdir -p "$OUT"
log(){ echo "[$(date +%T)] $*" | tee -a "$OUT/master.log"; }

log "=== BEGIN $TAG ($MODE) ==="
bash $T/scripts/run_bench.sh "$TAG" "$MODEL" "$OUT" "$BIN" 2>&1 | tee -a "$OUT/master.log"
if [ "$MODE" = "full" ]; then
  bash $T/scripts/run_ppl.sh  "$TAG" "$MODEL" "$OUT" "$BIN" 2>&1 | tee -a "$OUT/master.log"
fi
bash $T/scripts/run_eval.sh  "$TAG" "$MODEL" "$OUT" "$BIN" 2>&1 | tee -a "$OUT/master.log"
log "=== END $TAG ==="