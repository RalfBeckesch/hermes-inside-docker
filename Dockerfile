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
# Build:   docker build -t hermes-agent:latest .
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
	av \
        ; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Tools from this repo
# ------------------------------------------------------------
COPY generate-password-hash.sh /usr/local/bin/generate-password-hash
RUN chmod 755 /usr/local/bin/generate-password-hash

# ------------------------------------------------------------
# Example configuration files
# ------------------------------------------------------------
COPY examples/ /opt/hermes/examples/
