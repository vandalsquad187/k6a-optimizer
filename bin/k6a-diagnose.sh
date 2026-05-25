#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# k6a Optimizer — Diagnose Script v9.0
# Nutzung: su -c "sh /data/adb/modules/Bad4zz89_k6a_tweaks/bin/k6a-diagnose.sh"
# ═══════════════════════════════════════════════════════════════════════════════

MODDIR="/data/adb/modules/Bad4zz89_k6a_tweaks"
LOG="$MODDIR/config/service.log"
CONF="$MODDIR/config/settings.conf"
PROFILE="$MODDIR/config/active_profile"
MANUAL="$MODDIR/config/manual_profile"

SEP="============================================================"

echo "$SEP"
echo "k6a Optimizer — Diagnose $(date '+%Y-%m-%d %H:%M:%S')"
echo "$SEP"
echo ""

# ── CONTROLLER STATUS ─────────────────────────────────────────────────────────
echo "[ CONTROLLER STATUS ]"
ctrl_pid=$(cat "$MODDIR/run/controller.pid" 2>/dev/null)
if [ -n "$ctrl_pid" ] && [ -d "/proc/$ctrl_pid" ]; then
    ctrl_cmd=$(cat "/proc/$ctrl_pid/cmdline" 2>/dev/null | tr -d '\0')
    echo "  ✓ Controller läuft: PID=$ctrl_pid"
    echo "    CMD: $ctrl_cmd"
else
    echo "  ✗ Controller NICHT aktiv (PID=$ctrl_pid)"
fi
echo ""

# ── AKTIVES PROFIL ────────────────────────────────────────────────────────────
echo "[ PROFIL ]"
active=$(cat "$PROFILE" 2>/dev/null || echo "unknown")
manual=$(cat "$MANUAL" 2>/dev/null || echo "unknown")
echo "  active_profile : $active"
echo "  manual_profile : $manual"
echo ""

# ── CPU GOVERNOR + FREQ ───────────────────────────────────────────────────────
echo "[ CPU — GOVERNOR + FREQ ]"
for cpu in 0 1 2 3 4 5 6 7; do
    gov=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
    min=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_min_freq 2>/dev/null || echo "N/A")
    max=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq 2>/dev/null || echo "N/A")
    cur=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_cur_freq 2>/dev/null || echo "N/A")
    online=$(cat /sys/devices/system/cpu/cpu${cpu}/online 2>/dev/null || echo "N/A")
    
    status=""
    if [ "$online" = "0" ]; then
        status=" ← OFFLINE (Hotplug)"
    elif [ "$min" != "N/A" ] && [ "$max" != "N/A" ] && [ "$min" = "$max" ]; then
        status=" ← FROZEN!"
    fi
    
    echo "  cpu${cpu}: gov=$gov min=${min}Hz max=${max}Hz cur=${cur}Hz online=$online${status}"
done

# Policy Werte
p0_gov=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null || echo "N/A")
p0_min=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 2>/dev/null || echo "N/A")
p0_max=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null || echo "N/A")
p6_gov=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_governor 2>/dev/null || echo "N/A")
p6_min=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq 2>/dev/null || echo "N/A")
p6_max=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq 2>/dev/null || echo "N/A")

echo ""
echo "  policy0 (Silver): gov=$p0_gov min=${p0_min}Hz max=${p0_max}Hz"
echo "  policy6 (Gold):   gov=$p6_gov min=${p6_min}Hz max=${p6_max}Hz"

# schedutil rates
p6_up=$(cat /sys/devices/system/cpu/cpufreq/policy6/schedutil/up_rate_limit_us 2>/dev/null || echo "N/A")
p6_down=$(cat /sys/devices/system/cpu/cpufreq/policy6/schedutil/down_rate_limit_us 2>/dev/null || echo "N/A")
echo "  policy6 schedutil: up=${p6_up}µs down=${p6_down}µs"
echo ""

