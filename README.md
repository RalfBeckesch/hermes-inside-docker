# Hermes Agent -- Docker

Run [Hermes Agent](https://hermes-agent.nousresearch.com) by **Nous Research**
inside a Debian container and connect from an external GUI client.

## Project Files

```
hermes-inside-docker/
  Dockerfile                    Multi-stage build (bookworm-slim)
  docker-compose.yml            Service + init service definition
  docker-entrypoint.sh          Config check, initialisation, server start
  hermes-launcher.sh            Wrapper that finds the venv Python at runtime
  hermes-docker.service         systemd --user autostart (login=start, logout=stop)
  generate-password-hash.sh     Helper: generate an scrypt password hash
  .env.example                  Environment variable template
  README.md                     This document
  examples/
    config.openai.yaml          Config + password auth for OpenAI
    config.openrouter.yaml      Config + password auth for OpenRouter
    config.custom-openai.yaml   Config + password auth for any OpenAI-compatible endpoint
```

## Architecture

```
  Host
   +-------+    /data/ro (ro)        Read-only input data
   | input |----> container
   +-------+    /data/rw (rw)        Read-write work and results
   |workspc|----> container
   +-------+    /config (rw)         Persistent config (yaml + .env)
   |config |----> container
   +-------+    /vault (rw)          Optional Obsidian vault (opt-in)
   | vault |----> container
   +-------+
        GUI client --port 8080--> container
```

---

## Quick Start -- 5 Minutes

### 1. Build

```bash
cd hermes-inside-docker
docker compose build
```

Takes 3-5 min on first run. Subsequent builds are instant (cached).

### 2. Configure

Pick your LLM provider and copy the matching config:

```bash
# OpenAI
cp examples/config.openai.yaml hermes-config/config.yaml

# OpenRouter
cp examples/config.openrouter.yaml hermes-config/config.yaml

# Corporate / self-hosted OpenAI-compatible API
cp examples/config.custom-openai.yaml hermes-config/config.yaml
```

### 3. Set API Key

```bash
# OpenAI
echo "OPENAI_API_KEY=sk-proj-..." > hermes-config/.env

# OpenRouter
echo "OPENROUTER_API_KEY=sk-or-v1-..." > hermes-config/.env

# Custom
echo "CUSTOM_API_KEY=sk-..." > hermes-config/.env
```

### 4. Change Default Password (Important)

The example configs include a demo password: **username `admin`, password `demo`**.
Generate your own:

```bash
./generate-password-hash.sh your-secure-password
```

Replace the `password_hash` value in `hermes-config/config.yaml` with the output.

### 5. Start

```bash
docker compose up -d
```

### 6. Connect

Point your Hermes GUI client to:

```
http://<host-ip>:8080
```

Enter the username and password from step 4.

---

## Provider Configuration

### OpenAI

```yaml
model:
  default: gpt-4o
  provider: openai
```
| Env var: `OPENAI_API_KEY`

### OpenRouter

```yaml
model:
  default: openai/gpt-4o
  provider: openrouter
```
| Env var: `OPENROUTER_API_KEY`

Other models: `anthropic/claude-sonnet-4.6`, `deepseek/deepseek-chat`,
`google/gemini-2.5-pro`.

### Custom OpenAI-Compatible

```yaml
model:
  default: gpt-4o-mini
  provider: custom
  base_url: "https://api.your-company.com/v1"
  api_key: "${CUSTOM_API_KEY}"
```
| Env var: `CUSTOM_API_KEY`

Works with corporate API gateways, self-hosted vLLM/TGI, or local proxies.

### Interactive Setup (Alternative)

```bash
docker compose run --rm hermes-init
```

Runs the Hermes setup wizard interactively. Generated config is saved to
`./hermes-config/`.

---

## Auth -- Required for 0.0.0.0 Binding

Since June 2026, Hermes refuses to bind `serve` to `0.0.0.0` (all interfaces)
without an auth provider. You have three options:

| Option | Auth needed | External access |
|--------|-------------|-----------------|
| A. Password auth | yes | direct |
| B. SSH tunnel | no | via tunnel |
| C. WireGuard tunnel | no | via tunnel |

### A) Password Auth (Recommended)

All example configs include a `dashboard.basic_auth` block. Generate your own:

```bash
./generate-password-hash.sh my-password
```

Output:
```
dashboard:
  basic_auth:
    username: admin
    password_hash: "scrypt$16384$8$1$..."
```

Paste into `hermes-config/config.yaml`.

### B) SSH Tunnel (No Auth)

```yaml
server:
  host: 127.0.0.1
  port: 8080
```

```bash
ssh -L 8080:127.0.0.1:8080 user@docker-host
# Then connect to http://127.0.0.1:8080 from client machine
```

### C) WireGuard Tunnel (No Auth)

Same as SSH: bind to `127.0.0.1`, forward via WireGuard.

---

## Port

```bash
# Via .env
HERMES_PORT=9090

# Inline
HERMES_PORT=9090 docker compose up -d
```

Default: 8080.

---

## Data Directories

| Host path | Container | Mode | Purpose |
|-----------|-----------|------|---------|
| `./input/` | `/data/ro` | `:ro` | Read-only input from host |
| `./workspace/` | `/data/rw` | `:rw` | Read-write work and results |
| `./hermes-config/` | `/config` | `:rw` | Persistent configuration + API keys |
| *(optional)* `/vault` | `/vault` | `:rw` | Obsidian vault (opt-in below) |

---

## Optional Obsidian Vault Mount

Mount an existing Obsidian vault so Hermes can read, write, search, and
patch notes -- same full access as with its own HV.

### Setup

Uncomment the vault volume in `docker-compose.yml`:

```yaml
volumes:
  - /absolute/path/to/your/vault:/vault:rw
```

### UID/GID Match

The container user `hermes` has UID 1000 by default. Match it to your
host user:

```bash
docker compose build --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g)
```

### What Works

| Operation | How |
|-----------|-----|
| Read notes | `read_file(path="/vault/note.md")` |
| Write notes | `write_file(path="/vault/note.md", content="...")` |
| Search | `search_files(pattern="...", path="/vault")` |
| Patch notes | `patch(path="/vault/note.md", old_string="...", new_string="...")` |
| Navigate | `terminal(command="ls /vault/")` |

The entrypoint detects the mount and logs whether `.obsidian/` is present.

---

## Permission Model

```bash
# Match UID to your host user
docker compose build --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g)
```

The container runs as user `hermes` (UID/GID 1000 by default). Rebuild with
your UID for access to vault and workspace files.

---

## Container Commands

| Command | Effect |
|---------|--------|
| `docker compose up -d` | Start server in background |
| `docker compose down` | Stop server |
| `docker compose logs -f` | Follow logs |
| `docker compose run --rm hermes-init` | One-time interactive setup |
| `docker compose run --rm hermes config get default.model` | Read a config value |
| `docker compose run --rm hermes shell` | Debug shell |
| `docker compose run --rm hermes doctor` | Hermes diagnostics |

---

## Init Strategy -- No Stuck Wizards

The entrypoint checks on startup:

1. **config.yaml exists?** Yes -> start. No -> create minimal config.
2. **.env exists?** No -> warning with instructions.
3. **Neither exists?** Exit with error. Never stuck in a headless wizard.

---

## Autostart -- Start on Login, Stop on Logout

The project includes a **systemd --user service** that starts the container
when you log in and stops it when you log out.

### Install

```bash
mkdir -p ~/.config/systemd/user/
cp hermes-docker.service ~/.config/systemd/user/

# Edit the path to match your project location
nano ~/.config/systemd/user/hermes-docker.service
# Change WorkingDirectory to the full absolute path of your
# hermes-inside-docker directory, for example:
#   WorkingDirectory=/home/rb/hermes-inside-docker

systemctl --user daemon-reload
systemctl --user enable hermes-docker
systemctl --user start hermes-docker
```

### Verify

```bash
systemctl --user status hermes-docker
journalctl --user -u hermes-docker -f
```

### How It Works

- `WantedBy=default.target` -> starts when **your user session starts** (login)
- `Type=oneshot` + `RemainAfterExit=yes` -> runs `up -d`, marks as active
- systemd --user termination (logout) -> runs `ExecStop` -> `docker compose down`
- `Restart=on-failure` -> auto-restart on crash or Docker daemon restart

### Uninstall

```bash
systemctl --user stop hermes-docker
systemctl --user disable hermes-docker
rm ~/.config/systemd/user/hermes-docker.service
systemctl --user daemon-reload
```

### No systemd? Desktop Autostart

If your system doesn't use systemd --user, use `.desktop` files:

```bash
mkdir -p ~/.config/autostart/

# Start on login
cat > ~/.config/autostart/hermes-docker.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Hermes Agent
Exec=docker compose -f /home/rb/hermes-inside-docker/docker-compose.yml up -d
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# Stop on logout -- create a logout script in your DE settings
```

---

## Security

- **Non-root user:** `hermes` (UID/GID 1000, configurable)
- **No new privileges:** `security_opt: no-new-privileges:true`
- **No capabilities:** `cap_drop: [ALL]`
- **Auth required for public bind:** Password or OAuth

## Health Check

```yaml
healthcheck:
  test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/${HERMES_PORT} 2>/dev/null"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

TCP connect check (Hermes serve has no HTTP health endpoint).

## Logging

```bash
docker compose logs -f
docker compose run --rm hermes doctor
```

## Backup

```bash
tar czf hermes-config-backup-$(date +%F).tar.gz hermes-config/
tar xzf hermes-config-backup-YYYY-MM-DD.tar.gz
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container exits immediately | Config missing | Create `./hermes-config/config.yaml` |
| Cannot connect | Port not exposed | Check `docker compose ps` |
| Permission denied | UID mismatch | Rebuild with `USER_ID=$(id -u)` |
| "No API key" | `.env` missing | Add API key to `./hermes-config/.env` |
| Refuses bind 0.0.0.0 | Auth required | Add `dashboard.basic_auth` (see Auth section) |
| systemd service won't start | Wrong WorkingDirectory | Fix path in service file |

## Known Limitations

- **No desktop app build** inside container. `serve` provides JSON-RPC/WS.
- **Health check is TCP-only.** No HTTP health endpoint.
- **Large image** (~4.2 GB). Normal for Hermes -- includes ffmpeg, node,
  Python, browser agent, etc.
- **Memory:** ~200-400 MB RAM when idle.
- **`--insecure` is DEPRECATED** since June 2026 hardening. Use password auth
  or a tunnel (SSH/WireGuard).