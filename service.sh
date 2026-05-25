#!/system/bin/sh
# BadazZ89 k6a Optimizer — service.sh  v1.0
# Fix: Lock-File wird NACH boot_completed gesetzt, nicht davor.
#   Bug: KernelSU startet service.sh mehrfach während Boot.
# Fix: Lock erst nach Boot damit mehrfache KernelSU-Starts kein Problem
_log "k6a service.sh v1.0: starte k6a-controller"

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
                competitive|gaming)
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
