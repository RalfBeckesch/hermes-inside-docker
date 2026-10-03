# =============================================================================
# Dockerfile – Hermes Agent (Debian Bookworm)
# =============================================================================
# Hermes Agent: https://hermes-agent.nousresearch.com
# Build: docker build -t hermes-agent:latest .
# =============================================================================
ARG DEBIAN_VERSION=bookworm

FROM debian:${DEBIAN_VERSION}-slim AS build

# ------------------------------------------------------------
# 1. System dependencies for the install script
# ------------------------------------------------------------
RUN set -eux; \
    apt-get update -qq; \
    apt-get install -y -qq --no-install-recommends \
        ca-certificates \
        curl \
        git \
        libatomic1 \
        ; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# 2. Install Hermes Agent (non-interactive)
# ------------------------------------------------------------
# Installs system-wide so the hermes binary is in PATH for any user.
# --non-interactive skips terminal-interactive stages.
ARG HERMES_BRANCH=main
ARG HERMES_COMMIT=""

RUN set -eux; \
    INSTALL_ARGS=""; \
    if [ -n "${HERMES_COMMIT}" ]; then \
      INSTALL_ARGS="${INSTALL_ARGS} --commit ${HERMES_COMMIT}"; \
    fi; \
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
      | bash -s -- \
        --non-interactive \
        --branch "${HERMES_BRANCH}" \
        --dir /opt/hermes-agent \
        ${INSTALL_ARGS} \
        ; \
    # The installer places the 'hermes' launcher in ~/.local/bin/
    export PATH="$HOME/.local/bin:$PATH"; \
    hermes_bin=$(command -v hermes); \
    echo "hermes binary: $hermes_bin"; \
    $hermes_bin --version; \
    # Also copy the launcher into /opt/hermes-agent for the runtime stage
    mkdir -p /opt/hermes-agent/bin; \
    cp -a "$hermes_bin" /opt/hermes-agent/bin/hermes; \
    # Copy .hermes tools into the repo dir so the runtime stage can find them
    mkdir -p /opt/hermes-agent/.hermes; \
    cp -a /root/.hermes /opt/hermes-agent/ 2>/dev/null || true

# =============================================================================
# Runtime stage — smaller final image, no build-time dependencies
# =============================================================================
FROM debian:${DEBIAN_VERSION}-slim

# ------------------------------------------------------------
# 1. Runtime system dependencies
# ------------------------------------------------------------
RUN set -eux; \
    apt-get update -qq; \
    apt-get install -y -qq --no-install-recommends \
        ca-certificates \
        git \
        libatomic1 \
        ; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# 2. Copy Hermes from build stage
# ------------------------------------------------------------
# Copy the full Hermes installation (repo, venv, tools, and the 'hermes' launcher).
COPY --from=build /opt/hermes-agent /opt/hermes-agent

# The 'hermes' launcher was copied into /opt/hermes-agent/bin/ during build.
# It hardcodes the hermetic tools python without the venv site-packages.
# We overwrite the inner launcher with a wrapper that finds the venv Python.
COPY hermes-launcher.sh /opt/hermes-agent/.hermes/bin/hermes
RUN chmod 755 /opt/hermes-agent/.hermes/bin/hermes && \
    ln -sf /opt/hermes-agent/bin/hermes /usr/local/bin/hermes

# ------------------------------------------------------------
# 3. Create non-root user
# ------------------------------------------------------------
# UID/GID can be overridden at build time to match the host user.
ARG USER_ID=1000
ARG GROUP_ID=1000

RUN set -eux; \
    groupadd --gid "${GROUP_ID}" --non-unique hermes; \
    useradd  --uid "${USER_ID}" --gid "${GROUP_ID}" \
             --no-create-home --shell /usr/sbin/nologin \
             hermes; \
    # Make .hermes tools accessible to the non-root user, and fix any symlinks
    # that point to /root/.hermes/tools instead of /opt/hermes-agent/.hermes/tools.
    find /opt/hermes-agent/.hermes -exec chmod a+r {} \; 2>/dev/null; \
    find /opt/hermes-agent/.hermes -type d -exec chmod a+x {} \; 2>/dev/null; \
    find /opt/hermes-agent/.hermes -type f \( -name "python*" -o -name "pip*" -o -name "hermes*" -o -name "activate" \) -exec chmod a+x {} \; 2>/dev/null; \
    find /opt/hermes-agent/.hermes -lname "/root/.hermes/tools/*" -exec sh -c 'TARGET=$(readlink "$1"); NEWTARGET=$(echo "$TARGET" | sed "s|^/root/\.hermes/|/opt/hermes-agent/.hermes/|"); ln -sf "$NEWTARGET" "$1"' _ {} \; 2>/dev/null; \
    chmod 755 /root; \
    install -d -o hermes -g hermes -m 0755 \
        /config \
        /data/rw \
        /vault \
        /opt/hermes-agent/.hermes

# ------------------------------------------------------------
# 4. Volumes & environment
# ------------------------------------------------------------
# Persistent Hermes configuration (mount or named volume).
VOLUME /config

# Optional Obsidian vault mount for Hermes to read/write freely.
VOLUME /vault

# Read-only input data from host.
VOLUME /data/ro

# Read-write working data from host.
VOLUME /data/rw

ENV HERMES_HOME=/config
ENV HERMES_PORT=8080

EXPOSE ${HERMES_PORT}

# ------------------------------------------------------------
# 5. Entrypoint
# ------------------------------------------------------------
WORKDIR /data/rw
USER hermes

COPY --chown=hermes:hermes docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 755 /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["serve"]