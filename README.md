# Pox Kernel for Samsung Galaxy M20 (m20lte) 🇵🇸 #FreePalestine

[![GitHub Repo](https://img.shields.io/badge/GitHub-POX--project%2Fpox--m20lte--kernel-181717.svg?logo=github)](https://github.com/POX-project/pox-m20lte-kernel)
[![Kernel Version](https://img.shields.io/badge/Kernel-Linux%204.4.177-green.svg?logo=linux)](https://github.com/POX-project/pox-m20lte-kernel)
[![Pox Release](https://img.shields.io/badge/Pox%20Release-v2.1.0-blue.svg)](https://github.com/POX-project/pox-m20lte-kernel)
[![Device](https://img.shields.io/badge/Device-Samsung%20Galaxy%20M20%20(m20lte)-orange.svg?logo=samsung)](https://github.com/POX-project/pox-m20lte-kernel)
[![SoC](https://img.shields.io/badge/SoC-Samsung%20Exynos%207904%20(universal7885)-red.svg)](https://github.com/POX-project/pox-m20lte-kernel)
[![Solidarity](https://img.shields.io/badge/Stand%20With-Free%20Palestine%20🇵🇸-red?style=flat&colorA=000000&colorB=007A3D)](https://en.wikipedia.org/wiki/State_of_Palestine)
[![Maintainer](https://img.shields.io/badge/Maintainer-TXO%20R-purple.svg)](https://github.com/txorav)
[![License](https://img.shields.io/badge/License-GPLv2-yellow.svg)](COPYING)

**Pox Kernel** is an advanced, rock-solid custom Linux kernel engineered for the **Samsung Galaxy M20** (`m20lte` / `m20ltedd` / `m20`, Samsung Exynos 7904 / 7885 / `universal7885`).

> *"We aim for stability, not for anything else."* — **Stand for Justice. Free Palestine 🇵🇸**

---

> [!CAUTION]
> ### ⚠️ Critical Disclaimer & Legacy Version Advisory
> * **Older Versions (< 2.0.0 / v1.0.0-Beta & Prior) are OBSOLETE & UNSTABLE**: All releases prior to **2.0.0** (including v1.0.0-Beta and earlier prototypes) are strictly classified as **OLD, DEPRECATED, AND FOR HISTORICAL TESTING ONLY**. They suffer from touch driver slot reporting bugs that trigger phantom ghost touches, unhandled I2C bus lockup loops, and unthrottled sensor debug logging.
> * **NO LIABILITY / WARRANTY DISCLAIMER**: We are **NOT responsible** for anything that happens to you, your device, bricked motherboards, hardware brownouts, bootloops, data loss, or failed alarms. You flash completely at your own risk.
> * **FOLLOW MAINLINE**: For daily driving and rock-solid stability, always **follow mainline** and only install active supported releases from the current branch matrix (`onyx`). Never flash obsolete, unmaintained legacy builds.

---

## Table of Contents

- [Overview & Hardware Specifications](#overview--hardware-specifications)
- [Release Evolution: 1.0 Legacy to 2.0 Mainline](#release-evolution-10-legacy-to-20-mainline)
  - [Version 1.0 (Beta / Prototype - Deprecated)](#1-version-10-beta--prototype---deprecated)
  - [Version 2.0.0 (Mainline / Active Supported)](#2-version-200-mainline--active-supported)
- [Editions & The Variant Matrix](#editions--the-variant-matrix)
- [Comprehensive Kernel Addons & Features](#comprehensive-kernel-addons--features)
  - [1. Touchscreen Anti-Ghosting & Noise Filtration Engine](#1-touchscreen-anti-ghosting--noise-filtration-engine)
  - [2. I2C Bus Recovery & Peripheral Hang Protection](#2-i2c-bus-recovery--peripheral-hang-protection)
  - [3. Sensor & Fingerprint Debug Quieting](#3-sensor--fingerprint-debug-quieting)
  - [4. Fast Charging & Power Subsystem](#4-fast-charging--power-subsystem)
  - [5. Zero Frame-Drop Gaming & Sched BORE Engine](#5-zero-frame-drop-gaming--sched-bore-engine)
  - [6. Kprofiles Tri-State Governor](#6-kprofiles-tri-state-governor)
  - [7. Display True Tone & Reference Color Engine](#7-display-true-tone--reference-color-engine)
  - [8. Multi-Flavored Root Ecosystem](#8-multi-flavored-root-ecosystem)
  - [9. Audio & Low-Level Kernel Tweaks](#9-audio--low-level-kernel-tweaks)
- [Target & Variant Matrix (`onyx` Single Source)](#target--variant-matrix-onyx-single-source)
- [Installation Guide](#installation-guide)
- [On-Device Verification](#on-device-verification)
- [Building from Source](#building-from-source)
- [Repository Governance & Agent Hard Rules](#repository-governance--agent-hard-rules)
- [Project Roadmap & TODO](#project-roadmap--todo)
- [Credits & Acknowledgments](#credits--acknowledgments)
- [Solidarity & Free Palestine](#solidarity--free-palestine)
- [License](#license)

---

## Overview & Hardware Specifications

| Component | Target Specification |
|:---|:---|
| **Device Model** | Samsung Galaxy M20 (`m20lte` / `m20ltedd` / `m20`) |
| **SoC** | Samsung Exynos 7904 Octa (universal7885 platform, 14nm FinFET) |
| **CPU Complex** | Octa-Core: 2x Arm Cortex-A73 @ 1.77 GHz + 6x Arm Cortex-A53 @ 1.59 GHz |
| **GPU Complex** | Arm Mali-G71 MP2 (Bifrost Architecture) |
| **Base Kernel** | Linux 4.4.177 LTS (arm64 / AArch64) |
| **Partition Scheme** | Samsung A-only (`/dev/block/by-name/boot` / `BOOT`) |
| **Toolchain** | Google AOSP GCC 4.9 (`aarch64-linux-android-4.9`) & Modern Clang |
| **Packaging** | AnyKernel3 Dynamic Ramdisk Injection (osm0sis template) |
| **Supported OS** | Android 9 (Pie / OneUI), Android 10 (Q), Android 11 (R), Android 12/12L (S), Android 13 (T), Android 14 (U), GSIs & AOSP |

---

## Release Evolution: 1.0 Legacy to 2.0 Mainline

### 1. Version 1.0 (Beta / Prototype - Deprecated)
> **STATUS: OBSOLETE & UNSTABLE.** Do not use for daily driving. Follow mainline.

The 1.0 series was the initial prototype release:
* Initial port of Pox interfaces (`/proc/perfmgr/gaming_mode`, `/proc/perfmgr/pox_config`).
* Prototype integration of APatch and KernelSU-Next.
* *Known 1.0 Limitations*:
  * Touchscreen slot reporting flaw where unassigned slots fired continuous active touch events, leading to erratic phantom/ghost touches.
  * Long 500ms `msleep` recovery loops on Exynos USI I2C bus hangs, freezing user input.
  * Egis ET5xx fingerprint SPI driver firing unthrottled periodic wakeups every 11 seconds.
  * Lacked Samsung BOOT symlink detection in uppercase recovery paths.

---

### 2. Version 2.0.0 (Mainline / Active Supported)
> **STATUS: CURRENT RECOMMENDED MAINLINE RELEASE.**

The 2.0.0 release upgrades Pox Kernel for the Galaxy M20 into a production-grade downstream distribution:
* **Himax 83xxx Touchscreen Anti-Ghosting Engine**: Overhauled multi-touch slot verification. Fixed finger reporting logic to strictly validate `finger_id[i] != 0 && w[i] > 0 && !(x == 0 && y == 0)` before asserting `MT_TOOL_FINGER`, preventing empty slots from spamming ghost inputs.
* **Hardware Noise Filtration**: Integrated Himax hardware `EN_NoiseFilter` and `pox_touch_sensitivity_get()` to actively filter low-weight EMI spikes (`w < 6`). Silenced the periodic 30-second `work_print_info` reschedule waking the CPU.
* **Exynos I2C Bus Hang Immunization**: Switched USI pins to GPIO inputs before reading state in `recover_gpio_pins`, slashed timeout from 500ms down to 10ms (`udelay(100)`), and injected standard 16-cycle clock recovery pulses.
* **Sensor & Fingerprint Quieting**: Guarded Egis ET5xx SPI debug timers behind `CONFIG_POX_DEBUG_FPSENSOR`, eliminating 11-second periodic work queues.
* **Unified Single-Source Architecture**: Build-time modular patch sets (`patches/apatch.patch`, `patches/ksu.patch`) applied directly onto a clean `onyx` tree.
* **Automated CI Matrix on Colab Pool**: Sharded runner builds with dedicated ccache acceleration reducing compile times from 17 minutes to under 60 seconds.

---

### 3. Version 2.1.0 (Zero-Lag Engine, Max Charging Speed & Modern RAM Management)
> **STATUS: LATEST ACTIVE MAINLINE RELEASE.**

The 2.1.0 release targets absolute performance and lag eradication under Android 15 on 3GB RAM:
* **Max Charging Speed At All Times**:
  * **Screen-On Throttling Bypass**: Eliminated Samsung's 900mA / 500mA charging drop when the screen is turned on.
  * **Thermal SIOP Bypass**: Prevented the kernel from forcing 9V AFC charging down to 5V standard USB upon reaching mild usage temperatures.
  * **Universal Fast Charging**: Unlocked full 15W–18W rate across QuickCharge, USB-PD, and standard USB charger detection modes on GSIs (up to 2000mA input / 2400mA battery current).
* **Zero-Lag Interactive Governor & Big Cluster Uncapped**:
  * Uncapped Exynos 7904 Cortex-A73 Big cluster ceiling to full **2.18 GHz** (2184000 kHz) during gaming and performance profiles.
  * Slashed `go_hispeed_load` from 85% to **65%** and `target_loads` from 85% to **70%** for instant CPU ramp-up on touches and frame rendering.
  * Enabled `io_is_busy = true` by default so I/O wait times automatically boost CPU frequency during app launches and database reads.
* **Modern RAM Management for 3GB Exynos 7904**:
  * Enabled maximum swappiness (**180**) via `CONFIG_INCREASE_MAXIMUM_SWAPPINESS=y` so cold anonymous memory is aggressively compressed into ZRAM, preserving vital file-backed caches and preventing Direct Reclaim stalls.
  * Lowered `vfs_cache_pressure` to **50** to keep filesystem metadata and SQLite caches in memory.
  * Configured `page_cluster = 0` and optimized dirty writeback ratios (`vm_dirty_ratio = 10`, `dirty_background_ratio = 5`).
* **CI Runner Overhaul**:
  * Upgraded GitHub Actions workflow to standard `ubuntu-22.04` cloud runners, ensuring instant builds and release artifact generation without waiting for offline self-hosted runners.

---

## Comprehensive Kernel Addons & Features

### 1. Touchscreen Anti-Ghosting & Noise Filtration Engine
* **Strict Slot Validation**: Overhauled `himax_finger_report` in `drivers/input/touchscreen/himax_83xxx/himax_common.c`. Inactive slots now properly send `MT_TOOL_FINGER, 0` instead of falsely reporting contact due to loose coordinate bounds checks.
* **EMI & Charger Noise Rejection**: Low-amplitude charger noise and edge-palm touches (`w < 6`) are automatically rejected when connected to noisy chargers or during intense usage.
* **Touch Game Mode & Sensitivity Tuning**: Configurable sensitivity multipliers via `/proc/perfmgr/touch_sensitivity` and ultra-low input latency mode via `/proc/perfmgr/touch_game_mode`.
* **Gesture Control**: Native Double Tap to Wake (DT2W) engine exposed at `/proc/perfmgr/dt2w`.

### 2. I2C Bus Recovery & Peripheral Hang Protection
* **Fast Clock Pulses**: When a peripheral pulls SDA low, the kernel injects 16 rapid SCL recovery pulses instead of blocking the main thread.
* **GPIO Direction Switching**: Automatically flips USI pins to inputs before sampling bus state, preventing false low readings that previously locked up the bus.
* **10ms Safe Clamping**: Slashes the recovery delay from 500ms down to 10ms, eliminating perceptible micro-stutter during hardware bus timeouts.

### 3. Sensor & Fingerprint Debug Quieting
* **ET5xx SPI Sleep Watchdog**: Guarded `etspi_enable_debug_timer()` behind `CONFIG_POX_DEBUG_FPSENSOR`. Prevents the Egis fingerprint driver from spamming `ldo: 0...` every 11 seconds and waking CPUs from deep C-states.
* **Clean Kernel Log (dmesg)**: Silenced unnecessary vendor touch and sensor chatter for minimal logging overhead.

### 4. Fast Charging & Power Subsystem
* **15W Adaptive Fast Charging (AFC) Support**: Kernel-level fast charging toggle exposed at `/proc/perfmgr/fast_charge`.
* **Battery Bypass Mode**: Direct power delivery bypassing the battery cell during gaming or thermal stress (`/proc/perfmgr/battery_bypass`).
* **Configurable Battery Limiter**: Protects battery cycle health by stopping charging at user-defined thresholds (e.g., 80%) via `/proc/perfmgr/battery_limit`.
* **Safe Host Power Protection**: Clamps power draw on standard PC USB data ports to prevent host motherboard port overcurrent tripping.

### 5. Zero Frame-Drop Gaming & Sched BORE Engine
* **Sched BORE (Burst-Oriented Response Enhancer)**: Enhances responsiveness for interactive user interface tasks while preserving raw throughput for heavy workloads.
* **Unified Gaming Mode Controller**: Sysfs interface at `/proc/perfmgr/gaming_mode`:
  * `-1`: Ultra Powersave (maximum battery life).
  * `0`: Balanced daily governor.
  * `1`: Gaming mode with aggressive CPU frequency holding.
  * `2`: Extreme mode with locked Mali-G71 GPU boost and high DRAM bandwidth.

### 6. Kprofiles Tri-State Governor
* **Universal Governor Integration**: Fully compatible with the Kprofiles Android userspace manager via `/proc/perfmgr/profile` and `/sys/kernel/kprofiles`:
  * `0`: Disabled / Manual control.
  * `1`: Battery.
  * `2`: Balanced.
  * `3`: Performance.
  * `4`: Custom tunables via `/proc/perfmgr/kprofiles_custom`.

### 7. Display True Tone & Reference Color Engine
* **True Tone Mode**: Dynamic ambient white point calibration (`/proc/perfmgr/true_tone`).
* **Reference Calibration Profiles**: Exposed at `/proc/perfmgr/color_mode`:
  * `0`: Standard Samsung default.
  * `1`: iOS D65 Calibrated Reference mode.
  * `2`: S-Log3 cinema grading profile.
  * `3`: Custom RGB, saturation, contrast, and brightness multipliers via `/proc/perfmgr/color_custom`.
* **High Brightness Mode (HBM)**: Direct display driver boost for direct sunlight visibility (`/proc/perfmgr/hbm_mode`).

### 8. Multi-Flavored Root Ecosystem
* **Vanilla (Clean)**: 100% stock security model with zero hooking modifications for strict banking/Play Integrity compliance.
* **APatch / FolkPatch**: Full `CONFIG_KALLSYMS_ALL=y` symbol exposure with pre-patched AnyKernel3 ramdisk modifications and automatic FolkPatch APK bundling.
* **KernelSU-Next**: Integrated KernelSU-Next legacy driver with Exynos manual syscall hooks, `ALIGN_DOWN` and `in_compat_syscall` helpers, and forward-compatible flex-array sepolicy patches.

### 9. Audio & Low-Level Kernel Tweaks
* **Sound Control Subsystem**: Digital amplification controls for headphone output and microphone sensitivity (`/proc/perfmgr/headphone_gain`, `/proc/perfmgr/mic_gain`).
* **Dynamic Fsync**: Synchronous disk flushes suspended while the screen is on for stutter-free storage I/O (`/proc/perfmgr/dynamic_fsync`).
* **Wakelock Blocker**: Blocks misbehaving userspace wakelocks from preventing phone deep sleep (`/proc/perfmgr/wakelock_blocker`).
* **USB CD-ROM Emulation**: Enables DriveDroid / image emulation directly over USB (`/proc/perfmgr/usb_cdrom`).

---

## Target & Variant Matrix (`onyx` Single Source)

`onyx` is the single source branch. Root flavors are modular patch sets under `patches/` applied dynamically at build time:

| Target (`VARIANT`) | Edition | Root Subsystem | Defconfig | Description |
|:---|:---|:---:|:---:|:---|
| **`vanilla`** | Onyx (Vanilla) | Clean (Unrooted) | `exynos7885-m20_gsi_defconfig` | Base Onyx Gaming + clean stock security model, strict Play Integrity ready |
| **`apatch`** | Onyx-APatch | APatch / KernelPatch | `exynos7885-m20_apatch_defconfig` | KernelPatch symbol exposure + pre-patched boot image + bundled FolkPatch APK |
| **`ksu-next`** | Onyx-KSUN | KernelSU-Next | `exynos7885-m20_ksu_next_defconfig` | KernelSU-Next legacy engine + Exynos manual syscall hooks + flex-array patch |

---

## Installation Guide

### Prerequisites
1. Samsung Galaxy M20 (`m20lte`) with an **unlocked bootloader**.
2. Custom Recovery installed (TWRP or OrangeFox).
3. The AnyKernel3 flashable `.zip` corresponding to your preferred variant.

### Flashing via Recovery Sideload (Recommended)
```bash
# 1. Boot device into TWRP Recovery
adb reboot recovery

# 2. Enter Sideload mode on the device
adb shell twrp sideload

# 3. Stream and install the kernel zip
adb sideload Pox-Kernel-2.0-Onyx-m20lte.zip

# 4. Reboot system
adb reboot
```

---

## On-Device Verification

Once booted, open a terminal or run ADB shell:

```bash
# 1. Verify kernel release string
uname -a
# Expected: Linux localhost 4.4.177-Pox-2.0...

# 2. Check Pox gaming mode status
cat /proc/perfmgr/gaming_mode

# 3. Check battery protection & bypass status
cat /proc/perfmgr/battery_bypass
cat /proc/perfmgr/battery_status

# 4. Verify touch sensitivity and ghost touch filtration
cat /proc/perfmgr/touch_sensitivity
```

---

## Building from Source

Pox Kernel includes a self-contained build script and variant manager:

```bash
# Clone the repository from official POX-project
git clone https://github.com/POX-project/pox-m20lte-kernel.git
cd pox-m20lte-kernel

# Onyx is the single branch containing everything
git checkout onyx

# Build any target using the variant system:
./build.sh vanilla      # Clean Vanilla Onyx
./build.sh apatch       # APatch / FolkPatch Edition
./build.sh ksu-next     # KernelSU-Next Edition

# Restore tree to clean onyx base
./build.sh clean
```

---

## Repository Governance & Agent Hard Rules

To maintain absolute code quality and prevent regressions, all AI agents and contributors must strictly obey the governance guidelines defined in [`AGENTS.md`](AGENTS.md):

1. **Semantic Versioning Compliance**: Strictly adhere to `MAJOR.MINOR.PATCH` across releases and builds.
2. **Zero-Mutation Rule**: NEVER edit or stage files while a build, test, or flashing command is actively running.
3. **Anti-Spaghetti Code**: Clean, minimal diffs; standard Linux kernel coding conventions (8-space tabs); verify hardware limits before modifying drivers.
4. **Anti-Spaghetti Commits**: Strict Conventional Commits (`<type>(<scope>): <summary>`), atomic bisectable changes, with comprehensive technical explanation in the commit body.
5. **Modular Variant Baseline**: Maintain the single-branch `onyx` model; root modifications must live in clean-applying patches under `patches/`.

---

## Project Roadmap & TODO

- [x] **v1.0 Beta Release**: Initial prototype rollout and hardware bringing-up.
- [x] **v2.0.0 Architecture**: Unified single-source `onyx` branch with modular build-time variant patching.
- [x] **Touchscreen Ghost Touch Fix**: Himax 83xxx multi-touch slot reporting overhaul eliminating phantom touches.
- [x] **Himax EMI Noise Filtration**: Hardware noise filter and sensitivity thresholds rejecting low-weight noise (`w < 6`).
- [x] **Exynos I2C Bus Hang Immunization**: Fast 10ms clock recovery pulses preventing peripheral deadlocks.
- [x] **Fingerprint Debug Quieting**: Silencing ET5xx periodic 11-second debug wakeup loop.
- [x] **15W AFC & Battery Bypass Engine**: Battery protection, charge limits, and Samsung AFC fast charge integration.
- [x] **Kprofiles & Sched BORE Engine**: Tri-state governor and interactive latency optimization.
- [x] **AnyKernel3 Dynamic Packaging**: Automatic Samsung uppercase `BOOT` symlink handling and FolkPatch bundling.
- [x] **Colab 3-Runner Sharded CI**: High-speed parallel matrix builds with persistent ccache integration.
- [ ] **Android 15 (Vanilla Ice Cream) Testing**: Further validate GSI compatibility on newest vendor trees.

---

## Credits & Acknowledgments

* **Lead Developer & Maintainer**: **TXO R (Pox Project)** ([@txorav](https://github.com/txorav))
* **Linux Kernel Community**: Linus Torvalds and downstream LTS maintainers.
* **Samsung Electronics**: Exynos 7885 / 7904 board support and hardware drivers.
* **osm0sis @ XDA**: AnyKernel3 template and flash tools.
* **KernelSU-Next & APatch Developers**: Next-generation Android root hooking solutions.
* **M20 Community**: Testers, developers, and users keeping the Samsung Galaxy M20 thriving.

---

## Solidarity & Free Palestine 🇵🇸

We believe that open-source software and technology should stand for human dignity, justice, and the freedom of all oppressed peoples. 

```
   ████████████████████████████████████████████
   ████████████████████████████████████████████  (Black)
   ████████████████████████████████████████████
   ████████████████████████████████████████████
   ████████████████████████████████████████████  (White)
   ████████████████████████████████████████████
   ████████████████████████████████████████████
   ████████████████████████████████████████████  (Green)
   ████████████████████████████████████████████
          ▲ (Red Triangle on Hoist)
```

> **"Injustice anywhere is a threat to justice everywhere."**  
> We stand in solidarity with the Palestinian people in their struggle for self-determination, freedom, and human rights.  
> **Free Palestine. End the occupation. Peace, justice, and liberty for all.** 🇵🇸

---

## License

Pox Kernel is free software distributed under the terms of the **GNU General Public License version 2 (GPL-2.0)** as published by the Free Software Foundation. See [`COPYING`](COPYING) for complete details.
