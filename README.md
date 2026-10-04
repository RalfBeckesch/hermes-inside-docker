# Hermes Agent – Docker (official image)

Run [Hermes Agent](https://hermes-agent.nousresearch.com) by **Nous Research**
inside a Debian container. Uses the **official** `nousresearch/hermes-agent`
Docker image — no self-build, no entrypoint hacks, no wrapper scripts.

## Project files

```
hermes-inside-docker/
  Dockerfile                    Derived image (FROM official + extra tools)
  docker-compose.yml            Service definition (pull & start, no build)
  hermes-docker.service            systemd --user autostart
  generate-password-hash.sh     Helper: scrypt password hash generator
  .env.example                  Environment variable template
  .gitignore
  dev/                          Local dev files (not committed)
  examples/
    config.openai.yaml          Config + password auth for OpenAI
    config.openrouter.yaml      Config + password auth for OpenRouter
    config.custom-openai.yaml   Config + password auth for any OpenAI-compatible endpoint
```

## Architecture

```
  Host
   +-------+    /data/ro (ro)        Read-only input data
   | input |----> Container
   +-------+    /data/rw (rw)        Read-write workspace
   |workspc|----> Container
   +-------+    /opt/data (rw)       Persistent config (YAML + .env)
   | config |---> Container          (= HERMES_HOME)
   +-------+    /vault (rw)          Optional Obsidian vault (opt-in)
   | vault |----> Container
   +-------+
        GUI client --port 8080--> Container
```

The container runs under **s6-overlay** supervision. No custom entrypoint needed.

---

## Quick Start – 5 minutes

### 1. Prepare configuration

```bash
mkdir -p hermes-config input workspace

# Pick your provider and copy the matching config
cp examples/config.openai.yaml hermes-config/config.yaml

# Set your API key
echo "OPENAI_API_KEY=sk-proj-..." > hermes-config/.env
```

### 2. (Optional) UID mapping in .env

Make container-written files belong to your host user:

```bash
echo "PUID=$(id -u)" >> .env
echo "PGID=$(id -g)" >> .env
```

### 3. Start

```bash
docker compose up -d
```

No build — the image is pulled directly from Docker Hub (~920 MB compressed).

### 4. Connect

Point your Hermes GUI client to: `http://<host-ip>:8080`

Username: `admin`, password: `demo` (change this immediately, see Auth).

---

## Change password

```bash
./generate-password-hash.sh your-secure-password
```

Replace `dashboard.basic_auth.password_hash` in `hermes-config/config.yaml` with the output.

---

## Container commands

| Command | Effect |
|---------|--------|
| `docker compose up -d` | Start container (gateway mode) |
| `docker compose down` | Stop container |
| `docker compose logs -f` | Follow logs |
| `docker compose run --rm hermes-init setup` | Interactive setup |
| `docker compose run --rm hermes doctor` | Hermes diagnostics |
| `docker compose run --rm hermes bash` | Debug shell |

---

## UID/GID – Permission model

The official image runs as user `hermes` (UID 10000). With s6-overlay,
permissions are set via environment — no `--user` or `--build-arg` needed:

```bash
# In .env or compose environment:
PUID=1000
PGID=1000
```

The container starts as root, remaps the `hermes` user to the host UID,
chowns `/opt/data`, then s6 drops to the `hermes` user.

**Without PUID/PGID** files are written with UID 10000.

---

## Volumes

| Host path | Container | Mode | Purpose |
|-----------|-----------|------|---------|
| `./hermes-config/` | `/opt/data` | `:rw` | Persistent config (.yaml + .env) |
| `./input/` | `/data/ro` | `:ro` | Read-only input from host |
| `./workspace/` | `/data/rw` | `:rw` | Working directory |
| *(optional)* | `/vault` | `:rw` | Obsidian vault |

All paths are configurable via `.env` — see `.env.example`.

---

## Optional: Mount an Obsidian vault

Set `VAULT_DIR` in `.env`:

```env
VAULT_DIR=/path/to/your/vault
```

Or in `docker-compose.yml`:

```yaml
volumes:
  - /path/to/your/vault:/vault:rw
```

Hermes can then access notes via `read_file("/vault/note.md")`, write, search,
and patch — same as its own HV. The image detects the mount automatically
(stage2-hook).

---

## Security

- **Non-root user:** `hermes` (UID 10000, remappable via PUID/PGID)
- **No new privileges:** `security_opt: no-new-privileges:true`
- **No capabilities:** `cap_drop: [ALL]`, only `CAP_NET_BIND_SERVICE`
- **Auth required** when binding to `0.0.0.0`
- **Healthcheck:** TCP connect on the configured port

---

## Autostart (systemd --user)

```bash
mkdir -p ~/.config/systemd/user/
cp hermes-docker.service ~/.config/systemd/user/
# Adjust WorkingDirectory in the service file
systemctl --user daemon-reload
systemctl --user enable --now hermes-docker
```

---

## Migration summary (self-build → official image)

| Before (self-build) | After (official image) |
|---|---|
| Dockerfile builds Hermes via install.sh | `FROM nousresearch/hermes-agent:latest` |
| HERMES_HOME=/config | HERMES_HOME=/opt/data |
| Volumes mapped to /config | Volumes mapped to /opt/data |
| UID 1000 via --build-arg | UID 10000, remap via PUID/PGID |
| Custom docker-entrypoint.sh | main-wrapper.sh (in image) |
| Custom hermes-launcher.sh | `hermes` in PATH directly |
| `docker compose build` required | `docker compose up -d`, no build |
| CMD `serve` | Default `gateway run` (richer feature set) |
| ~4.2 GB image | ~920 MB (compressed) |