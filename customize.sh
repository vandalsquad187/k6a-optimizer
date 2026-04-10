#!/system/bin/sh
SKIPUNZIP=1
ui_print "BadazZ89 k6a Optimizer v7.0"
ui_print "SM7150 sweet_k6a — Openela 4.14 / Lunaris 3.8"
unzip -o "$ZIPFILE" -d "$MODPATH"
set_perm "$MODPATH/service.sh"          root root 0755
set_perm "$MODPATH/bin/k6a-controller"  root root 0755
set_perm "$MODPATH/bin/k6a-daemon"      root root 0755
set_perm "$MODPATH/boot-completed.sh"   root root 0755
mkdir -p "$MODPATH/run" "$MODPATH/config"
CONF="$MODPATH/config/settings.conf"
[ -f "$CONF" ] || cat > "$CONF" << 'CONF_EOF'
# ── k6a Optimizer — settings.conf ────────────────────────────────────────────
thermal_disable=0
battery_spoof_enable=0
battery_spoof_temp=1
auto_detection=1
# Thread Pinning: RenderThread+UnityMain auf Gold (0=aus, 1=ein)
thread_pin_enable=1
# Thermale Vorhersage: preemptiver Cap bei +3°C/Tick UND >75°C
thermal_prediction_enable=1
# Boot-Verzögerung in Sekunden (3–60)
boot_delay=8
# Watchdog-Neustart-Verzögerung nach Crash (1–30)
crash_restart_delay=5
# Debug-Logging (0=aus, 1=verbose)
debug=0
CONF_EOF
[ -f "$MODPATH/config/freeze.conf" ] || \
    printf '# trigger_pkg=freeze_pkg1,freeze_pkg2\n' > "$MODPATH/config/freeze.conf"
[ -f "$MODPATH/config/manual_profile" ] || printf 'balanced' > "$MODPATH/config/manual_profile"
