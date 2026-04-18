#!/system/bin/sh
# BadazZ89 k6a Optimizer — service.sh  v7.7
# KernelSU Next kompatibel: endet mit exec — kein Watchdog-Loop.
# Der Controller bringt seinen eigenen Neustart-Mechanismus mit.

MODDIR=${0%/*}
CTRL="$MODDIR/bin/k6a-controller"
LOG="$MODDIR/config/service.log"
CONF="$MODDIR/config/settings.conf"

mkdir -p "$MODDIR/run" "$MODDIR/config"

# Boot-Delay aus Config lesen (Default 8s)
BOOT_DELAY=$(grep "^boot_delay=" "$CONF" 2>/dev/null | cut -d= -f2)
case "$BOOT_DELAY" in ''|*[!0-9]*) BOOT_DELAY=8 ;; esac
[ "$BOOT_DELAY" -lt 3  ] && BOOT_DELAY=3
[ "$BOOT_DELAY" -gt 60 ] && BOOT_DELAY=60

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
sleep "$BOOT_DELAY"

printf '[%s] k6a service.sh: exec k6a-controller\n' \
    "$(date '+%H:%M:%S')" >> "$LOG"

[ -x "$CTRL" ] || {
    printf '[%s] ERR: k6a-controller nicht gefunden\n' \
        "$(date '+%H:%M:%S')" >> "$LOG"
    exit 1
}

# Watchdog-Loop: Controller bei Crash automatisch neu starten.
# KernelSU Next: exec würde den Prozess ersetzen und bei Crash den Service
# komplett beenden. Stattdessen Loop mit kurzer Pause vor Neustart.
# Max 10 Neustarts in 60s (Crash-Storm-Schutz).
_crash_count=0
_crash_window_start=$(date +%s)

while true; do
    "$CTRL" "$MODDIR"
    _exit=$?
    _now=$(date +%s)

    # Crash-Storm-Schutz: >10 Crashes in 60s → Service gibt auf
    if [ $(( _now - _crash_window_start )) -lt 60 ]; then
        _crash_count=$(( _crash_count + 1 ))
        if [ "$_crash_count" -gt 10 ]; then
            printf '[%s] ERR: k6a-controller crash-storm (%d crashes) — giving up\n' \
                "$(date '+%H:%M:%S')" "$_crash_count" >> "$LOG"
            exit 1
        fi
    else
        # Neues Fenster: Counter zurücksetzen
        _crash_count=1
        _crash_window_start=$_now
    fi

    printf '[%s] k6a-controller beendet (exit=%d) — Neustart in 3s\n' \
        "$(date '+%H:%M:%S')" "$_exit" >> "$LOG"
    sleep 3
done
