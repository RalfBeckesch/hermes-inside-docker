#!/usr/bin/env bash
# =============================================================================
# setup-ssh-key.sh – passwordless SSH for the Hermes agent container
# =============================================================================
# The container's hermes user has HOME=/opt/data, which is the bind-mounted
# hermes-config directory. So a key in ./hermes-config/.ssh/ is automatically
# ~/.ssh/ inside the container — no extra volume, no image rebuild.
#
# Usage:
#   ./setup-ssh-key.sh [keyname]     # keyname default: id_ed25519
#
# Afterwards:
#   1. Copy the printed public key to the target hosts:
#        ssh-copy-id -i hermes-config/.ssh/id_ed25519.pub user@target-host
#   2. Test from inside the container:
#        docker compose exec hermes ssh user@target-host hostname
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

# Resolve config dir: env var wins, then HERMES_CONFIG_DIR from .env, default.
CONFIG_DIR="${HERMES_CONFIG_DIR:-}"
if [ -z "$CONFIG_DIR" ] && [ -f .env ]; then
    CONFIG_DIR="$(grep -E '^\s*HERMES_CONFIG_DIR\s*=' .env | tail -1 | cut -d= -f2- | tr -d '"'"'"' ')"
fi
CONFIG_DIR="${CONFIG_DIR:-./hermes-config}"
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"   # expand leading ~ like docker compose does
SSH_DIR="${CONFIG_DIR}/.ssh"
KEY_NAME="${1:-id_ed25519}"
KEY_FILE="${SSH_DIR}/${KEY_NAME}"

# ---- Sanity: the config dir must exist (it holds config.yaml + .env) --------
if [ ! -d "$CONFIG_DIR" ]; then
    echo "ERROR: config dir '$CONFIG_DIR' not found — run the normal setup first." >&2
    exit 1
fi

# ---- Warn if PUID is not set -------------------------------------------------
# Without PUID the container user is UID 10000, but the key file on the host
# belongs to you — ssh refuses keys not owned by the calling user.
if ! grep -Eq '^\s*PUID\s*=' .env 2>/dev/null; then
    echo "WARNING: PUID is not set in .env — the container runs as UID 10000 and" >&2
    echo "         will refuse the key (wrong owner). Fix with:" >&2
    echo "           echo 'PUID=\$(id -u)' >> .env && echo 'PGID=\$(id -g)' >> .env" >&2
    echo >&2
fi

# ---- Create the key ----------------------------------------------------------
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -f "$KEY_FILE" ]; then
    echo "Key already exists: $KEY_FILE (leaving it untouched)"
else
    ssh-keygen -t ed25519 -a 100 -N '' -C "hermes-agent@$(hostname)" -f "$KEY_FILE"
    echo "Created: $KEY_FILE (no passphrase — dedicated agent key)"
fi
chmod 600 "$KEY_FILE" "${KEY_FILE}.pub"

# ---- SSH client defaults for unattended use ----------------------------------
SSH_CONFIG="${SSH_DIR}/config"
if [ ! -f "$SSH_CONFIG" ]; then
    cat > "$SSH_CONFIG" <<'EOF'
# Hermes agent container — unattended SSH defaults
Host *
    StrictHostKeyChecking accept-new
    IdentitiesOnly yes
    IdentityFile ~/.ssh/id_ed25519
EOF
    chmod 600 "$SSH_CONFIG"
    echo "Created: $SSH_CONFIG"
else
    echo "SSH config already exists: $SSH_CONFIG (leaving it untouched)"
fi

# ---- Result ------------------------------------------------------------------
echo
echo "==========================================================================="
echo "Done. Inside the container this is ~/.ssh/ (HOME=/opt/data)."
echo
echo "Public key — distribute to target hosts:"
echo "---------------------------------------------------------------------------"
cat "${KEY_FILE}.pub"
echo "---------------------------------------------------------------------------"
echo "Copy to a target:   ssh-copy-id -i ${KEY_FILE}.pub user@target-host"
echo "Test in container:  docker compose exec hermes ssh user@target-host hostname"
echo
echo "Security notes:"
echo "  * This key has NO passphrase — keep hermes-config/ private (gitignored)."
echo "  * Use a DEDICATED key, never your personal one."
echo "  * On targets, optionally restrict the key in authorized_keys:"
echo "      from=\"10.0.0.0/8\",no-agent-forwarding ssh-ed25519 AAAA... hermes-agent"
echo "==========================================================================="
