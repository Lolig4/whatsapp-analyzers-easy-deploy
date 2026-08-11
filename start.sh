#!/usr/bin/env bash
#
# start.sh - start all three analyzers at once, in the background.
#
#   1-irfanchahyadi-dash          Dash        http://localhost:8051
#   2-karanprasadgupta-streamlit  Streamlit   http://localhost:8502
#   3-campusx-streamlit           Streamlit   http://localhost:8503
#
# Every app that answers is opened in the default browser.
#
#   ./start.sh                start everything and open the browser
#   ./start.sh --no-browser   start without opening tabs (e.g. on a server)
#
# Logs : logs/<app>.log
# PIDs : pids/<app>.pid
# Stop : ./stop.sh
#
set -Eeuo pipefail

# Enable job control so every background job gets its OWN process group
# (pgid == pid). Without it all three apps share this script's process group,
# and stop.sh would kill all of them while stopping just the first one.
set -m

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE"

LOG_DIR="$BASE/logs"
PID_DIR="$BASE/pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

OPEN_BROWSER=1
[[ "${1:-}" == "--no-browser" ]] && OPEN_BROWSER=0

if [[ -t 1 ]]; then
    B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
    B=""; G=""; Y=""; R=""; N=""
fi
info() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
die()  { printf '%sERROR:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# name | directory | port
APPS=(
    "dash-irfanchahyadi|1-irfanchahyadi-dash|8051"
    "streamlit-karanprasadgupta|2-karanprasadgupta-streamlit|8502"
    "streamlit-campusx|3-campusx-streamlit|8503"
)

# --- preconditions ------------------------------------------------------------
for entry in "${APPS[@]}"; do
    IFS='|' read -r name dir port <<< "$entry"
    [[ -x "$BASE/$dir/.venv/bin/python" ]] \
        || die "venv missing in $dir - run ./setup.sh first."
done

port_busy() {
    # 0 = busy. Prefers ss, falls back to Python.
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn "sport = :$port" 2>/dev/null | grep -q LISTEN
    else
        "$BASE/1-irfanchahyadi-dash/.venv/bin/python" - "$port" <<'PY'
import socket, sys
s = socket.socket()
try:
    s.bind(("127.0.0.1", int(sys.argv[1]))); sys.exit(1)
except OSError:
    sys.exit(0)
finally:
    s.close()
PY
    fi
}

# --- start --------------------------------------------------------------------
start_app() {
    local name="$1" dir="$2" port="$3"
    local log="$LOG_DIR/$name.log"
    local pidfile="$PID_DIR/$name.pid"
    local py="$BASE/$dir/.venv/bin/python"

    # already running?
    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        printf '  %s!%s %-28s already running (PID %s)\n' "$Y" "$N" "$name" "$(cat "$pidfile")"
        return 0
    fi
    if port_busy "$port"; then
        printf '  %s!%s %-28s port %s taken by another process - skipped\n' \
               "$Y" "$N" "$name" "$port"
        return 0
    fi

    # Important: start from inside the project directory.
    # Both Streamlit apps open stop_hinglish.txt relative to the CWD, and
    # project 1 uses the relative path sqlite:///src/wca.db.
    (
        cd "$BASE/$dir"
        # Agg = headless backend, otherwise matplotlib looks for a GUI backend.
        export MPLBACKEND=Agg
        if [[ "$dir" == 1-* ]]; then
            # Dash: host/port come from src/settings.py (env-overridable).
            WCA_HOST=127.0.0.1 WCA_PORT="$port" \
                exec "$py" app.py
        else
            # Streamlit: flags win on top of .streamlit/config.toml.
            local entrypoint="main.py"
            [[ -f app.py ]] && entrypoint="app.py"
            exec "$py" -m streamlit run "$entrypoint" \
                --server.port "$port" \
                --server.address localhost \
                --server.headless true \
                --browser.gatherUsageStats false
        fi
    ) >> "$log" 2>&1 &

    echo $! > "$pidfile"
    printf '  %s+%s %-28s PID %-8s port %s\n' "$G" "$N" "$name" "$!" "$port"
}

info "Starting all three apps"
for entry in "${APPS[@]}"; do
    IFS='|' read -r name dir port <<< "$entry"
    : > "$LOG_DIR/$name.log"          # fresh log per start
    start_app "$name" "$dir" "$port"
done

# --- wait until the ports answer ----------------------------------------------
info "Waiting for HTTP response (up to 90s)"
overall=0
READY_URLS=()
for entry in "${APPS[@]}"; do
    IFS='|' read -r name dir port <<< "$entry"
    up=0
    for _ in $(seq 1 90); do
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
                "http://localhost:$port/" 2>/dev/null || true)"
        if [[ "$code" =~ ^(200|302|303)$ ]]; then
            printf '  %s+%s %-28s HTTP %s  ->  http://localhost:%s\n' \
                   "$G" "$N" "$name" "$code" "$port"
            READY_URLS+=("http://localhost:$port")
            up=1; break
        fi
        # did the process die early?
        pidfile="$PID_DIR/$name.pid"
        if [[ -f "$pidfile" ]] && ! kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if (( ! up )); then
        printf '  %sx%s %-28s no response - see logs/%s.log\n' \
               "$R" "$N" "$name" "$name"
        overall=1
    fi
done

# --- open in the browser ------------------------------------------------------
# Only apps that actually answered - a tab pointing at a dead port helps nobody.
open_url() {
    local url="$1"
    if [[ -n "${BROWSER:-}" ]]; then
        "$BROWSER" "$url" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 &
    elif command -v gio >/dev/null 2>&1; then
        gio open "$url" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then          # macOS
        open "$url" >/dev/null 2>&1 &
    else
        # Last resort: Python's webbrowser module from one of the venvs.
        "$BASE/1-irfanchahyadi-dash/.venv/bin/python" -m webbrowser -t "$url" \
            >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
}

if (( OPEN_BROWSER )) && (( ${#READY_URLS[@]} > 0 )); then
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "$(uname)" != "Darwin" ]]; then
        # No graphical display (SSH session, server) - a browser makes no sense.
        info "No display detected - not opening a browser"
    else
        info "Opening ${#READY_URLS[@]} tab(s) in the browser"
        for url in "${READY_URLS[@]}"; do
            printf '  %s>%s %s\n' "$B" "$N" "$url"
            open_url "$url"
            sleep 1     # small stagger, some browsers swallow rapid-fire calls
        done
    fi
fi

echo
if (( overall == 0 )); then
    printf '%sAll three are running.%s\n' "$G" "$N"
else
    printf '%sAt least one app failed to start.%s\n' "$Y" "$N"
fi
cat <<EOF

  Project 1 (Dash, irfanchahyadi)         http://localhost:8051
  Project 2 (Streamlit, karanprasadgupta) http://localhost:8502
  Project 3 (Streamlit, campusx)          http://localhost:8503

  Logs: tail -f logs/*.log
  Stop: ./stop.sh
EOF

exit $overall
