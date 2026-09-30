#!/usr/bin/env bash
# Stop the llama-server instance started by deploy.sh.
#
# Sends SIGTERM, waits for a clean exit, then escalates to SIGKILL. The PID is
# validated against the recorded metadata so a recycled PID is never signalled.
#
# Usage: ./scripts/stop-model.sh [--timeout <sec>]
set -euo pipefail

TIMEOUT=30

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT/.run"
PIDFILE="$RUN_DIR/server.pid"

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *)         die "unknown option: $1" ;;
  esac
done
case "$TIMEOUT" in ''|*[!0-9]*) die "--timeout must be a number, got: $TIMEOUT" ;; esac

[ -f "$PIDFILE" ] || die "no pid file at $PIDFILE — nothing to stop (is it running via --foreground?)"

PID="$(cat "$PIDFILE" 2>/dev/null || true)"
[ -n "$PID" ] || die "pid file is empty"

if ! kill -0 "$PID" 2>/dev/null; then
  log "pid $PID is not running — clearing stale pid file"
  rm -f "$PIDFILE"
  exit 0
fi

# Guard against signalling an unrelated process that reused the PID.
#
# Compare the process's resolved executable against the expected binary rather
# than grepping its command line: a shell wrapper's cmdline contains the whole
# invoking command text, so a substring match would accept any process that
# merely mentions llama-server as an argument.
EXPECTED_EXE="$(readlink -f "$ROOT/llama.cpp/build/bin/llama-server" 2>/dev/null || true)"
ACTUAL_EXE="$(readlink -f "/proc/$PID/exe" 2>/dev/null || true)"
if [ -n "$ACTUAL_EXE" ]; then
  if [ "$ACTUAL_EXE" != "$EXPECTED_EXE" ]; then
    die "pid $PID is running '$ACTUAL_EXE', not llama-server; refusing to signal it.
       This is almost certainly a recycled PID. Remove $PIDFILE once you have
       confirmed what pid $PID is."
  fi
else
  printf 'warning: cannot read /proc/%s/exe; proceeding without the identity check\n' "$PID" >&2
fi

log "sending SIGTERM to pid $PID"
kill -TERM "$PID" 2>/dev/null || true

for _ in $(seq 1 "$TIMEOUT"); do
  if ! kill -0 "$PID" 2>/dev/null; then
    log "stopped cleanly"
    rm -f "$PIDFILE"
    exit 0
  fi
  sleep 1
done

log "still alive after ${TIMEOUT}s — escalating to SIGKILL"
kill -KILL "$PID" 2>/dev/null || true
sleep 1
if kill -0 "$PID" 2>/dev/null; then
  die "could not stop pid $PID"
fi
log "killed"
rm -f "$PIDFILE"