#!/usr/bin/env bash
# Run llama-perplexity on the fixed corpus for one model file.
# Usage: run_ppl.sh <tag> <model_path> <outdir> <bindir>
set -euo pipefail

[ "$#" -eq 4 ] || { echo "usage: $(basename "$0") <tag> <model_path> <outdir> <bindir>" >&2; exit 2; }

TAG="$1"; MODEL="$2"; OUT="$3"; BIN="$4"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS="$HERE/../eval/ppl_corpus.txt"
OUTP="$OUT/$TAG.ppl.txt"

[ -x "$BIN/llama-perplexity" ] || { echo "error: $BIN/llama-perplexity not found" >&2; exit 1; }
[ -f "$CORPUS" ] || { echo "error: perplexity corpus missing: $CORPUS" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "error: model not found: $MODEL" >&2; exit 1; }

# Capture the exit code before logging it, so the failure is recorded rather
# than preempted by `set -e`.
rc=0
"$BIN/llama-perplexity" -m "$MODEL" -f "$CORPUS" -c 256 -t 4 --chunks -1 \
  > "$OUTP" 2>&1 || rc=$?
echo "PPL_EXIT=$rc"
grep -E "Final estimate" "$OUTP" || tail -5 "$OUTP"

[ "$rc" -eq 0 ] || exit "$rc"