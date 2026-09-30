#!/usr/bin/env bash
# Run the fixed qualitative eval suite (11 prompts) for one model file.
# Usage: run_eval.sh <tag> <model_path> <outdir> <bindir>
set -euo pipefail

[ "$#" -eq 4 ] || { echo "usage: $(basename "$0") <tag> <model_path> <outdir> <bindir>" >&2; exit 2; }

TAG="$1"; MODEL="$2"; OUT="$3"; BIN="$4"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN_PROG="$HERE/../eval/prompts.py"
SEED=100
TOKENS=48
OUTTSV="$OUT/$TAG.eval.tsv"

[ -x "$BIN/llama-cli" ] || { echo "error: $BIN/llama-cli not found" >&2; exit 1; }
[ -f "$GEN_PROG" ] || { echo "error: prompt set missing: $GEN_PROG" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "error: model not found: $MODEL" >&2; exit 1; }

EXPECTED=$(python3 "$GEN_PROG" | grep -c .)
printf "prompt_id\twall_s\toutput\n" > "$OUTTSV"

while IFS=$'\t' read -r pid prompt; do
  [ -z "$pid" ] && continue
  t0=$(date +%s)
  # The inline filter strips llama-cli's banner/progress output so the TSV holds
  # only model responses. Logic is fixed across quants — do not alter it without
  # invalidating comparison against already-recorded runs.
  resp=$("$BIN/llama-cli" -m "$MODEL" -p "$prompt" -n "$TOKENS" --seed "$SEED" \
         -t 4 -c 1024 --no-display-prompt --no-warmup -rea off -st < /dev/null 2>/dev/null | \
         python3 -c '
import sys
PREF = ("Loading model", "\u25c4", "\u2588", "\u2580", "build ", "model ", "ftype",
        "modalities", "available commands", "/exit", "/regen", "/clear", "/read",
        "/glob", "> ")
SUB  = ("[ Prompt:", "[Start thinking]", "Thinking Process", "Exiting...", "\u2591", "\u2588")
out = []
for ln in sys.stdin:
    s = ln.strip()
    if not s: continue
    if s.startswith(PREF): continue
    if any(x in s for x in SUB): continue
    if s.replace("-", "").replace("|", "").replace(chr(92), "").replace("/", "") == "" and len(s) < 20 and len(s) > 0: continue
    out.append(s)
print(" ".join(out))
')
  t1=$(date +%s)
  wall=$((t1 - t0))
  printf "%s\t%d\t%s\n" "$pid" "$wall" "$resp" >> "$OUTTSV"
  echo "[$(date +%T)] eval $TAG $pid done in ${wall}s"
done < <(python3 "$GEN_PROG")

# Guard against a silently truncated suite. The recorded e2b_qat run produced
# 2 of 11 rows after a generator failure and still reported success; comparing
# against EXPECTED makes that condition an error instead.
GOT=$(( $(wc -l < "$OUTTSV") - 1 ))
if [ "$GOT" -ne "$EXPECTED" ]; then
  echo "EVAL_INCOMPLETE $TAG: $GOT/$EXPECTED prompts recorded in $OUTTSV" >&2
  exit 1
fi
echo "EVAL_DONE $TAG ($GOT/$EXPECTED prompts)"