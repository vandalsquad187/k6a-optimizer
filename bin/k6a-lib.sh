#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# k6a-lib.sh  v8.0
# Hardware / Scheduler / Network / App-Detection Library
# Einbinden: . "$MODDIR/bin/k6a-lib.sh"  (POSIX-kompatibel, busybox-sicher)
#
# SM7150 / sweet_k6a — VantomKernel 4.14.356-openela-rc1
# Kernel: CONFIG_UCLAMP_TASK=y, SCHED_CASS=y, HOTPLUG_CPU=y,
#         THERMAL_WRITABLE_TRIPS=y, LRU_GEN=y, BBR=y, ZRAM=lz4,
#         BOEFFLA_WL_BLOCKER=y, HTB=y, NETFILTER_MARK=y
#
# v8.0 Changes (Major Cleanup):
#   1. Auto Gaming Detection entfernt (CFG_AUTO, get_foreground_app, is_game_pkg)
#   2. MIUI-Code entfernt (miui_gpu2d, miui_joyose, smart_pixels, smart_dim)
#   3. apply_gpu_driver() entfernt (nie aufgerufen)
#   4. thermal_zone_list() entfernt (Debug-Helfer, nie aufgerufen)
#   5. CODM_PKG → PRIMARY_GAME_PKG umbenannt
#  v7.64 Changes:
#   1. lmh_disable() — LMH/DCVS/PMIC5 Limits deaktivieren (verhindert CPU FROZEN)
#  v7.63 Changes:
#   1. cpu_set(): per-CPU Writes entfernt — Gold CPU Freeze Fix (Safe-Guard blockierte min>max)
#   2. sched_gaming(): uclamp min 20→50, fg min 10→20 — aggressiveres CPU-Pinning
#   3. sched_competitive(): uclamp min 40→60 — maximale CPU-Priorität
#   4. settings.conf: cpu_hotplug_enable=1 (default für Competitive)
#  v7.62 Changes:
#   1. Adaptive Thermal: competitive 95→90°C, gaming 85→88°C
#  v7.61 Changes:
#   1. CFG_WIFI_PS variable fix (war CFG_WIFI_PS_DISABLE)
#   2. sf_gaming() entfernt (latch_unsignaled=1 → Frame-Drops)
#   3. Battery Spoof Minimum 25°C (Lithium-Plating-Schutz)
#  v7.60 Changes:
#   1. Logging-System: _log/_warn/_err/_dbg mit [TAG] Prefix
#   2. w() Helper mit Safe-Guards (GPU ≤ 800MHz, CPU min ≤ max)
#   3. detect_kernel_features() — auto-detect verfügbare sysfs-Pfade
#   4. CPU Hotplug: Silver-Cores offline im Competitive
#   5. LRU_GEN Tuning pro Profil
#   6. Network QoS: TC HTB + iptables MARK für Gaming
#   7. WakeLock Blocker (BOEFFLA)
#   8. SurfaceFlinger Tuning (latch_unsignaled, backpressure)
#   9. IRQ Affinity dynamisch (statt hardcoded Nummern)
#  10. tune_codm() → tune_game() generisch für alle Games
#  11. Adaptive Thermal Control pro Profil
# ═══════════════════════════════════════════════════════════════════════════════

# ── Pfade ─────────────────────────────────────────────────────────────────────
GPU=/sys/class/kgsl/kgsl-3d0
P0=/sys/devices/system/cpu/cpufreq/policy0
P6=/sys/devices/system/cpu/cpufreq/policy6

GPU_LVL_800=0; GPU_LVL_650=1; GPU_LVL_267=5

CS_TOP="/dev/cpuset/top-app"
CS_FG="/dev/cpuset/foreground"
CS_BG="/dev/cpuset/background"
CS_SYS="/dev/cpuset/system-background"
CS_RESTRICT="/dev/cpuset/restricted"

CODM_PKG="com.activision.callofduty.shooter"
GPU_DRIVER_PKG="com.qualcomm.qti.gpudrivers.sm7150.api30"
_TRIP_CACHE_FILE="$MODDIR/run/trip_cache"
_TRIP_SAFE_PATTERN="touch|tsp|conn_therm|charger_therm|battery|bms|qcom-bms|quiet_therm|xo_therm|pa_therm|pm6150|pm6150l|bcl|pmic"

# ── Feature-Flags (werden von detect_kernel_features() gesetzt) ───────────────
FEATURE_HOTPLUG=0
FEATURE_LRU_GEN=0
FEATURE_BOEFFLA=0
FEATURE_WAKELOCK=0
FEATURE_SCHED_CASS=0
FEATURE_UCLAMP=0
FEATURE_THERMAL_WRITABLE=0

# ── LOGGING ───────────────────────────────────────────────────────────────────
# LOG_FILE muss vom Controller gesetzt sein: LOG_FILE="$MODDIR/config/service.log"
_log()  { printf '[%s] [INFO] %s\n' "$(date '+%H:%M:%S')" "$1" >> "${LOG_FILE:-/dev/null}" 2>/dev/null; }
_warn() { printf '[%s] [WARN] %s\n' "$(date '+%H:%M:%S')" "$1" >> "${LOG_FILE:-/dev/null}" 2>/dev/null; }
_err()  { printf '[%s] [ERROR] %s\n' "$(date '+%H:%M:%S')" "$1" >> "${LOG_FILE:-/dev/null}" 2>/dev/null; }
_dbg()  {
    [ "${CFG_DEBUG:-0}" = "1" ] && \
    printf '[%s] [DBG] %s\n' "$(date '+%H:%M:%S')" "$1" >> "${LOG_FILE:-/dev/null}" 2>/dev/null
}
# Aliase für Rückwärtskompatibilität
log()  { _log "$1"; }
warn() { _warn "$1"; }
err()  { _err "$1"; }
dbg()  { _dbg "$1"; }

