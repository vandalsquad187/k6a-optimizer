#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# BadazZ89 k6a Optimizer v8.0 — customize.sh
# SM7150 sweet_k6a — VantomKernel 4.14.356
# KernelSU Next / Magisk kompatibel
# ═══════════════════════════════════════════════════════════════════════════════

SKIPUNZIP=1

ui_print " "
ui_print "╔══════════════════════════════════════╗"
ui_print "║  BadazZ89 k6a Optimizer v9.0        ║"
ui_print "║  SM7150 sweet_k6a // sweet2          ║"
ui_print "║  VantomKernel 4.14.356               ║"
ui_print "║  2-Mode: Daily + Cooking             ║"
ui_print "╚══════════════════════════════════════╝"
ui_print " "

# ── Entpacken ─────────────────────────────────────────────────────────────────
ui_print "> Extracting module files..."
unzip -o "$ZIPFILE" -d "$MODPATH" || {
    ui_print "ERR: unzip failed"
    exit 1
}

# ── Permissions ───────────────────────────────────────────────────────────────
ui_print "> Setting permissions..."
set_perm "$MODPATH/service.sh"          root root 0755
set_perm "$MODPATH/bin/k6a-controller"  root root 0755
set_perm "$MODPATH/bin/k6a-daemon"      root root 0755
set_perm "$MODPATH/bin/k6a-lib.sh"      root root 0755
set_perm "$MODPATH/boot-completed.sh"   root root 0755
set_perm "$MODPATH/post-fs-data.sh"     root root 0755

# ── Verzeichnisse ─────────────────────────────────────────────────────────────
mkdir -p "$MODPATH/run" "$MODPATH/config"

# ── settings.conf — NUR beim ersten Flash erstellen ───────────────────────────
CONF="$MODPATH/config/settings.conf"
if [ ! -f "$CONF" ]; then
    ui_print "> Creating default settings.conf..."
    cat > "$CONF" << 'CONF_EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# k6a Optimizer v9.0 — settings.conf (2-Mode: daily + cooking)
# ═══════════════════════════════════════════════════════════════════════════════
# cpu_hotplug_enable: 0=all cores | 1=Silver offline in cooking
boot_delay=8
debug=0
cpu_hotplug_enable=0
CONF_EOF
else
    ui_print "> settings.conf exists — keeping your settings"
fi

# ── freeze.conf ───────────────────────────────────────────────────────────────
if [ ! -f "$MODPATH/config/freeze.conf" ]; then
    ui_print "> Creating default freeze.conf..."
    printf '# trigger_pkg=freeze_pkg1,freeze_pkg2\n' > "$MODPATH/config/freeze.conf"
fi

# ── manual_profile ────────────────────────────────────────────────────────────
if [ ! -f "$MODPATH/config/manual_profile" ]; then
    printf 'daily' > "$MODPATH/config/manual_profile"
fi

# ── Log-Rotation beim Install ─────────────────────────────────────────────────
LOG="$MODPATH/config/service.log"
if [ -f "$LOG" ]; then
    _size=$(wc -c < "$LOG" 2>/dev/null)
    if [ "${_size:-0}" -gt 204800 ]; then
        mv "$LOG" "${LOG}.old"
        ui_print "> Old service.log rotated"
    fi
fi

# ── Cleanup: Runtime-Dateien die aus dem Zip kommen koennen ───────────────────
rm -f "$MODPATH/run/controller.pid" "$MODPATH/run/daemon.pid" "$MODPATH/run/service.lock"
rm -f "$MODPATH/config/active_profile" "$MODPATH/config/cache_kb.tmp"
rm -f "$MODPATH/config/ping.txt" "$MODPATH/config/service_start.log"

ui_print " "
ui_print "> Installation complete — Reboot recommended"
ui_print " "
