#!/usr/bin/env bash
#
# setup.sh - One-Click-Einrichtung aller drei WhatsApp-Chat-Analyzer.
#
# Legt pro Projekt eine isolierte venv an, installiert die Abhaengigkeiten aus
# requirements.local.txt und holt die CDN-Assets von Projekt 1 nach lokal.
# Idempotent: mehrfaches Ausfuehren ist unschaedlich.
#
# Braucht Internet (pip + Vendor-Assets). Danach laufen die Apps vollstaendig
# offline.
#
#   ./setup.sh            normale Einrichtung
#   ./setup.sh --force    venvs vorher loeschen und neu bauen
#
set -Eeuo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE"

P1="1-irfanchahyadi-dash"
P2="2-karanprasadgupta-streamlit"
P3="3-campusx-streamlit"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# --- huebsche Ausgabe ---------------------------------------------------------
if [[ -t 1 ]]; then
    B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
    B=""; G=""; Y=""; R=""; N=""
fi
info() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '  %s+%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%sFEHLER:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

trap 'die "abgebrochen in Zeile $LINENO"' ERR

# --- 1. Python-Interpreter bestimmen -----------------------------------------
# Die Projekte stammen von 2020-2023 (Projekt 1 nennt Python 3.10 in
# runtime.txt). Wir bevorzugen 3.11: neuer Python (3.13/3.14) hat bei diesen
# aelteren Abhaengigkeitsbaeumen regelmaessig keine passenden Wheels.
find_python() {
    local candidate
    for candidate in python3.11 python3.12 python3.10; do
        if command -v "$candidate" >/dev/null 2>&1; then
            echo "$candidate"; return 0
        fi
    done
    return 1
}

PYTHON="${PYTHON:-$(find_python || true)}"
[[ -n "$PYTHON" ]] || die "Kein Python 3.10-3.12 gefunden.
Bitte installieren (Fedora: sudo dnf install python3.11) oder setzen:
  PYTHON=/pfad/zu/python3.11 ./setup.sh"

info "Python: $PYTHON ($("$PYTHON" --version 2>&1))"

# --- 2. venv + Abhaengigkeiten pro Projekt ------------------------------------
setup_project() {
    local dir="$1"
    local venv="$BASE/$dir/.venv"
    local req="$BASE/$dir/requirements.local.txt"

    info "$dir"

    [[ -d "$BASE/$dir" ]] || die "Projektordner fehlt: $dir"
    [[ -f "$req" ]] || die "requirements.local.txt fehlt in $dir"

    if (( FORCE )) && [[ -d "$venv" ]]; then
        warn "loesche vorhandene venv (--force)"
        rm -rf "$venv"
    fi

    if [[ ! -x "$venv/bin/python" ]]; then
        "$PYTHON" -m venv "$venv" || die "venv-Erstellung fehlgeschlagen in $dir"
        ok "venv angelegt"
    else
        ok "venv vorhanden"
    fi

    "$venv/bin/python" -m pip install --quiet --upgrade pip
    "$venv/bin/python" -m pip install --quiet -r "$req" \
        || die "pip install fehlgeschlagen in $dir"
    ok "Abhaengigkeiten installiert"
}

setup_project "$P1"
setup_project "$P2"
setup_project "$P3"

# --- 3. Offline-Assets fuer Projekt 1 ----------------------------------------
# Projekt 1 laedt im Original Bootstrap (jsdelivr) und FontAwesome
# (use.fontawesome.com) per CDN. Ohne Netz waere das Layout kaputt und die
# Icons fehlten, deshalb einmalig lokal ablegen.
BOOTSTRAP_VER="5.3.3"
FA_VER="5.15.4"
VENDOR="$BASE/$P1/assets/vendor"

fetch() {
    local url="$1" dest="$2"
    [[ -s "$dest" ]] && return 0
    mkdir -p "$(dirname "$dest")"
    curl -fsSL --retry 3 --connect-timeout 20 -o "$dest.tmp" "$url" \
        || { rm -f "$dest.tmp"; die "Download fehlgeschlagen: $url"; }
    mv "$dest.tmp" "$dest"
}

info "Offline-Assets fuer $P1"
if [[ -s "$VENDOR/css/bootstrap.vendor.css" && -s "$VENDOR/css/fontawesome.vendor.css" ]]; then
    ok "Vendor-Assets bereits vorhanden"
else
    fetch "https://cdn.jsdelivr.net/npm/bootstrap@${BOOTSTRAP_VER}/dist/css/bootstrap.min.css" \
          "$VENDOR/css/bootstrap.vendor.css"
    ok "Bootstrap ${BOOTSTRAP_VER}"

    # FontAwesome-CSS referenziert die Schriften relativ als ../webfonts/*,
    # deshalb muss webfonts/ ein Geschwisterordner von css/ sein.
    fetch "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/${FA_VER}/css/all.min.css" \
          "$VENDOR/css/fontawesome.vendor.css"
    # Nur die tatsaechlich benutzten Familien: fas (solid) und fab (brands).
    for f in fa-solid-900 fa-brands-400 fa-regular-400; do
        for ext in woff2 woff ttf; do
            fetch "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/${FA_VER}/webfonts/${f}.${ext}" \
                  "$VENDOR/webfonts/${f}.${ext}"
        done
    done
    ok "FontAwesome ${FA_VER} inkl. Webfonts"
fi

# --- 4. Kurzer Importtest -----------------------------------------------------
info "Importtest"
"$BASE/$P1/.venv/bin/python" -c "import dash, dash_bootstrap_components, dash_cytoscape, dash_daq, sqlalchemy, wordcloud" \
    && ok "$P1"
"$BASE/$P2/.venv/bin/python" -c "import streamlit, pandas, matplotlib, seaborn, wordcloud, urlextract, emoji" \
    && ok "$P2"
"$BASE/$P3/.venv/bin/python" -c "import streamlit, pandas, matplotlib, seaborn, wordcloud, urlextract, emoji" \
    && ok "$P3"

echo
printf '%sSetup fertig.%s Jetzt starten mit:  ./start.sh\n' "$G" "$N"
