BadazZ89 k6a Optimizer — Changelog
Gerät: Xiaomi Redmi Note 12 Pro 4G (sweet2 / SM7150)
Kernel: VantomKernel 4.14.356-openela-rc1 (EAS/uclamp)
v1.0 — 2026-05-25
Neu (Architektur)
k6a-controller: Single-Writer State Machine ersetzt monolithisches service.sh (keine Race-Conditions mehr)
k6a-lib.sh: Modulare Shell-Library mit allen Tuning-Funktionen
Competitive Mode (COOK1NG): Vollständiges Thermal-Disable + GPU-Lock 800MHz + EAS=0
apply_adaptive_thermal entfernt: Tot-Code (nie gelesen)
Thermal Crash Watchdog: service.sh stellt thermal zones + daemons automatisch wieder her
Multi-Instance Lock: Lock-File mit PID-Check verhindert duplicate service.sh
Performance
sched_gaming: sched_boost=1, Input Boost, schedutil 500/20000µs
sched_balanced: schedutil 2000/8000µs, sched_boost=0
sched_battery: schedutil 5000/20000µs, sched_boost=0
vm_gaming(): swappiness=10, dirty_ratio=10, page-cluster=0, extra_free_kbytes=24576
zram_gaming/balanced: Force lz4 + page-cluster=0
IO scheduler: mq-deadline für UFS blk-mq
fstrim /data alle 90s
GPU gaming min_freq: 650MHz
Network QoS: TC HTB ingress/egress
WiFi Power Save: automatische Deaktivierung in gaming/competitive
Behoben
grep -Eqi Bug (4 Stellen) — Thermal Safety, Freeze Whitelist, IRQ affinity brachen
vm_gaming() silent no-op (wurde aufgerufen aber nie definiert)
Thermal Daemon Restore silent fail (Funktion in falscher Datei)
write_data Race-Condition (tmp+mv atomic)
data.txt-Ping Integration (separate .ping file)
Log-Rotation tail -c → tail -n
CPU Freeze Log-Level err → warn
_CODM_PID_CACHE entfernt (tote Variable)
Config
cpu_hotplug_enable default: 0 (Hotplug kills UI smoothness)
net_qos_enable default: 1 (TC HTB aktiv)
wifi_ps_disable default: 1 (WiFi PS aus in gaming/competitive)
MIUI-spezifische Configs entfernt
Entfernt
module/ legacy directory
webroot/Index (leer)
apply_adaptive_thermal, _CODM_PID_CACHE, LAST_APP, freeze_for/unfreeze_for, lmk_battery
MIUI-spezifische Toggles und Props
