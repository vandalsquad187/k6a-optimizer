#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# k6a Optimizer — Diagnose Script v9.8
# Nutzung: su -c "sh /data/adb/modules/Bad4zz89_k6a_tweaks/bin/k6a-diagnose.sh"
# Fix: KGSL-Loops mit Timeout (read blockiert bei GPU-Hang)
# ═══════════════════════════════════════════════════════════════════════════════

MODDIR="/data/adb/modules/Bad4zz89_k6a_tweaks"
LOG="$MODDIR/config/service.log"
CONF="$MODDIR/config/settings.conf"
PROFILE="$MODDIR/config/active_profile"
MANUAL="$MODDIR/config/manual_profile"

SEP="============================================================"

# Timeout-Lesefunktion — verhindert Blockade bei defekten sysfs-Nodes
safe_read() {
    local file="$1" timeout="${2:-1}" result=""
    result=$(timeout "$timeout" cat "$file" 2>/dev/null || echo "TIMEOUT")
    printf '%s' "$result"
}

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

# Gold Cap Check
if [ "$manual" = "cooking" ] && [ "${p6_max:-0}" -lt "2169600" ] && [ "${p6_max:-0}" -gt "0" ]; then
    echo "  ⚠ Gold CAPPED! max=${p6_max}Hz < Ziel 2169600Hz"
fi

# CPU Debug: Hardware-Limits + verfügbare Freqs
p0_cmin=$(cat /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_min_freq 2>/dev/null || echo "N/A")
p0_cmax=$(cat /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq 2>/dev/null || echo "N/A")
p6_cmin=$(cat /sys/devices/system/cpu/cpufreq/policy6/cpuinfo_min_freq 2>/dev/null || echo "N/A")
p6_cmax=$(cat /sys/devices/system/cpu/cpufreq/policy6/cpuinfo_max_freq 2>/dev/null || echo "N/A")
echo "  policy0 (Silver): cpuinfo_min=${p0_cmin}Hz cpuinfo_max=${p0_cmax}Hz"
echo "  policy6 (Gold):   cpuinfo_min=${p6_cmin}Hz cpuinfo_max=${p6_cmax}Hz"
p0_avail=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies 2>/dev/null || echo "N/A")
p6_avail=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_available_frequencies 2>/dev/null || echo "N/A")
echo "  policy0 avail_freqs: $p0_avail"
echo "  policy6 avail_freqs: $p6_avail"

# Limit-Nodes in cpufreq suchen
for node in cpufreq_limit scaling_max_freq_limit scaling_cur_freq_limit; do
    for dir in /sys/devices/system/cpu/cpufreq/policy0 /sys/devices/system/cpu/cpufreq/policy6; do
        [ -f "$dir/$node" ] && echo "  ⚠ $dir/$node = $(cat "$dir/$node" 2>/dev/null)"
    done
done

# Per-CPU cpufreq unbekannte Nodes scannen
for cpu in 6 7; do
    dir="/sys/devices/system/cpu/cpu${cpu}/cpufreq"
    if [ -d "$dir" ]; then
        for entry in "$dir"/*; do
            [ -f "$entry" ] || continue
            name="${entry##*/}"
            case "$name" in
                scaling_governor|scaling_min_freq|scaling_max_freq|scaling_cur_freq|\
                scaling_setspeed|scaling_available_frequencies|scaling_driver|scaling_available_governors|\
                cpuinfo_min_freq|cpuinfo_max_freq|cpuinfo_transition_latency|\
                related_cpus|affected_cpus|stats) continue ;;
            esac
            echo "  cpu${cpu}/cpufreq/$name = $(safe_read "$entry" 1 | tr '\n' ' ' | head -c 80)"
        done
    fi
done

# Limit-überwachende Kernel-Threads/Module
for mod in cpufreq_limit cpu_freq_limit msm_cpufreq_limit; do
    lsmod 2>/dev/null | grep -q "$mod" && echo "  ⚠ Kernel-Modul geladen: $mod"
done
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
gpu_gov=$(safe_read "$GPU/devfreq/governor")
gpu_min=$(safe_read "$GPU/devfreq/min_freq")
gpu_max=$(safe_read "$GPU/devfreq/max_freq")
gpu_cur=$(safe_read "$GPU/devfreq/cur_freq")
gpu_pwr_min=$(safe_read "$GPU/min_pwrlevel")
gpu_pwr_max=$(safe_read "$GPU/max_pwrlevel")
gpu_thermal=$(safe_read "$GPU/thermal_pwrlevel")
gpu_clk=$(safe_read "$GPU/force_clk_on")
gpu_bus=$(safe_read "$GPU/force_bus_on")
gpu_throttle=$(safe_read "$GPU/throttling")

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

