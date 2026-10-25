FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# System dependencies
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake ninja-build gperf ccache \
    dfu-util device-tree-compiler \
    wget curl xz-utils file make \
    gcc g++ \
    python3 python3-venv python3-pip python3.12-dev\
    libsdl2-dev libusb-1.0-0 libusb-1.0-0-dev \
    libssl-dev libffi-dev ca-certificates \
    vim nano \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# uv + Python env
# ------------------------------------------------------------
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

ENV VIRTUAL_ENV=/opt/venv
RUN uv venv ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

RUN uv pip install west esptool

# ------------------------------------------------------------
# Zephyr SDK (cached in image)
# ------------------------------------------------------------
ENV ZEPHYR_SDK_VERSION=1.0.1
ENV ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk

WORKDIR /opt

RUN wget -q https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-x86_64_minimal.tar.xz && \
    tar xf zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-x86_64_minimal.tar.xz && \
    rm zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-x86_64_minimal.tar.xz

RUN /opt/zephyr-sdk-${ZEPHYR_SDK_VERSION}/setup.sh -t xtensa-espressif_esp32_zephyr-elf -h
RUN /opt/zephyr-sdk-${ZEPHYR_SDK_VERSION}/setup.sh -t arm-zephyr-eabi -h

ENV ZEPHYR_TOOLCHAIN_VARIANT=zephyr
ENV ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk-${ZEPHYR_SDK_VERSION}

# ------------------------------------------------------------
# Workspace
# ------------------------------------------------------------
WORKDIR /workspace

ENTRYPOINT ["./scripts/docker/entrypoint.sh"]