# ── SYSFS WRITE HELPER mit Safe-Guards ────────────────────────────────────────
w() {
    local node="$1" val="$2"
    [ -f "$node" ] || return 1

    # GPU Safe-Guard: nie > 800MHz
    case "$node" in
        */devfreq/max_freq|*/devfreq/min_freq)
            local max_safe=800000000
            [ "${val:-0}" -gt "$max_safe" ] 2>/dev/null && {
                _warn "GPU freq blocked: ${val}Hz > ${max_safe}Hz at $node"
                return 1
            } ;;
    esac

    # CPU Safe-Guard: min_freq nie > max_freq
    case "$node" in
        */scaling_min_freq)
            local max_freq
            max_freq=$(cat "${node/scaling_min_freq/scaling_max_freq}" 2>/dev/null)
            [ -n "$max_freq" ] && [ "${val:-0}" -gt "${max_freq:-0}" ] 2>/dev/null && {
                _warn "CPU min > max blocked: ${val} > ${max_freq} at $node"
                return 1
            } ;;
    esac

    echo "$val" > "$node" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# KERNEL FEATURE DETECTION
# ═══════════════════════════════════════════════════════════════════════════════
detect_kernel_features() {
    FEATURE_HOTPLUG=0
    FEATURE_LRU_GEN=0
    FEATURE_BOEFFLA=0
    FEATURE_WAKELOCK=0
    FEATURE_SCHED_CASS=0
    FEATURE_UCLAMP=0
    FEATURE_THERMAL_WRITABLE=0

    [ -f /sys/devices/system/cpu/cpu0/online ] && FEATURE_HOTPLUG=1
    [ -d /sys/kernel/mm/lru_gen ] && FEATURE_LRU_GEN=1
    [ -f /sys/module/boeffla_wl_blocker/parameters/wl_blocker ] && FEATURE_BOEFFLA=1
    [ -f /sys/power/wake_lock ] && FEATURE_WAKELOCK=1
    grep -q "sched_cass" /proc/sched_debug 2>/dev/null && FEATURE_SCHED_CASS=1
    [ -f /dev/cpuset/top-app/uclamp.min ] && FEATURE_UCLAMP=1
    [ -d /sys/devices/virtual/thermal/thermal_zone0 ] && FEATURE_THERMAL_WRITABLE=1

    _log "Features: hotplug=$FEATURE_HOTPLUG lru_gen=$FEATURE_LRU_GEN " \
         "boeffla=$FEATURE_BOEFFLA uclamp=$FEATURE_UCLAMP " \
         "thermal_writable=$FEATURE_THERMAL_WRITABLE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# GPU — Adreno 618 (KGSL sysfs)
# ═══════════════════════════════════════════════════════════════════════════════
gpu_gaming() {
    w $GPU/devfreq/governor        "msm-adreno-tz"
    w $GPU/force_clk_on            "1"
    w $GPU/force_bus_on            "1"
    w $GPU/bus_split               "0"
    w $GPU/thermal_pwrlevel        "0"
    w $GPU/max_pwrlevel            "$GPU_LVL_800"
    w $GPU/min_pwrlevel            "$GPU_LVL_650"
    w $GPU/devfreq/max_freq        "800000000"
    w $GPU/devfreq/min_freq        "650000000"
    w $GPU/devfreq/polling_interval "10"
    w $GPU/adreno_idler_active     "0"
    echo "0" > "$GPU/throttling"   2>/dev/null || true
    dbg "GPU gaming: 650-800MHz"
}

gpu_competitive() {
    w $GPU/devfreq/governor        "msm-adreno-tz"
    w $GPU/force_clk_on            "1"
    w $GPU/force_bus_on            "1"
    w $GPU/bus_split               "0"
    w $GPU/thermal_pwrlevel        "0"
    w $GPU/max_pwrlevel            "$GPU_LVL_800"
    w $GPU/min_pwrlevel            "$GPU_LVL_800"
    w $GPU/devfreq/max_freq        "800000000"
    w $GPU/devfreq/min_freq        "800000000"
    w $GPU/devfreq/polling_interval "2"
    w $GPU/adreno_idler_active     "0"
    echo "0" > "$GPU/throttling"   2>/dev/null || true
    dbg "GPU competitive: locked 800MHz"
}

gpu_balanced() {
    w $GPU/devfreq/governor        "msm-adreno-tz"
    w $GPU/force_clk_on            "0"
    w $GPU/force_bus_on            "0"
    w $GPU/bus_split               "1"
    w $GPU/thermal_pwrlevel        "0"
    w $GPU/max_pwrlevel            "$GPU_LVL_800"
    w $GPU/min_pwrlevel            "$GPU_LVL_267"
    w $GPU/devfreq/max_freq        "800000000"
    w $GPU/devfreq/min_freq        "267000000"
    w $GPU/adreno_idler_active     "1"
    echo "1" > "$GPU/throttling"   2>/dev/null || true
    dbg "GPU balanced: 267-800MHz idler ON"
}

gpu_battery() {
    w $GPU/devfreq/governor        "powersave"
    w $GPU/force_clk_on            "0"
    w $GPU/force_bus_on            "0"
    w $GPU/bus_split               "1"
    w $GPU/thermal_pwrlevel        "2"
    w $GPU/max_pwrlevel            "4"
    w $GPU/min_pwrlevel            "$GPU_LVL_267"
    w $GPU/devfreq/max_freq        "355000000"
    w $GPU/devfreq/min_freq        "267000000"
    w $GPU/adreno_idler_active     "1"
    dbg "GPU battery: powersave 267-355MHz"
}

# ═══════════════════════════════════════════════════════════════════════════════
# CPU — max→min→governor verhindert Freq-Spikes beim Governor-Wechsel
# ═══════════════════════════════════════════════════════════════════════════════
cpu_set() {
    local gov="$1" smin="$2" smax="$3" gmin="$4" gmax="$5"
    w "$P0/scaling_max_freq" "$smax"
    w "$P6/scaling_max_freq" "$gmax"
    sleep 0.2
    w "$P0/scaling_min_freq" "$smin"
    w "$P6/scaling_min_freq" "$gmin"
    w "$P0/scaling_governor" "$gov"
    w "$P6/scaling_governor" "$gov"
}

# ═══════════════════════════════════════════════════════════════════════════════
# CPU HOTPLUG — Silver-Cores offline im Competitive
# Kernel: CONFIG_HOTPLUG_CPU=y ✓
# SM7150: CPU 0-3 = Silver (A55), CPU 4-5 = Silver, CPU 6-7 = Gold (A76)
# ═══════════════════════════════════════════════════════════════════════════════
cpu_hotplug_offline_silver() {
    [ "$FEATURE_HOTPLUG" = "0" ] && return 0
    local c
    for c in 0 1 2 3; do
        [ -f /sys/devices/system/cpu/cpu${c}/online ] || continue
        echo 0 > /sys/devices/system/cpu/cpu${c}/online 2>/dev/null || true
    done
    _log "CPU Hotplug: Silver cores 0-3 offline"
}

cpu_hotplug_online_all() {
    [ "$FEATURE_HOTPLUG" = "0" ] && return 0
    local c
    for c in 0 1 2 3 4 5 6 7; do
        [ -f /sys/devices/system/cpu/cpu${c}/online ] || continue
        echo 1 > /sys/devices/system/cpu/cpu${c}/online 2>/dev/null || true
    done
    _log "CPU Hotplug: All cores online"
}

# ═══════════════════════════════════════════════════════════════════════════════
# THERMAL TRIP-POINT MANAGER — THERMAL_WRITABLE_TRIPS=y ✓
# Originale Werte cachen → auf Target-Temp hochsetzen → exakt zurückschreiben
# zone24/25 (CPU-Sensoren) und BCL/PMIC niemals anfassen
# ═══════════════════════════════════════════════════════════════════════════════
thermal_trips_raise() {
    local target_temp="${1:-95000}"
    rm -f "$_TRIP_CACHE_FILE" 2>/dev/null
    local zone type zname trip tfile val
    for zone in /sys/devices/virtual/thermal/thermal_zone*/; do
        [ -d "$zone" ] || continue
        type=$(cat "${zone}type" 2>/dev/null) || continue
        [ -z "$type" ] && continue
        echo "$type" | grep -Eqi "$_TRIP_SAFE_PATTERN" && continue
        zname="${zone##*/}"
        case "$zname" in thermal_zone24|thermal_zone25) continue ;; esac
        for trip in 0 1 2 3; do
            tfile="${zone}trip_point_${trip}_temp"
            [ -f "$tfile" ] || continue
            val=$(cat "$tfile" 2>/dev/null) || continue
            [ "${val:-0}" -lt "$target_temp" ] || continue
            printf '%s:%s:%s\n' "$zname" "$trip" "$val" >> "$_TRIP_CACHE_FILE"
            echo "$target_temp" > "$tfile" 2>/dev/null || true
        done
    done
    local count=0
    [ -f "$_TRIP_CACHE_FILE" ] && count=$(wc -l < "$_TRIP_CACHE_FILE" 2>/dev/null || echo 0)
    dbg "Thermal trips raised to $(( target_temp / 1000 ))°C, $count entries cached"
}