# ── CPU HOTPLUG STATUS ────────────────────────────────────────────────────────
echo "[ CPU HOTPLUG ]"
hotplug_cfg=$(grep "^cpu_hotplug_enable=" "$CONF" 2>/dev/null | cut -d= -f2 || echo "N/A")
echo "  Config: cpu_hotplug_enable=$hotplug_cfg"
for cpu in 0 1 2 3; do
    online=$(cat /sys/devices/system/cpu/cpu${cpu}/online 2>/dev/null || echo "N/A")
    [ "$online" = "0" ] && echo "  cpu${cpu}: OFFLINE ✓" || echo "  cpu${cpu}: online"
done
echo ""

# ── GPU STATUS ────────────────────────────────────────────────────────────────
echo "[ GPU — Adreno 618 ]"
GPU="/sys/class/kgsl/kgsl-3d0"
gpu_gov=$(cat $GPU/devfreq/governor 2>/dev/null || echo "N/A")
gpu_min=$(cat $GPU/devfreq/min_freq 2>/dev/null || echo "N/A")
gpu_max=$(cat $GPU/devfreq/max_freq 2>/dev/null || echo "N/A")
gpu_cur=$(cat $GPU/devfreq/cur_freq 2>/dev/null || echo "N/A")
gpu_pwr_min=$(cat $GPU/min_pwrlevel 2>/dev/null || echo "N/A")
gpu_pwr_max=$(cat $GPU/max_pwrlevel 2>/dev/null || echo "N/A")
gpu_thermal=$(cat $GPU/thermal_pwrlevel 2>/dev/null || echo "N/A")
gpu_clk=$(cat $GPU/force_clk_on 2>/dev/null || echo "N/A")
gpu_bus=$(cat $GPU/force_bus_on 2>/dev/null || echo "N/A")
gpu_throttle=$(cat $GPU/throttling 2>/dev/null || echo "N/A")

echo "  governor       : $gpu_gov"
echo "  min_freq       : $gpu_min"
echo "  max_freq       : $gpu_max"
echo "  cur_freq       : $gpu_cur"
echo "  min_pwrlevel   : $gpu_pwr_min"
echo "  max_pwrlevel   : $gpu_pwr_max"
echo "  thermal_pwrlevel: $gpu_thermal"
echo "  force_clk_on   : $gpu_clk"
echo "  force_bus_on   : $gpu_bus"
echo "  throttling     : $gpu_throttle"
echo ""

# ── IRQ AFFINITÄT ─────────────────────────────────────────────────────────────
echo "[ IRQ AFFINITÄT ]"
for irq_dir in /proc/irq/*/; do
    irq_num=$(basename "$irq_dir")
    irq_name=$(cat "${irq_dir}actions" 2>/dev/null || echo "unknown")
    affinity=$(cat "${irq_dir}smp_affinity" 2>/dev/null || echo "N/A")
    smp_list=$(cat "${irq_dir}smp_affinity_list" 2>/dev/null || echo "N/A")
    
    case "$irq_name" in
        *goodix*|*touch*|*fts*|*novatek*)
            echo "  IRQ $irq_num ($irq_name): affinity=$affinity list=$smp_list"
            [ "$affinity" = "c0" ] || [ "$affinity" = "c" ] && echo "    ✓ Touch auf Gold (6-7)" || echo "    ✗ Touch NICHT auf Gold"
            ;;
        *kgsl*|*gpu*)
            echo "  IRQ $irq_num ($irq_name): affinity=$affinity list=$smp_list"
            echo "    ℹ GPU-IRQ (PM_QOS verwaltet)"
            ;;
        *ufshcd*|*ufs*)
            echo "  IRQ $irq_num ($irq_name): affinity=$affinity list=$smp_list"
            [ "$affinity" = "02" ] || [ "$affinity" = "2" ] && echo "    ✓ UFS auf CPU1" || echo "    ✗ UFS NICHT auf CPU1"
            ;;
        *wlan*|*rmnet*|*gsi*|*ipa*)
            echo "  IRQ $irq_num ($irq_name): affinity=$affinity list=$smp_list"
            ;;
    esac
done
echo ""

# ── THERMAL ───────────────────────────────────────────────────────────────────
echo "[ THERMAL ]"
for zone in /sys/devices/virtual/thermal/thermal_zone*/; do
    [ -d "$zone" ] || continue
    type=$(cat "${zone}type" 2>/dev/null || echo "?")
    temp=$(cat "${zone}temp" 2>/dev/null || echo "?")
    echo "  ${zone##*/}: type=$type temp=$(( ${temp:-0} / 1000 ))°C"
