# [BadazZ89] k6a Optimizer v9.9

KernelSU Next module for **Redmi Note 12 Pro 4G (sweet2 / sweet_k6a)**
SoC: Snapdragon 730 (SM7150) · Kernel: VantomKernel 4.14.356-openela-rc1 (https://github.com/Lafactorial/kernel_xiaomi_sm6150/tree/23.2) (EAS/uclamp/SCHED_CASS)

---

## Download

Flash via KernelSU Next — module is available in the repository browser.  
Or grab the latest `.zip` from **[Releases](../../releases/latest)**.

---

## Features

| Feature | Detail |
|---------|--------|
| **2-Mode Architecture** | Daily (Power-Save, kühl) + Cooking (max FPS für CODM) |
| **Daily Sparmodus** | Silver 576-1248 MHz · Gold 6-7 offline · GPU 140-267 MHz Lock · Trips 55°C · mi_thermald deaktiviert |
| **Cooking (COOK1NG)** | Full thermal disable + LMH off + GPU lock 800MHz (pwrscale=0) + EAS=0 + IRQ pinning — max FPS für CODM |
| **SCHED_FIFO** | RenderThread/UnityMain/GLThread/AudioTrack → Echtzeit-Prio in Cooking |
| **GPU pwrscale=0** | Nutzt neuen Adreno 0819.0-Treiber-Node für Performance-Modus |
| **Gold-Freeze Watchdog** | Erkennt + recovered Gold min=max in Cooking |
| **CPU-Freeze-Watchdog** | VantomKernel clamt scaling_max_freq zurück → auto-raise + retry-loop + lmh_disable cleanup |
| **UFS Swapfile 2G** | Cooking: UFS-Swapfile statt ZRAM (kein CPU-Overhead). Daily: ZRAM |
| **Adreno Driver Erkennung** | Erkennt installierten Adreno GPU Driver v2.1 (V@0819.0) → nutzt neue sysfs-Nodes |
| **GPU Max-Freq dynamisch** | Liest `gpu_available_frequencies` aus — kein hardcoded Limit |
| **Schedutil tuning** | Custom `hispeed_load/freq/pl` exklusiv für VantomKernel |
| **WebUI** | Echtzeit via Rust-WebSocket (<100ms) — Sparkline, Accordions, Live-Cards |
| **k6a-diagnose.sh** | Vollständiger System-Dump: CPU/GPU/Thermal/Scheduler/ZRAM/IRQ/WakeLocks |
| **Battery spoofing** | 25°C in Cooking → verhindert conn_therm HW-Interrupt |
| **Network QoS** | TC HTB — priorisiert CoD UDP-Ports (ingress/egress) |
| **IRQ affinity** | Pin network/interrupts to Gold cores during gaming |
| **LRU_GEN** | Enable kernel MGLRU at boot |
| **Wakelock Blocker** | Boeffla-basiert: PowerManagerService/NfcService/GMS/SyncLoop blockiert |

---

## Profiles

| Profile | CPU Silver | CPU Gold | GPU | EAS | Thermal | Use case |
|---------|-----------|---------|-----|-----|---------|----------|
| **Daily** | 576-1248 MHz | Offline (6-7) | 140-267 MHz Lock | on | 55°C Trips, mi_thermald off | Everyday use — kühl + sparsam |
| **Cooking** | 1497-1804 MHz (+Hotplug) | 2169-2304 MHz | 800 MHz Lock, pwrscale=0 | off | disabled (full) | CODM max FPS |

---

## Changelog

| Version | Highlights |
|---------|-----------|
| **v9.9** | pwrscale=0 GPU-Boost · Gold-Freeze Erkennung · Daily Rauschen reduziert |
| **v9.8** | Gold-Freeze Fix · Daily-Loop optimiert |
| **v9.7** | KGSL Diagnose-Crash gefixt (rekursive Dump-Funktion entfernt) |
| **v9.6** | Gold offline Fix (nur 6-7) · Daily freq check |
| **v9.5** | KGSL Komplett-Dump · Adreno 0819.0 Node-Scanner |
| **v9.4** | Daily Sparmodus (Gold offline, GPU 140-267 Lock, Trips 55°C) |
| **v9.3** | GPU Max-Freq dynamisch · Adreno Driver Erkennung |
| **v9.2** | SCHED_FIFO · Gold-Isolation · Swapfile (UFS 2G) |
| **v9.1** | schedutil custom knobs · VM Tuning |
| **v9.0** | CPU-Freeze-Fix · WebUI Rewrite |

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
bin/
  k6a-controller        — main state machine (shell)
  k6a-daemon            — pre-built Rust WebSocket binary
  k6a-lib.sh            — hardware/scheduler/net library
  k6a-diagnose.sh       — diagnostic script
config/
  settings.conf         — user settings
  freeze.conf           — app-freeze whitelist
  manual_profile        — current profile
webroot/
  index.html            — WebUI (daily + cooking)
  ascii.txt             — ASCII art logo
service.sh              — boot wrapper with watchdog
customize.sh            — installer
system.prop             — boot-time props
module.prop             — module metadata
```

---

## WebUI

Open via KernelSU WebUI button or navigate to `http://127.0.0.1:7071` in any browser on the device.
