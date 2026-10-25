#!/bin/bash
set -e

cd /workspace

echo "🚀 Zephyr dev container starting..."

# ------------------------------------------------------------
# 1. Initialize west ONLY if needed
# ------------------------------------------------------------
if [ ! -d .west ]; then
  echo "📦 Initializing west workspace..."
  west init . --mf west.yml
fi

# ------------------------------------------------------------
# 2. Update modules (safe every time, but fast after first run)
# ------------------------------------------------------------
echo "🔄 Updating west modules..."
west update --narrow zephyr cmsis_6 hal_st hal_stm32

# ------------------------------------------------------------
# 3. Install Zephyr Python deps (cached)
# ------------------------------------------------------------
if [ ! -f .zephyr_deps_installed ]; then
  echo "🐍 Installing Zephyr Python requirements..."
  uv pip install -r zephyr/scripts/requirements.txt
  touch .zephyr_deps_installed
fi

uv pip install pyelftools
uv pip install jsonschema

# ------------------------------------------------------------
# 4. Optional: Hardware blobs (run once)
# ------------------------------------------------------------
if [ ! -f .st_blobs ]; then
  echo "📡 Fetching ST blobs..."
  west blobs fetch hal_st || true
  touch .st_blobs
fi

# ------------------------------------------------------------
# 5. Toolchain check (ensure required toolchains are installed)
# ------------------------------------------------------------
if [ ! -d "${ZEPHYR_SDK_INSTALL_DIR}/arm-zephyr-eabi" ]; then
  echo "🛠️ Installing ARM toolchain..."
  "${ZEPHYR_SDK_INSTALL_DIR}/setup.sh" -t arm-zephyr-eabi -h
fi

echo "✅ Ready."

if [ "$1" = "build" ]; then
  echo "🛠️ Starting build..."
  shift
  ./scripts/docker/build.sh "$@"
  exit 0
fi

exec "$@"