done
echo ""

for svc in thermal-engine mi_thermald; do
    status=$(getprop init.svc.vendor.${svc} 2>/dev/null || echo "unknown")
    echo "  vendor.$svc : $status"
done

for te in /vendor/bin/thermal-engine /vendor/bin/mi_thermald; do
    if mount | grep -q "$te"; then
        echo "  $te : BIND-MOUNTED (disabled)"
    fi
done
echo ""

# ── SCHEDULER + CPUSET ───────────────────────────────────────────────────────
echo "[ SCHEDULER + CPUSET ]"
for cs in top-app foreground background system-background restricted; do
    cpus=$(cat /dev/cpuset/$cs/cpus 2>/dev/null || echo "N/A")
    uclamp_min=$(cat /dev/cpuset/$cs/uclamp.min 2>/dev/null || echo "N/A")
    uclamp_max=$(cat /dev/cpuset/$cs/uclamp.max 2>/dev/null || echo "N/A")
    echo "  $cs: cpus=$cpus uclamp.min=$uclamp_min uclamp.max=$uclamp_max"
done

upmigrate=$(cat /proc/sys/kernel/sched_upmigrate 2>/dev/null || echo "N/A")
downmigrate=$(cat /proc/sys/kernel/sched_downmigrate 2>/dev/null || echo "N/A")
eas=$(cat /proc/sys/kernel/sched_energy_aware 2>/dev/null || echo "N/A")
uclamp_global=$(cat /proc/sys/kernel/sched_util_clamp_min 2>/dev/null || echo "N/A")
echo ""
echo "  sched_upmigrate=$upmigrate sched_downmigrate=$downmigrate"
echo "  sched_energy_aware=$eas sched_util_clamp_min=$uclamp_global"
echo ""

# ── WIFI POWER SAVE ──────────────────────────────────────────────────────────
echo "[ WIFI POWER SAVE ]"
wifi_ps=$(iw dev wlan0 get power_save 2>/dev/null | grep -o "on\|off" || echo "N/A")
echo "  Status: $wifi_ps"
echo ""

# ── NETWORK ──────────────────────────────────────────────────────────────────
echo "[ NETWORK ]"
net_type=$(ip route show default 2>/dev/null | grep -o "dev [^ ]*" | head -1 | cut -d' ' -f2)
echo "  Interface: $net_type"

if [ -n "$net_type" ]; then
    tc_rules=$(tc qdisc show dev "$net_type" 2>/dev/null | head -3)
    if echo "$tc_rules" | grep -q "htb"; then
        echo "  TC HTB: AKTIV ✓"
        echo "$tc_rules" | sed 's/^/    /'
    else
        echo "  TC HTB: nicht aktiv"
    fi
fi

dns1=$(getprop net.dns1 2>/dev/null || echo "N/A")
dns2=$(getprop net.dns2 2>/dev/null || echo "N/A")
echo "  DNS: $dns1 / $dns2"
echo ""

# ── LRU_GEN ──────────────────────────────────────────────────────────────────
echo "[ LRU_GEN ]"
if [ -d /sys/kernel/mm/lru_gen ]; then
    lru_enabled=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo "N/A")
    echo "  enabled: $lru_enabled"
else
    echo "  LRU_GEN: nicht verfügbar"
fi
echo ""

