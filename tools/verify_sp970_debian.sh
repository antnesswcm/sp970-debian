#!/bin/sh
# verify_sp970_debian.sh - 刷机后验证清单（M2）
# 用法: 在设备上运行（Debian rootfs 内）或经 SSH 调用
# 验证: SIM/4G/WiFi/LED/NAT

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "============================================"
echo " SP970 Debian 刷机后验证（M2）"
echo "============================================"

echo "[1] 系统"
[ "$(cat /etc/os-release 2>/dev/null | grep -c 'Debian')" -ge 1 ] && ok "Debian 系统" || bad "非 Debian: $(head -1 /etc/os-release 2>/dev/null)"
[ -d /run/systemd/system ] && ok "systemd 运行" || bad "systemd 未运行"

echo "[2] WiFi 热点"
nmcli device status 2>/dev/null | grep -q wlan0 && ok "wlan0 存在" || bad "无 wlan0"
ip -4 addr show wlan0 2>/dev/null | grep -q "192.168.4.1" && ok "热点 IP 192.168.4.1" || bad "热点 IP 异常"

echo "[3] modem / SIM"
mmcli -L 2>/dev/null | grep -q Modem && ok "MM 识别 modem" || bad "MM 无 modem"
mmcli -m 0 2>/dev/null | grep -q "sim" && ok "MM 认 SIM" || bad "MM 无 SIM"

echo "[4] SIM 激活（N958St fix）"
ls /var/log/sp970-sim-activate.log >/dev/null 2>&1 && {
    grep -q "registration wait done" /var/log/sp970-sim-activate.log && ok "sim-activate 跑完" || bad "sim-activate 未完成"
} || bad "无 sim-activate 日志"

echo "[5] 4G 注册"
mmcli -m 0 2>/dev/null | grep -q "registered" && ok "4G 已注册" || bad "4G 未注册"
nmcli device status 2>/dev/null | grep -q wwan && ok "NM 管 wwan" || bad "NM 无 wwan"

echo "[6] 数据面"
ip -4 addr show wwan0 2>/dev/null | grep -q "inet " && ok "wwan0 有 IP: $(ip -4 addr show wwan0 | grep -o 'inet [0-9.]*' | head -1)" || bad "wwan0 无 IP"
ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1 && ok "外网通" || bad "外网不通"

echo "[7] NAT"
iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q MASQUERADE && ok "NAT 规则存在" || bad "无 NAT 规则"
cat /proc/sys/net/ipv4/ip_forward 2>/dev/null | grep -q 1 && ok "ip_forward=1" || bad "ip_forward 未开"

echo "[8] LED"
ls /sys/class/leds/red:os/trigger >/dev/null 2>&1 && ok "LED sysfs 存在" || bad "无 LED sysfs"
grep -q heartbeat /sys/class/leds/green:4g/trigger 2>/dev/null && ok "绿心跳" || bad "绿非心跳"

echo "[9] sp970 services"
for s in sp970-sim-activate sp970-led sp970-nat; do
    systemctl is-active $s.service >/dev/null 2>&1 && ok "$s 活动" || bad "$s 非活动"
done

echo "============================================"
echo " 结果: $PASS 通过, $FAIL 失败"
echo "============================================"
[ "$FAIL" -eq 0 ]
