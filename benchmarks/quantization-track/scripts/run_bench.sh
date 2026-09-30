#!/usr/bin/env bash
# Generic per-file benchmark helper: llama-bench plus peak RSS.
# Usage: run_bench.sh <tag> <model_path> <outdir> <bindir>
set -euo pipefail

[ "$#" -eq 4 ] || { echo "usage: $(basename "$0") <tag> <model_path> <outdir> <bindir>" >&2; exit 2; }

TAG="$1"; MODEL="$2"; OUT="$3"; BIN="$4"
LOG="$OUT/$TAG.log"

[ -x "$BIN/llama-bench" ] || { echo "error: $BIN/llama-bench not found" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "error: model not found: $MODEL" >&2; exit 1; }

echo "[$(date +%T)] START $TAG" > "$LOG"
ls -l "$MODEL" | awk '{printf "size_bytes=%d\n", $5}' >> "$LOG"
ls -lh "$MODEL" | awk '{printf "size_human=%s\n", $5}' >> "$LOG"

echo "[$(date +%T)] bench" >> "$LOG"
rc=0
/usr/bin/time -v "$BIN/llama-bench" -m "$MODEL" -p 128 -n 64 -r 2 -t 4 \
  2> "$OUT/$TAG.bench.time" > "$OUT/$TAG.bench.md" || rc=$?
echo "bench_exit=$rc" >> "$LOG"
grep -E "Maximum resident set size" "$OUT/$TAG.bench.time" \
  | awk '{printf "bench_maxrss_kb=%s\n", $6}' >> "$LOG" || true

echo "[$(date +%T)] DONE $TAG" >> "$LOG"
[ "$rc" -eq 0 ] || exit "$rc"