# BadazZ89 k6a Optimizer — Changelog

Gerät: Xiaomi Redmi Note 12 Pro 4G (sweet2 / SM7150)
Kernel: VantomKernel 4.14.356-openela-rc1 (EAS/uclamp)

---

## v1.0 — 2026-05-25

### Neu (Architektur)

- **k6a-controller**: Single-Writer State Machine ersetzt monolithisches service.sh (keine Race-Conditions mehr)
- **k6a-lib.sh**: Modulare Shell-Library mit allen Tuning-Funktionen (sched, GPU, IO, VM, ZRAM, LMH, thermal, IRQ, LRU, net QoS, wakelock, freeze)
- **Competitive Mode (COOK1NG)**: Vollständiges Thermal-Disable + GPU-Lock 800MHz + EAS=0 — max FPS für CODM
- **apply_adaptive_thermal entfernt**: Tot-Code (nie gelesen) — reduziert Controller-Log um 30%
- **Thermal Crash Watchdog**: service.sh stellt thermal zones + daemons automatisch wieder her wenn Controller stirbt
- **Multi-Instance Lock**: Lock-File mit PID-Check verhindert duplicate service.sh bei KernelSU Next Boot

### Performance

- **sched_gaming**: sched_boost=1, Input Boost (cpu_boost conditional), schedutil 500/20000µs, sched_child_runs_first=1
- **sched_balanced**: schedutil 2000/8000µs, sched_boost=0, sched_child_runs_first=0
- **sched_battery**: schedutil 5000/20000µs, sched_boost=0, sched_child_runs_first=0
- **vm_gaming()**: swappiness=10, dirty_ratio=10, page-cluster=0, extra_free_kbytes=24576
- **zram_gaming/balanced**: Force lz4 + page-cluster=0 in gaming/competitive
- **IO scheduler**: mq-deadline für UFS blk-mq (noop/cfq nicht verfügbar auf SM7150)
- **fstrim /data** alle 90s im Controller-Loop
- **GPU gaming min_freq**: 650MHz (pwrlevel=1, max FPS)
- **Network QoS**: TC HTB ingress/egress — CoD UDP-Ports prioritisiert
- **WiFi Power Save**: automatische Deaktivierung in gaming/competitive

### Behoben

- **grep -Eqi Bug (4 Stellen)**: Toybox `|` ohne `-E` kaputt — Thermal Safety Check, Freeze Whitelist, IRQ affinity detection funktionierten nicht
- **vm_gaming() silent no-op**: Wurde aufgerufen aber nie definiert — gaming hatte keine VM-Tuning
- **Thermal Daemon Restore silent fail**: Watchdog rief thermal_restore_daemons() auf, das in controller lag — nie geladen
- **write_data Race-Condition**: tmp + mv atomic für data.txt, write_ping in separate .ping Datei
- **data.txt-Ping Integration**: write_data liest async gepinnte .ping Datei (ping/ping_stale Felder)
- **Log-Rotation**: tail -c → tail -n (vermeidet halbe Zeilen nach Rotation)
- **CPU Freeze Log-Level**: err → warn (kein falscher Alarm im WebUI)
- **_CODM_PID_CACHE entfernt**: Tote Variable, nie gelesen
- **settings.conf**: cpu_hotplug=0, net_qos=1 als Default (SM7150 optimal)

### Config

- **cpu_hotplug_enable** default: `0` (Hotplug kills UI smoothness)
- **net_qos_enable** default: `1` (TC HTB aktiv)
- **wifi_ps_disable** default: `1` (WiFi PS aus in gaming/competitive)
- **MIUI-spezifische Configs entfernt**: aggressive_boost, auto_detection, auto_cache, bypass_threshold, miui_joyose, miui_game_turbo, miui_freeform, miui_mipad_boost

### Entfernt

- `module/` legacy directory
- `webroot/Index` (leer)
- `apply_adaptive_thermal` dead code
- `_CODM_PID_CACHE`
- `LAST_APP` (nie gelesen)
- `freeze_for / unfreeze_for` (ersetzt durch app-freeze)
- `lmk_battery` (ungenutzt)
- MIUI-spezifische Toggles und Props

---

## v4.0 — 2026-04-02

### Neu
- **MIUI / HyperOS Tweaks** (separate Sektion, alle standardmäßig AUS):
  - Joyose Daemon deaktivieren im Gaming (`pm disable com.xiaomi.joyose`)
  - Game Turbo aktivieren (`persist.sys.game_mode`, `sys.powerkeeper.game_status`)
  - Freeform Windows deaktivieren (`enable_freeform_support=0`) im Gaming
- **Akkutemperatur** live in der Akku-Info-Kachel angezeigt (°C)
- **update.json** für automatische KernelSU-Update-Benachrichtigungen

