#!/system/bin/sh
SKIPUNZIP=1
ui_print "BadazZ89 k6a Optimizer v4.0"
ui_print "SD730 / SM7150 / sweet2"
unzip -o "$ZIPFILE" -d "$MODPATH"
set_perm "$MODPATH/service.sh"        root root 0755
set_perm "$MODPATH/bin/k6a-daemon"    root root 0755
set_perm "$MODPATH/boot-completed.sh" root root 0755
mkdir -p "$MODPATH/run"
mkdir -p "$MODPATH/config"

# Settings initialisieren wenn nicht vorhanden
CONF="$MODPATH/config/settings.conf"
if [ ! -f "$CONF" ]; then
    cat > "$CONF" << 'CONF_EOF'
thermal_disable=0
aggressive_boost=0
battery_saver=0
auto_detection=1
auto_cache=0
battery_spoof_enable=0
battery_spoof_temp=1
bypass_threshold=35
miui_joyose=0
miui_game_turbo=0
miui_freeform=0
miui_mipad_boost=0
CONF_EOF
fi