# Adreno 0819.0-spezifische Nodes prüfen (falls neuer Treiber neue bringt)
for node in force_bus_vote force_clk_vote perf_mode gpu_clock gpu_busy gpu_load \
            gpu_preemption_stride gpu_preemption_latency gpu_rt_busy gpu_rt_level \
            pwrscale sched_0 sched_1 sched_2 sched_3 sched_4 sched_5 sched_6 sched_7; do
    nfile="$GPU/$node"
    [ -f "$nfile" ] && echo "  ${node}       : $(safe_read "$nfile")"
done

# Adreno GPU Driver Modul erkennen
if [ -d /data/adb/modules/adreno_gpu_driver ]; then
    driver_ver=$(grep "^version=" /data/adb/modules/adreno_gpu_driver/module.prop 2>/dev/null | cut -d= -f2)
    driver_desc=$(grep "^description=" /data/adb/modules/adreno_gpu_driver/module.prop 2>/dev/null | cut -d= -f2)
    echo "  GPU Driver     : installiert — $driver_ver"
    [ -n "$driver_desc" ] && echo "  Beschreibung   : $driver_desc"
fi

# Zusätzliche KGSL Nodes
gpu_avail_freq=$(safe_read "$GPU/gpu_available_frequencies")
echo "  available_freqs: $gpu_avail_freq"

# Adreno Driver Modul — vollständige Info
if [ -d /data/adb/modules/adreno_gpu_driver ]; then
    echo "  ── Adreno Driver Module ──"
    for prop in module.prop action.sh post-fs-data.sh service.sh customize.sh system.prop; do
        pfile="/data/adb/modules/adreno_gpu_driver/$prop"
        [ -f "$pfile" ] && echo "  ✓ $prop ($(wc -c < "$pfile" 2>/dev/null || echo 0) bytes)"
    done
    desc=$(grep "^description=" /data/adb/modules/adreno_gpu_driver/module.prop 2>/dev/null | cut -d= -f2-)
    author=$(grep "^author=" /data/adb/modules/adreno_gpu_driver/module.prop 2>/dev/null | cut -d= -f2-)
    [ -n "$desc" ] && echo "  description      : $desc"
    [ -n "$author" ] && echo "  author           : $author"
fi

# Cooking-Soll-Vergleich
if [ "$manual" = "cooking" ]; then
    echo "  ── Cooking Soll/Ist ──"
    echo "  expected: force_clk_on=1 force_bus_on=1 min_pwrlevel=5 max_pwrlevel=0"
    echo "  actual:   force_clk_on=$gpu_clk force_bus_on=$gpu_bus min_pwrlevel=$gpu_pwr_min max_pwrlevel=$gpu_pwr_max"
    [ "$gpu_clk" != "1" ] && echo "  ⚠ force_clk_on=$gpu_clk (soll 1)"
    [ "$gpu_bus" != "1" ] && echo "  ⚠ force_bus_on=$gpu_bus (soll 1)"
    [ "$gpu_pwr_min" != "5" ] 2>/dev/null && echo "  ⚠ min_pwrlevel=$gpu_pwr_min (soll 5 = 650)"
    [ "$gpu_pwr_max" != "0" ] 2>/dev/null && echo "  ⚠ max_pwrlevel=$gpu_pwr_max (soll 0 = 800)"
fi

# ── KGSL KOMPLETT-DUMP (mit Timeout, hängt bei GPU-Crash) ─────────────────────
echo "[ KGSL — alle Nodes ]"
for entry in /sys/class/kgsl/kgsl-3d0/*; do
    [ -f "$entry" ] || continue
    name="${entry##*/}"
    val=$(safe_read "$entry" 1 | tr '\n' ' ' | head -c 80)
    echo "  $name = $val"
done
for entry in /sys/class/kgsl/kgsl-3d0/devfreq/*; do
    [ -f "$entry" ] || continue
    name="devfreq/${entry##*/}"
    val=$(safe_read "$entry" 1 | tr '\n' ' ' | head -c 80)
    echo "  $name = $val"
done
echo ""

