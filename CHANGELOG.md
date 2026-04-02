# BadazZ89 k6a Optimizer — Changelog

Gerät: Xiaomi Redmi Note 12 Pro 4G (sweet2 / SM7150)
Kernel: 4.14 CAF (spoofed als 6.12)

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
