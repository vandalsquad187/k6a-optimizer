#!/system/bin/sh
# BadazZ89 k6a Optimizer — service.sh  v8.0
# ─────────────────────────────────────────────────────────────────────────────
# v7.10 Fix: Lock-File wird NACH boot_completed gesetzt, nicht davor.
#   v7.9 Bug: KernelSU startet service.sh mehrfach während Boot.
#   Zweite Instanz sah erste als "aktiv" (noch im Boot-Wait) und beendete sich.
#   Erste Instanz starb dann lautlos ohne Controller zu starten.
#   Fix: Boot-Wait zuerst, dann Lock — nur eine Instanz kommt durch.

MODDIR=${0%/*}
CTRL="$MODDIR/bin/k6a-controller"
LOG="$MODDIR/config/service.log"
CONF="$MODDIR/config/settings.conf"
LOCKFILE="$MODDIR/run/service.lock"

_log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG"; }

_rotate_log() {
    [ -f "$LOG" ] || return
    local size; size=$(wc -c < "$LOG" 2>/dev/null) || return
    [ "$size" -gt 204800 ] && mv "$LOG" "${LOG}.old"
}

_uptime_s() { cut -d. -f1 /proc/uptime 2>/dev/null || date +%s; }

mkdir -p "$MODDIR/run" "$MODDIR/config"
_rotate_log

# ── Boot-Delay aus Config ─────────────────────────────────────────────────────
BOOT_DELAY=$(grep "^boot_delay=" "$CONF" 2>/dev/null | cut -d= -f2)
case "$BOOT_DELAY" in ''|*[!0-9]*) BOOT_DELAY=8 ;; esac
[ "$BOOT_DELAY" -lt 3  ] && BOOT_DELAY=3
[ "$BOOT_DELAY" -gt 60 ] && BOOT_DELAY=60

# ── Boot-Wait ZUERST — dann Lock ──────────────────────────────────────────────
# FIX v7.10: Lock erst nach Boot damit mehrfache KernelSU-Starts kein Problem
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done

_ready_wait=0
until [ -d /sys/class/thermal ] && [ -d /sys/devices/system/cpu/cpufreq ]; do
    sleep 1; _ready_wait=$(( _ready_wait + 1 ))
    [ "$_ready_wait" -ge 30 ] && break
done
[ "$_ready_wait" -gt 0 ] && _log "Ready-State: ${_ready_wait}s gewartet"

sleep "$BOOT_DELAY"
_rotate_log

# ── Multi-Instance Lock — nach Boot-Wait ──────────────────────────────────────
if [ -f "$LOCKFILE" ]; then
    _old_pid=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$_old_pid" ] && [ -d "/proc/$_old_pid" ]; then
        _log "WARN: service.sh bereits aktiv (PID $_old_pid) — beende"
        exit 0
    fi
    rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"
_HC_PID=""; _WD_PID=""
_cleanup() {
    [ -n "$_HC_PID" ] && kill "$_HC_PID" 2>/dev/null || true
    [ -n "$_WD_PID" ] && kill "$_WD_PID" 2>/dev/null || true
    rm -f "$LOCKFILE"
}
trap '_cleanup; exit' EXIT INT TERM

# ── Controller-Check ──────────────────────────────────────────────────────────
[ -x "$CTRL" ] || {
    _log "ERR: k6a-controller nicht gefunden oder nicht ausführbar"
    exit 1
}

_log "k6a service.sh v8.0: starte k6a-controller"

# ── Health-Check: PID-Verifikation nach Start ─────────────────────────────────
_health_check() {
    sleep 5
    local pid
    pid=$(cat "$MODDIR/run/controller.pid" 2>/dev/null)
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
        _log "Health-Check: OK — controller PID $pid alive"
    else
        _log "Health-Check: FAIL — controller PID $pid not found"
    fi
}
_health_check & _HC_PID=$!

# ── Thermal Crash Watchdog — stellt Thermal-Schutz wieder her wenn Controller stirbt
_thermal_watchdog() {
    local state_file="$MODDIR/config/active_profile"
    LOG_FILE="$LOG"
    while true; do
        sleep 5
        local ctrl_pid
        ctrl_pid=$(cat "$MODDIR/run/controller.pid" 2>/dev/null)
        if [ -n "$ctrl_pid" ] && ! [ -d "/proc/$ctrl_pid" ]; then
            local profile
            profile=$(cat "$state_file" 2>/dev/null)
            case "$profile" in
                cooking)
                    _log "WATCHDOG: Controller tot ($profile) → restore thermal"
                    . "$MODDIR/bin/k6a-lib.sh"
                    thermal_trips_restore
                    thermal_restore_daemons
                    _log "WATCHDOG: Thermal-Schutz wiederhergestellt"
                    ;;
            esac
        fi
    done
}
_thermal_watchdog & _WD_PID=$!

# ── Watchdog-Loop mit Exponential Backoff ─────────────────────────────────────
_backoff=3
_crash_count=0
_crash_window_start=$(_uptime_s)

while true; do
    nice -n -5 "$CTRL" "$MODDIR"
    _exit=$?
    _now=$(_uptime_s)

    case "$_exit" in
        0)
            _log "k6a-controller sauber beendet (exit=0) — kein Neustart"
            exit 0
            ;;
        3)
            _log "k6a-controller: Service deaktiviert (exit=3) — kein Neustart"
            exit 0
            ;;
        143)
            _log "k6a-controller via SIGTERM — Neustart in 2s (WebUI restart)"
            sleep 2; _backoff=3; _rotate_log; continue
            ;;
        2)
            _log "k6a-controller Soft-Reload (exit=2) — sofortiger Neustart"
            _backoff=3; _rotate_log; continue
            ;;
    esac

    if [ $(( _now - _crash_window_start )) -lt 60 ]; then
        _crash_count=$(( _crash_count + 1 ))
        if [ "$_crash_count" -gt 10 ]; then
            _log "ERR: crash-storm ($_crash_count in 60s) — giving up"
            exit 1
        fi
        [ "$_backoff" -lt 30 ] && _backoff=$(( _backoff * 2 ))
    else
        _crash_count=1; _backoff=3; _crash_window_start=$_now
    fi

    _log "k6a-controller beendet (exit=$_exit) — Neustart in ${_backoff}s (crash #$_crash_count)"
    _rotate_log; sleep "$_backoff"
done