# ── UNBEKANNTE KGSL-NODES ─────────────────────────────────────────────────────
echo "[ KGSL — unbekannte / neue Nodes ]"
for entry in /sys/class/kgsl/kgsl-3d0/*; do
    [ -f "$entry" ] || continue
    name="${entry##*/}"
    case "$name" in
        min_pwrlevel|max_pwrlevel|thermal_pwrlevel|num_pwrlevels|gpu_freq_table|\
        force_clk_on|force_bus_on|force_rail_on|bus_split|throttling|\
        gpu_available_frequencies|gpu_busy_percentage|gpu_busy|gpu_load|\
        gpu_model|gpu_model_number|gpu_clock|gpu_preemption_stride|\
        gpu_preemption_latency|adreno_idler_active|adreno_idler_idleworkload|\
        snapshots|wake_mask|pwrscale|gpuclk|gpubusy|devfreq|\
        gpu_llc_slice_enable|gpu_rt_busy|gpu_rt_level|cluster*) continue ;;
    esac
    val=$(safe_read "$entry" 1 | tr '\n' ' ' | head -c 80)
    echo "  $name = $val"
done
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

# ── MSM_THERMAL (Kernel) ─────────────────────────────────────────────────────
echo "[ MSM_THERMAL (Kernel) ]"
found=0
for f in /sys/kernel/msm_thermal/enabled /sys/module/msm_thermal/parameters/enabled; do
    [ -f "$f" ] && { echo "  $f = $(cat $f 2>/dev/null)"; found=1; }
done
lsmod 2>/dev/null | grep -q msm_thermal && { echo "  msm_thermal: geladen (kernel module)"; found=1; }
[ "$found" = "0" ] && echo "  msm_thermal: kein sysfs/module gefunden (kernel-seitig nicht aktiv)"
echo ""

# ── LMH STATUS ────────────────────────────────────────────────────────────────
echo "[ LMH STATUS ]"
lmh_found=0
for f in /sys/power/lmh_enabled /sys/kernel/lmh/lmh_enabled \
         /sys/module/msm_thermal/parameters/lmh_enabled \
         /sys/devices/system/cpu/cpufreq/policy6/lmh_freq_limit \
         /sys/devices/system/cpu/cpufreq/policy0/lmh_freq_limit; do
    [ -f "$f" ] && { echo "  $f = $(cat $f 2>/dev/null)"; lmh_found=1; }
done
[ "$lmh_found" = "0" ] && echo "  Keine LMH sysfs gefunden (LMH vermutlich nicht aktiv)"
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
echo "  SCHEDUTIL custom:"
for p in 0 6; do
    hispeed_load=$(cat /sys/devices/system/cpu/cpufreq/policy${p}/schedutil/hispeed_load 2>/dev/null || echo "N/A")
    hispeed_freq=$(cat /sys/devices/system/cpu/cpufreq/policy${p}/schedutil/hispeed_freq 2>/dev/null || echo "N/A")
    pl=$(cat /sys/devices/system/cpu/cpufreq/policy${p}/schedutil/pl 2>/dev/null || echo "N/A")
    up=$(cat /sys/devices/system/cpu/cpufreq/policy${p}/schedutil/up_rate_limit_us 2>/dev/null || echo "N/A")
    down=$(cat /sys/devices/system/cpu/cpufreq/policy${p}/schedutil/down_rate_limit_us 2>/dev/null || echo "N/A")
    pol="Silver"; [ "$p" = "6" ] && pol="Gold"
    echo "  policy${p} (${pol}): hispeed_load=${hispeed_load} hispeed_freq=${hispeed_freq} pl=${pl} up=${up}µs down=${down}µs"
done
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

dirty_expire=$(cat /proc/sys/vm/dirty_expire_centisecs 2>/dev/null || echo "N/A")
dirty_writeback=$(cat /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null || echo "N/A")
watermark=$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null || echo "N/A")
min_free=$(cat /proc/sys/vm/min_free_kbytes 2>/dev/null || echo "N/A")

echo "  swappiness=$swappiness vfs_cache_pressure=$vfs"
echo "  dirty_ratio=$dirty extra_free_kbytes=$extra"
echo "  dirty_expire_centisecs=$dirty_expire dirty_writeback_centisecs=$dirty_writeback"
echo "  watermark_scale_factor=$watermark min_free_kbytes=$min_free"
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
    if [ "${zram_size:-0}" -gt "0" ] 2>/dev/null; then
        zram_mb=$(( zram_size / 1048576 ))
        echo "  Disksize (lesbar): ${zram_mb}MB ($(( zram_mb / 1024 ))GB)"
    fi
else
    echo "  ZRAM: nicht verfügbar"
fi
swap_total=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
swap_free=$(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print $2}')
if [ -n "$swap_total" ] && [ "$swap_total" -gt 0 ] 2>/dev/null; then
    swap_used=$(( swap_total - swap_free ))
    swap_pct=$(( swap_used * 100 / swap_total ))
    echo "  Swap: ${swap_used}K / ${swap_total}K (${swap_pct}%)"
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
                                                                                                                                                                                                                                                                                                                                                                                             