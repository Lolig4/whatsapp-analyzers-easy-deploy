# WhatsApp Chat Analyzer — lokales Offline-Deployment

> **Dieses Deployment wurde von Claude (Anthropic) erstellt** — Einrichtung,
> Reparatur der Abhängigkeiten, Offline-Umbau, die Skripte `setup.sh` /
> `start.sh` / `stop.sh`, das Git-Repository samt Commit-Historie und diese
> README. Der Code der drei Analyzer selbst stammt von den jeweiligen
> Upstream-Autoren (siehe Tabelle unten); Claudes Änderungen daran sind unten
> einzeln aufgeführt und liegen als separate Commits vor.

Drei WhatsApp-Chat-Analyzer von GitHub, lokal lauffähig gemacht: je eine eigene
virtuelle Umgebung, ein eigener Port, und **keinerlei externe Netzwerkzugriffe
zur Laufzeit**. Internet wird nur einmalig für `setup.sh` gebraucht (pip +
Bootstrap/FontAwesome).

| # | Projekt | Framework | URL |
|---|---------|-----------|-----|
| 1 | [irfanchahyadi/Whatsapp-Chat-Analyzer](https://github.com/irfanchahyadi/Whatsapp-Chat-Analyzer) | Plotly Dash | <http://localhost:8051> |
| 2 | [karanprasadgupta/WhatsAppChatAnalzyer](https://github.com/karanprasadgupta/WhatsAppChatAnalzyer) | Streamlit | <http://localhost:8502> |
| 3 | [campusx-official/whatsapp-chat-analysis](https://github.com/campusx-official/whatsapp-chat-analysis) | Streamlit | <http://localhost:8503> |

Alle drei binden ausschließlich an `127.0.0.1` / `localhost` und sind damit vom
Netzwerk aus nicht erreichbar.

---

## Schnellstart

```bash
./setup.sh     # einmalig: venvs + Abhängigkeiten + Offline-Assets
./start.sh     # startet alle drei, prüft die Ports, öffnet den Browser
./stop.sh      # beendet alle drei
```

`start.sh` öffnet jede App, die erfolgreich geantwortet hat, im
Standardbrowser (`$BROWSER`, sonst `xdg-open`/`gio`/`open`, sonst Pythons
`webbrowser`). Ohne Grafik-Display — etwa über SSH — wird das übersprungen.

```bash
./start.sh --no-browser    # startet ohne Browser-Tabs
```

`setup.sh` ist idempotent — mehrfaches Ausführen schadet nicht. `./setup.sh --force`
baut die venvs von Grund auf neu.

`start.sh` schreibt pro App ein Log nach `logs/` und die PID nach `pids/`,
wartet danach bis zu 90 s pro App auf eine HTTP-Antwort und liefert einen
Exitcode ≠ 0, wenn eine App nicht hochkommt.

```bash
tail -f logs/*.log          # Logs mitlesen
```

### Bedienung
Alle drei Apps erwarten eine aus WhatsApp exportierte `.txt`-Datei
(*Chat → Mehr → Chat exportieren → Ohne Medien*). Projekt 1 nimmt sie per
Drag-and-drop, Projekt 2 und 3 über den Datei-Dialog in der Seitenleiste; bei
2 und 3 muss danach **„Show Analysis"** geklickt werden.

---

## Python-Version

Die venvs werden mit **Python 3.11** gebaut, nicht mit dem System-Default
(hier 3.14). Die Projekte stammen von 2020–2023 (Projekt 1 nennt in seiner
`runtime.txt` Python 3.10) und für ihre Abhängigkeitsbäume gibt es unter sehr
neuem Python regelmäßig keine passenden Wheels.

`setup.sh` sucht automatisch `python3.11`, `python3.12`, `python3.10` — in
dieser Reihenfolge. Überschreibbar:

```bash
PYTHON=/pfad/zu/python3.11 ./setup.sh
```

Am System wird nichts verändert; die Python-Wahl betrifft nur die venvs.

---

## Struktur

```
whatsapp-analyzers/
├── setup.sh / start.sh / stop.sh
├── logs/  pids/                     (nicht im Git)
├── 1-irfanchahyadi-dash/
│   ├── .venv/                       (nicht im Git)
│   ├── requirements.txt             Original, unverändert
│   ├── requirements.local.txt       ← das, was installiert wird
│   └── assets/vendor/               von setup.sh geholt, nicht im Git
├── 2-karanprasadgupta-streamlit/
│   ├── .streamlit/config.toml       Port 8502, localhost, keine Telemetrie
│   └── requirements.local.txt
└── 3-campusx-streamlit/
    ├── .streamlit/config.toml       Port 8503, localhost, keine Telemetrie
    └── requirements.local.txt
```

Die Original-`requirements.txt` jedes Projekts bleibt **unangetastet**;
installiert wird jeweils `requirements.local.txt`. So bleibt nachvollziehbar,
was original war und was repariert wurde.

---

## Was geändert wurde und warum

Jede Änderung ist ein eigener Commit (`git log`). Die drei `vendor:`-Commits am
Anfang enthalten den unveränderten Upstream-Stand:

| Projekt | Upstream-Commit | Stand |
|---|---|---|
| 1 | `f6eb7d8` | 2023-01-21 |
| 2 | `37e856a` | 2023-06-24 |
| 3 | `80b156e` | 2023-01-24 |

### Projekt 1 — Dash

**Abhängigkeiten** (`requirements.local.txt`)
- `psycopg2` **entfernt** — die App nutzt SQLite (`sqlite:///src/wca.db`),
  psycopg2 wird nirgends importiert, braucht aber `libpq-devel` zum Bauen.
  Allein daran scheiterte `pip install` bisher.
- `dash-core-components`, `dash-html-components`, `dash-renderer`, `dash-table`
  **entfernt** — seit Dash 2.0 leere Stub-Pakete; der Code nutzt bereits
  `from dash import dcc/html`.
- `gunicorn` **entfernt** — nur für das Heroku-`Procfile`.
- `dash` auf `>=2.16,<3` **gepinnt** — Dash 3 hat `app.run_server()` entfernt.
- `dash-bootstrap-components` auf `<2` **gepinnt** — dbc 2.x verlangt Dash 3.
- `SQLAlchemy` auf `<2.0` **gepinnt** — 2.x verbietet
  `con.execute("<raw sql>", params)`, genau das tut `src/db_handler.py`.
- `pandas` auf `<3` **gepinnt** — siehe „Bekannte Probleme".
- `numpy` **ergänzt** — wurde benutzt, fehlte in der Liste.

**Offline** (`app.py`, `src/settings.py`)
- Google-Analytics-Block (`googletagmanager.com`) aus `index_string` entfernt.
- Bootstrap kam über `dbc.themes.BOOTSTRAP` von `cdn.jsdelivr.net`, FontAwesome
  von `use.fontawesome.com`. Beide liegen jetzt lokal unter `assets/vendor/`
  (von `setup.sh` geholt). Ohne das war die Seite offline komplett ungestylt
  und ohne Icons.
- `assets_ignore=r"\.vendor\.css$"` ist nötig, weil Dash sonst jede `.css` unter
  `assets/` **zusätzlich** automatisch einbindet — und zwar nach `custom.css`,
  wodurch Bootstrap die Anpassungen des Projekts überschrieben hätte.

**Start**
- `app.run_server(debug=True)` → `app.run(host=settings.HOST, port=settings.PORT,
  debug=False)`. Host/Port kommen aus `src/settings.py` (Default
  `127.0.0.1:8051`, per `WCA_HOST`/`WCA_PORT` überschreibbar) statt auf Dashs
  Default-Port 8050 zu landen. `debug=False`, weil der Reloader den Prozess neu
  startet und die in `pids/` abgelegte PID danach ins Leere zeigt.

### Projekt 2 — Streamlit
- `numpy` in `requirements.local.txt` ergänzt (wird in `main.py` importiert,
  kam bisher nur zufällig über pandas mit). Sonst keine Code-Änderung nötig.
- `.streamlit/config.toml` im Projekt angelegt: Port 8502, `address = localhost`,
  headless, `gatherUsageStats = false`.

### Projekt 3 — Streamlit
- `helper.py:88`: `emoji.UNICODE_EMOJI['en']` → `emoji.EMOJI_DATA`. Das Attribut
  wurde in **emoji 2.0 entfernt**; mit aktuellem `emoji`-Paket brach die
  Emoji-Analyse beim Klick auf „Show Analysis" mit `AttributeError` ab.
  Alternative wäre `emoji<2.0` gewesen — dann kennt die Bibliothek aber nur
  Unicode 13 und zählt neuere Emoji nicht.
- `numpy` ergänzt, `.streamlit/config.toml` wie bei Projekt 2, aber Port 8503.

### Beide Streamlit-Projekte
Das mitgelieferte `setup.sh` der Repos wird **nicht** benutzt. Es schrieb nach
`~/.streamlit/config.toml` — also global ins Home-Verzeichnis und außerhalb
dieses Ordners — und übernahm den Port aus `$PORT` (Heroku). Ersetzt durch je
eine projektlokale `.streamlit/config.toml`.

---

## Sendet irgendetwas Daten nach außen?

**Nein.** Ergebnis eines Audits über Projektcode, Bibliotheken, Server und das
im Browser ausgelieferte JavaScript.

### Projektcode
Keines der drei Projekte importiert `requests`, `urllib`, `socket`, `httpx`
oder ähnliches und macht keinen einzigen ausgehenden Aufruf. Die im Code
gefundenen URLs sind ausnahmslos Links (`href` auf GitHub/LinkedIn),
Lizenz-Kommentare oder SVG-Namespaces (`w3.org`) — nichts davon wird
abgerufen. Alle Chatdaten bleiben im Prozessspeicher bzw. in der lokalen
SQLite-Datei von Projekt 1.

### Beweis per Netzwerk-Isolation
Alle drei Apps wurden in einem Netzwerk-Namespace **ohne jeden Netzzugang**
gestartet (`unshare -rn`, gegengeprüft: `curl` scheitert dort mit Exit 7):

- Alle drei Server kommen hoch und antworten mit HTTP 200.
- Die komplette Analyse-Pipeline läuft durch — Projekt 1 (Parsing + Charts),
  Projekt 2 (9 Funktionen), Projekt 3 (10 Funktionen), alle ohne Fehler.

Hätte irgendein Schritt einen Server gebraucht, wäre er dort gescheitert.

### Telemetrie der Bibliotheken
- **Streamlit** hat eine eingebaute Nutzungsstatistik. Sie ist über
  `browser.gatherUsageStats = false` in der projektlokalen `.streamlit/config.toml`
  abgeschaltet — verifiziert mit `streamlit config show`. Im Frontend hängt der
  Versand an `actuallySendMetrics = gatherUsageStats && metricsUrl !== "off"`,
  und `gatherUsageStats` kommt vom Server (`app_session.py:1186`). Ist es
  `false`, wird `data.streamlit.io/metrics.json` nie kontaktiert.
- Streamlits `credentials.py` kann `data.streamlit.io` aufrufen — aber nur in
  `_send_email()`, also wenn man beim interaktiven Start eine E-Mail-Adresse
  einträgt. Im Headless-Modus kehrt die Prüfung vorher zurück; es gibt keinen
  Prompt und keinen Request.
- **`urlextract`** (Projekt 2 und 3) lädt **keine** TLD-Liste nach: Version
  1.9.0 liefert sie im Paket mit (`urlextract/data/tlds-alpha-by-domain.txt`)
  und lädt nur bei explizitem `.update()` — das ruft keines der Projekte auf.
- **Dash/Plotly** arbeiten rein lokal; Plotly rendert offline, es gibt keine
  chart-studio-Anbindung.

### Browser-Seite
Das gesamte ausgelieferte JavaScript wurde heruntergeladen (Dash 2,6 MB,
Streamlit 2,2 MB) und auf bekannte Tracker geprüft — Google Analytics,
Segment, Mixpanel, Amplitude, Sentry, Hotjar, FullStory, PostHog, Datadog,
Matomo, Facebook und weitere: **keine Treffer**. Die Suchtreffer für
„amplitude" und „doubleClick" sind Fehlalarme (SVG-Attributname bzw. React
DOM-Event).

Zwei externe Hosts stecken im Streamlit-Bundle, beide inaktiv:
`data.streamlit.io` (siehe oben, per Config abgeschaltet) und
`fonts.gstatic.com`, das nur für Material-Symbol-Icons der Syntax
`:material/name:` benutzt wird — die kommt in keinem der beiden Projekte vor.

Der Google-Analytics-Block von Projekt 1 wurde entfernt; das ausgelieferte HTML
enthält davon nur noch den erklärenden Kommentar.

### Netzwerkbindung
`ss -ltn` zeigt für alle drei Ports ausschließlich `127.0.0.1` — vom Netzwerk
aus ist keine der Apps erreichbar.

### Was außerhalb dieses Ordners geschrieben wurde
Nichts, außer dem üblichen pip-Download-Cache unter `~/.cache/pip` beim
Installieren. Kein `~/.streamlit`, kein `~/.cache/urlextract` — das
mitgelieferte `setup.sh` der Repos, das nach `~/.streamlit/config.toml`
geschrieben hätte, wird bewusst nicht benutzt.

---

## Bekannte Probleme

**Projekt 1: pandas 3 bricht den Parser.** Mit pandas 3.0.x scheitert jeder
Chat-Upload in `src/chat_parser.py`:

```
TypeError: Invalid value '('encrypted', 'created group', 'added')' for dtype 'float64'
```

pandas 3 castet eine leere `float64`-Spalte bei `.loc`-Zuweisung nicht mehr
still auf `object` hoch. Deshalb ist pandas auf `<3` gepinnt (installiert:
2.3.3). Projekt 2 und 3 sind nicht betroffen und laufen auf pandas 3.

**Projekt 1: Spracherkennung greift bei aktuellen Exporten nicht.**
`detect_language()` erkennt einen Chat nur, wenn das Muster
`.+\s(encrypted)\s.+` passt — „encrypted" muss also von Leerzeichen umgeben
sein. Aktuelle englische Exporte schreiben „…are end-to-end encrypted." mit
Punkt, was nie matcht; die App antwortet dann mit *„Language not supported"*.
Das ist ein Upstream-Fehler und wurde hier **nicht** gepatcht (er steckt in der
Sprach-/Regex-Logik des Projekts). Unterstützt sind laut `src/settings.py`
ohnehin nur Englisch und Indonesisch — **deutsche Exporte funktionieren mit
Projekt 1 nicht**. Für deutsche Chats Projekt 2 oder 3 nehmen.

**Projekt 1: „Save"-Schalter ohne Funktion.** Wird beim Upload der
Save-Schalter aktiviert, schlägt `db_handler.add_chat()` fehl — es schreibt SQL
im PostgreSQL-Dialekt gegen die mitgelieferte SQLite-Datenbank:

```
sqlite3.OperationalError: near "%": syntax error
[SQL: insert into uploaded (datetime, chat_type, url, lang) values (%s, %s, %s, %s) returning id;]
```

SQLite erwartet `?` statt `%s`. Upstream lief das gegen Postgres auf Heroku;
das Projekt selbst weist im Tooltip darauf hin, dass die Speicherfunktion nicht
mehr verfügbar ist. Betrifft nur das Teilen per URL-Key — **die Analyse selbst
funktioniert**, solange der Schalter aus bleibt (Standard). Nicht gepatcht,
weil es fremde Persistenzlogik ist und für den lokalen Betrieb keine Rolle
spielt.

**Projekt 2 und 3: Datumsformat.** Beide erwarten das Format
`d/m/yy, HH:MM - `. Projekt 2 hat dafür eine Umschaltung (`dd-mm-yy` /
`mm-dd-yy`) direkt in der Oberfläche, Projekt 3 nimmt fest `%d/%m/%Y`. Passt
das Format des Exports nicht, bleibt die Auswertung leer oder bricht ab.

**Ports belegt.** `start.sh` überspringt Apps, deren Port schon von einem
fremden Prozess belegt ist, mit einer Warnung, statt sie doppelt zu starten.

**Verwaiste Prozesse.** Falls `stop.sh` mal nichts findet, aber Ports belegt
bleiben:

```bash
ss -ltnp | grep -E ':(8051|8502|8503)'
```

---

## Datenschutz

Die Apps verarbeiten private Chatverläufe. Es geht nichts nach außen: alle
Analysen laufen lokal, Telemetrie ist abgeschaltet. Die `.gitignore` schließt
zusätzlich `*_chat.txt` und `WhatsApp Chat*.txt` aus, damit ein Export nicht
versehentlich in die Git-History gerät.
