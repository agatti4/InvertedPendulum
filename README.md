# Inverted Pendulum (Zephyr RTOS)

[![CI Build](https://github.com/agatti4/InvertedPendulum/actions/workflows/ci_cd.yml/badge.svg)](https://github.com/agatti4/InvertedPendulum/actions/workflows/ci_cd.yml)
![Zephyr RTOS](https://img.shields.io/badge/RTOS-Zephyr-blue.svg)
![Target Board](https://img.shields.io/badge/Target-Nucleo--F767ZI-red.svg)

An inverted pendulum balancing and positioning controller ported to **[Zephyr RTOS](https://www.zephyrproject.org/)** running on the **STMicroelectronics NUCLEO-F767ZI** (ARM Cortex-M7 @ 216 MHz).

The firmware executes a deterministic **1 kHz control loop** implementing dual PID loops:
1. **Balance Control:** Fast inner loop reading pendulum angle and calculating motor acceleration to maintain vertical equilibrium.
2. **Center Control:** Outer position loop reading cart motor encoder and applying gentle centering bias to keep the cart centered on the rail.

---

## Hardware & Pinout

The peripheral mappings and pin assignments are configured in [`boards/nucleo_f767zi.overlay`](boards/nucleo_f767zi.overlay):

| Signal | Zephyr Devicetree Alias | Hardware Peripheral / Pin | Description |
|---|---|---|---|
| **Pendulum Encoder** | `qdec1` | `TIM1` (PE9 / PE11) | Pendulum quadrature encoder (CPR: 4000) |
| **Cart Motor Encoder** | `qdec0` | `TIM8` (PC6 / PC7) | Cart carriage position quadrature encoder |
| **Motor PWM** | `motor_pwm` | `TIM4` CH3 (PD14) | PWM drive signal (Period: ~22.5 kHz) |
| **Motor Direction** | `motor_dir` | `PB9` | Digital output for motor direction |
| **Motor Inhibit / Enable** | `motor_inhibit` | `PA5` | Digital output to enable/disable motor H-bridge |

---

## Requirements

### Host Machine
* **Docker** or **Podman** (used to containerize the complete Zephyr SDK and cross-compilation toolchain).
* **Python 3.10+** (used by the host flashing script to create a local virtual environment and invoke `west flash`).
* **ST-LINK / USB Debugger Support**: On-board ST-LINK/V2-1 connected via USB (supported via `pyocd`, `openocd`, or `stm32cubeprogrammer`).
* *(Optional)* **Clang-Format 18+** for running local code formatting checks.

---

## Quickstart Guide

### 1. Clone the Repository

```bash
git clone https://github.com/agatti4/InvertedPendulum.git
cd InvertedPendulum
```

### 2. Build the Docker Build Image

Before building the firmware for the first time, build the local Docker image containing the Zephyr SDK (`arm-zephyr-eabi`) and dependencies:

```bash
docker compose build
```

---

### 3. Build the Firmware

Use the wrapper script `BuildView.sh` (or `scripts/host/build.sh` directly) to invoke the build inside the container:

```bash
./BuildView.sh build nucleo
```

* The build script mounts your repository into `/workspace` inside the container.
* Build artifacts are output directly to the host in `build_nucleo_f767zi/` (including `zephyr.bin` and `zephyr.elf`).
* Extra flags can be passed through to `west build`, such as `-p always` for a pristine build:
  ```bash
  ./BuildView.sh build nucleo -p always
  ```

---

### 4. Flash to the Nucleo Board

Connect the NUCLEO-F767ZI development board to your computer via the USB ST-LINK port (`CN1`), then run:

```bash
./BuildView.sh flash nucleo
```

**How host flashing works:**
* The flashing script runs natively on the host machine where the USB ST-LINK hardware is connected.
* It automatically creates a lightweight Python virtual environment at `.venv/` (if not already present).
* It verifies and installs `west` and flashing runner prerequisites.
* It flashes the pre-built binary without rebuilding:
  ```bash
  west flash --no-rebuild -d build_nucleo_f767zi
  ```

---

## Command Reference (`BuildView.sh`)

[`BuildView.sh`](BuildView.sh) provides a unified CLI for all common host operations:

```bash
./BuildView.sh <command> [args]
```

| Command | Description | Example |
|---|---|---|
| `build [board] [args]` | Builds firmware inside the container | `./BuildView.sh build nucleo` |
| `flash [board]` | Flashes pre-compiled firmware from the host | `./BuildView.sh flash nucleo` |
| `runClangFormat check` | Verifies C/C++ style compliance against `.clang-format` | `./BuildView.sh runClangFormat check` |
| `runClangFormat fix` | Auto-formats C/C++ files in-place | `./BuildView.sh runClangFormat fix` |
| `help` | Displays command usage | `./BuildView.sh help` |

---

## Serial Console

* Baud rate: `115200`
* Interface: ST-LINK Virtual COM port (USART3 / USB serial)

---

## Code Formatting & CI

* **Formatting**: Verified with `clang-format` (Google style base with 4-space indentation, defined in [`.clang-format`](.clang-format)).
* **CI/CD**: GitHub Actions workflow ([`.github/workflows/ci_cd.yml`](.github/workflows/ci_cd.yml)) runs on Ubuntu 24.04:
  1. Compiles the firmware inside the Docker container to ensure build health.
  2. Runs `clang-format --dry-run --Werror` to enforce code style.
