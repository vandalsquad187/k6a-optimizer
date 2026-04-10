#!/system/bin/sh
# BadazZ89 k6a Optimizer — service.sh  v7.0
# Single entry point: Watchdog für k6a-controller.
# k6a-daemon wird vom Controller als Child-Prozess gestartet (single ownership).
MODDIR=${0%/*}
CTRL="$MODDIR/bin/k6a-controller"
PIDFILE="$MODDIR/run/controller.pid"
LOG="$MODDIR/config/service.log"
CONF="$MODDIR/config/settings.conf"

mkdir -p "$MODDIR/run" "$MODDIR/config"

get_conf() { grep "^$1=" "$CONF" 2>/dev/null | cut -d= -f2-; }

load_config() {
    DEBUG=$(get_conf debug);           [ "$DEBUG" != "1" ] && DEBUG=0
    BOOT_DELAY=$(get_conf boot_delay)
    case "$BOOT_DELAY" in ''|*[!0-9]*) BOOT_DELAY=8 ;; esac
    [ "$BOOT_DELAY" -lt 3  ] && BOOT_DELAY=3
    [ "$BOOT_DELAY" -gt 60 ] && BOOT_DELAY=60
    CRASH_RESTART_DELAY=$(get_conf crash_restart_delay)
    case "$CRASH_RESTART_DELAY" in ''|*[!0-9]*) CRASH_RESTART_DELAY=5 ;; esac
    [ "$CRASH_RESTART_DELAY" -lt 1  ] && CRASH_RESTART_DELAY=1
    [ "$CRASH_RESTART_DELAY" -gt 30 ] && CRASH_RESTART_DELAY=30
}

log() {
    local level="$1"; shift
    [ "$level" = "DBG" ] && [ "$DEBUG" != "1" ] && return
    printf '[%s][%s] %s\n' "$(date '+%H:%M:%S')" "$level" "$*" >> "$LOG"
}
dbg() { log DBG "$*"; }

rotate_log() {
    [ -f "$LOG" ] || return
    local size; size=$(wc -c < "$LOG" 2>/dev/null) || return
    if [ "$size" -gt 102400 ]; then
        tail -c 51200 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
        log INFO "Log rotiert (war ${size} Bytes)"
    fi
}

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
load_config; rotate_log
log INFO "k6a Optimizer service startet (boot_delay=${BOOT_DELAY}s, debug=${DEBUG})"
dbg "MODDIR=$MODDIR"
sleep "$BOOT_DELAY"

[ -x "$CTRL" ] || { log ERR "k6a-controller nicht gefunden: $CTRL"; exit 1; }

while true; do
    rotate_log; load_config
    "$CTRL" "$MODDIR" &
    CTRL_PID=$!
    printf '%d\n' "$CTRL_PID" > "$PIDFILE"
    log INFO "k6a-controller gestartet (PID $CTRL_PID)"
    wait "$CTRL_PID"; EXIT_CODE=$?
    rm -f "$PIDFILE"
    [ "$EXIT_CODE" -eq 0 ] && { log INFO "k6a-controller sauber beendet — Watchdog stoppt"; break; }
    log ERR "k6a-controller abgestürzt (code $EXIT_CODE) — Neustart in ${CRASH_RESTART_DELAY}s"
    sleep "$CRASH_RESTART_DELAY"
done
