#!/system/bin/sh
MODDIR=${0%/*}
CONFIG="$MODDIR/config/settings.conf"
PERAPP="$MODDIR/config/per_app.conf"
LOG="$MODDIR/config/service.log"
PROFILE="$MODDIR/config/active_profile"
CACHE_TRIGGER="$MODDIR/config/clean_cache_now"
CACHE_LAST="$MODDIR/config/cache_last_cleaned"
RAM_TRIGGER="$MODDIR/config/clean_ram_now"
DATA="$MODDIR/webroot/data.txt"

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 10

log_msg() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG"; }
cfg()     { grep "^${1}=" "$CONFIG" 2>/dev/null | cut -d= -f2; }
trim_log() {
    [ "$(wc -l < "$LOG" 2>/dev/null)" -gt 200 ] && \
        tail -150 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}

# ═══════════════════════════════════════════════════════════════════════════════
# CPU: Snapdragon 730 (SM7150) — Redmi Note 12 Pro (sweet2)
# Silver cpu0-5: Kryo 470 Silver (A55-based), max 1804 MHz
# Gold   cpu6-7: Kryo 470 Gold   (A76-based), max 2304 MHz
# ═══════════════════════════════════════════════════════════════════════════════
set_cpu() {
    # $1=governor $2=silver_min $3=gold_min $4=silver_max $5=gold_max
    for i in 0 1 2 3 4 5; do
        echo "$1" > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor 2>/dev/null
        echo "$2" > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_min_freq  2>/dev/null
        [ -n "$4" ] && echo "$4" > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_max_freq 2>/dev/null
    done
    for i in 6 7; do
        echo "$1" > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor 2>/dev/null
        echo "$3" > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_min_freq  2>/dev/null
        [ -n "$5" ] && echo "$5" > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_max_freq 2>/dev/null
    done
}

tune_schedutil() {
    # $1=silver_hispeed_load $2=gold_hispeed_load $3=silver_hispeed_freq $4=gold_hispeed_freq
    #
    # Kernel 4.14 CAF (real kernel, spoofed as 6.12):
    # schedutil tunables live at the POLICY level, not per-cpu:
    #   /sys/devices/system/cpu/cpufreq/policy0/schedutil/  — Silver cluster
    #   /sys/devices/system/cpu/cpufreq/policy6/schedutil/  — Gold cluster
    # The per-cpu path /sys/devices/system/cpu/cpuN/cpufreq/schedutil/
    # does NOT exist on 4.14 CAF and writes silently fail.

    # Silver cluster — policy0 (cpu0-5)
    SU0=/sys/devices/system/cpu/cpufreq/policy0/schedutil
    if [ -d "$SU0" ]; then
        echo "$1"   > "$SU0/hispeed_load"       2>/dev/null
        echo "$3"   > "$SU0/hispeed_freq"       2>/dev/null
        echo "4000" > "$SU0/up_rate_limit_us"   2>/dev/null
        echo "16000"> "$SU0/down_rate_limit_us" 2>/dev/null
        log_msg "Schedutil Silver: hispeed_load=$1 hispeed_freq=$3"
    fi

    # Gold cluster — policy6 (cpu6-7)
    SU6=/sys/devices/system/cpu/cpufreq/policy6/schedutil
    if [ -d "$SU6" ]; then
        echo "$2"   > "$SU6/hispeed_load"       2>/dev/null
        echo "$4"   > "$SU6/hispeed_freq"       2>/dev/null
        echo "2000" > "$SU6/up_rate_limit_us"   2>/dev/null
        echo "8000" > "$SU6/down_rate_limit_us" 2>/dev/null
        log_msg "Schedutil Gold:   hispeed_load=$2 hispeed_freq=$4"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# GPU: Adreno 618 (SM7150)
# ═══════════════════════════════════════════════════════════════════════════════
GPU=/sys/class/kgsl/kgsl-3d0

set_gpu_balanced() {
    echo "msm-adreno-tz" > $GPU/devfreq/governor 2>/dev/null
    echo 0 > $GPU/force_clk_on 2>/dev/null
    echo 1 > $GPU/bus_split     2>/dev/null
    echo 0 > $GPU/max_pwrlevel  2>/dev/null
    echo 5 > $GPU/min_pwrlevel  2>/dev/null
}
set_gpu_gaming() {
    echo "msm-adreno-tz" > $GPU/devfreq/governor 2>/dev/null  # let it scale, not pinned
    echo 1 > $GPU/force_clk_on  2>/dev/null
    echo 0 > $GPU/bus_split      2>/dev/null
    echo 0 > $GPU/max_pwrlevel   2>/dev/null  # allow full burst
    echo 3 > $GPU/min_pwrlevel   2>/dev/null  # sustained floor ~70%, reduces heat
    echo 257000000 > $GPU/devfreq/min_freq 2>/dev/null
}
set_gpu_battery() {
    echo "powersave" > $GPU/devfreq/governor 2>/dev/null
    echo 0 > $GPU/force_clk_on  2>/dev/null
    echo 1 > $GPU/bus_split      2>/dev/null
    echo 5 > $GPU/min_pwrlevel   2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# I/O
# ═══════════════════════════════════════════════════════════════════════════════
set_io_balanced() {
    for q in /sys/block/*/queue/scheduler; do
        echo "cfq" > "$q" 2>/dev/null || echo "bfq" > "$q" 2>/dev/null || true
    done
    echo 512 > /sys/block/mmcblk0/queue/read_ahead_kb 2>/dev/null || true
    echo 0   > /sys/block/mmcblk0/queue/add_random    2>/dev/null || true
}
set_io_gaming() {
    for q in /sys/block/*/queue/scheduler; do
        echo "mq-deadline" > "$q" 2>/dev/null || \
        echo "deadline"    > "$q" 2>/dev/null || true
    done
    echo 2048 > /sys/block/mmcblk0/queue/read_ahead_kb 2>/dev/null || true
    echo 64   > /sys/block/mmcblk0/queue/nr_requests   2>/dev/null || true
    echo 0    > /sys/block/mmcblk0/queue/add_random    2>/dev/null || true
}
set_io_battery() {
    for q in /sys/block/*/queue/scheduler; do
        echo "cfq" > "$q" 2>/dev/null || echo "bfq" > "$q" 2>/dev/null || true
    done
    echo 128 > /sys/block/mmcblk0/queue/read_ahead_kb 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# ZRAM / MEMORY (sweet2 — 8GB RAM, kernel 4.14 CAF)
# NOTE: zstd was NOT mainlined until kernel 5.1.
#       4.14 CAF supports lz4 and lzo only — use lz4 directly.
# NOTE: /proc/sys/vm/extra_free_kbytes does NOT exist on 4.14 CAF kernels.
#       Writes to it silently fail — removed entirely.
# ═══════════════════════════════════════════════════════════════════════════════
set_zram_gaming() {
    # lz4 — best latency/ratio on 4.14 CAF Cortex-A55
    for z in /sys/block/zram*/comp_algorithm; do
        [ -f "$z" ] || continue
        echo "lz4" > "$z" 2>/dev/null && log_msg "ZRAM: lz4 (gaming)" || \
        log_msg "ZRAM: comp_algorithm write failed"
    done
    # page-cluster=0: no read-ahead on swap — critical for ZRAM latency
    echo 0   > /proc/sys/vm/page-cluster        2>/dev/null
    # Keep filesystem dentries/inodes cached longer during gaming
    echo 50  > /proc/sys/vm/vfs_cache_pressure  2>/dev/null
}

set_zram_balanced() {
    echo 0   > /proc/sys/vm/page-cluster        2>/dev/null
    echo 100 > /proc/sys/vm/vfs_cache_pressure  2>/dev/null
}

set_zram_battery() {
    echo 0   > /proc/sys/vm/page-cluster        2>/dev/null
    echo 200 > /proc/sys/vm/vfs_cache_pressure  2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# LMKD — Low Memory Killer tuning (sweet2 8GB)
# minfree values: 6 thresholds in pages (1 page = 4KB)
# Default Android values are too conservative for 8GB gaming use
# ═══════════════════════════════════════════════════════════════════════════════
set_lmk_gaming() {
    # Keep more RAM free for the game — kill background apps earlier
    # Thresholds: foreground/visible/secondary_server/hidden/content/empty
    echo "2048,3072,4096,6144,7168,8192" > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null || true
    # Higher score_adj means kill less important things first
    echo "0,100,200,300,900,906" > /sys/module/lowmemorykiller/parameters/adj 2>/dev/null || true
}

set_lmk_balanced() {
    echo "4096,5120,6144,7168,8192,9216" > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null || true
    echo "0,100,200,300,900,906"         > /sys/module/lowmemorykiller/parameters/adj     2>/dev/null || true
}

set_lmk_battery() {
    # More aggressive — kill background faster to save power
    echo "8192,10240,12288,14336,16384,20480" > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null || true
    echo "0,100,200,300,900,906"              > /sys/module/lowmemorykiller/parameters/adj     2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# THERMAL — Selective zone disable (SM7150/sweet2 specific)
#
# Strategy: disable ONLY CPU/GPU performance zones so they stop throttling gaming.
# Hardware-safety zones are LEFT ENABLED intentionally:
#   conn_therm      -> hits 94°C under load; HW interrupt at ~95°C freezes buttons
#   charger_therm   -> battery safety
#   battery/bms     -> battery safety
#   quiet_therm/xo_therm/pa_therm -> board-level safety
#   touch/tsp/ts*   -> touch controller
#
# No chmod on any sysfs node - that hits touch interrupt handlers on SM7150.
# ═══════════════════════════════════════════════════════════════════════════════
disable_thermal_safe() {
    for zone in /sys/devices/virtual/thermal/thermal_zone*; do
        type=$(cat "$zone/type" 2>/dev/null)
        [ -z "$type" ] && continue

        # Always keep enabled: touch, connectivity, power/battery, board safety
        echo "$type" | grep -qiE "touch|tsp|ts[0-9]|conn_therm|charger_therm|battery|bms|qcom-bms|quiet_therm|xo_therm|pa_therm|pm6150-tz|pm6150l-tz|^soc$" && continue

        # Only disable known CPU/GPU/media performance zones
        echo "$type" | grep -qiE "cpu|gpu|aoss|audio|ddr|q6.hvx|camera|mdm|npu|video|ibat|cpuss|gpuss" || continue

        echo "disabled" > "$zone/mode"      2>/dev/null
        echo "0"        > "$zone/thm_enable" 2>/dev/null
    done
    log_msg "Thermal: selective-disabled (conn/charger/battery zones active)"
}

restore_thermal() {
    # Re-enable all zones that were selectively disabled
    for zone in /sys/devices/virtual/thermal/thermal_zone*; do
        echo "enabled" > "$zone/mode"      2>/dev/null
        echo "1"       > "$zone/thm_enable" 2>/dev/null
    done
    start vendor.thermal-engine 2>/dev/null
    log_msg "Thermal: restored"
}

# ═══════════════════════════════════════════════════════════════════════════════
# BATTERY SPOOFING (SM7150/sweet2)
# Reports a low battery temp to the thermal policy engine so the conn_therm
# hardware interrupt threshold (~95°C) is never triggered by policy escalation.
# This is what LickT does — spoof_val is read from config (default 1°C = 10 raw).
# Does NOT affect real battery protection — those zones stay hardware-guarded.
# ═══════════════════════════════════════════════════════════════════════════════
spoof_battery() {
    [ "$(cfg battery_spoof_enable)" = "1" ] || return 0
    SPOOF_C=$(cfg battery_spoof_temp)
    SPOOF_C=${SPOOF_C:-1}
    SPOOF_RAW=$(( SPOOF_C * 10 ))
    for node in /sys/class/power_supply/battery/temp \
                /sys/class/power_supply/bms/temp; do
        [ -f "$node" ] && echo "$SPOOF_RAW" > "$node" 2>/dev/null
    done
    cmd thermalservice override-status 0 2>/dev/null || true
    log_msg "Battery spoof: ${SPOOF_C}°C (raw ${SPOOF_RAW})"
}

restore_battery() {
    # Remove override — kernel will resume reading real hardware value
    cmd thermalservice reset 2>/dev/null || true
    log_msg "Battery spoof: restored"
}

# ═══════════════════════════════════════════════════════════════════════════════
# BYPASS POWER SUPPLY (sweet2 / MIUI HyperOS)
# During gaming, lower the bypass threshold so the charger powers the device
# directly instead of charging the battery — removes charging heat from the
# thermal budget and keeps conn_therm further from its HW cutoff.
# Threshold is stored in: /sys/class/power_supply/battery/input_suspend
# and via MIUI battery service prop: persist.vendor.battery.bypass_temp_thresh
# Default threshold on sweet2: 41°C — we lower to 35°C during gaming.
# ═══════════════════════════════════════════════════════════════════════════════
enable_bypass() {
    THRESH=$(cfg bypass_threshold)
    THRESH=${THRESH:-35}
    # Confirmed paths on sweet2 (via Termux):
    # persist.vendor.battery.bypass_temp_thresh=41 ✓
    # persist.sys.battery_bypass_supported=true ✓
    # /sys/class/power_supply/battery/input_suspend=0 ✓
    # resetprop writes to live system immediately (no reboot needed)
    resetprop persist.vendor.battery.bypass_temp_thresh "$THRESH" 2>/dev/null || \
        setprop persist.vendor.battery.bypass_temp_thresh "$THRESH" 2>/dev/null || true
    log_msg "Bypass power supply: threshold ${THRESH}°C (gaming mode)"
}

restore_bypass() {
    # Restore Xiaomi default threshold of 41°C
    resetprop persist.vendor.battery.bypass_temp_thresh "41" 2>/dev/null || \
        setprop persist.vendor.battery.bypass_temp_thresh "41" 2>/dev/null || true
    log_msg "Bypass power supply: restored (41°C)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROFILE
# ═══════════════════════════════════════════════════════════════════════════════
apply_balanced() {
    log_msg ">>> Profil wechselt zu: BALANCED"
    # Silver uncapped, Gold uncapped — let schedutil decide
    set_cpu "schedutil" "300000" "652000" "1804800" "2304000"
    tune_schedutil "80" "75" "1324800" "1612800"
    set_gpu_balanced
    set_io_balanced
    set_zram_balanced
    set_lmk_balanced
    sysctl -w vm.swappiness=15              2>/dev/null
    sysctl -w vm.dirty_ratio=20             2>/dev/null
    sysctl -w vm.dirty_background_ratio=5   2>/dev/null
    echo 0 > /proc/sys/kernel/sched_boost   2>/dev/null
    restore_thermal
    restore_battery
    restore_bypass
    restore_miui
    start logd                              2>/dev/null
    echo "balanced" > "$PROFILE"
}

apply_gaming() {
    log_msg ">>> Profil wechselt zu: GAMING"
    if [ "$(cfg aggressive_boost)" = "1" ]; then
        # Aggressive: performance governor, Gold pinned to ~70% min
        set_cpu "performance" "652000" "1612800" "1804800" "2304000"
    else
        # Normal: tuned schedutil — responsive without wasting power
        set_cpu "schedutil" "652000" "1113600" "1804800" "2304000"
        tune_schedutil "60" "50" "1324800" "1804800"
    fi
    set_gpu_gaming
    set_io_gaming
    set_zram_gaming
    set_lmk_gaming
    sysctl -w vm.swappiness=5               2>/dev/null
    sysctl -w vm.dirty_ratio=10             2>/dev/null
    sysctl -w vm.dirty_background_ratio=3   2>/dev/null
    echo 1 > /proc/sys/kernel/sched_boost   2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true
    sysctl -w net.core.rmem_max=16777216          2>/dev/null || true
    sysctl -w net.core.wmem_max=16777216          2>/dev/null || true
    stop logd 2>/dev/null || true
    if [ "$(cfg thermal_disable)" = "1" ]; then
        disable_thermal_safe
    else
        restore_thermal
    fi
    spoof_battery
    enable_bypass
    apply_miui_gaming
    echo "gaming" > "$PROFILE"
}

apply_battery() {
    log_msg ">>> Profil wechselt zu: BATTERY"
    # Cap Silver at 1324MHz, Gold at 1113MHz to save power
    set_cpu "powersave" "300000" "300000" "1324800" "1113600"
    set_gpu_battery
    set_io_battery
    set_zram_battery
    set_lmk_battery
    sysctl -w vm.swappiness=60              2>/dev/null
    sysctl -w vm.dirty_ratio=40             2>/dev/null
    sysctl -w vm.dirty_background_ratio=10  2>/dev/null
    echo 0 > /proc/sys/kernel/sched_boost   2>/dev/null
    restore_thermal
    restore_battery
    restore_bypass
    restore_miui
    start logd                              2>/dev/null
    echo "battery" > "$PROFILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# CACHE + RAM
# ═══════════════════════════════════════════════════════════════════════════════
do_clean_cache() {
    log_msg "Cache wird geleert..."
    find /data/data/*/cache/*           -delete 2>/dev/null
    find /data/data/*/code_cache/*      -delete 2>/dev/null
    find /data/user_de/*/*/cache/*      -delete 2>/dev/null
    find /data/user_de/*/*/code_cache/* -delete 2>/dev/null
    find /sdcard/Android/data/*/cache/* -delete 2>/dev/null
    sync
    date '+%d.%m.%Y %H:%M:%S' > "$CACHE_LAST"
    log_msg "Cache geleert"
}

do_clean_ram() {
    # Never drop caches during gaming — causes massive asset reload stutter
    if [ "$(cat "$PROFILE" 2>/dev/null)" = "gaming" ]; then
        log_msg "RAM cleaner: übersprungen (Gaming aktiv)"
        return 0
    fi
    log_msg "RAM wird bereinigt..."
    am kill-all 2>/dev/null || true
    sync
    echo 3 > /proc/sys/vm/drop_caches   2>/dev/null
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
    log_msg "RAM bereinigt"
}

# ═══════════════════════════════════════════════════════════════════════════════
# AUTO DETECTION
# Uses /proc/*/cmdline — pure kernel memory read, zero binder IPC.
# dumpsys activity was the original approach but blocks on the binder thread
# pool under gaming load, stalling the kernel input event subsystem and
# freezing touch + buttons while the game keeps running.
# ═══════════════════════════════════════════════════════════════════════════════
get_foreground_app() {
    # Read the top activity from the window focus file — no binder needed
    # /proc/<pid>/cmdline gives the package name directly for focused apps
    local focus_pid
    focus_pid=$(cat /proc/$(cat /sys/fs/cgroup/top-app/cgroup.procs 2>/dev/null \
        | head -1)/cmdline 2>/dev/null | tr -d '\0' | cut -d: -f1)
    if [ -n "$focus_pid" ]; then
        echo "$focus_pid"
        return
    fi
    # Fallback: read from window focus via /proc without dumpsys
    # Find the PID of the focused window via /dev/input + /proc link
    local pkg
    pkg=$(cat /proc/$(cat /sys/fs/cgroup/top-app/tasks 2>/dev/null \
        | head -1)/cmdline 2>/dev/null | tr '\0' '\n' | head -1)
    echo "${pkg:-}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# DATA.TXT
# ═══════════════════════════════════════════════════════════════════════════════
write_data() {
    # Spoofed kernel (shown by uname -r — may be faked by spoof module)
    KERNEL=$(uname -r 2>/dev/null || echo "?")
    # Real kernel — /proc/version is read directly from kernel memory, harder to spoof
    KERNEL_REAL=$(cat /proc/version 2>/dev/null | grep -oP 'Linux version \K[^ ]+' || echo "?")
    ANDROID=$(getprop ro.build.version.release 2>/dev/null || echo "?")
    SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo "?")
    BAT_L=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "?")
    BAT_S=$(cat /sys/class/power_supply/battery/status   2>/dev/null || echo "?")
    BAT_T_RAW=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo "0")
    BAT_T=$(awk "BEGIN{printf \"%.1f\", $BAT_T_RAW/10}")
    UT_RAW=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
    UT_H=$(( UT_RAW / 3600 ))
    UT_M=$(( (UT_RAW % 3600) / 60 ))
    ACTIVE=$(cat "$PROFILE" 2>/dev/null || echo "balanced")
    MANUAL_P=$(cat "$MODDIR/config/manual_profile" 2>/dev/null || echo "balanced")
    LAST_CLEAN=$(cat "$CACHE_LAST" 2>/dev/null || echo "")
    PING_VAL=$(cat "$MODDIR/config/ping.txt" 2>/dev/null || echo "")
    CACHE_KB=$(du -sk /data/data/*/cache /data/data/*/code_cache \
        /data/user_de/*/*/cache /sdcard/Android/data/*/cache 2>/dev/null \
        | awk '{s+=$1} END{print s+0}')
    MEM_TOTAL=$(grep MemTotal     /proc/meminfo | awk '{print $2}')
    MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    MEM_USED=$(( (MEM_TOTAL - MEM_AVAIL) / 1024 ))
    MEM_TOTAL_MB=$(( MEM_TOTAL / 1024 ))
    A=$(cfg auto_detection);        A=${A:-0}
    T=$(cfg thermal_disable);       T=${T:-0}
    B=$(cfg aggressive_boost);      B=${B:-0}
    C=$(cfg auto_cache);            C=${C:-0}
    SE=$(cfg battery_spoof_enable); SE=${SE:-0}
    ST=$(cfg battery_spoof_temp);   ST=${ST:-1}
    BP=$(cfg bypass_threshold);     BP=${BP:-35}
    MJ=$(cfg miui_joyose);          MJ=${MJ:-0}
    MGT=$(cfg miui_game_turbo);     MGT=${MGT:-0}
    MFF=$(cfg miui_freeform);       MFF=${MFF:-0}
    PERAPP_LINE=$(grep -v "^#" "$PERAPP" 2>/dev/null | grep "=" | tr '\n' '|')
    LOG_LINE=$(tail -30 "$LOG" 2>/dev/null | tr '\n' '\x01')
    {
        echo "kernel=$KERNEL"
        echo "kernel_real=$KERNEL_REAL"
        echo "android=Android $ANDROID (API $SDK)"
        echo "bat=${BAT_L}% - $BAT_S"
        echo "bat_temp=$BAT_T"
        echo "uptime=${UT_H}h ${UT_M}m"
        echo "profile=$ACTIVE"
        echo "manual_profile=$MANUAL_P"
        echo "pid=$$"
        echo "cache_kb=$CACHE_KB"
        echo "last_clean=$LAST_CLEAN"
        echo "ping=$PING_VAL"
        echo "ram_used=$MEM_USED"
        echo "ram_total=$MEM_TOTAL_MB"
        echo "conf_auto=$A"
        echo "conf_thermal=$T"
        echo "conf_boost=$B"
        echo "conf_autocache=$C"
        echo "conf_spoof_enable=$SE"
        echo "conf_spoof_temp=$ST"
        echo "conf_bypass_thresh=$BP"
        echo "conf_miui_joyose=$MJ"
        echo "conf_miui_game_turbo=$MGT"
        echo "conf_miui_freeform=$MFF"
        echo "perapp=$PERAPP_LINE"
        echo "log=$LOG_LINE"
    } > "${DATA}.tmp" && mv "${DATA}.tmp" "$DATA"
}

write_ping() {
    MS=$(ping -c 1 -W 2 1.1.1.1 2>/dev/null | \
         sed -n 's/.*time=\([0-9.]*\).*/\1/p')
    echo "${MS:-timeout}" > "$MODDIR/config/ping.txt"
}


# ═══════════════════════════════════════════════════════════════════════════════
# MIUI / HyperOS TWEAKS (separat — nur wenn vom Nutzer aktiviert)
# Alle MIUI-Tweaks sind optional und standardmäßig deaktiviert.
# Sie werden AUSSCHLIESSLICH über die Toggles in der WebUI gesteuert.
# ═══════════════════════════════════════════════════════════════════════════════
apply_miui_gaming() {
    # ── Joyose deaktivieren ────────────────────────────────────────────────────
    # Joyose ist MIUIs Power/Thermal-Management-Daemon — setzt Frequenzen zurück
    # und drosselt FPS. Im Gaming-Modus unterdrückt er den vollen CPU/GPU-Boost.
    if [ "$(cfg miui_joyose)" = "1" ]; then
        pm disable com.xiaomi.joyose 2>/dev/null || true
        am force-stop com.xiaomi.joyose 2>/dev/null || true
        log_msg "MIUI: Joyose deaktiviert"
    fi

    # ── Game Turbo aktivieren ──────────────────────────────────────────────────
    # Xiaomis nativer Gaming-Boost erhöht Priorität für den Vordergrund-Prozess
    # und reduziert App-Switching-Overhead.
    if [ "$(cfg miui_game_turbo)" = "1" ]; then
        setprop persist.sys.game_mode 1 2>/dev/null || true
        setprop sys.powerkeeper.game_status 1 2>/dev/null || true
        log_msg "MIUI: Game Turbo aktiviert"
    fi

    # ── Freeform Windows deaktivieren (Gaming) ─────────────────────────────────
    # Verhindert dass andere Apps im Freeform-Modus CPU/GPU-Zeit stehlen
    if [ "$(cfg miui_freeform)" = "1" ]; then
        settings put global enable_freeform_support 0 2>/dev/null || true
        log_msg "MIUI: Freeform deaktiviert (Gaming)"
    fi
}

restore_miui() {
    # Joyose wiederherstellen
    pm enable com.xiaomi.joyose 2>/dev/null || true
    setprop persist.sys.game_mode 0 2>/dev/null || true
    setprop sys.powerkeeper.game_status 0 2>/dev/null || true
    settings put global enable_freeform_support 1 2>/dev/null || true
    log_msg "MIUI: Tweaks restored"
}

# ═══════════════════════════════════════════════════════════════════════════════
# START
# ═══════════════════════════════════════════════════════════════════════════════
log_msg "BadazZ89 k6a Optimizer v4.0 gestartet (SD730/SM7150 — sweet2, kernel 4.14 CAF)"

# Initialize manual_profile if missing — prevents silent stuck-on-balanced bug
if [ ! -f "$MODDIR/config/manual_profile" ]; then
    echo "balanced" > "$MODDIR/config/manual_profile"
    log_msg "manual_profile initialisiert: balanced"
fi
write_ping &
apply_balanced
write_data

TICK=0
LAST_PROFILE="balanced"   # FIX: nicht leer — verhindert doppelten Log-Eintrag beim Start
LAST_APP_VAL=""

while true; do
    if [ -f "$CACHE_TRIGGER" ]; then
        rm -f "$CACHE_TRIGGER"
        do_clean_cache
        write_data  # Sofort nach Cache-Reinigung aktualisieren
    fi

    if [ -f "$RAM_TRIGGER" ]; then
        rm -f "$RAM_TRIGGER"
        do_clean_ram
        write_data  # Sofort nach RAM-Bereinigung aktualisieren
    fi

    if [ "$(cfg auto_cache)" = "1" ] && \
       [ $((TICK % 1200)) -eq 0 ] && [ $TICK -gt 0 ]; then
        KB=$(awk -F= '/^cache_kb/{print $2}' "$DATA" 2>/dev/null || echo 0)
        [ "${KB:-0}" -gt 1024000 ] && do_clean_cache
    fi

    # ── Profil bestimmen ───────────────────────────────────────────────────────
    if [ "$(cfg battery_saver)" = "1" ]; then
        TARGET="battery"
    elif [ "$(cfg auto_detection)" = "1" ]; then
        # Only poll every 5 ticks (15s) — reduces overhead during sustained gaming
        if [ $((TICK % 5)) -eq 0 ]; then
            APP=$(get_foreground_app)
            if [ -n "$APP" ] && [ "$APP" != "$LAST_APP_VAL" ]; then
                LAST_APP_VAL="$APP"
                PROF=$(grep "^${APP}=" "$PERAPP" 2>/dev/null | cut -d= -f2)
                [ -n "$PROF" ] && TARGET="$PROF" || TARGET="balanced"
            else
                TARGET="$LAST_PROFILE"
            fi
        else
            TARGET="$LAST_PROFILE"
        fi
    else
        # Manuelles Profil — IMMER aus manual_profile lesen
        TARGET=$(cat "$MODDIR/config/manual_profile" 2>/dev/null || echo "balanced")
    fi
    [ -z "$TARGET" ] && TARGET="balanced"

    # FIX: Profil bei JEDEM Wechsel anwenden, auch manuell gesetzt
    if [ "$TARGET" != "$LAST_PROFILE" ]; then
        log_msg "Profilwechsel: $LAST_PROFILE → $TARGET"
        case "$TARGET" in
            gaming)  apply_gaming  ;;
            battery) apply_battery ;;
            *)       apply_balanced;;
        esac
        LAST_PROFILE="$TARGET"
        write_data  # Sofort nach Profilwechsel aktualisieren
    fi

    TICK=$((TICK + 1))
    # Heartbeat log every 10 minutes so log shows daemon is alive
    [ $((TICK % 200)) -eq 0 ] && log_msg "♥ aktiv — Profil: $LAST_PROFILE (tick $TICK)"
    GAMING_NOW=$(cat "$PROFILE" 2>/dev/null)
    # During gaming: write_data every 60s instead of 30s, skip ping entirely
    if [ "$GAMING_NOW" = "gaming" ]; then
        [ $((TICK % 20)) -eq 0 ] && write_data
    else
        [ $((TICK % 10)) -eq 0 ] && write_data
        [ $((TICK % 20)) -eq 0 ] && write_ping &
    fi
    [ $((TICK % 50)) -eq 0 ] && trim_log
    sleep 3
done
