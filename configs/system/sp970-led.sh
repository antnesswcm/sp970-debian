#!/bin/sh
# sp970-led — Debian 版 LED 状态脚本（移植自 sp970-alpine led-daemon.start）
# 红(LED off)→关, 绿(4G)→心跳, 蓝(WiFi phy0tx)保持
R=/sys/class/leds/red:os
G=/sys/class/leds/green:4g

# wait for sysfs
i=0
while [ "$i" -lt 50 ]; do
    [ -e "$R/trigger" ] && [ -e "$G/trigger" ] && break
    sleep 0.2
    i=$((i+1))
done

# red: disable heartbeat, turn off
echo none > "$R/trigger" 2>/dev/null
echo 0 > "$R/brightness" 2>/dev/null
# green: take over heartbeat
echo heartbeat > "$G/trigger" 2>/dev/null
# blue: phy0tx kept (DTS), untouched

exit 0
