#!/usr/bin/env bash
# Report on the llama-server instance started by deploy.sh.
#
# Shows the health endpoint, process state, resident memory, and system
# headroom. Exits non-zero when the server is not serving.
#
# Usage: ./scripts/status-model.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT/.run"
PIDFILE="$RUN_DIR/server.pid"
METAFILE="$RUN_DIR/server.meta"

# Defaults for when no deployment metadata exists.
HOST="127.0.0.1"; PORT="8080"; LOGFILE="$RUN_DIR/server.log"
[ -f "$METAFILE" ] && while IFS='=' read -r k v; do
  case "$k" in
    host)  HOST="$v" ;;
    port)  PORT="$v" ;;
    log)   LOGFILE="$v" ;;
  esac
done < "$METAFILE"

PID=""
[ -f "$PIDFILE" ] && PID="$(cat "$PIDFILE" 2>/dev/null || true)"

echo "deployment"
if [ -f "$METAFILE" ]; then
  sed 's/^/  /' "$METAFILE"
else
  echo "  (no deployment metadata — has deploy.sh been used?)"
fi

echo
echo "process"
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  echo "  state    running (pid $PID)"
  ps -o pid,ppid,etime,rss,vsz,args -p "$PID" 2>/dev/null | tail -n +2 | sed 's/^/  /' || true
else
  echo "  state    not running${PID:+ (stale pid file for $PID)}"
fi

echo
echo "health"
if body="$(curl -sf --max-time 5 "http://$HOST:$PORT/health" 2>/dev/null)"; then
  echo "  status   ok — $body"
  echo "  url      http://$HOST:$PORT"
  HEALTHY=0
else
  echo "  status   unreachable at http://$HOST:$PORT/health"
  HEALTHY=1
fi

echo
echo "system memory"
free -h 2>/dev/null | sed 's/^/  /' || echo "  (free unavailable)"

echo
echo "log tail ($LOGFILE)"
if [ -f "$LOGFILE" ]; then
  tail -n 5 "$LOGFILE" | sed 's/^/  /'
else
  echo "  (no log file)"
fi

exit "$HEALTHY"