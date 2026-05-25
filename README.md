# [BadazZ89] k6a Optimizer v1.0

KernelSU Next module for **Redmi Note 12 Pro 4G (sweet2 / sweet_k6a)**
SoC: Snapdragon 730 (SM7150) · Kernel: VantomKernel 4.14.356-openela-rc1 (EAS/uclamp)

---

## Download

Go to **[Actions](../../actions/workflows/build.yml)** → latest run → **Artifacts** → download `BadazZ89-k6a-Optimizer-v1.0.zip`

Flash via KernelSU Next or Magisk, reboot.

---

## Features

| Feature | Detail |
|---|---|
| **k6a-controller** | Shell-based state machine — single-writer pattern, no race conditions |
| **k6a-lib.sh** | Modular shell library — sched, GPU, IO, VM, ZRAM, LMH, thermal, IRQ, LRU, net QoS, wakelock, freeze |
| **Selective thermal disable** | CPU/GPU zones disabled, conn_therm/touch/battery kept active |
| **Battery spoofing** | Reports low battery temp to prevent conn_therm HW interrupt |
| **Competitive (COOK1NG)** | Full thermal disable + GPU lock 800MHz + EAS=0 — max FPS for CODM |
| **Schedutil tuning** | 500µs up / 20000µs down in gaming, sched_boost=1, correct policy0/policy6 paths |
| **UFS IO scheduler** | mq-deadline for blk-mq (noop/cfq unavailable on UFS) |
| **ZRAM lz4** | Force lz4 compression, page-cluster=0 during gaming |
| **VM gaming profile** | swappiness=10, dirty_ratio=10, page-cluster=0, extra_free_kbytes=24576 |
| **Network QoS** | TC HTB — prioritizes CoD UDP ports (ingress/egress) |
| **IRQ affinity** | Pin network/interrupts to Gold cores (CPU4-7) during gaming |
| **LRU_GEN** | Enable kernel MGLRU at boot |
| **Thermal crash watchdog** | service.sh auto-restores thermal trips + daemons if controller dies |
| **Multi-instance lock** | Prevents duplicate service.sh on kernelSU Next boot |
| **k6a-daemon** | Rust WebSocket daemon — real-time WebUI updates (<100ms) |
| **WebUI fallback** | Falls back to data.txt polling (with ping via separate .ping file) |

---

## Profiles

| Profile | CPU Silver | CPU Gold | GPU | Thermal | Use case |
|---|---|---|---|---|---|
| **Battery** | 300-1401MHz | 300-1420MHz | 220-430MHz | enabled | Daily, music, idle |
| **Balanced** | 300-1555MHz | 825-1843MHz | 430-600MHz | enabled | Daily + light gaming |
| **Gaming** | 1248-1804MHz | 1843-2304MHz | 650-800MHz | disabled (surgical) | CODM default |
| **Competitive** | 1497-1804MHz | 2169-2304MHz | 800MHz lock | full disable | CODM max FPS |

---

## Building locally

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Android NDK via Android Studio or:
# https://developer.android.com/ndk/downloads

# Build daemon
cd k6a-daemon
export ANDROID_NDK=~/Android/Sdk/ndk/25.2.9519653
cargo build --release --target aarch64-linux-android
```

---

## Repo structure

```
.github/workflows/build.yml         — GitHub Actions CI
k6a-daemon/
  src/main.rs                       — Rust WebSocket daemon source
  Cargo.toml                        — dependencies
bin/
  k6a-controller                    — main state machine binary (shell)
  k6a-daemon                        — pre-built Rust binary
  k6a-lib.sh                        — shell library
  k6a-diagnose.sh                   — diagnostic script
config/
  settings.conf                     — user settings
  freeze.conf                       — app-freeze whitelist
  manual_profile                    — current profile
service.sh                          — boot wrapper with watchdog
customize.sh                        — installer
system.prop                         — boot-time props
module.prop                         — module metadata
webroot/
  index.html                        — WebUI
  ascii.txt                         — ASCII art logo
```

---

## WebUI

Open via KernelSU WebUI button or navigate to `http://127.0.0.1:7071` in any browser on the device.
