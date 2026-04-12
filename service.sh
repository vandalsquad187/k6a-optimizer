#!/system/bin/sh
# BadazZ89 k6a Optimizer — service.sh  v7.0
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

# exec ersetzt den service.sh Prozess direkt —
# KernelSU Next behandelt den Controller als den eigentlichen Service-Prozess.
exec "$CTRL" "$MODDIR"
