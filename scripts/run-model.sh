#!/usr/bin/env bash
# Launch llama-server against a local GGUF model.
#
# Usage:
#   ./scripts/run-model.sh <model.gguf> [profile] [extra llama-server args...]
#
# Profiles set the context/batch flags that were verified to fit this class of
# hardware (CPU-only VM, ~7.7 GiB RAM, 4 cores):
#   default  - llama-server stock defaults; verified for Gemma 4 E2B / Qwen3.5-4B
#   e4b      - reduced context/batch; required for Gemma 4 E4B on this VM
#   gpu      - offload all layers to an NVIDIA GPU (requires a GGML_CUDA=ON build)
set -euo pipefail

MODEL="${1:-}"
[ -n "$MODEL" ] || { printf 'usage: %s <model.gguf> [default|e4b|gpu] [args...]\n' "$0" >&2; exit 2; }
shift

# The second positional is optional: treat it as a profile only if it names one.
PROFILE=default
case "${1:-}" in
  default|e4b|gpu) PROFILE="$1"; shift ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/llama.cpp/build/bin"
SERVER="$BIN/llama-server"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f "$MODEL" ] || die "model file not found: $MODEL"
case "$MODEL" in /*) ;; *) MODEL="$PWD/$MODEL" ;; esac
[ -x "$SERVER" ] || die "llama-server not found at $SERVER — run ./scripts/setup.sh first"

# Memory sizing. Defaults are llama-server's own (-b 2048, -ub 512); only the
# e4b profile deviates, because Gemma 4 E4B needs the reduced window to stay
# inside ~7.7 GiB of RAM on this VM.
ARGS=(-m "$MODEL")
# Only inject --host/--port when the caller did not already pass one; passing
# both makes llama-server warn about a duplicated argument.
have_flag(){ local f; for f in "$@"; do [ "$f" = "$1" ] && return 0; done; return 1; }
have_flag --host "$@" || have_flag -h "$@" || ARGS+=(--host "$HOST")
have_flag --port "$@" || have_flag -p "$@" || ARGS+=(--port "$PORT")
case "$PROFILE" in
  default) log "profile=default (stock context/batch)" ;;
  e4b)
    ARGS+=(-c 1024 -b 128 -ub 64)
    log "profile=e4b (reduced context/batch: -c 1024 -b 128 -ub 64)"
    ;;
  gpu)
    ARGS+=(-ngl 99)
    log "profile=gpu (offloading all layers; needs a GGML_CUDA=ON build)"
    ;;
  *) die "unknown profile: $PROFILE (expected: default, e4b, or gpu)" ;;
esac

SIZE=$(ls -lh "$MODEL" | awk '{print $5}')
log "model=$MODEL ($SIZE)"
log "serving on http://${HOST}:${PORT} (override by passing --host/--port)"
printf '\n  smoke test:\n    curl -s http://%s:%s/health\n    curl -s http://%s:%s/v1/chat/completions \\\n      -H "Content-Type: application/json" \\\n      -d %s\n\n' \
  "$HOST" "$PORT" "$HOST" "$PORT" \
  "{\"model\":\"local\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":64}" >&2

exec "$SERVER" "${ARGS[@]}" "$@"