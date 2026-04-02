# [BadazZ89] >k6a Optimiz3r

KernelSU/Magisk module for **Redmi Note 12 Pro 4G (sweet2)**
SoC: Snapdragon 730 (SM7150) · Kernel: 4.14 CAF

#[![Build](https://github.com/YOUR_USERNAME/k6a-optimizer/actions/workflows/build.yml/badge.svg)](https://github.com/YOUR_USERNAME/k6a-optimizer/actions/workflows/build.yml)

---

## Download

Go to **[Actions](../../actions/workflows/build.yml)** → latest run → **Artifacts** → download `BadazZ89-k6a-Optimizer-v3.10.zip`

Flash via KernelSU or Magisk, reboot.

---

## Features

| Feature | Detail |
|---|---|
| **Selective thermal disable** | CPU/GPU zones disabled, conn_therm/touch/battery kept active |
| **Battery spoofing** | Reports low battery temp to prevent conn_therm HW interrupt |
| **Bypass power supply** | Lowers bypass threshold during gaming to reduce charging heat |
| **Binder-free auto detection** | Reads `/proc/cgroup` instead of `dumpsys activity` — no input freeze |
| **Schedutil tuning** | Correct 4.14 CAF policy paths (policy0/policy6) |
| **ZRAM lz4** | zstd not available on 4.14 CAF — uses lz4 directly |
| **LMKD tuning** | Per-profile minfree thresholds for 8GB RAM |
| **k6a-daemon** | Rust WebSocket daemon — real-time WebUI updates (<100ms) |
| **WebUI fallback** | Falls back to data.txt polling if daemon not running |

---

## Building locally

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Android NDK via Android Studio or:
# https://developer.android.com/ndk/downloads

# Build
cd k6a-daemon
export ANDROID_NDK=~/Android/Sdk/ndk/25.2.9519653
../build.sh
```

---

## Repo structure

```
.github/workflows/build.yml   — GitHub Actions CI
k6a-daemon/
  src/main.rs                 — Rust WebSocket daemon source
  Cargo.toml                  — dependencies
module/
  service.sh                  — main shell service
  system.prop                 — boot-time props
  module.prop                 — module metadata
  index.html                  — WebUI
```

---

## WebUI

Open via KernelSU WebUI button or navigate to `http://127.0.0.1:7071` in any browser on the device.

When `k6a-daemon` is running, the WebUI connects via WebSocket (`ws://127.0.0.1:7070`) for real-time updates. Falls back to polling `data.txt` every 5s if the daemon is not running.
