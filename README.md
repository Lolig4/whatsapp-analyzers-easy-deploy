# WhatsApp Analyzers — Easy Deploy

> **Built by Claude (Anthropic)**: the setup, dependency repairs, offline
> conversion, the `setup.sh` / `start.sh` / `stop.sh` scripts, the git history
> and this README. The analyzer code itself belongs to the upstream authors;
> every change made to it is listed below and exists as its own commit.

Three WhatsApp chat analyzers from GitHub, running locally: one isolated venv
and one port each, and **no outbound network traffic at runtime**. Internet is
only needed once, for `setup.sh`.

| # | Project | Framework | URL |
|---|---------|-----------|-----|
| 1 | [irfanchahyadi/Whatsapp-Chat-Analyzer](https://github.com/irfanchahyadi/Whatsapp-Chat-Analyzer) (`f6eb7d8`) | Plotly Dash | <http://localhost:8051> |
| 2 | [karanprasadgupta/WhatsAppChatAnalzyer](https://github.com/karanprasadgupta/WhatsAppChatAnalzyer) (`37e856a`) | Streamlit | <http://localhost:8502> |
| 3 | [campusx-official/whatsapp-chat-analysis](https://github.com/campusx-official/whatsapp-chat-analysis) (`80b156e`) | Streamlit | <http://localhost:8503> |

All three bind to `127.0.0.1` only and are unreachable from the network.

## Quick start

```bash
./setup.sh                 # once: venvs + dependencies + offline assets
./start.sh                 # start all three, check ports, open browser tabs
./stop.sh                  # stop all three

./setup.sh --force         # rebuild the venvs from scratch
./start.sh --no-browser    # start without opening tabs
tail -f logs/*.log         # follow the logs
```

`start.sh` logs to `logs/` and writes a PID to `pids/` per app, waits up to 90s
each for an HTTP response, and exits non-zero if one fails. Apps that answered
open in the default browser (`$BROWSER`, else `xdg-open` / `gio` / `open`);
skipped without a graphical display.

**Usage:** all three want a WhatsApp `.txt` export (*Chat → More → Export chat →
Without media*). Project 1 takes it via drag-and-drop, projects 2 and 3 through
the sidebar file dialog — there you also have to click **"Show Analysis"**.

## Python version

The venvs are built with **Python 3.11**, not the system default. These projects
are from 2020–2023 (project 1 pins Python 3.10 in its `runtime.txt`) and their
dependency trees frequently have no wheels on very new Python. `setup.sh` looks
for `python3.11`, `python3.12`, `python3.10` in that order; override with
`PYTHON=/path/to/python3.11 ./setup.sh`. Nothing on the system is modified.

## What was changed

Each project's original `requirements.txt` is **untouched**; what gets installed
is `requirements.local.txt` next to it. Every change is a separate commit, and
the three `vendor:` commits hold the pristine upstream code.

**Project 1 (Dash)**
- Dropped `psycopg2` (app uses SQLite, never imports it, needs `libpq-devel` to
  build — this alone broke `pip install`), the four Dash stub packages (empty
  since Dash 2.0) and `gunicorn` (Heroku only).
- Pinned `dash<3` (Dash 3 removed `app.run_server()`),
  `dash-bootstrap-components<2` (needs Dash 3), `SQLAlchemy<2.0` (2.x forbids
  the raw-string `con.execute()` in `db_handler.py`), `pandas<3` (see below).
  Added `numpy`.
- Offline: Google Analytics block removed from `app.py`; Bootstrap and
  FontAwesome served from `assets/vendor/` instead of jsdelivr and
  use.fontawesome.com. `assets_ignore=r"\.vendor\.css$"` is required, or Dash
  auto-includes the vendor CSS again *after* `custom.css` and Bootstrap
  overrides the project's styling.
- `app.run_server(debug=True)` → `app.run(host, port, debug=False)`, host/port
  from `settings.py` (`WCA_HOST` / `WCA_PORT`, default `127.0.0.1:8051`).

**Project 2 (Streamlit)** — added `numpy` (imported by `main.py`, missing from
the list). No code change needed.

**Project 3 (Streamlit)** — `helper.py:88`: `emoji.UNICODE_EMOJI['en']` →
`emoji.EMOJI_DATA`, removed in emoji 2.0; with a current `emoji` package the
analysis died with `AttributeError` on "Show Analysis". Added `numpy`.

**Both Streamlit projects** — their bundled `setup.sh` is unused: it wrote to
`~/.streamlit/config.toml` (global, outside this folder) and took the port from
`$PORT`. Replaced by a project-local `.streamlit/config.toml`.

## Does anything send data out? No.

Audited across project code, libraries, server and the JavaScript served to the
browser:

- **Project code** imports no networking module at all and makes no outbound
  calls. The URLs in the code are `href` links, license comments and SVG
  namespaces — none are fetched.
- **Proof by isolation**: all three were run in a network namespace with no
  network access (`unshare -rn`; verified that `curl` fails there). All three
  serve HTTP 200 and the full analysis pipeline completes — project 1 (parsing
  + charts), project 2 (9 functions), project 3 (10 functions).
- **Streamlit telemetry** is off via `browser.gatherUsageStats = false`
  (verified with `streamlit config show`). The frontend gates sending on
  `actuallySendMetrics = gatherUsageStats && metricsUrl !== "off"`, and that
  flag comes from the server (`app_session.py:1186`). The other
  `data.streamlit.io` call sits in `_send_email()` and only fires if you type an
  email at the interactive prompt — headless returns before that.
- **`urlextract`** downloads no TLD list: 1.9.0 ships one and only fetches on an
  explicit `.update()`, which neither project calls.
- **Browser side**: all served JavaScript (Dash 2.6 MB, Streamlit 2.2 MB) was
  scanned for Google Analytics, Segment, Mixpanel, Amplitude, Sentry, Hotjar,
  FullStory, PostHog, Datadog, Matomo, Facebook and more — no hits. Streamlit's
  `fonts.gstatic.com` reference only serves `:material/name:` icons, which
  neither project uses.
- Nothing was written outside this folder apart from the usual `~/.cache/pip`.

`.gitignore` also excludes `*_chat.txt` and `WhatsApp Chat*.txt`, so a private
export cannot land in git by accident.

## Known issues

**Project 1 rejects most chat exports.** `detect_language()` only matches
`.+\s(encrypted)\s.+`, so "encrypted" must have whitespace on both sides.
Current English exports write "…end-to-end encrypted." with a period and never
match, giving *"Language not supported"*. Only English and Indonesian exist
anyway, so **German exports do not work with project 1** — use project 2 or 3.
Upstream bug, not patched.

**Project 1 breaks on pandas 3**, hence the `<3` pin (installed: 2.3.3). Every
upload failed with `TypeError: Invalid value (...) for dtype 'float64'`, because
pandas 3 no longer upcasts an empty `float64` column on `.loc` assignment.
Projects 2 and 3 are unaffected and run on pandas 3.

**Project 1's "Save" switch is broken.** `db_handler.add_chat()` writes
PostgreSQL-dialect SQL (`%s` placeholders) against SQLite:
`sqlite3.OperationalError: near "%": syntax error`. Upstream this ran on Heroku
Postgres. Only affects URL sharing; the analysis works with the switch off (the
default). Not patched.

**Date formats.** Projects 2 and 3 expect `d/m/yy, HH:MM - `. Project 2 has a
`dd-mm-yy` / `mm-dd-yy` toggle in the UI, project 3 hardcodes `%d/%m/%Y`. A
mismatched export yields an empty or failing analysis.

**Busy ports.** `start.sh` skips apps whose port is taken. Find leftovers with
`ss -ltnp | grep -E ':(8051|8502|8503)'`.
