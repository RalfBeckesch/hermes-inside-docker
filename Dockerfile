# =============================================================================
# Dockerfile – Hermes Agent (derived image)
# =============================================================================
# Based on the official Hermes Docker image.
# The official image already ships: Hermes, ffmpeg, python3, node, npm,
# uv, git, curl, openssl, ripgrep, cmake, gcc, xvfb, chromium (playwright).
# This Dockerfile adds optional admin/debugging tools.
#
# Docs:    https://hermes-agent.nousresearch.com/docs/user-guide/docker
# Image:   nousresearch/hermes-agent
# Build:   ./build.sh        (names/tags automatically: hermes-agent-custom)
# Pull:    docker pull nousresearch/hermes-agent:latest
# =============================================================================
FROM nousresearch/hermes-agent:latest

# ------------------------------------------------------------
# Extra tools (optional – admin / debugging)
# ------------------------------------------------------------
RUN set -eux; \
    apt-get update -qq; \
    apt-get install -y -qq --no-install-recommends \
        wget \
        jq \
        nano \
        unzip \
        zip \
        yt-dlp \
        neovim \
        bash \
        bash-completion \
        screen \
        tmux \
	shellcheck \
        ; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# PyAV (Python bindings for ffmpeg) in the Hermes venv
# (no apt package `av` exists in Debian trixie; the uv-built venv
#  has no pip, so bootstrap it via ensurepip first)
# ------------------------------------------------------------
RUN /opt/hermes/.venv/bin/python -m ensurepip --upgrade \
    && /opt/hermes/.venv/bin/python -m pip install --no-cache-dir av \
    && /opt/hermes/.venv/bin/python -c "import av; print('PyAV', av.__version__)" \
    && /opt/hermes/.venv/bin/python -m pip uninstall -y pip setuptools

# ------------------------------------------------------------
# Tools from this repo
# ------------------------------------------------------------
COPY generate-password-hash.sh /usr/local/bin/generate-password-hash
RUN chmod 755 /usr/local/bin/generate-password-hash

# ------------------------------------------------------------
# Example configuration files
# ------------------------------------------------------------
COPY examples/ /opt/hermes/examples/
