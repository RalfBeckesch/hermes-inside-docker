Create a complete, production-grade Docker solution for **Hermes** based on a current Debian image.

## Goal

Hermes shall run inside a Debian-based container and be reachable from outside the container via its server mode. The container must execute Hermes on startup with `serve --host --port` so I can connect with an external GUI client.

## Requirements

### Container Base

- Use a current, slim Debian image, preferably `debian:bookworm-slim` or newer.
- Cleanly install all runtime dependencies required by Hermes in the Dockerfile.
- Install Hermes in a traceable and version-pinned manner. If Hermes is installed via a package manager, release binary, or installer, document the chosen installation method.
- The container should run as a non-root user where possible.
- Create sensible working, configuration, and data directories.

### Networking

- Hermes must run persistently as a server when the container starts.
- Use a configurable port, default e.g. `8080`.
- Start Hermes explicitly with:

  ```bash
  hermes serve --host 0.0.0.0 --port "${HERMES_PORT}"
  ```

  If the actual Hermes CLI requires different syntax or parameters, verify these and use the correct variant.

- The port must be documented in the Dockerfile with `EXPOSE`.
- Provide a `docker-compose.yml` that can publish the port on the host, for example:

  ```yaml
  ports:
    - "8080:8080"
  ```

- Account for the fact that `127.0.0.1` is **not** sufficient, since the GUI client connects from outside the container.

### Host Directories

I need two separate mount points:

| Purpose | Container Path | Mount Mode |
|---|---|---|
| Readable input data from host | `/data/ro` | Read-only |
| Writable working and result data from host | `/data/rw` | Read-write |

The mounts must be clearly defined in `docker-compose.yml`, for example:

```yaml
volumes:
  - ./input:/data/ro:ro
  - ./workspace:/data/rw:rw
```

Hermes must be able to write to `/data/rw` under the non-root user being used. Therefore, clearly document how host directory permissions, UID, and GID should be handled.

### Persistent Configuration

- The Hermes configuration must not be lost on every container restart.
- Use a separate persistent directory for this, for example:

  ```text
  /config
  ```

- Mount this directory in Compose as a host mount or a named Docker volume.
- Ensure via environment variables, startup parameters, or symlinks that Hermes actually uses its configuration from that location.

## First Start / Interactive Configuration Mode

A central problem is that Hermes may open an interactive configuration wizard on first start. That is not acceptable in a persistently running, headless Docker container.

Therefore, implement a robust initialisation strategy with the following priority:

1. **Non-interactive Hermes mode:**  
   First check whether Hermes offers an official option such as `--non-interactive`, `--yes`, `--config`, `init`, `configure`, environment variables, or comparable mechanisms. Use it if available.

2. **Prepared configuration:**  
   If Hermes does not support a clean non-interactive initialisation, allow mounting ready-made configuration files from the host to `/config`, for example:

   ```yaml
   volumes:
     - ./hermes-config:/config:rw
   ```

   Describe exactly:
   - Which file(s) are needed.
   - At which path Hermes expects them.
   - How these can be created once, or exported from a temporary interactive container.
   - Which settings must be set before the first server start.

3. **Init container or one-time setup command:**  
   If necessary, additionally provide a separate Compose service or a documented `docker compose run` command to create the configuration interactively once. The normal service must then run exclusively headless in server mode.

4. **Entrypoint check:**  
   Implement an entrypoint script that detects at startup whether the required configuration is present.
   - If the configuration is present: start Hermes normally in server mode.
   - If it is missing: do not get stuck in an invisible interactive wizard.
   - Instead, output a comprehensible error message stating which configuration file or which initialisation step is missing, and exit the container with a non-zero exit code.
   - Optionally: if a reliable non-interactive initialisation is possible and well-tested, run it automatically.

## Security and Operations

- Do not use a privileged container.
- Do not run Hermes as root.
- Where possible, use:
  - `read_only: true` for the container filesystem,
  - `tmpfs` for temporary directories,
  - `security_opt: no-new-privileges:true`,
  - `cap_drop: [ALL]`.
- If Hermes requires write access to additional internal paths, explicitly define them as a volume or `tmpfs`.
- Add sensible logging hints and a healthcheck, provided Hermes supports a suitable HTTP, TCP, or CLI healthcheck.

## Expected Output

Deliver all required files completely and ready to copy:

1. `Dockerfile`
2. `docker-compose.yml`
3. `docker-entrypoint.sh`
4. Optional: `.env.example`
5. Optional: separate Compose profile or service for the one-time interactive configuration
6. A short `README.md`-style guide including:
   - Build and start
   - Port configuration
   - Using the external GUI client
   - Setting up the read-only and read-write mounts
   - UID/GID / permissions model
   - First-time initialisation and importing prepared configuration files
   - Backing up the persistent configuration
   - Troubleshooting a stuck or failed first start

## Quality Requirements

- Do not invent Hermes CLI parameters or configuration paths. If these are version-dependent or unknown, clearly mark them as placeholders and provide verification commands, e.g. `hermes --help` or `hermes serve --help`.
- Briefly explain every assumption.
- Prefer a robust, maintainable solution over the shortest possible one.
- Avoid solutions where an interactive setup wizard can block unobserved on normal container startup.