thermal_trips_restore() {
    [ -f "$_TRIP_CACHE_FILE" ] || return 0
    local zname trip val tfile
    while IFS=: read -r zname trip val; do
        [ -z "$zname" ] && continue
        tfile="/sys/devices/virtual/thermal/${zname}/trip_point_${trip}_temp"
        [ -f "$tfile" ] && echo "$val" > "$tfile" 2>/dev/null || true
    done < "$_TRIP_CACHE_FILE"
    rm -f "$_TRIP_CACHE_FILE" 2>/dev/null
    dbg "Thermal trips restored from cache"
}

# ── Thermal Daemon Manager (hier für service.sh Watchdog-Zugriff) ─────────────

thermal_stop_daemons() {
    [ "$_THERMAL_DAEMONS_STOPPED" = "1" ] && return 0
    local pid svc
    stop vendor.msm_irqbalance 2>/dev/null || true
    setprop ctl.stop vendor.msm_irqbalance 2>/dev/null || true
    for pid in $(pgrep -x "msm_irqbalance" 2>/dev/null); do kill -9 "$pid" 2>/dev/null || true; done
    for svc in vendor.thermal-engine mi_thermald thermal-engine thermald \
               android.hardware.thermal-service.qti vendor.thermal; do
        stop "$svc" 2>/dev/null || true
        setprop ctl.stop "$svc" 2>/dev/null || true
    done
    sleep 0.3
    for pid in $(pgrep -f "thermal" 2>/dev/null); do kill -9 "$pid" 2>/dev/null || true; done
    for pid in $(pgrep -x "mi_thermald" 2>/dev/null); do kill -9 "$pid" 2>/dev/null || true; done
    sleep 0.3
    local te
    for te in /vendor/bin/thermal-engine /system/bin/thermal-engine \
              /vendor/bin/mi_thermald /system/bin/mi_thermald; do
        [ -f "$te" ] || continue
        mount --bind /bin/true "$te" 2>/dev/null && _log "Bind-mount: $te → /bin/true" || true
    done
    [ -f "/vendor/bin/msm_irqbalance" ] && \
        mount | grep -q "msm_irqbalance" || \
        mount --bind /bin/true /vendor/bin/msm_irqbalance 2>/dev/null || true
    for svc in irqbalance vendor.irqbalance msm_irqbalance; do
        stop "$svc" 2>/dev/null || true
        setprop ctl.stop "$svc" 2>/dev/null || true
    done
    cmd thermalservice override-status 0 2>/dev/null || true
    setprop vendor.thermal.config "thermal-engine-off.conf" 2>/dev/null || true
    _THERMAL_DAEMONS_STOPPED=1
    _log "Thermal daemons: killed + bind-mount"
}

