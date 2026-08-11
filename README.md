# WhatsApp Analyzers — Easy Deploy

> **Built by Claude (Anthropic)**: the setup, dependency repairs, offline
> conversion, the scripts, the git history and this README. The analyzer code
> itself belongs to the upstream authors; every change to it is listed below and
> exists as its own commit.

Three WhatsApp chat analyzers from GitHub, running locally: one isolated venv and
one port each, and **no outbound network traffic at runtime**. Internet is only
needed once, for `setup.sh`.

| # | Project | Framework | URL |
|---|---------|-----------|-----|
| 1 | [irfanchahyadi/Whatsapp-Chat-Analyzer](https://github.com/irfanchahyadi/Whatsapp-Chat-Analyzer) (`f6eb7d8`) | Plotly Dash | <http://localhost:8051> |
| 2 | [karanprasadgupta/WhatsAppChatAnalzyer](https://github.com/karanprasadgupta/WhatsAppChatAnalzyer) (`37e856a`) | Streamlit | <http://localhost:8502> |
| 3 | [campusx-official/whatsapp-chat-analysis](https://github.com/campusx-official/whatsapp-chat-analysis) (`80b156e`) | Streamlit | <http://localhost:8503> |

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
open in the default browser; skipped without a graphical display.

**Usage:** all three want a WhatsApp `.txt` export (*Chat → More → Export chat →
Without media*). Project 1 takes it via drag-and-drop, projects 2 and 3 through
the sidebar file dialog — there you also have to click **"Show Analysis"**.

## Python version

The venvs are built with **Python 3.11**, not the system default: these projects
are from 2020–2023 and their dependency trees frequently have no wheels on very
new Python. `setup.sh` looks for `python3.11`, `python3.12`, `python3.10` in that
order; override with `PYTHON=/path/to/python3.11 ./setup.sh`. Nothing on the
system is modified.

## What was changed

Each project's original `requirements.txt` is **untouched**; what gets installed
is `requirements.local.txt` next to it. Every change is a separate commit, and
the three `vendor:` commits hold the pristine upstream code.

**Project 1 (Dash)**
- Dropped `psycopg2` (app uses SQLite, never imports it, needs `libpq-devel` to
  build — this alone broke `pip install`), the four Dash stub packages and
  `gunicorn`.
- Pinned `dash<3` (removed `app.run_server()`), `dash-bootstrap-components<2`,
  `SQLAlchemy<2.0` (2.x forbids the raw-string `con.execute()` in
  `db_handler.py`) and `pandas<3` (see below). Added `numpy`.
- Offline: Google Analytics removed from `app.py`; Bootstrap and FontAwesome
  served from `assets/vendor/`. `assets_ignore=r"\.vendor\.css$"` is required,
  or Dash auto-includes the vendor CSS again *after* `custom.css` and Bootstrap
  overrides the project's styling.
- `app.run_server(debug=True)` → `app.run(host, port, debug=False)`, host/port
  from `settings.py` (`WCA_HOST` / `WCA_PORT`, default `127.0.0.1:8051`).
- Six defects that left the analysis view empty or broken. The one that hid all
  statistics on a personal chat: the personalchat layout was copied from the
  groupchat one and kept `id='counter'`, while `update_personalchat` outputs to
  `counter2` — a missing output component makes the Dash frontend skip the whole
  callback, silently, with nothing in the log. Also: `Series.iteritems()`
  (removed in pandas 2.0) broke `award_list()` and with it every analysis page;
  `db_handler.get_chat()` returned 2 values instead of 3 for unknown keys;
  `display_page()` missed the `?from=landing_page` marker because `dcc.Location`
  moves it into `search`; `Counter(...list_link.sum())` broke on chats without
  links; and five callbacks did `json.loads(None)` before the store was filled
  (now `PreventUpdate`).

**Project 2 (Streamlit)** — added `numpy`. Its whole script body sits in one
`except Exception` printing "Unable to Process Your Request", hiding failures.

**Project 3 (Streamlit)** — `helper.py:88`: `emoji.UNICODE_EMOJI['en']` was
removed in emoji 2.0, so the analysis died with `AttributeError` on "Show
Analysis"; now `emoji.is_emoji()`. Added `numpy`.

**All three: non-US date formats.** Upstream every project matched only `d/m/yy`
dates. German exports use dots (`20.12.25, 21:33 - `), so projects 2 and 3
silently produced an *empty* analysis and project 1 rejected the file outright.
Projects 2 and 3 now accept `.`, `/` and `-` separators and strip WhatsApp's
bidi marks; project 1 gained a German `LANGUAGE` entry. Verified against a real
German export.

**Both Streamlit projects** — their bundled `setup.sh` is unused: it wrote to
`~/.streamlit/config.toml` (global, outside this folder) and took the port from
`$PORT`. Replaced by a project-local `.streamlit/config.toml`. Both also
crashed on chats without emoji (`KeyError: 1` from a column-less DataFrame, then
`ax.pie` on empty data) — they now say "No emoji found in this chat."

## Upstream pull requests

All 18 open PRs on project 3's repo were reviewed: six adopted — adapted, not
merged, since each would have reverted the fixes above — and twelve rejected as
broken, redundant or cosmetic. Reasons per PR are in `git log`.

## Does anything send data out? No.

Audited across project code, libraries, server and the JavaScript served to the
browser:

- **Project code** imports no networking module and makes no outbound calls. The
  URLs in it are `href` links, license comments and SVG namespaces — none fetched.
- **Proof by isolation**: all three run in a network namespace with no network
  access (`unshare -rn`; `curl` verified to fail there), serving HTTP 200 with
  the full analysis pipeline completing.
- **Streamlit telemetry** is off via `browser.gatherUsageStats = false` (verified
  with `streamlit config show`). The frontend gates sending on
  `actuallySendMetrics = gatherUsageStats && metricsUrl !== "off"`, and that flag
  comes from the server (`app_session.py:1186`). The other `data.streamlit.io`
  call sits in `_send_email()` and only fires if you type an email at the
  interactive prompt — headless returns before that.
- **`urlextract`** downloads no TLD list: 1.9.0 ships one and only fetches on an
  explicit `.update()`, which neither project calls.
- **Browser side**: all served JavaScript (Dash 2.6 MB, Streamlit 2.2 MB) was
  scanned for Google Analytics, Segment, Mixpanel, Amplitude, Sentry, Hotjar,
  FullStory, PostHog, Datadog, Matomo, Facebook and more — no hits. Streamlit's
  `fonts.gstatic.com` reference only serves `:material/name:` icons, unused here.
- Nothing was written outside this folder apart from `~/.cache/pip`, and
  `.gitignore` excludes `*_chat.txt` so a private export cannot land in git.

## Known issues

Things that are **not** fixed — deliberately left alone or inherent. Everything
repaired during this work is under *What was changed* above.

**English exports may be rejected by project 1.** `detect_language()` matches
`.+\s(encrypted)\s.+`, so "encrypted" needs whitespace on both sides. Current
English exports write "…end-to-end encrypted." with a period and never match,
giving *"Language not supported"*. Upstream bug, not patched; German and
Indonesian tokens do sit between spaces and are unaffected.

**German group events are not classified (project 1).** Messages parse fine, but
"created group", "added" etc. are matched by regexes encoding English word order
(`X created group "Y"` vs `X hat die Gruppe "Y" erstellt`), so they stay raw text
instead of typed events. Personal chats are unaffected.

**Ambiguous date formats.** `03/04/25` could be day- or month-first; projects 2
and 3 try day-first, and project 2 has a `dd-mm-yy` / `mm-dd-yy` toggle in its UI.

**Project 1 breaks on pandas 3**, hence the `<3` pin (installed: 2.3.3): pandas 3
no longer upcasts an empty `float64` column on `.loc` assignment, so every upload
failed. Projects 2 and 3 are unaffected and run on pandas 3.

**Project 1's "Save" switch is broken.** `db_handler.add_chat()` writes
PostgreSQL-dialect SQL (`%s` placeholders) against SQLite:
`sqlite3.OperationalError: near "%": syntax error`. Only affects URL sharing;
the analysis works with the switch off (the default). Not patched.

**Busy ports.** `start.sh` skips apps whose port is taken; find leftovers with
`ss -ltnp | grep -E ':(8051|8502|8503)'`.
