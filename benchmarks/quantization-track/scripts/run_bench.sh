#!/usr/bin/env bash
# Generic per-file benchmark helper.
# Usage: run_one.sh <tag> <model_path> <outdir> <bins>
set -u
TAG="$1"; MODEL="$2"; OUT="$3"; BIN="$4"
LOG="$OUT/$TAG.log"
echo "[$(date +%T)] START $TAG" > "$LOG"

# --- file size ---
ls -l "$MODEL" | awk '{printf "size_bytes=%d\n", $5}' >> "$LOG"
ls -lh "$MODEL" | awk '{printf "size_human=%s\n", $5}' >> "$LOG"

# --- llama-bench (pp128 / tg64, warmup + 2 reps) with peak RSS ---
echo "[$(date +%T)] bench" >> "$LOG"
/usr/bin/time -v "$BIN/llama-bench" -m "$MODEL" -p 128 -n 64 -r 2 -t 4 \
  2> "$OUT/$TAG.bench.time" > "$OUT/$TAG.bench.md"
echo "bench_exit=$?" >> "$LOG"
grep -E "Maximum resident set size" "$OUT/$TAG.bench.time" | awk '{printf "bench_maxrss_kb=%s\n", $6}' >> "$LOG"

echo "[$(date +%T)] DONE $TAG" >> "$LOG"