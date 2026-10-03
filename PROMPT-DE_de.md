Erstelle eine vollständige, produktionsnahe Docker-Lösung für **Hermes** auf Basis eines aktuellen Debian-Images.

## Ziel

Hermes soll in einem Debian-basierten Container laufen und über seinen Server-Modus von außerhalb des Containers erreichbar sein. Der Container muss Hermes beim Start mit `serve --host --port` ausführen, damit ich mich mit einem externen GUI-Client verbinden kann.

## Anforderungen

### Container-Basis

- Verwende ein aktuelles, schlankes Debian-Image, bevorzugt `debian:bookworm-slim` oder neuer.
- Installiere alle für Hermes benötigten Laufzeitabhängigkeiten sauber im Dockerfile.
- Installiere Hermes nachvollziehbar und versionssicher. Falls Hermes über einen Paketmanager, Release-Binary oder Installer installiert wird, dokumentiere die gewählte Installationsmethode.
- Der Container soll möglichst als nicht-root Benutzer laufen.
- Lege sinnvolle Arbeits-, Konfigurations- und Datenverzeichnisse an.

### Netzwerk

- Hermes muss beim Containerstart dauerhaft als Server laufen.
- Verwende einen konfigurierbaren Port, standardmäßig z. B. `8080`.
- Starte Hermes explizit mit:

  ```bash
  hermes serve --host 0.0.0.0 --port "${HERMES_PORT}"
  ```

  Falls die tatsächliche Hermes-CLI andere Syntax oder Parameter erfordert, prüfe diese und verwende die korrekte Variante.

- Der Port muss im Dockerfile mit `EXPOSE` dokumentiert werden.
- Liefere eine `docker-compose.yml`, über die der Port auf dem Host veröffentlicht werden kann, beispielsweise:

  ```yaml
  ports:
    - "8080:8080"
  ```

- Berücksichtige, dass `127.0.0.1` **nicht** genügt, da sich der GUI-Client außerhalb des Containers verbinden soll.

### Host-Verzeichnisse

Ich benötige zwei getrennte Mount-Punkte:

| Zweck | Containerpfad | Mount-Modus |
|---|---|---|
| Lesbare Eingabedaten vom Host | `/data/ro` | Read-only |
| Schreibbare Arbeits- und Ergebnisdaten vom Host | `/data/rw` | Read-write |

Die Mounts sollen in der `docker-compose.yml` eindeutig definiert sein, etwa:

```yaml
volumes:
  - ./input:/data/ro:ro
  - ./workspace:/data/rw:rw
```

Hermes muss unter dem verwendeten nicht-root Benutzer auf `/data/rw` schreiben können. Dokumentiere daher klar, wie Host-Verzeichnisrechte, UID und GID gehandhabt werden sollen.

### Persistente Konfiguration

- Die Hermes-Konfiguration darf nicht bei jedem Container-Neustart verloren gehen.
- Verwende hierfür ein separates persistentes Verzeichnis, beispielsweise:

  ```text
  /config
  ```

- Binde dieses Verzeichnis in Compose als Host-Mount oder benanntes Docker-Volume ein.
- Stelle durch Umgebungsvariablen, Startparameter oder Symlinks sicher, dass Hermes seine Konfiguration tatsächlich dort verwendet.

## Erster Start / interaktiver Konfigurationsmodus

Ein zentrales Problem ist, dass Hermes beim ersten Start möglicherweise einen interaktiven Konfigurationsassistenten öffnet. Das ist in einem dauerhaft gestarteten, headless Docker-Container nicht akzeptabel.

Implementiere deshalb eine robuste Initialisierungsstrategie mit folgender Priorität:

1. **Nicht-interaktiver Hermes-Modus:**  
   Prüfe zuerst, ob Hermes eine offizielle Option wie `--non-interactive`, `--yes`, `--config`, `init`, `configure`, Umgebungsvariablen oder vergleichbare Mechanismen bietet. Nutze diese, falls verfügbar.

