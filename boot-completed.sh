#!/system/bin/sh
MODDIR=${0%/*}
DAEMON="$MODDIR/bin/k6a-daemon"
PIDFILE="$MODDIR/run/daemon.pid"
LOG="$MODDIR/config/daemon.log"
mkdir -p "$MODDIR/run"
if [ -f "$PIDFILE" ]; then
    OLD=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$OLD" ] && kill "$OLD" 2>/dev/null
    rm -f "$PIDFILE"
fi
if [ -x "$DAEMON" ]; then
    "$DAEMON" >> "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
fi
