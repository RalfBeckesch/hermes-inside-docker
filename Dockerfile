# =============================================================================
# Dockerfile – Hermes Agent (derived image)
# =============================================================================
# Based on the official Hermes Docker image.
# The official image already ships: Hermes, ffmpeg, python3, node, npm,
# uv, git, curl, openssl, ripgrep, cmake, gcc, xvfb, chromium (playwright).
# This Dockerfile adds:
#   * Systempakete für Dokumente (PDF rendern, OCR, Datenbank-Clients, Schriften)
#   * uv im PATH (das Basis-Image legt es nur unter /opt/hermes/tools/ ab)
#   * Python-Pakete für den Werkzeug-Interpreter /opt/hermes/.venv
#   * das Laufzeit-Skript hermes-python-setup für /opt/data/.venv
#
# Docs:    https://hermes-agent.nousresearch.com/docs/user-guide/docker
# Image:   nousresearch/hermes-agent
# Build:   ./build.sh        (names/tags automatically: hermes-agent-custom)
# Pull:    docker pull nousresearch/hermes-agent:latest
# =============================================================================
FROM nousresearch/hermes-agent:latest

# ------------------------------------------------------------
# Extra tools: admin/debugging and documents
#   PDF rendern: libpangoft2-1.0-0, libpangocairo-1.0-0, libgdk-pixbuf-2.0-0
#                (WeasyPrint braucht die Pango-Backends; ohne sie bricht der Import ab)
#   PDF-Werkzeuge: poppler-utils (pdftotext/pdftoppm), qpdf, ghostscript
#   OCR gescannter Belege: tesseract-ocr mit deu/eng, imagemagick
#   Datenbanken: sqlite3, default-mysql-client, postgresql-client
#   Archive: 7zip
#   Schriften: ohne Liberation/Noto werden Emoji und Sonderzeichen zu Kaestchen
#   Bash-Pruefung: shellcheck
#
# WICHTIG: keine #-Kommentare INNERHALB der mit \ fortgesetzten Zeile. Ein
# Kommentar dort beendet die Zeile, und alle folgenden Pakete werden als eigene
# Befehle ausgefuehrt - der Bau laeuft durch, installiert aber nur die Haelfte.
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
        libpangoft2-1.0-0 \
        libpangocairo-1.0-0 \
        libgdk-pixbuf-2.0-0 \
        poppler-utils \
        qpdf \
        ghostscript \
        tesseract-ocr \
        tesseract-ocr-deu \
        tesseract-ocr-eng \
        imagemagick \
        sqlite3 \
        default-mysql-client \
        postgresql-client \
        7zip \
        fonts-liberation \
        fonts-noto-core \
        fonts-noto-color-emoji \
        fonts-dejavu-extra \
        ; \
    fc-cache -f; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# uv in den PATH
# Das Basis-Image bringt uv mit, es ist aber nicht aufrufbar (der Pfad enthaelt
# die Version). Der Stern haelt den Link auch nach einem Basis-Image-Update
# gueltig; zeigt er ins Leere, wurde die Version im Basis-Image umbenannt.
# ------------------------------------------------------------
RUN ln -sf /opt/hermes/tools/uv-*/uv /usr/local/bin/uv \
    && uv --version

# ------------------------------------------------------------
# Python-Pakete fuer den Werkzeug-Interpreter (/opt/hermes/.venv)
# Das ist der Interpreter, den das Hermes-Werkzeug "execute_code" benutzt.
# Die Paketliste steht in python-packages-tools.txt - DIESELBE Datei liest das
# Laufzeit-Skript hermes-python-setup, damit Image und laufender Container
# nicht auseinanderlaufen. Fuer das Daten-venv /opt/data/.venv siehe
# python-packages-data.txt: /opt/data ist ein Bind-Mount und beim Bau nicht
# vorhanden, dort installiert das Skript im laufenden Container.
#
# uv braucht kein pip im Ziel-venv - der frueher noetige Umweg ueber
# ensurepip entfaellt damit.
# ------------------------------------------------------------
COPY python-packages-tools.txt /opt/hermes/python-packages-tools.txt
COPY python-packages-data.txt /opt/hermes/python-packages-data.txt
RUN uv pip install --python /opt/hermes/.venv/bin/python -r /opt/hermes/python-packages-tools.txt \
    && /opt/hermes/.venv/bin/python -c "import av, pandas, matplotlib, weasyprint, openpyxl, docx, pptx, yaml; print('Python-Pakete bereit')"

# ------------------------------------------------------------
# Tools from this repo
# ------------------------------------------------------------
COPY generate-password-hash.sh /usr/local/bin/generate-password-hash
COPY hermes-python-setup.sh /usr/local/bin/hermes-python-setup
RUN chmod 755 /usr/local/bin/generate-password-hash /usr/local/bin/hermes-python-setup

# ------------------------------------------------------------
# Example configuration files
# ------------------------------------------------------------
COPY examples/ /opt/hermes/examples/