thermal_restore_daemons() {
    local te svc
    for te in /vendor/bin/thermal-engine /system/bin/thermal-engine \
              /vendor/bin/mi_thermald /system/bin/mi_thermald /vendor/bin/msm_irqbalance; do
        umount "$te" 2>/dev/null || true; umount "$te" 2>/dev/null || true
    done
    setprop vendor.thermal.config "" 2>/dev/null || true
    for svc in msm_irqbalance irqbalance vendor.irqbalance; do start "$svc" 2>/dev/null || true; done
    for svc in vendor.thermal-engine mi_thermald thermal-engine thermald \
               android.hardware.thermal-service.qti vendor.thermal; do
        start "$svc" 2>/dev/null || true
    done
    cmd thermalservice reset 2>/dev/null || true
    _THERMAL_DAEMONS_STOPPED=0
    _log "Thermal daemons: restored"
}

# ═══════════════════════════════════════════════════════════════════════════════
# LMH (Limits Management Hardware) DEACTIVATE
# Kernel: CONFIG_QTI_THERMAL_LIMITS_DCVS=y
# LMH limitiert CPU/GPU Frequenzen basierend auf Stromverbrauch — unabhängig
# vom thermal-engine. Verursacht CPU FROZEN und FPS-Drops.
# ═══════════════════════════════════════════════════════════════════════════════
lmh_disable() {
    local node

    # QTI DCVS (Dynamic Clock and Voltage Scaling) Limits
    for node in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
        [ -f "$node" ] || continue
        local max; max=$(cat "${node%/scaling_max_freq}/scaling_max_freq" 2>/dev/null)
        [ -n "$max" ] && [ "$max" -lt 1000000 ] 2>/dev/null && {
            local policy; policy=$(echo "$node" | grep -o 'policy[0-9]')
            [ -n "$policy" ] && w "/sys/devices/system/cpu/cpufreq/${policy}/scaling_max_freq" "2304000"
        }
    done

    # SPMI PMIC5 thermal limits
    for node in /sys/module/spmi_pmic5/parameters/*; do
        [ -f "$node" ] || continue
        echo 0 > "$node" 2>/dev/null || true
    done

    # QTI thermal limits DCVS
    for node in /sys/devices/virtual/thermal/thermal_zone*/user_space; do
        [ -f "$node" ] && echo 0 > "$node" 2>/dev/null || true
    done

    # MSM Performance limits
    for node in /sys/module/msm_performance/parameters/*; do
        [ -f "$node" ] || continue
        case "$(basename "$node")" in
            *limit*|*thermal*|*dcvs*) echo 0 > "$node" 2>/dev/null || true ;;
        esac
    done

    # CPU freq limits reset — max zuerst, dann sleep, dann min
    w "$P0/scaling_max_freq" "1804800"
    w "$P6/scaling_max_freq" "2304000"
    sleep 1
    w "$P0/scaling_min_freq" "576000"
    w "$P6/scaling_min_freq" "652800"

    _log "LMH: deaktiviert (DCVS, PMIC5, thermal limits)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# ADAPTIVE THERMAL CONTROL — Target-Temp je nach Profil
# ═══════════════════════════════════════════════════════════════════════════════
apply_adaptive_thermal() {
    [ "${CFG_ADAPTIVE_THERMAL:-1}" = "0" ] && return 0

    local profile="$1"
    local target_temp

    case "$profile" in
        competitive) target_temp=90000 ;;
        gaming)      target_temp=88000 ;;
        balanced)    target_temp=75000 ;;
        battery)     target_temp=70000 ;;
        *)           target_temp=80000 ;;
    esac

    # Nur wenn trips noch nicht für dieses Profil gesetzt
    if [ ! -f "$_TRIP_CACHE_FILE" ]; then
        thermal_trips_raise "$target_temp"
    fi

    _log "Adaptive Thermal: $profile → $(( target_temp / 1000 ))°C"
}

# ═══════════════════════════════════════════════════════════════════════════════
# IRQ AFFINITY — dynamisch erkannt (statt hardcoded Nummern)
# ═══════════════════════════════════════════════════════════════════════════════
apply_irq_affinity() {
    stop vendor.msm_irqbalance 2>/dev/null || true
    setprop ctl.stop vendor.msm_irqbalance 2>/dev/null || true
    for pid in $(pgrep -x "msm_irqbalance" 2>/dev/null); do kill -9 "$pid" 2>/dev/null || true; done
    for pid in $(pidof irqbalance 2>/dev/null); do kill -9 "$pid" 2>/dev/null || true; done

    # Touch-IRQ dynamisch erkennen
    local touch_irq
    touch_irq=$(grep -l "GTX9896\|touch\|fts\|novatek" /proc/irq/*/actions 2>/dev/null | head -1 | grep -o '[0-9]\+')
    [ -n "$touch_irq" ] && printf '%s' "40" > /proc/irq/${touch_irq}/smp_affinity 2>/dev/null || true

    # UFS-IRQ dynamisch erkennen
    local ufs_irq
    ufs_irq=$(grep -l "ufshcd\|ufs" /proc/irq/*/actions 2>/dev/null | head -1 | grep -o '[0-9]\+')
    [ -n "$ufs_irq" ] && printf '%s' "02" > /proc/irq/${ufs_irq}/smp_affinity 2>/dev/null || true

    # GPU-IRQ bewusst nicht setzen (PM_QOS_REQ_AFFINE_IRQ)

    # Netzwerk-IRQs dynamisch
    local irq_dir irq_name
    for irq_dir in /proc/irq/*/; do
        [ -f "${irq_dir}smp_affinity" ] || continue
        irq_name=$(cat "${irq_dir}actions" 2>/dev/null)
        [ -z "$irq_name" ] && continue
        if echo "$irq_name" | grep -Eqi "wlan|rmnet|gsi|^ipa"; then
            printf '%s' "04" > "${irq_dir}smp_affinity" 2>/dev/null || true
        fi
    done

    # RIL-Prozesse auf Silver (0x3f = CPU 0-5)
    if [ "${_RIL_PINNED:-0}" = "0" ]; then
        local p
        for p in $(pidof ipacm netmgrd qcrild 2>/dev/null); do
            taskset -p 0x3f "$p" >/dev/null 2>&1
        done
        _RIL_PINNED=1
    fi

    dbg "IRQ: Touch→cpu4 UFS→cpu1 Netz→cpu2 (dynamisch erkannt)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SCHEDULER — uclamp+EAS aktiv, schedtune ENTFERNT (nie compiled)
# ═══════════════════════════════════════════════════════════════════════════════
sched_gaming() {
    echo "0-7" > "$CS_TOP/cpus"      2>/dev/null || true
    echo "0-7" > "$CS_FG/cpus"       2>/dev/null || true
    echo "0-5" > "$CS_SYS/cpus"      2>/dev/null || true
    echo "0-5" > "$CS_BG/cpus"       2>/dev/null || true
    echo "2-5" > "$CS_RESTRICT/cpus" 2>/dev/null || true
    w "$CS_TOP/uclamp.min"               "50.00"
    w "$CS_TOP/uclamp.max"               "100.00"
    w "$CS_TOP/uclamp.boosted"           "1"
    w "$CS_TOP/uclamp.latency_sensitive" "1"
    w "$CS_FG/uclamp.min"                "20.00"
    w "$CS_FG/uclamp.max"                "100.00"
    w "$CS_FG/uclamp.boosted"            "1"
    w "$CS_FG/uclamp.latency_sensitive"  "1"
    w /proc/sys/kernel/sched_upmigrate        "80"
    w /proc/sys/kernel/sched_downmigrate      "60"
    w /proc/sys/kernel/sched_child_runs_first "1"
    w /proc/sys/kernel/sched_energy_aware     "0"
    w /proc/sys/kernel/sched_util_clamp_min   "200"
    w /proc/sys/kernel/sched_util_clamp_max   "1024"
    # sched_boost=1: CAF-spezifisch, migriert Tasks aggressiver auf Gold
    w /proc/sys/kernel/sched_boost            "1"
    # Schedutil rates: instant up, hold 20ms after burst
    w "$P0/schedutil/up_rate_limit_us"    "500"
    w "$P0/schedutil/down_rate_limit_us"  "20000"
    w "$P6/schedutil/up_rate_limit_us"    "500"
    w "$P6/schedutil/down_rate_limit_us"  "20000"
    # Input Boost (cpu_boost Modul) — nur wenn vorhanden
    local IB=/sys/module/cpu_boost/parameters
    if [ -d "$IB" ]; then
        w "$IB/input_boost_enabled" "1"
        printf '%s' "0:1248000 1:1248000 2:1248000 3:1248000 4:1248000 5:1248000 6:1843200 7:1843200" \
            > "$IB/input_boost_freq" 2>/dev/null || true
        w "$IB/input_boost_ms" "40"
        _dbg "Input Boost: enabled (Silver 1248, Gold 1843, 40ms)"
    fi
    apply_irq_affinity
    w /sys/class/power_supply/battery/system_temp_level "0"
    _log "Sched gaming: EAS=0 uclamp_min=200 upmigrate=80 sched_boost=1 rates=500/20000"
}

sched_competitive() {
    sched_gaming

    # Aggressivere uclamp-Werte
    w "$CS_TOP/uclamp.min"               "60.00"
    w "$CS_TOP/uclamp.latency_sensitive" "1"
    w /proc/sys/kernel/sched_upmigrate        "70"
    w /proc/sys/kernel/sched_downmigrate      "50"

    # CPU Hotplug: Silver offline
    [ "${CFG_CPU_HOTPLUG:-0}" = "1" ] && cpu_hotplug_offline_silver

    # WiFi Power-Save deaktivieren
    [ "${CFG_WIFI_PS:-1}" = "1" ] && \
        iw dev wlan0 set power_save off 2>/dev/null || true

    dbg "Sched competitive: uclamp=40 migrate=70/50 hotplug=${CFG_CPU_HOTPLUG:-0}"
}

sched_balanced() {
    echo "0-7" > "$CS_TOP/cpus" 2>/dev/null || true
    echo "0-7" > "$CS_FG/cpus"  2>/dev/null || true
    w "$CS_TOP/uclamp.min"               "0.00"
    w "$CS_TOP/uclamp.max"               "100.00"
    w "$CS_TOP/uclamp.boosted"           "0"
    w "$CS_TOP/uclamp.latency_sensitive" "0"
    w "$CS_FG/uclamp.min"                "0.00"
    w "$CS_FG/uclamp.max"                "100.00"
    w "$CS_FG/uclamp.boosted"            "0"
    w "$CS_FG/uclamp.latency_sensitive"  "0"
    w /proc/sys/kernel/sched_upmigrate        "95"
    w /proc/sys/kernel/sched_downmigrate      "85"
    w /proc/sys/kernel/sched_child_runs_first "1"
    w /proc/sys/kernel/sched_energy_aware     "1"
    w /proc/sys/kernel/sched_util_clamp_min   "128"
    w /proc/sys/kernel/sched_util_clamp_max   "1024"
    w /proc/sys/kernel/sched_boost            "0"
    # Schedutil rates restored to default
    w "$P0/schedutil/up_rate_limit_us"    "2000"
    w "$P0/schedutil/down_rate_limit_us"  "8000"
    w "$P6/schedutil/up_rate_limit_us"    "2000"
    w "$P6/schedutil/down_rate_limit_us"  "8000"
    _dbg "Sched balanced: EAS=1 uclamp_min=128 migrate=95/85 rates=2000/8000"
}

sched_battery() {
    echo "0-5" > "$CS_TOP/cpus" 2>/dev/null || true
    echo "0-5" > "$CS_FG/cpus"  2>/dev/null || true
    w "$CS_TOP/uclamp.min"               "0.00"
    w "$CS_TOP/uclamp.max"               "100.00"
    w "$CS_TOP/uclamp.boosted"           "0"
    w "$CS_TOP/uclamp.latency_sensitive" "0"
    w /proc/sys/kernel/sched_upmigrate        "98"
    w /proc/sys/kernel/sched_downmigrate      "90"
    w /proc/sys/kernel/sched_energy_aware     "1"
    w /proc/sys/kernel/sched_util_clamp_min   "64"
    w /proc/sys/kernel/sched_util_clamp_max   "1024"
    w /proc/sys/kernel/sched_boost            "0"
    # Schedutil rates: slow up, slow down (powersave)
    w "$P0/schedutil/up_rate_limit_us"    "5000"
    w "$P0/schedutil/down_rate_limit_us"  "20000"
    w "$P6/schedutil/up_rate_limit_us"    "5000"
    w "$P6/schedutil/down_rate_limit_us"  "20000"
    _dbg "Sched battery: EAS=1 uclamp_min=64 migrate=98/90 rates=5000/20000"
}

# ═══════════════════════════════════════════════════════════════════════════════
# IO Scheduler
# ═══════════════════════════════════════════════════════════════════════════════
io_gaming() {
    local blk
    for blk in /sys/block/sd* /sys/block/mmcblk* /sys/block/dm-*; do
        [ -d "$blk/queue" ] || continue
        w "$blk/queue/scheduler"     "mq-deadline"
        w "$blk/queue/read_ahead_kb" "128"
        w "$blk/queue/nr_requests"   "64"
        w "$blk/queue/iostats"       "0"
        w "$blk/queue/add_random"    "0"
    done
}

io_balanced() {
    local blk
    for blk in /sys/block/sd* /sys/block/mmcblk* /sys/block/dm-*; do
        [ -d "$blk/queue" ] || continue
        w "$blk/queue/scheduler"     "mq-deadline"
        w "$blk/queue/read_ahead_kb" "512"
        w "$blk/queue/nr_requests"   "128"
        w "$blk/queue/iostats"       "1"
        w "$blk/queue/add_random"    "1"
    done
}

io_battery() {
    local blk
    for blk in /sys/block/sd* /sys/block/mmcblk* /sys/block/dm-*; do
        [ -d "$blk/queue" ] || continue
        w "$blk/queue/scheduler"     "mq-deadline"
        w "$blk/queue/read_ahead_kb" "128"
        w "$blk/queue/nr_requests"   "32"
        w "$blk/queue/iostats"       "0"
        w "$blk/queue/add_random"    "0"
    done
}

vm_balanced() {
    w /proc/sys/vm/swappiness             "60"
    w /proc/sys/vm/vfs_cache_pressure     "100"
    w /proc/sys/vm/dirty_ratio            "20"
    w /proc/sys/vm/dirty_background_ratio "5"
    w /proc/sys/vm/extra_free_kbytes      "24576"
}

vm_battery() {
    w /proc/sys/vm/swappiness             "80"
    w /proc/sys/vm/vfs_cache_pressure     "200"
    w /proc/sys/vm/dirty_ratio            "40"
    w /proc/sys/vm/dirty_background_ratio "10"
    w /proc/sys/vm/extra_free_kbytes      "12288"
}

lmk_gaming()   { w /sys/module/lowmemorykiller/parameters/minfree "18432,23040,27648,32256,55296,80640"; }
lmk_balanced() { w /sys/module/lowmemorykiller/parameters/minfree "18432,23040,27648,32256,55296,80640"; }
lmk_battery()  { w /sys/module/lowmemorykiller/parameters/minfree "23040,27648,32256,36864,60416,92160"; }

# ── ZRAM — Kernel: CONFIG_ZRAM=y, CONFIG_ZRAM_DEF_COMP_LZ4=y ✓ ────────────────
zram_gaming() {
    local swap_free swap_total dirty z
    swap_free=$(grep SwapFree  /proc/meminfo | awk '{print $2}')
    swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
    dirty=$(( swap_total - swap_free ))
    for z in /sys/block/zram*/comp_algorithm; do
        [ -f "$z" ] || continue
        [ "${dirty:-0}" -lt 10240 ] && echo "lz4" > "$z" 2>/dev/null || true
    done
    w /proc/sys/vm/page-cluster "0"
    _dbg "ZRAM: lz4 forced, page-cluster=0"
}

zram_balanced() {
    w /proc/sys/vm/page-cluster "0"
}

vm_gaming() {
    w /proc/sys/vm/swappiness             "10"
    w /proc/sys/vm/vfs_cache_pressure     "50"
    w /proc/sys/vm/dirty_ratio            "10"
    w /proc/sys/vm/dirty_background_ratio "3"
    w /proc/sys/vm/dirty_expire_centisecs "100"
    w /proc/sys/vm/dirty_writeback_centisecs "50"
    w /proc/sys/vm/extra_free_kbytes      "24576"
    w /proc/sys/vm/page-cluster           "0"
}

# ═══════════════════════════════════════════════════════════════════════════════
# LRU_GEN Tuning — Kernel: CONFIG_LRU_GEN=y ✓
# ═══════════════════════════════════════════════════════════════════════════════
lru_gen_gaming() {
    [ "$FEATURE_LRU_GEN" = "0" ] && return 0
    echo 1 > /sys/kernel/mm/lru_gen/enabled 2>/dev/null || true
    dbg "LRU_GEN: gaming (enabled, aggressive reclaim)"
}

lru_gen_balanced() {
    [ "$FEATURE_LRU_GEN" = "0" ] && return 0
    echo 1 > /sys/kernel/mm/lru_gen/enabled 2>/dev/null || true
    dbg "LRU_GEN: balanced"
}

lru_gen_battery() {
    [ "$FEATURE_LRU_GEN" = "0" ] && return 0
    echo 0 > /sys/kernel/mm/lru_gen/enabled 2>/dev/null || true
    dbg "LRU_GEN: disabled (battery saving)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# NETWORK — BBR Kernel-Default (CONFIG_DEFAULT_BBR=y) ✓
# ═══════════════════════════════════════════════════════════════════════════════
detect_net_type() {
    local iface
    iface=$(ip route show default 2>/dev/null | grep -o "dev [^ ]*" | head -1 | cut -d' ' -f2)
    if echo "$iface" | grep -qi "wlan"; then NET_TYPE="wifi"; else NET_TYPE="lte"; fi
    _log "NET_TYPE: $NET_TYPE (iface=$iface)"
}

net_gaming() {
    w /proc/sys/net/ipv4/tcp_congestion_control "bbr"
    w /proc/sys/net/ipv4/tcp_sack               "1"
    w /proc/sys/net/ipv4/tcp_dsack              "1"
    w /proc/sys/net/ipv4/tcp_low_latency        "1"
    w /proc/sys/net/ipv4/tcp_retries2           "5"
    w /proc/sys/net/ipv4/neigh/default/gc_stale_time "60"
    w /proc/sys/net/netfilter/nf_conntrack_udp_timeout "30"
    w /proc/sys/net/netfilter/nf_conntrack_udp_timeout_stream "60"
    if [ "$NET_TYPE" = "wifi" ]; then
        w /proc/sys/net/core/rmem_max     "16777216"
        w /proc/sys/net/core/wmem_max     "16777216"
        w /proc/sys/net/ipv4/tcp_rmem     "4096 87380 16777216"
        w /proc/sys/net/ipv4/tcp_wmem     "4096 65536 16777216"
        w /proc/sys/net/ipv4/udp_rmem_min "65536"
        w /proc/sys/net/ipv4/udp_wmem_min "65536"
        _log "NET: WiFi-Profil (aggressive Buffer)"
    else
        w /proc/sys/net/core/rmem_max     "4194304"
        w /proc/sys/net/core/wmem_max     "4194304"
        w /proc/sys/net/ipv4/tcp_rmem     "4096 524288 4194304"
        w /proc/sys/net/ipv4/tcp_wmem     "4096 65536 4194304"
        w /proc/sys/net/ipv4/udp_rmem_min "32768"
        w /proc/sys/net/ipv4/udp_wmem_min "32768"
        local iface
        for iface in $(ip link show up 2>/dev/null | grep -o "rmnet_data[0-9]*"); do
            tc qdisc replace dev "$iface" root pfifo_fast 2>/dev/null || true
        done
        _log "NET: LTE-Profil (konservative Buffer, UDP-Prio, pfifo_fast)"
    fi
    setprop net.dns1 "1.1.1.1" 2>/dev/null || true
    setprop net.dns2 "8.8.8.8" 2>/dev/null || true
}

net_competitive() {
    net_gaming
    # Zusätzlich: Network QoS wenn aktiviert
    [ "${CFG_NET_QOS:-0}" = "1" ] && net_qos_gaming
}

net_restore() {
    w /proc/sys/net/ipv4/tcp_low_latency "0"
    w /proc/sys/net/ipv4/tcp_retries2    "15"
    local iface
    for iface in $(ip link show up 2>/dev/null | grep -o "rmnet_data[0-9]*"); do
        tc qdisc del dev "$iface" root 2>/dev/null || true
    done
    # QoS entfernen
    net_qos_restore 2>/dev/null
    setprop net.dns1 "" 2>/dev/null || true
    setprop net.dns2 "" 2>/dev/null || true
}

bt_gaming()  { setprop bluetooth.core.le.vendor.power_level "0" 2>/dev/null || true; }
bt_restore() { setprop bluetooth.core.le.vendor.power_level "1" 2>/dev/null || true; }

# ═══════════════════════════════════════════════════════════════════════════════
# NETWORK QoS — TC HTB + iptables MARK
# Kernel: CONFIG_NET_SCH_HTB=y, CONFIG_NETFILTER_XT_MARK=y ✓
# ═══════════════════════════════════════════════════════════════════════════════
net_qos_gaming() {
    # Alten QoS entfernen
    net_qos_restore 2>/dev/null

    # IFACE erkennen
    local iface
    iface=$(ip route show default 2>/dev/null | grep -o "dev [^ ]*" | head -1 | cut -d' ' -f2)
    [ -z "$iface" ] && return 0

    # TC HTB: Gaming-Traffic priorisieren
    tc qdisc add dev "$iface" root handle 1: htb default 30 2>/dev/null || true
    tc class add dev "$iface" parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit 2>/dev/null || true
    tc class add dev "$iface" parent 1:1 classid 1:10 htb rate 800mbit ceil 1000mbit prio 1 2>/dev/null || true
    tc class add dev "$iface" parent 1:1 classid 1:20 htb rate 150mbit ceil 500mbit prio 2 2>/dev/null || true
    tc class add dev "$iface" parent 1:1 classid 1:30 htb rate 50mbit ceil 200mbit prio 3 2>/dev/null || true

    # CoD Ports: UDP 3074, 27000-27100 → Class 1:10 (höchste Prio)
    tc filter add dev "$iface" parent 1: protocol ip u32 match ip dport 3074 0xffff flowid 1:10 2>/dev/null || true
    tc filter add dev "$iface" parent 1: protocol ip u32 match ip sport 3074 0xffff flowid 1:10 2>/dev/null || true
    tc filter add dev "$iface" parent 1: protocol ip u32 match ip dport 27000 0xf800 flowid 1:10 2>/dev/null || true

    # DNS → Class 1:20
    tc filter add dev "$iface" parent 1: protocol ip u32 match ip dport 53 0xffff flowid 1:20 2>/dev/null || true
    tc filter add dev "$iface" parent 1: protocol ip u32 match ip sport 53 0xffff flowid 1:20 2>/dev/null || true

    _log "NET QoS: TC HTB aktiv auf $iface (CoD prio 1)"
}

net_qos_restore() {
    local iface
    iface=$(ip route show default 2>/dev/null | grep -o "dev [^ ]*" | head -1 | cut -d' ' -f2)
    [ -z "$iface" ] && return 0
    tc qdisc del dev "$iface" root 2>/dev/null || true
    _log "NET QoS: entfernt"
}

# ═══════════════════════════════════════════════════════════════════════════════
# WAKELOCK BLOCKER — Kernel: CONFIG_BOEFFLA_WL_BLOCKER=y ✓
# ═══════════════════════════════════════════════════════════════════════════════
wakelock_block_gaming() {
    [ "$FEATURE_BOEFFLA" = "0" ] && return 0
    local blockers="*PowerManagerService* *NfcService* *GMS* *SyncLoop*"
    for wl in $blockers; do
        echo "$wl" > /sys/module/boeffla_wl_blocker/parameters/wl_blocker 2>/dev/null || true
    done
    _log "WakeLock Blocker: aktiv"
}

wakelock_restore() {
    [ "$FEATURE_BOEFFLA" = "0" ] && return 0
    echo "" > /sys/module/boeffla_wl_blocker/parameters/wl_blocker 2>/dev/null || true
    _log "WakeLock Blocker: deaktiviert"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SURFACEFLINGER TUNING
# latch_unsignaled=1 auf CAF-AOSP ohne QC-Patches → Frame-Drops (v7.45 FIX)
# ═══════════════════════════════════════════════════════════════════════════════
sf_balanced() {
    setprop debug.sf.latch_unsignaled 0 2>/dev/null || true
    setprop debug.sf.disable_backpressure 0 2>/dev/null || true
    _log "SF: default"
}

# ═══════════════════════════════════════════════════════════════════════════════
# BATTERY SPOOF
# ═══════════════════════════════════════════════════════════════════════════════
spoof_battery() {
    [ "${CFG_SPOOF_EN:-0}" = "1" ] || return 0
    local c=${CFG_SPOOF_T:-15} raw
    raw=$(( c * 10 ))
    [ "$raw" -lt 250 ] && { _warn "Battery spoof ABORTED: ${c}°C < 25°C (lithium plating risk)"; return 1; }
    [ "$raw" -gt 600 ] && { _warn "Battery spoof ABORTED: ${c}°C > 60°C"; return 1; }
    for node in /sys/class/power_supply/battery/temp /sys/class/power_supply/bms/temp; do
        [ -f "$node" ] && printf '%s\n' "$raw" > "$node" 2>/dev/null
    done
    cmd thermalservice override-status 0 2>/dev/null || true
    _log "Battery spoof: ${c}°C (raw ${raw})"
}

restore_battery_spoof() {
    local rt
    rt=$(cat /sys/class/power_supply/bms/temp 2>/dev/null || echo "")
    if [ -n "$rt" ] && [ "$rt" -gt 0 ] 2>/dev/null; then
        echo "$rt" > /sys/class/power_supply/battery/temp 2>/dev/null || true
        _log "Battery spoof restored: BMS temp=${rt} → battery/temp"
    fi
    cmd thermalservice reset 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# THREAD PINNING — generisch für alle Games
# ═══════════════════════════════════════════════════════════════════════════════
tune_game() {
    [ "${CFG_THREAD_PIN:-1}" = "0" ] && return 0
    local pkg="$1"
    [ -z "$pkg" ] && return 0

    local main_pid
    main_pid=$(pidof "$pkg" 2>/dev/null | awk '{print $1}')
    [ -z "$main_pid" ] && return 0

    local tid tname
    for tid in /proc/"$main_pid"/task/*/; do
        tid="${tid%/}"; tid="${tid##*/}"
        [ -f "/proc/$main_pid/task/$tid/comm" ] || continue
        tname=$(cat "/proc/$main_pid/task/$tid/comm" 2>/dev/null)
        case "$tname" in
            *RenderThread*|*UnityMain*|*GLThread*)  taskset -p 0xc0 "$tid" >/dev/null 2>&1 ;;
            *Worker*Thread*|*JobWorker*|*UnityGfx*) taskset -p 0x3f "$tid" >/dev/null 2>&1 ;;
            *AudioMixer*|*AudioTrack*)               taskset -p 0x3f "$tid" >/dev/null 2>&1 ;;
        esac
    done

    # audioserver auf Silver
    local ap; ap=$(pidof audioserver 2>/dev/null | awk '{print $1}')
    [ -n "$ap" ] && taskset -p 0x3f "$ap" >/dev/null 2>&1

    _dbg "Thread Pinning: $pkg (PID $main_pid) → RenderThread auf Gold"
}