# ── WAKELOCK BLOCKER ─────────────────────────────────────────────────────────
echo "[ WAKELOCK BLOCKER ]"
if [ -f /sys/module/boeffla_wl_blocker/parameters/wl_blocker ]; then
    wl=$(cat /sys/module/boeffla_wl_blocker/parameters/wl_blocker 2>/dev/null || echo "N/A")
    echo "  wl_blocker: $wl"
else
    echo "  BOEFFLA: nicht verfügbar"
fi
echo ""

# ── VM / MEMORY ──────────────────────────────────────────────────────────────
echo "[ VM / MEMORY ]"
swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "N/A")
vfs=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "N/A")
dirty=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null || echo "N/A")
extra=$(cat /proc/sys/vm/extra_free_kbytes 2>/dev/null || echo "N/A")
lmk=$(cat /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null || echo "N/A")

echo "  swappiness=$swappiness vfs_cache_pressure=$vfs"
echo "  dirty_ratio=$dirty extra_free_kbytes=$extra"
echo "  LMK minfree=$lmk"

ram_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
ram_avail=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
if [ -n "$ram_total" ] && [ -n "$ram_avail" ]; then
    ram_used=$(( ram_total - ram_avail ))
    ram_total_mb=$(( ram_total / 1024 ))
    ram_used_mb=$(( ram_used / 1024 ))
    echo "  RAM: ${ram_used_mb}MB / ${ram_total_mb}MB verwendet"
fi
echo ""

# ── ZRAM ─────────────────────────────────────────────────────────────────────
echo "[ ZRAM ]"
if [ -f /sys/block/zram0/comp_algorithm ]; then
    zram_algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "N/A")
    zram_size=$(cat /sys/block/zram0/disksize 2>/dev/null || echo "N/A")
    echo "  Algorithm: $zram_algo"
    echo "  Disksize: $zram_size"
else
    echo "  ZRAM: nicht verfügbar"
fi
echo ""

# ── CONFIG SETTINGS ──────────────────────────────────────────────────────────
echo "[ CONFIG settings.conf ]"
if [ -f "$CONF" ]; then
    while IFS= read -r line; do
        case "$line" in
            \#*|"") continue ;;
        esac
        echo "  $line"
    done < "$CONF"
else
    echo "  Config nicht gefunden!"
fi
echo ""

# ── SERVICE LOG (letzte 20 Zeilen) ───────────────────────────────────────────
echo "[ SERVICE LOG — letzte 20 Zeilen ]"
if [ -f "$LOG" ]; then
    tail -20 "$LOG" 2>/dev/null
else
    echo "  Log nicht gefunden!"
fi
echo ""

# ── WARNINGS DETECTION ───────────────────────────────────────────────────────
echo "[ WARNINGS / ERRORS — letzte 50 Zeilen Log ]"
if [ -f "$LOG" ]; then
    warnings=$(grep -E "\[WARN\]|\[ERROR\]" "$LOG" 2>/dev/null | tail -10)
    if [ -n "$warnings" ]; then
        echo "$warnings"
    else
        echo "  Keine Warnungen/Fehler gefunden ✓"
    fi
fi
echo ""

# ── FROZEN CPU DETECTION ─────────────────────────────────────────────────────
echo "[ FROZEN CPU DETECTION ]"
frozen=0
for cpu in 0 1 2 3 4 5 6 7; do
    min=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_min_freq 2>/dev/null || echo "0")
    max=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq 2>/dev/null || echo "0")
    online=$(cat /sys/devices/system/cpu/cpu${cpu}/online 2>/dev/null || echo "1")
    if [ "$online" = "1" ] && [ "$min" = "$max" ] && [ "$min" != "0" ]; then
        echo "  ✗ cpu${cpu}: FROZEN bei ${min}Hz (min=max)"
        frozen=1
    fi
done
[ "$frozen" = "0" ] && echo "  Keine Frozen CPUs gefunden ✓"
echo ""

# ── DIAGNOSE ZUSAMMENFASSUNG ─────────────────────────────────────────────────
echo "$SEP"
echo "DIAGNOSE ENDE"
echo "$SEP"
