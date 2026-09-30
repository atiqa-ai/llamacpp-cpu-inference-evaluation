#!/usr/bin/env bash
# Deploy a local GGUF model with llama-server.
#
# Runs the server in the background, records its PID, and waits until the
# health endpoint reports ready. Pair with stop-model.sh and status-model.sh.
#
# Usage:
#   ./scripts/deploy.sh <model.gguf> [options]
#
# Options:
#   --profile <default|e4b|gpu>  memory profile (default: default)
#   --host <addr>                bind address (default: 127.0.0.1)
#   --port <n>                   bind port (default: 8080)
#   --api-key <key>              require this key on API requests
#   --api-key-file <path>        file with one key per line
#   --log-file <path>            llama-server log (default: .run/server.log)
#   --no-webui                   disable the bundled web UI
#   --timeout <sec>              health-wait timeout (default: 600)
#   --foreground                 run in the foreground instead of backgrounding
#   --allow-unauthenticated      permit a non-loopback bind without --api-key
set -euo pipefail

MODEL="${1:-}"
if [ -z "$MODEL" ] || [ "${MODEL#-}" != "$MODEL" ]; then
  printf 'usage: %s <model.gguf> [options]\n' "$(basename "$0")" >&2
  exit 2
fi
shift

PROFILE=default
HOST=127.0.0.1
PORT=8080
API_KEY=""
API_KEY_FILE=""
NO_WEBUI=0
FOREGROUND=0
ALLOW_UNAUTH=0
TIMEOUT=600

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT/.run"
PIDFILE="$RUN_DIR/server.pid"
LOGFILE="$RUN_DIR/server.log"
METAFILE="$RUN_DIR/server.meta"
SERVER="$ROOT/llama.cpp/build/bin/llama-server"

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)          PROFILE="${2:?--profile needs a value}"; shift 2 ;;
    --host)             HOST="${2:?--host needs a value}"; shift 2 ;;
    --port)             PORT="${2:?--port needs a value}"; shift 2 ;;
    --api-key)          API_KEY="${2:?--api-key needs a value}"; shift 2 ;;
    --api-key-file)     API_KEY_FILE="${2:?--api-key-file needs a value}"; shift 2 ;;
    --log-file)         LOGFILE="${2:?--log-file needs a value}"; shift 2 ;;
    --timeout)          TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --no-webui)         NO_WEBUI=1; shift ;;
    --foreground)       FOREGROUND=1; shift ;;
    --allow-unauthenticated) ALLOW_UNAUTH=1; shift ;;
    -h|--help)          sed -n '2,20p' "$0"; exit 0 ;;
    *)                  die "unknown option: $1 (try --help)" ;;
  esac
done

case "$PROFILE" in default|e4b|gpu) ;; *) die "unknown profile: $PROFILE" ;; esac
case "$PORT" in ''|*[!0-9]*) die "--port must be a number, got: $PORT" ;; esac
case "$TIMEOUT" in ''|*[!0-9]*) die "--timeout must be a number, got: $TIMEOUT" ;; esac

# --- preflight --------------------------------------------------------------
[ -f "$MODEL" ] || die "model file not found: $MODEL"
case "$MODEL" in /*) ;; *) MODEL="$PWD/$MODEL" ;; esac
[ -x "$SERVER" ] || die "llama-server not built at $SERVER — run ./scripts/setup.sh first"
command -v curl >/dev/null 2>&1 || die "curl is required for the health check"

# Refuse an unauthenticated non-loopback bind: the API has no auth by default,
# so exposing it on a routable interface would hand anyone on the LAN the model.
case "$HOST" in
  127.0.0.1|localhost|::1|"[$HOST]") ;;
  *)
    if [ -z "$API_KEY" ] && [ -z "$API_KEY_FILE" ] && [ "$ALLOW_UNAUTH" -eq 0 ]; then
      die "refusing to bind $HOST without authentication: pass --api-key <key> (recommended),
       --api-key-file <path>, or --allow-unauthenticated to override knowingly"
    fi
    log "WARNING: binding $HOST — ensure the host firewall restricts access"
    ;;
esac

if [ -f "$PIDFILE" ]; then
  old="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    die "already running (pid $old) on a previous deployment — run ./scripts/stop-model.sh first"
  fi
  log "clearing stale pid file (pid $old not running)"
  rm -f "$PIDFILE"
fi

if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$PORT\$"; then
  die "port $PORT is already in use by another process"
fi

# --- build server args ------------------------------------------------------
# run-model.sh owns the profile -> flag mapping; deploy.sh only supplies the
# deployment-specific options, so that logic lives in exactly one place.
ARGS=(--host "$HOST" --port "$PORT" --log-file "$LOGFILE")
[ -n "$API_KEY" ] && ARGS+=(--api-key "$API_KEY")
[ -n "$API_KEY_FILE" ] && ARGS+=(--api-key-file "$API_KEY_FILE")
[ "$NO_WEBUI" -eq 1 ] && ARGS+=(--no-webui)

if [ "$FOREGROUND" -eq 1 ]; then
  log "running in the foreground (Ctrl-C to stop) — not writing a pid file"
  exec "$ROOT/scripts/run-model.sh" "$MODEL" "$PROFILE" "${ARGS[@]}"
fi

# --- launch -----------------------------------------------------------------
mkdir -p "$RUN_DIR"
log "model   $MODEL ($(ls -lh "$MODEL" | awk '{print $5}'))"
log "profile $PROFILE"
log "binding $HOST:$PORT${API_KEY:+ (api-key required)}${API_KEY_FILE:+ (api-key file)}"
log "log     $LOGFILE"

"$ROOT/scripts/run-model.sh" "$MODEL" "$PROFILE" "${ARGS[@]}" > /dev/null 2>&1 &
PID=$!
echo "$PID" > "$PIDFILE"
{
  echo "pid=$PID"
  echo "model=$MODEL"
  echo "profile=$PROFILE"
  echo "host=$HOST"
  echo "port=$PORT"
  echo "log=$LOGFILE"
  echo "started=$(date -Is)"
} > "$METAFILE"

# --- wait for ready ---------------------------------------------------------
log "waiting for health endpoint (timeout ${TIMEOUT}s, pid $PID)"
ready=0
for _ in $(seq 1 "$TIMEOUT"); do
  if ! kill -0 "$PID" 2>/dev/null; then
    log "server process exited during startup — last log lines:"
    tail -n 15 "$LOGFILE" 2>/dev/null | sed 's/^/    /' >&2 || true
    rm -f "$PIDFILE"
    exit 1
  fi
  if curl -sf --max-time 3 "http://$HOST:$PORT/health" > /dev/null 2>&1; then
    ready=1; break
  fi
  sleep 1
done

if [ "$ready" -ne 1 ]; then
  log "timed out after ${TIMEOUT}s waiting for /health"
  log "last log lines:"
  tail -n 15 "$LOGFILE" 2>/dev/null | sed 's/^/    /' >&2 || true
  printf 'note: on CPU a large model can take minutes to load; raise --timeout if needed\n' >&2
  exit 1
fi

log "ready  http://$HOST:$PORT  (pid $PID)"
log "check  ./scripts/status-model.sh"
log "stop   ./scripts/stop-model.sh"