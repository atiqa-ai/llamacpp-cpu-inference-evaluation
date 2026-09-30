#!/usr/bin/env bash
# Provision llama.cpp from source and build the CPU backend.
# Usage: ./scripts/setup.sh [install_dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${1:-$ROOT}"
SRC_DIR="$INSTALL_DIR/llama.cpp"
BUILD_DIR="$SRC_DIR/build"
JOBS="$(nproc)"

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

# --- toolchain prerequisites -------------------------------------------------
for tool in git cmake make cc; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
command -v c++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 \
  || die "missing required tool: c++ / g++"

# --- clone -------------------------------------------------------------------
if [ -d "$SRC_DIR/.git" ]; then
  log "llama.cpp already present at $SRC_DIR — skipping clone"
else
  log "cloning llama.cpp into $SRC_DIR"
  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$SRC_DIR"
fi

# --- build ------------------------------------------------------------------
# CPU-only Release build. This matches the configuration every measurement in
# docs/ and benchmarks/ was taken under; see docs/02-environment.md.
log "configuring (Release, CPU backend only)"
cmake -B "$BUILD_DIR" \
  -S "$SRC_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=OFF \
  -DGGML_NATIVE=ON \
  -DGGML_LLAMAFILE=ON \
  -DLLAMA_BUILD_SERVER=ON

log "building with $JOBS jobs (this takes a while)"
cmake --build "$BUILD_DIR" --config Release -j "$JOBS"

# --- verify ------------------------------------------------------------------
BINS=(llama-cli llama-server llama-bench llama-perplexity)
log "verifying binaries in $BUILD_DIR/bin"
missing=0
for b in "${BINS[@]}"; do
  if [ -x "$BUILD_DIR/bin/$b" ]; then
    log "  ok  $b"
  else
    log "  MISSING  $b"
    missing=1
  fi
done
[ "$missing" -eq 0 ] || die "build completed but expected binaries are absent"

log "done: $($BUILD_DIR/bin/llama-cli --version 2>&1 | head -1)"
log "next: place a .gguf model and run ./scripts/run-model.sh"