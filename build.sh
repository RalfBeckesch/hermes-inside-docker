#!/usr/bin/env bash
# =============================================================================
# build.sh – Build the derived Hermes image with sane naming & tagging
# =============================================================================
# Every build produces TWO tags:
#   hermes-agent-custom:latest        -> always the newest build (convenience)
#   hermes-agent-custom:YYYYMMDD-HHMM -> immutable snapshot (rollback possible)
#
# Usage:
#   ./build.sh                  Build with defaults
#   ./build.sh --no-cache       Forward any extra args to `docker build`
#   IMAGE_NAME=foo ./build.sh   Override image name
#   NO_PULL=1 ./build.sh        Skip refreshing the base image
#
# After building, start the container with the new image:
#   HERMES_IMAGE=hermes-agent-custom:latest docker compose up -d
# =============================================================================
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

IMAGE_NAME="${IMAGE_NAME:-hermes-agent-custom}"
BUILD_TAG="${BUILD_TAG:-$(date +%Y%m%d-%H%M)}"

# Refresh the base image so the build starts from the newest upstream release.
# (Explicit `docker pull` instead of `docker build --pull always`, because the
#  legacy builder only knows the boolean `--pull` without a value.)
if [ "${NO_PULL:-0}" != "1" ]; then
    echo "==> Pulling base image nousresearch/hermes-agent:latest"
    docker pull nousresearch/hermes-agent:latest
fi

echo "==> Building ${IMAGE_NAME}:${BUILD_TAG} (+ :latest)"

docker build -t "${IMAGE_NAME}:latest" \
    -t "${IMAGE_NAME}:${BUILD_TAG}" \
    "$@" \
    .

echo
echo "==> Done. Tags created:"
docker image ls "${IMAGE_NAME}" --format '  {{.Repository}}:{{.Tag}}  ({{.Size}}, built {{.CreatedSince}})' | head -n 5
echo
echo "Start with the new image:"
echo "  HERMES_IMAGE=${IMAGE_NAME}:latest docker compose up -d"
echo
echo "Rollback to an earlier build:"
echo "  HERMES_IMAGE=${IMAGE_NAME}:<timestamp> docker compose up -d"
