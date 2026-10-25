#!/bin/bash
set -euo pipefail

# ---------------------------
# Config
# ---------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")"/../../ && pwd)"
ZEPHYR_BASE="${ZEPHYR_BASE:-$PROJECT_ROOT/zephyr}"
VENV_DIR="${VENV_DIR:-$PROJECT_ROOT/.venv}"

DEFAULT_BOARD="esp32_devkitc/esp32/procpu"

if [ $# -gt 0 ]; then
  BOARD="$1"
  shift
else
  BOARD="${BOARD:-$DEFAULT_BOARD}"
fi

if [ "$BOARD" = "frdm_mcxn947" ]; then
  BOARD="frdm_mcxn947/mcxn947/cpu0"
elif [ "$BOARD" = "esp32" ]; then
  BOARD="esp32_devkitc/esp32/procpu"
elif [ "$BOARD" = "nucleo" ]; then
  BOARD="nucleo_f767zi"
fi

BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build_${BOARD//\//_}}"

echo "⚡ Zephyr Flash Script"
echo "Board:       $BOARD"
echo "Build dir:   $BUILD_DIR"

# ---------------------------
# venv
# ---------------------------
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

pip install --upgrade pip setuptools wheel >/dev/null

# ---------------------------
# Python deps
# ---------------------------
REQ_FILE="$ZEPHYR_BASE/scripts/requirements.txt"

if [ -f "$REQ_FILE" ]; then
    pip install -r "$REQ_FILE"
    # pip install esptool
else
    echo "⚠️ Missing Zephyr requirements"
fi

if ! command -v west >/dev/null 2>&1; then
    pip install west
fi

# ---------------------------
# LinkServer check/install
# ---------------------------
# echo "🔎 Checking LinkServer..."

# if ! command -v LinkServer >/dev/null 2>&1; then
#     echo "❌ LinkServer not found in PATH"

#     LINKSERVER_DIR="$PROJECT_ROOT/tools/LinkServer"

#     if [ ! -d "$LINKSERVER_DIR" ]; then
#         echo "⬇️  Download LinkServer from NXP and extract it to:"
#         echo "    $LINKSERVER_DIR"
#         echo ""
#         echo "👉 https://www.nxp.com/design/design-center/software/development-software/mcuxpresso-software-and-tools-/linkserver-for-microcontrollers:LINKERSERVER"
#         exit 1
#     fi

#     export PATH="$LINKSERVER_DIR:$PATH"
# fi

# echo "✅ LinkServer found: $(command -v LinkServer)"

# ---------------------------
# Flash
# ---------------------------
echo "🚀 Flashing firmware (no rebuild)..."

west flash \
  --no-rebuild \
  -d "$BUILD_DIR"