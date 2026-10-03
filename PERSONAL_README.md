# Personal README -- Hermes in Docker

Letzte Zusammenfassung vom 02.10.2026 -- sobald ich das Projekt das nächste Mal
in die Hand nehme, steht hier alles Nötige.

## Projektverzeichnis

```
/daten/home/rb/_Syncthing/Ralf-Temporaer/_Arbeit/hermes-projekte/hermes-inside-docker/
```

## Dateien (11 Stück, ~1023 Zeilen, kein Deutsch)

| Datei | Zweck |
|-------|-------|
| `Dockerfile` | Multi-Stage Build (bookworm-slim) |
| `docker-compose.yml` | Compose + `init: true` (PID-1-Fix) |
| `docker-entrypoint.sh` | Config-Prüfung, Vault-Erkennung, Serverstart |
| `hermes-launcher.sh` | Wrapper für venv-Python (Import-Fix) |
| `hermes-docker.service` | **systemd --user:** Start bei Login, Stop bei Logout |
| `generate-password-hash.sh` | Passwort-Hash für Auth generieren |
| `.env.example` | Umgebungsvariablen-Vorlage |
| `README.md` | Vollständige Anleitung (englisch) |
| `examples/config.openai.yaml` | Config + Auth-Block für OpenAI |
| `examples/config.openrouter.yaml` | Config + Auth-Block für OpenRouter |
| `examples/config.custom-openai.yaml` | Config + Auth-Block für Custom-Provider |

## Build

```bash
cd /daten/home/rb/_Syncthing/Ralf-Temporaer/_Arbeit/hermes-projekte/hermes-inside-docker
docker compose build
```

Dauer Erstbau: ~3-5 min (holt Debian, klont Hermes, installiert Python-Deps,
baut Web-UI). Danach gecached.

## Einrichtung

```bash
# Config kopieren
cp examples/config.openai.yaml hermes-config/config.yaml

# API-Key setzen
echo "OPENAI_API_KEY=sk-proj-..." > hermes-config/.env

# Passwort-Hash generieren und in config.yaml eintragen
./generate-password-hash.sh mein-passwort

# Starten
docker compose up -d

# Verbinden: http://<host>:8080 (User: admin, Passwort: selbst gesetzt)
```

## Auth (wichtig)

Seit Juni 2026 verweigert Hermes den Bind auf `0.0.0.0` ohne Auth.
Alle Beispiel-Configs haben einen `dashboard.basic_auth`-Block.
Demo-Passwort: `admin/demo`. Eigenes generieren mit `generate-password-hash.sh`.

Alternativen: SSH-Tunnel oder WireGuard auf `127.0.0.1`.

## Autostart (systemd --user)

```bash
cp hermes-docker.service ~/.config/systemd/user/
# In ~/.config/systemd/user/hermes-docker.service Pfad anpassen:
#   WorkingDirectory=/daten/home/rb/_Syncthing/Ralf-Temporaer/_Arbeit/hermes-projekte/hermes-inside-docker
systemctl --user daemon-reload
systemctl --user enable hermes-docker
systemctl --user start hermes-docker
```

Startet Container bei Login, stoppt bei Logout. Kontrolle:
`systemctl --user status hermes-docker`

## Besonderheiten

- Image ~4.2 GB (ffmpeg, node, Python, Browser-Agent -- Hermes' PM-Tools)
- RAM ~200-400 MB im Leerlauf
- Healthcheck: TCP-Connect (kein HTTP-Endpoint)
- `--insecure` ist seit Juni 2026 abgeschaltet, bringt nichts
- `/root` musste auf 755 gesetzt werden (Symlink-Traversal für venv-Python)