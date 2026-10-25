#!/bin/bash
set -euo pipefail

IMAGE=${IMAGE:-invertedpendulum-zephyr}
# Default board if not provided
DEFAULT_BOARD="esp32_devkitc/esp32/procpu"

# If first arg is provided, use it as BOARD, otherwise use environment or default
if [ $# -gt 0 ]; then
  BOARD="$1"
  shift
else
  BOARD="${BOARD:-$DEFAULT_BOARD}"
fi

# Mapping for specific boards
if [ "$BOARD" = "frdm_mcxn947" ]; then
  BOARD="frdm_mcxn947/mcxn947/cpu0"
elif [ "$BOARD" = "esp32" ]; then
  BOARD="esp32_devkitc/esp32/procpu"
elif [ "$BOARD" = "nucleo" ]; then
  BOARD="nucleo_f767zi"
fi

PROJECT_ROOT="$(cd "$(dirname "$0")"/../../ && pwd)"

# Detect container engine if not already set
if [ -z "${DOCKER_EXE:-}" ]; then
  if command -v podman >/dev/null 2>&1; then
    DOCKER_EXE="podman"
  elif command -v docker >/dev/null 2>&1; then
    DOCKER_EXE="docker"
  else
    echo "❌ Error: Neither podman nor docker found."
    exit 1
  fi
fi

# Use -it only if in a TTY
INTERACTIVE_FLAG=""
if [ -t 0 ]; then
  INTERACTIVE_FLAG="-it"
fi

echo "🚀 Running Zephyr build using $DOCKER_EXE"
echo "Image: $IMAGE"
echo "Board: $BOARD"
echo "Project root: $PROJECT_ROOT"

$DOCKER_EXE run --rm $INTERACTIVE_FLAG \
  -v "$PROJECT_ROOT:/workspace" \
  -w /workspace \
  -e BOARD="$BOARD" \
  "$IMAGE" \
  build "$BOARD" "$@"