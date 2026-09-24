#!/bin/bash
# =============================================================================
# down.sh — Stop Hermes Suite container
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yaml"

# --- Load config from versions.env ---
if [ -f "${SCRIPT_DIR}/versions.env" ]; then
    eval "$(grep -E '^(AGENT_VERSION|CONTAINER_RUNTIME|USE_SUDO)=' "${SCRIPT_DIR}/versions.env")"
fi
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
USE_SUDO="${USE_SUDO:-false}"

# --- Auto-detect ---
if [ "$CONTAINER_RUNTIME" = "auto" ]; then
    if command -v podman &>/dev/null; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker &>/dev/null; then
        CONTAINER_RUNTIME="docker"
    else
        echo "ERROR: Neither podman nor docker found."
        exit 1
    fi
fi

# --- Determine sudo prefix ---
SUDO_PREFIX=""
if [ "$USE_SUDO" = "true" ]; then
    SUDO_PREFIX="sudo"
fi

# --- Derive image tag from versions.env ---
AGENT_VER_CLEAN="${AGENT_VERSION#v}"
export HERMES_SUITE_IMAGE_TAG="${AGENT_VER_CLEAN}"

# For sudo: compose needs explicit env passthrough
if [ "$USE_SUDO" = "true" ]; then
    COMPOSE_PREFIX="sudo env HERMES_SUITE_IMAGE_TAG=${HERMES_SUITE_IMAGE_TAG}"
else
    COMPOSE_PREFIX=""
fi

# --- Stop ---
case "$CONTAINER_RUNTIME" in
    podman)
        export PATH="$HOME/.local/bin:$PATH"
        PODMAN_COMPOSE="$(command -v podman-compose)"
        $COMPOSE_PREFIX "$PODMAN_COMPOSE" -f "${COMPOSE_FILE}" down
        ;;
    docker|docker-nolog)
        $COMPOSE_PREFIX docker compose -f "${COMPOSE_FILE}" down
        ;;
    *)
        echo "ERROR: Unknown CONTAINER_RUNTIME: $CONTAINER_RUNTIME"
        exit 1
        ;;
esac

echo "Hermes Suite stopped."
