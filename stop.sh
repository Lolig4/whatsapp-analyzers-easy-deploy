#!/usr/bin/env bash
#
# stop.sh - stop everything start.sh launched.
#
# SIGTERM first, SIGKILL after 10s. Signals the whole process group so child
# processes go too (Streamlit runs as a child of "python -m streamlit").
#
set -Eeuo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_DIR="$BASE/pids"

if [[ -t 1 ]]; then
    B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; N=$'\033[0m'
else
    B=""; G=""; Y=""; N=""
fi

printf '%s==>%s Stopping apps\n' "$B" "$N"

shopt -s nullglob
found=0

for pidfile in "$PID_DIR"/*.pid; do
    found=1
    name="$(basename "$pidfile" .pid)"
    pid="$(cat "$pidfile" 2>/dev/null || true)"

    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        printf '  %s!%s %-28s was not running\n' "$Y" "$N" "$name"
        rm -f "$pidfile"
        continue
    fi

    # Kill the whole process group so no Streamlit children survive.
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [[ -n "$pgid" ]]; then
        kill -TERM -"$pgid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    else
        kill -TERM "$pid" 2>/dev/null || true
    fi

    for _ in $(seq 1 10); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done

    if kill -0 "$pid" 2>/dev/null; then
        [[ -n "$pgid" ]] && kill -KILL -"$pgid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        printf '  %s!%s %-28s force-killed (SIGKILL)\n' "$Y" "$N" "$name"
    else
        printf '  %s+%s %-28s stopped\n' "$G" "$N" "$name"
    fi

    rm -f "$pidfile"
done

if (( ! found )); then
    printf '  %s!%s No running apps found (pids/ is empty).\n' "$Y" "$N"
fi
