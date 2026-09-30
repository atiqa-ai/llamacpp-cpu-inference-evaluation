#!/usr/bin/env bash
# Run llama-perplexity on the fixed corpus for one model file.
# Usage: run_ppl.sh <tag> <model_path> <outdir> <bindir>
set -u
TAG="$1"; MODEL="$2"; OUT="$3"; BIN="$4"
CORPUS="/home/devops/local-llm-llama-cpp/benchmarks/quantization-track/eval/ppl_corpus.txt"
OUTP="$OUT/$TAG.ppl.txt"
"$BIN/llama-perplexity" -m "$MODEL" -f "$CORPUS" -c 256 -t 4 --chunks -1 \
  > "$OUTP" 2>&1
echo "PPL_EXIT=$?"
grep -E "Final estimate|Final estimate \(without" "$OUTP" || cat "$OUTP" | tail -5