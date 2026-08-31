#!/bin/sh
# sp970-nat — Debian 版 NAT 转发（移植自 sp970-alpine nat.start）
# WiFi(192.168.4.x) -> 4G(wwan0) MASQUERADE（随身 WiFi 形态）
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -C POSTROUTING -o wwan0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o wwan0 -j MASQUERADE
exit 0