2. **Vorbereitete Konfiguration:**  
   Falls Hermes keine saubere nicht-interaktive Initialisierung unterstützt, ermögliche das Einhängen fertiger Konfigurationsdateien vom Host nach `/config`, zum Beispiel:

   ```yaml
   volumes:
     - ./hermes-config:/config:rw
   ```

   Beschreibe exakt:
   - Welche Datei(en) benötigt werden.
   - An welchem Pfad Hermes sie erwartet.
   - Wie diese einmalig erstellt oder aus einem temporär interaktiven Container exportiert werden können.
   - Welche Einstellungen vor dem ersten Serverstart gesetzt sein müssen.

3. **Init-Container oder einmaliger Setup-Befehl:**  
   Falls erforderlich, liefere zusätzlich einen separaten Compose-Service oder einen dokumentierten `docker compose run`-Befehl, mit dem die Konfiguration einmalig interaktiv erzeugt wird. Der normale Service darf anschließend ausschließlich headless im Server-Modus laufen.

4. **Entrypoint-Prüfung:**  
   Implementiere ein EntryPoint-Skript, das beim Start erkennt, ob die notwendige Konfiguration vorhanden ist.
   - Wenn die Konfiguration vorhanden ist: Hermes normal im Server-Modus starten.
   - Wenn sie fehlt: Nicht in einem unsichtbaren interaktiven Wizard hängen bleiben.
   - Stattdessen eine verständliche Fehlermeldung ausgeben, welche Konfigurationsdatei oder welcher Initialisierungsschritt fehlt, und den Container mit einem nicht-null Exit-Code beenden.
   - Optional: Falls eine belegte, zuverlässige nicht-interaktive Initialisierung möglich ist, diese automatisch ausführen.

## Sicherheit und Betrieb

- Verwende keinen privilegierten Container.
- Führe Hermes nicht als root aus.
- Verwende nach Möglichkeit:
  - `read_only: true` für das Container-Dateisystem,
  - `tmpfs` für temporäre Verzeichnisse,
  - `security_opt: no-new-privileges:true`,
  - `cap_drop: [ALL]`.
- Falls Hermes Schreibzugriff auf weitere interne Pfade benötigt, definiere diese explizit als Volume oder `tmpfs`.
- Ergänze sinnvolle Logging-Hinweise und einen Healthcheck, sofern Hermes einen geeigneten HTTP-, TCP- oder CLI-Healthcheck unterstützt.

## Erwartete Ausgabe

Liefere alle benötigten Dateien vollständig und direkt kopierbar:

1. `Dockerfile`
2. `docker-compose.yml`
3. `docker-entrypoint.sh`
4. Optional: `.env.example`
5. Optional: separates Compose-Profil oder Service für die einmalige interaktive Konfiguration
6. Eine kurze `README.md`-artige Anleitung mit:
   - Build und Start
   - Port-Konfiguration
   - Verwendung des externen GUI-Clients
   - Einrichtung der Read-only- und Read-write-Mounts
   - UID/GID- bzw. Berechtigungsmodell
   - Erstinitialisierung und Import vorbereiteter Konfigurationsdateien
   - Backup der persistenten Konfiguration
   - Troubleshooting für einen hängenden oder fehlgeschlagenen ersten Start

## Qualitätsanforderungen

- Erfinde keine Hermes-CLI-Parameter oder Konfigurationspfade. Wenn diese versionsabhängig oder unbekannt sind, markiere sie deutlich als Platzhalter und liefere Prüfkommandos, etwa `hermes --help` oder `hermes serve --help`.
- Erkläre jede Annahme kurz.
- Bevorzuge eine robuste, wartbare Lösung gegenüber einer möglichst kurzen Lösung.
- Vermeide Lösungen, bei denen ein interaktiver Setup-Assistent beim normalen Containerstart unbeobachtet blockieren kann.
