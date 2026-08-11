#!/usr/bin/env bash
#
# setup.sh - one-click setup for all three WhatsApp chat analyzers.
#
# Creates an isolated venv per project, installs the dependencies from
# requirements.local.txt and fetches project 1's CDN assets for local use.
# Idempotent: running it more than once is harmless.
#
# Needs internet (pip + vendor assets). Afterwards the apps run fully offline.
#
#   ./setup.sh            normal setup
#   ./setup.sh --force    delete and rebuild the venvs first
#
set -Eeuo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE"

P1="1-irfanchahyadi-dash"
P2="2-karanprasadgupta-streamlit"
P3="3-campusx-streamlit"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# --- output helpers -----------------------------------------------------------
if [[ -t 1 ]]; then
    B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
    B=""; G=""; Y=""; R=""; N=""
fi
info() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '  %s+%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%sERROR:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

trap 'die "aborted at line $LINENO"' ERR

# --- 1. pick a Python interpreter ---------------------------------------------
# These projects are from 2020-2023 (project 1 pins Python 3.10 in runtime.txt).
# Prefer 3.11: on very new Python (3.13/3.14) their dependency trees regularly
# have no matching wheels.
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
[[ -n "$PYTHON" ]] || die "No Python 3.10-3.12 found.
Install one (Fedora: sudo dnf install python3.11) or point at it explicitly:
  PYTHON=/path/to/python3.11 ./setup.sh"

info "Python: $PYTHON ($("$PYTHON" --version 2>&1))"

# --- 2. venv + dependencies per project ---------------------------------------
setup_project() {
    local dir="$1"
    local venv="$BASE/$dir/.venv"
    local req="$BASE/$dir/requirements.local.txt"

    info "$dir"

    [[ -d "$BASE/$dir" ]] || die "project directory missing: $dir"
    [[ -f "$req" ]] || die "requirements.local.txt missing in $dir"

    if (( FORCE )) && [[ -d "$venv" ]]; then
        warn "removing existing venv (--force)"
        rm -rf "$venv"
    fi

    if [[ ! -x "$venv/bin/python" ]]; then
        "$PYTHON" -m venv "$venv" || die "venv creation failed in $dir"
        ok "venv created"
    else
        ok "venv present"
    fi

    "$venv/bin/python" -m pip install --quiet --upgrade pip
    "$venv/bin/python" -m pip install --quiet -r "$req" \
        || die "pip install failed in $dir"
    ok "dependencies installed"
}

setup_project "$P1"
setup_project "$P2"
setup_project "$P3"

# --- 3. offline assets for project 1 ------------------------------------------
# Upstream, project 1 loads Bootstrap (jsdelivr) and FontAwesome
# (use.fontawesome.com) from a CDN. Without network the layout would be broken
# and all icons missing, so fetch them once and serve them locally.
BOOTSTRAP_VER="5.3.3"
FA_VER="5.15.4"
VENDOR="$BASE/$P1/assets/vendor"

fetch() {
    local url="$1" dest="$2"
    [[ -s "$dest" ]] && return 0
    mkdir -p "$(dirname "$dest")"
    curl -fsSL --retry 3 --connect-timeout 20 -o "$dest.tmp" "$url" \
        || { rm -f "$dest.tmp"; die "download failed: $url"; }
    mv "$dest.tmp" "$dest"
}

info "Offline assets for $P1"
if [[ -s "$VENDOR/css/bootstrap.vendor.css" && -s "$VENDOR/css/fontawesome.vendor.css" ]]; then
    ok "vendor assets already present"
else
    fetch "https://cdn.jsdelivr.net/npm/bootstrap@${BOOTSTRAP_VER}/dist/css/bootstrap.min.css" \
          "$VENDOR/css/bootstrap.vendor.css"
    ok "Bootstrap ${BOOTSTRAP_VER}"

    # The FontAwesome CSS references its fonts relatively as ../webfonts/*, so
    # webfonts/ has to be a sibling directory of css/.
    fetch "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/${FA_VER}/css/all.min.css" \
          "$VENDOR/css/fontawesome.vendor.css"
    # Only the families actually used: fas (solid) and fab (brands).
    for f in fa-solid-900 fa-brands-400 fa-regular-400; do
        for ext in woff2 woff ttf; do
            fetch "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/${FA_VER}/webfonts/${f}.${ext}" \
                  "$VENDOR/webfonts/${f}.${ext}"
        done
    done
    ok "FontAwesome ${FA_VER} incl. webfonts"
fi

# --- 4. quick import check ----------------------------------------------------
info "Import check"
"$BASE/$P1/.venv/bin/python" -c "import dash, dash_bootstrap_components, dash_cytoscape, dash_daq, sqlalchemy, wordcloud" \
    && ok "$P1"
"$BASE/$P2/.venv/bin/python" -c "import streamlit, pandas, matplotlib, seaborn, wordcloud, urlextract, emoji" \
    && ok "$P2"
"$BASE/$P3/.venv/bin/python" -c "import streamlit, pandas, matplotlib, seaborn, wordcloud, urlextract, emoji" \
    && ok "$P3"

echo
printf '%sSetup complete.%s Start everything with:  ./start.sh\n' "$G" "$N"
