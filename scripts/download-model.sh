#!/usr/bin/env bash
# Download a GGUF model from Hugging Face into models/.
#
# Uses plain curl (no huggingface-cli / python deps required), resumes partial
# downloads, and verifies both the transfer length and the GGUF magic bytes.
# The magic check matters: a failed request can leave an HTML error page saved
# with a .gguf name, which otherwise fails much later with a confusing
# "tensor ... not within the file bounds" error from llama.cpp.
#
# Usage:
#   ./scripts/download-model.sh --list
#   ./scripts/download-model.sh <hf-repo-id> <filename> [-o <dir>]
#   ./scripts/download-model.sh --preset <name> [-o <dir>]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/models"

# Model files used throughout this project. All three are Apache-2.0 and ship
# pre-built GGUFs, so no HF -> GGUF conversion step is required.
PRESETS="gemma-4-e2b-qat google/gemma-4-E2B-it-qat-q4_0-gguf/gemma-4-E2B-it-Q4_0.gguf
gemma-4-e4b-qat google/gemma-4-E4B-it-qat-q4_0-gguf/gemma-4-E4B-it-Q4_0.gguf
qwen3.5-4b     lmstudio-community/Qwen3.5-4B-GGUF/Qwen3.5-4B-Q4_K_M.gguf"

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

usage(){ sed -n '2,15p' "$0"; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --list)
    echo "available presets:"
    printf '%s\n' "$PRESETS" | while read -r name path; do
      printf '  %-16s %s\n' "$name" "${path%%/*}/${path##*/}"
    done
    exit 0 ;;
esac

SPEC=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --preset)
      name="${2:?--preset needs a name}"
      SPEC="$(printf '%s\n' "$PRESETS" | awk -v n="$name" '$1==n {print $2}')"
      [ -n "$SPEC" ] || die "unknown preset '$name' (try --list)"
      shift 2 ;;
    -o|--output) DEST="${2:?-o needs a directory}"; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$SPEC" ] || die "unexpected argument: $1"; SPEC="$1"; shift ;;
  esac
done

[ -n "$SPEC" ] || { usage >&2; exit 2; }

REPO="${SPEC%%/*}"
FILE="${SPEC##*/}"
[ "$FILE" != "$REPO" ] || die "spec must be <hf-repo-id>/<filename>, got: $SPEC"

URL="https://huggingface.co/$REPO/resolve/main/$FILE"
mkdir -p "$DEST"
OUT="$DEST/$FILE"

command -v curl >/dev/null 2>&1 || die "curl is required"

log "repo  $REPO"
log "file  $FILE"
log "url   $URL"
log "dest  $OUT"

# --- expected size ----------------------------------------------------------
# HF reports the blob size on the redirect target. Any specific expected size
# argument, use it instead of failing.
EXPECTED=0
if SIZE=$(curl -sIL --max-time 30 "$URL" 2>/dev/null \
          | tr -d '\r' | awk 'tolower($1)=="x-linked-size:"{s=$2} tolower($1)=="content-length:"{c=$2} END{print (s!=""?s:c)}'); then
  case "$SIZE" in ''|*[!0-9]*) EXPECTED=0 ;; *) EXPECTED="$SIZE" ;; esac
fi
if [ "$EXPECTED" -gt 0 ]; then
  log "expecting $EXPECTED bytes ($(( EXPECTED / 1024 / 1024 )) MiB)"
else
  log "could not determine expected size from server; will verify magic bytes only"
fi

# --- download (resumable) ---------------------------------------------------
PART="$OUT.part"
if [ -f "$OUT" ]; then
  if [ "$EXPECTED" -gt 0 ] && [ "$(stat -c %s "$OUT")" -eq "$EXPECTED" ]; then
    log "already present with the expected size — skipping download"
    PART="$OUT"
  else
    log "existing file does not match expected size — re-downloading"
    rm -f "$OUT"
  fi
fi

if [ "$PART" != "$OUT" ]; then
  curl -L --fail --retry 3 --retry-delay 2 -C - \
       --progress-bar -o "$PART" "$URL" \
    || die "download failed; rerun to resume from $(stat -c %s "$PART" 2>/dev/null || echo 0) bytes"
fi

# --- verify -----------------------------------------------------------------
ACTUAL="$(stat -c %s "$PART")"
if [ "$EXPECTED" -gt 0 ] && [ "$ACTUAL" -ne "$EXPECTED" ]; then
  log "size mismatch: got $ACTUAL, expected $EXPECTED"
  log "keeping the partial file at $PART — rerun this command to resume"
  exit 1
fi

MAGIC="$(head -c 4 "$PART" 2>/dev/null || true)"
if [ "$MAGIC" != "GGUF" ]; then
  log "missing GGUF magic bytes (got '$MAGIC') — this is not a GGUF file"
  log "it is most likely an HTML error page or a gated/LFS-redirect response"
  log "the partial file is kept at $PART for inspection"
  exit 1
fi

mv -f "$PART" "$OUT"
log "verified $ACTUAL bytes with valid GGUF header -> $OUT"
log "sanity check before serving:"
log "  ./llama.cpp/build/bin/llama-cli -m $OUT -p 'hi' -n 8"