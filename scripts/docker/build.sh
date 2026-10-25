#!/bin/bash
set -e

BOARD=${1:-esp32_devkitc/esp32/procpu}
shift || true

# Mapping for specific boards
if [ "$BOARD" = "frdm_mcxn947" ]; then
  BOARD="frdm_mcxn947/mcxn947/cpu0"
elif [ "$BOARD" = "esp32" ]; then
  BOARD="esp32_devkitc/esp32/procpu"
elif [ "$BOARD" = "nucleo" ]; then
  BOARD="nucleo_f767zi"
fi

# Use board-specific build directory to avoid conflicts
BUILD_DIR="build_${BOARD//\//_}"

echo "Listing west projects"
west list

echo "Building Zephyr app"
echo "Board: $BOARD"
echo "Build Directory: $BUILD_DIR"

west build -b "$BOARD" -d "$BUILD_DIR" . -- "$@"