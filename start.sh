#!/usr/bin/env bash
#
# start.sh - startet alle drei Analyzer gleichzeitig im Hintergrund.
#
#   1-irfanchahyadi-dash          Dash        http://localhost:8051
#   2-karanprasadgupta-streamlit  Streamlit   http://localhost:8502
#   3-campusx-streamlit           Streamlit   http://localhost:8503
#
# Sobald eine App antwortet, wird sie im Standardbrowser geoeffnet.
#
#   ./start.sh                startet alles und oeffnet den Browser
#   ./start.sh --no-browser   startet alles ohne Browser (z.B. auf einem Server)
#
# Logs   : logs/<projekt>.log
# PIDs   : pids/<projekt>.pid
# Stoppen: ./stop.sh
#
set -Eeuo pipefail

# Job-Control einschalten: dadurch bekommt jeder Hintergrundjob eine EIGENE
# Prozessgruppe (pgid == pid). Ohne das landen alle drei Apps in der
# Prozessgruppe dieses Skripts - stop.sh beendet dann beim Stoppen der ersten
# App unabsichtlich auch die beiden anderen.
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
die()  { printf '%sFEHLER:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# name | verzeichnis | port
APPS=(
    "dash-irfanchahyadi|1-irfanchahyadi-dash|8051"
    "streamlit-karanprasadgupta|2-karanprasadgupta-streamlit|8502"
    "streamlit-campusx|3-campusx-streamlit|8503"
)

# --- Vorbedingungen -----------------------------------------------------------
for entry in "${APPS[@]}"; do
    IFS='|' read -r name dir port <<< "$entry"
    [[ -x "$BASE/$dir/.venv/bin/python" ]] \
        || die "venv fehlt in $dir - bitte zuerst ./setup.sh ausfuehren."
done

port_busy() {
    # 0 = belegt. Bevorzugt ss, faellt sonst auf Python zurueck.
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

# --- Starten ------------------------------------------------------------------
start_app() {
    local name="$1" dir="$2" port="$3"
    local log="$LOG_DIR/$name.log"
    local pidfile="$PID_DIR/$name.pid"
    local py="$BASE/$dir/.venv/bin/python"

    # laeuft schon?
    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        printf '  %s!%s %-28s laeuft bereits (PID %s)\n' "$Y" "$N" "$name" "$(cat "$pidfile")"
        return 0
    fi
    if port_busy "$port"; then
        printf '  %s!%s %-28s Port %s ist von einem Fremdprozess belegt - uebersprungen\n' \
               "$Y" "$N" "$name" "$port"
        return 0
    fi

    # Wichtig: aus dem Projektverzeichnis heraus starten.
    # Beide Streamlit-Apps oeffnen stop_hinglish.txt relativ zum CWD, und
    # Projekt 1 nutzt den relativen Pfad sqlite:///src/wca.db.
    (
        cd "$BASE/$dir"
        # Agg = headless-Backend, sonst versucht matplotlib ein GUI-Backend.
        export MPLBACKEND=Agg
        if [[ "$dir" == 1-* ]]; then
            # Dash: Host/Port kommen aus src/settings.py (env-ueberschreibbar).
            WCA_HOST=127.0.0.1 WCA_PORT="$port" \
                exec "$py" app.py
        else
            # Streamlit: Flags gewinnen zusaetzlich zu .streamlit/config.toml.
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
    printf '  %s+%s %-28s PID %-8s Port %s\n' "$G" "$N" "$name" "$!" "$port"
}

info "Starte alle drei Apps"
for entry in "${APPS[@]}"; do
    IFS='|' read -r name dir port <<< "$entry"
    : > "$LOG_DIR/$name.log"          # Log pro Start frisch
    start_app "$name" "$dir" "$port"
done

# --- Warten bis die Ports antworten ------------------------------------------
info "Warte auf HTTP-Antwort (max. 90s)"
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
        # Prozess vorzeitig gestorben?
        pidfile="$PID_DIR/$name.pid"
        if [[ -f "$pidfile" ]] && ! kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if (( ! up )); then
        printf '  %sx%s %-28s antwortet nicht - siehe logs/%s.log\n' \
               "$R" "$N" "$name" "$name"
        overall=1
    fi
done

# --- Im Browser oeffnen -------------------------------------------------------
# Nur die Apps, die tatsaechlich geantwortet haben - ein Tab auf einen toten
# Port hilft niemandem.
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
        # Letzter Ausweg: Pythons webbrowser-Modul aus einer der venvs.
        "$BASE/1-irfanchahyadi-dash/.venv/bin/python" -m webbrowser -t "$url" \
            >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
}

if (( OPEN_BROWSER )) && (( ${#READY_URLS[@]} > 0 )); then
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "$(uname)" != "Darwin" ]]; then
        # Kein Grafik-Display (SSH-Sitzung, Server) - Browser waere sinnlos.
        info "Kein Display erkannt - Browser wird nicht geoeffnet"
    else
        info "Oeffne ${#READY_URLS[@]} Tab(s) im Browser"
        for url in "${READY_URLS[@]}"; do
            printf '  %s>%s %s\n' "$B" "$N" "$url"
            open_url "$url"
            sleep 1     # kleiner Versatz, sonst verschluckt der Browser Tabs
        done
    fi
fi

echo
if (( overall == 0 )); then
    printf '%sAlle drei laufen.%s\n' "$G" "$N"
else
    printf '%sMindestens eine App ist nicht hochgekommen.%s\n' "$Y" "$N"
fi
cat <<EOF

  Projekt 1 (Dash, irfanchahyadi)        http://localhost:8051
  Projekt 2 (Streamlit, karanprasadgupta) http://localhost:8502
  Projekt 3 (Streamlit, campusx)          http://localhost:8503

  Logs:    tail -f logs/*.log
  Stoppen: ./stop.sh
EOF

exit $overall