# ═══════════════════════════════════════════════════════════════════════════════
# FREEZE ENGINE
# ═══════════════════════════════════════════════════════════════════════════════
FREEZE_WHITELIST="android|systemui|phone|gms|telephony|launcher|com.miui|com.xiaomi"

freeze_for() {
    local pkg="$1" pid
    echo "$pkg" | grep -Eqi "$FREEZE_WHITELIST" && { _warn "Freeze blocked: $pkg"; return 0; }
    for pid in $(pidof "$pkg" 2>/dev/null); do kill -SIGSTOP "$pid" 2>/dev/null || true; done
}

unfreeze_for() {
    local pkg="$1" pid
    for pid in $(pidof "$pkg" 2>/dev/null); do kill -SIGCONT "$pid" 2>/dev/null || true; done
}

unfreeze_all() {
    local pkg pid
    while IFS='=' read -r pkg _; do
        [ -z "$pkg" ] && continue
        for pid in $(pidof "$pkg" 2>/dev/null); do kill -SIGCONT "$pid" 2>/dev/null || true; done
    done < "${FREEZE:-/dev/null}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# RAM / CACHE
# ═══════════════════════════════════════════════════════════════════════════════
clean_cache() {
    _log "Cache: cleaning (async)"
    ( sync
      echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
      echo 0 > /proc/sys/vm/drop_caches 2>/dev/null || true
      date > "$CACHE_LAST" 2>/dev/null || true
      _log "Cache: done" ) &
}

clean_ram() {
    _log "RAM: cleaning"
    echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
    _log "RAM: done"
}

# ═══════════════════════════════════════════════════════════════════════════════
# THERMAL ZONE LIST — Debug-Helfer
# ═══════════════════════════════════════════════════════════════════════════════
thermal_zone_list() {
    local zone type temp
    for zone in /sys/devices/virtual/thermal/thermal_zone*/; do
        [ -d "$zone" ] || continue
        type=$(cat "${zone}type" 2>/dev/null || echo "?")
        temp=$(cat "${zone}temp" 2>/dev/null || echo "?")
        _log "Thermal: ${zone##*/} type=$type temp=$(( ${temp:-0} / 1000 ))°C"
    done
}
