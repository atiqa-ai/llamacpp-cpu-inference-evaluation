#!/usr/bin/env bash
# Run fixed qualitative eval suite (11 prompts) for one model file.
# Usage: run_eval.sh <tag> <model_path> <outdir> <bindir>
set -u
TAG="$1"; MODEL="$2"; OUT="$3"; BIN="$4"
T=/home/devops/local-llm-llama-cpp/benchmarks/quantization-track
GEN_PROG="$T/eval/prompts.py"
SEED=100
TOKENS=48
OUTTSV="$OUT/$TAG.eval.tsv"
printf "prompt_id\twall_s\toutput\n" > "$OUTTSV"

while IFS=$'\t' read -r pid prompt; do
  [ -z "$pid" ] && continue
  t0=$(date +%s)
  resp=$($BIN/llama-cli -m "$MODEL" -p "$prompt" -n "$TOKENS" --seed "$SEED" \
         -t 4 -c 1024 --no-display-prompt --no-warmup -rea off -st </dev/null 2>/dev/null | \
         python3 -c "
import sys,re
PREF=('Loading model','\u25c4','\u2588','\u2580','build ','model ','ftype','modalities','available commands','/exit','/regen','/clear','/read','/glob','> ')
SUB=('[ Prompt:','[Start thinking]','Thinking Process','Exiting...','\u2591','\u2588')
out=[]
for ln in sys.stdin:
    s=ln.strip()
    if not s: continue
    if s.startswith(PREF): continue
    if any(x in s for x in SUB): continue
    if s.replace('-','').replace('|','').replace(chr(92),'').replace('/','')=='' and len(s)<20 and len(s)>0: continue
    out.append(s)
print(' '.join(out))
" )
  t1=$(date +%s)
  wall=$((t1-t0))
  printf "%s\t%d\t%s\n" "$pid" "$wall" "$resp" >> "$OUTTSV"
  echo "[$(date +%T)] eval $TAG $pid done in ${wall}s"
done < <(python3 "$GEN_PROG")
echo "EVAL_DONE $TAG"