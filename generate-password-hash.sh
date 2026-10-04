#!/bin/sh
# =============================================================================
# generate-password-hash.sh -- Generate a Hermes password hash for basic auth
# =============================================================================
# Usage:
#   ./generate-password-hash.sh [password]
#
# Examples:
#   ./generate-password-hash.sh                        # default: "demo"
#   ./generate-password-hash.sh your-secure-password
# =============================================================================
set -e

IMAGE_NAME="${IMAGE_NAME:-nousresearch/hermes-agent:latest}"
PASSWORD="${1:-demo}"

# Ensure the image is available locally
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Pulling image $IMAGE_NAME ..."
    docker pull "$IMAGE_NAME"
fi

echo "Generating hash for password: $PASSWORD"
echo ""

HASH=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "
python3 -c \"
from plugins.dashboard_auth.basic import hash_password
import sys
pwd = sys.argv[1] if len(sys.argv) > 1 else '${PASSWORD}'
print(hash_password(pwd))
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