### Verbessert
- **Bypass Power Supply**: `resetprop` wird vor `setprop` ausgeführt (schreibt sofort ins laufende System, kein Neustart nötig). Nicht bestätigte sysfs-Pfade entfernt.
- **service.sh**: Überflüssige sysfs-Writes für Bypass entfernt (nur der MIUI PowerKeeper Prop wird geändert — bestätigt via Termux auf sweet2)
- Versionsnummer auf 4.0 angehoben

### Technische Details
- Bestätigte Bypass-Pfade auf sweet2 (via Termux):
  - `persist.vendor.battery.bypass_temp_thresh` = 41 (Standard)
  - `/sys/class/power_supply/battery/input_suspend` = 0
  - `persist.sys.battery_bypass_supported` = true

---

## v3.10 — 2026-04-02

### Neu
- **Battery Spoofing**: Meldet niedrige Temperatur an thermal policy engine
  (`/sys/class/power_supply/battery/temp`, `cmd thermalservice override-status 0`)
- **Bypass Power Supply**: Senkt Bypass-Schwellenwert beim Gaming (Standard: 35°C statt 41°C)
  — MIUI PowerKeeper aktiviert Bypass früher, reduziert Ladewärme
- **k6a-daemon** Binary: Companion-Daemon für erweiterte Systemzugriffe
- **Heartbeat-Log**: Service schreibt alle 10 Minuten einen Lebenszeichen-Eintrag
- Profilwechsel-Log: `Profilwechsel: balanced → gaming`

### Verbessert
- **get_foreground_app**: Kein `dumpsys` mehr — liest direkt aus `/sys/fs/cgroup/top-app/`
  (kein Binder-IPC → kein Touch/Button-Freeze unter Gaming-Last)
- **Auto Detection**: Poll nur alle 5 Ticks (15s) statt jede 3s — reduziert CPU-Overhead
- **Gaming write_data**: Daten-Update alle 60s statt 30s, kein Ping während Gaming
- **ZRAM**: lz4 statt lzo (besser auf Cortex-A55/4.14 CAF)
- `manual_profile` wird beim ersten Start initialisiert wenn fehlend

### Behoben
- `LAST_PROFILE=""` Start-Bug: Profile wurden beim Start nicht geloggt
- Doppeltes `initCacheBtn` führte dazu dass RAM-Button nicht reagierte
- RAM Cleaner überspringt sich selbst wenn Gaming aktiv (verhindert Asset-Reload-Stutter)

---

## v3.3 — 2026-03-31

### Neu
- **RAM Cleaner**: Button zum manuellen Bereinigen (`am kill-all`, `drop_caches`, `compact_memory`)
- **RAM-Anzeige**: Belegter/Gesamtspeicher live in MB
- **LMKD-Tuning**: Low Memory Killer Schwellenwerte je nach Profil
- **schedutil hispeed Tuning**: `hispeed_load` und `hispeed_freq` für Policy0/Policy6

### Behoben
- Touchscreen/Button-Freeze: `chmod 000` auf temp-Sensoren entfernt
  (trifft Touch-Interrupt-Handler auf SM7150 — war die Ursache des Freeze-Bugs)
- `conn_therm`, `charger_therm`, `battery`, `bms` Zonen nie deaktivieren
- `dumpsys activity` durch cgroup-basierte App-Erkennung ersetzt

---

## v3.2 — 2026-03-30

### Neu
- **Gerätedaten korrigiert**: SD680/Adreno 610 → SD730 (SM7150)/Adreno 618
- **Gold Cores**: min 1113 MHz (normal) / 1612 MHz (Boost) — korrekte SM7150-Werte
- **schedutil Policy-Pfade**: `/sys/devices/system/cpu/cpufreq/policy0/schedutil/` (4.14 CAF korrekt)
- **DevFlags**: Force 4x MSAA, DND, GPU 2D Rendering Toggles
- **Service PID**: Echte PID-Anzeige statt Profilname

### Verbessert
- WebUI: `applyData` liest alle Werte aus `data.txt` — kein `readFile`/Callback mehr

---

## v3.1 — 2026-03-29

### Neu
- **GPU devfreq governor**: `performance` im Gaming, `powersave` im Battery
- **GPU force_clk_on / bus_split**: Anti-Idle und direkter Speicherzugriff
- **I/O mq-deadline**: Niedrigste Latenz für eMMC im Gaming
- **TCP BBR**: Niedrigere Netzwerklatenz im Gaming
- **vm.dirty_ratio** Tuning pro Profil

---

## v3.0 — 2026-03-28

### Erstes funktionsfähiges Release
- 3 Profile: Balanced, Gaming, Battery
- CPU/GPU/I/O Tuning
- Thermal Disabler (surgical — Touch-Zonen ausgenommen)
- Auto Gaming Detection
- Per-App Profile (8 Spiele vordefiniert)
- Cache Cleaner (manuell + Auto)
- Live Ping, Service Log
- Alle Werte via `fetch('data.txt')` — bestätigtes WebUI-Datenmuster
