# Hermes Agent – Docker (official image)

Run [Hermes Agent](https://hermes-agent.nousresearch.com) by **Nous Research**
inside a Debian container. Uses the **official** `nousresearch/hermes-agent`
Docker image — no self-build, no entrypoint hacks, no wrapper scripts.

## Project files

```
hermes-inside-docker/
  Dockerfile                    Derived image (FROM official + extra tools)
  build.sh                      One-command build with naming & tagging
  docker-compose.yml            Service definition (pull & start, no build)
  hermes-docker.service            systemd --user autostart
  generate-password-hash.sh     Helper: scrypt password hash generator
  setup-ssh-key.sh              Helper: passwordless SSH key for the agent
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
   +------------+    /hermes-input-ro (ro)      Read-only input data
   |   input    |----> Container
   +------------+    /hermes-workspace-rw (rw)   Read-write workspace
   |  workspace |----> Container
   +------------+    /opt/data (rw)              Persistent config (YAML + .env)
   |   config   |---> Container                 (= HERMES_HOME)
   +------------+    /hermes-vault (rw)          Optional Obsidian vault (opt-in)
   |   vault    |----> Container
   +------------+
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

## Passwordless SSH from the agent

The container's `hermes` user has `HOME=/opt/data` — which is the bind-mounted
config directory. A key in `<HERMES_CONFIG_DIR>/.ssh/` is therefore
automatically `~/.ssh/` inside the container: no extra volume, no rebuild,
and the key survives container updates (the image already ships `ssh`).

```bash
./setup-ssh-key.sh
```

The script creates a dedicated passphrase-less `id_ed25519` key plus an
`~/.ssh/config` with unattended defaults (`StrictHostKeyChecking accept-new`),
and prints the public key. Distribute it to your targets:

```bash
ssh-copy-id -i <HERMES_CONFIG_DIR>/.ssh/id_ed25519.pub user@target-host
```

Test from inside the running container:

```bash
docker compose exec hermes ssh user@target-host hostname
```

Requirements & security notes:

- **PUID/PGID must be set** in `.env` — ssh refuses keys whose owner doesn't
  match the calling user (without PUID the container runs as UID 10000).
- Never `COPY` keys into the image — they would persist in every layer and
  require a rebuild on rotation. The bind mount keeps rotation trivial.
- Use a **dedicated key**, never your personal one. On the targets you can
  restrict it per-key in `authorized_keys`, e.g.
  `from="192.168.1.0/24",no-agent-forwarding ssh-ed25519 AAAA... hermes-agent`.
- The key has no passphrase (unattended use), so treat the config directory
  as a secret — it is gitignored here.

---

## Build a custom image (build.sh)

The `Dockerfile` derives from the official image and adds extra tools
(neovim, tmux, screen, yt-dlp, PyAV, ...). After editing the Dockerfile,
one command rebuilds everything:

```bash
./build.sh
```

What the script does:

1. `docker pull nousresearch/hermes-agent:latest` — start from the newest base
2. `docker build` with two tags (see naming below)
3. Prints the resulting images and the command to run them

### Naming & tagging

Every build creates **two tags** of the image `hermes-agent-custom`:

| Tag | Example | Purpose |
|-----|---------|---------|
| `latest` | `hermes-agent-custom:latest` | Convenience — always the newest build |
| timestamp | `hermes-agent-custom:20261106-1532` | Immutable snapshot — rollback target |

`latest` alone is convenient but not reproducible: once rebuilt, the old
state is gone. The timestamp tag keeps every build reachable, so switching
back to an earlier image is one command (see Rollback).

The derived image deliberately uses its **own name** instead of reusing
`nousresearch/hermes-agent` — official and self-built images stay
distinguishable in `docker image ls`.

### Options

```bash
./build.sh --no-cache          # extra args are forwarded to `docker build`
IMAGE_NAME=my-name ./build.sh  # override image name
BUILD_TAG=v1.2 ./build.sh      # override timestamp tag
NO_PULL=1 ./build.sh           # skip refreshing the base image
```

### Run the self-built image

`docker-compose.yml` reads the image from `HERMES_IMAGE` (default: official
image). No file editing needed:

```bash
# one-off
HERMES_IMAGE=hermes-agent-custom:latest docker compose up -d

# permanent: put it in .env
echo "HERMES_IMAGE=hermes-agent-custom:latest" >> .env
docker compose up -d
```

### Rollback

```bash
docker image ls hermes-agent-custom        # list available builds
HERMES_IMAGE=hermes-agent-custom:20261106-1532 docker compose up -d
```

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
| `docker compose run --rm hermes-init setup` | Interactive setup (first-run wizard) |
| `docker compose run --rm hermes doctor` | Hermes diagnostics |
| `docker compose run --rm hermes bash` | Debug shell |

> **`hermes-init`** is a separate service in `docker-compose.yml` (profile: `init`)
> for one-shot interactive tasks. It shares the same config volume as the main
> container but runs with `stdin_open: true` so you can answer prompts.

---

## Shared memory (browser tools)

Playwright/Chromium inside the container needs `/dev/shm` larger than 64 MB.
`docker-compose.yml` sets `shm_size: 1g` — no action needed on a standard
Docker host. If you deploy to an orchestrator that ignores compose `shm_size`,
pass `--shm-size=1g` in the deploy command.

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
| `./input/` | `/hermes-input-ro` | `:ro` | Read-only input from host |
| `./workspace/` | `/hermes-workspace-rw` | `:rw` | Working directory |
| *(optional)* | `/hermes-vault` | `:rw` | Obsidian vault |

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
  - /path/to/your/vault:/hermes-vault:rw
```

Hermes can then access notes via `read_file("/hermes-vault/note.md")`, write, search,
and patch — same as its own HV. The image detects the mount automatically
(stage2-hook).

---

## Security

- **Non-root user:** `hermes` (UID 10000, remappable via PUID/PGID)
- **s6-overlay supervision:** minimal surface — drops privileges after bootstrap via `s6-setuidgid`
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