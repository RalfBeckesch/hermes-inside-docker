#!/bin/sh
# =============================================================================
# generate-password-hash.sh -- Generate a Hermes password hash for basic auth
# =============================================================================
# Usage:
#   docker compose build   # one-time
#   ./generate-password-hash.sh [password]
#
# Or directly via Docker:
#   docker run --rm --entrypoint bash hermes-agent:latest -c \
#     'PASSWORD="${1:-demo}"; exec /opt/hermes-agent/.hermes/tools/python-*/bin/python3
#       -c "import sys; sys.path.insert(0,\"/opt/hermes-agent\"); import glob; [sys.path.insert(0,sp) for sp in glob.glob(\"/opt/hermes-agent/.hermes/installs/*/environments/*/venv/lib/python*/site-packages\")]; from plugins.dashboard_auth.basic import hash_password; print(hash_password(\"'$1'\" if len(sys.argv)>1 else \"demo\"))"'
# =============================================================================
set -e

IMAGE_NAME="${IMAGE_NAME:-hermes-agent:latest}"
PASSWORD="${1:-demo}"

if [ -n "$1" ]; then
	PASSWORD="$1"
fi

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Building image $IMAGE_NAME first ..."
    docker compose build 2>/dev/null || docker build -t "$IMAGE_NAME" .
fi

echo "Generating hash for password: $PASSWORD"
echo ""

HASH=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "
/opt/hermes-agent/.hermes/tools/python-*/bin/python3 -c \"
import sys
sys.path.insert(0, '/opt/hermes-agent')
import glob
for sp in glob.glob('/opt/hermes-agent/.hermes/installs/*/environments/*/venv/lib/python*/site-packages'):
    sys.path.insert(0, sp)
from plugins.dashboard_auth.basic import hash_password
print(hash_password('$PASSWORD'))
\"
")

echo "Password: $PASSWORD"
echo "Hash: $HASH"
echo ""
echo "Add to your config.yaml:"
echo ""
echo "  dashboard:"
echo "    basic_auth:"
echo "      username: admin"
echo "      password_hash: \"$HASH\""
echo ""
echo "Connect to http://host:8080 — your browser will prompt for username + password."
