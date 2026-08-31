#!/bin/sh
# sp970-sim-activate — Debian 版 SIM 激活脚本（移植自 sp970-alpine sim-activate.start）
#
# 背景: N958St modem UIM Get Slot Status NotSupported → MM 开机误判 sim-missing
#       + power-off modem。Debian 下 MM 由 systemd 管理（开机即起），
#       本脚本在 MM 启动前先 qmicli 激活 SIM（AID 发现→provision→CFUN→注册）。
#
# 由 sp970-sim-activate.service 调用（Before=ModemManager.service）。
# 日志: /var/log/sp970-sim-activate.log
#
# 注: 若 SimAdmin 的 QMI auto-activate + modem-recovery 已覆盖 N958St bug，
#     本服务可禁用（systemctl disable sp970-sim-activate）。默认保留兜底。

LOG=/var/log/sp970-sim-activate.log
QMI_BIN="$(command -v qmicli || echo /usr/bin/qmicli)"
[ "$(id -u)" = "0" ] || { echo "需要 root" >> "$LOG"; exit 1; }

echo "[$(date)] === sp970-sim-activate start ===" >> "$LOG"

# 1. 等待 QMI 控制端口（udev 已 settle，最多 60s）
i=0
while [ ! -e /dev/wwan0qmi0 ] && [ "$i" -lt 60 ]; do sleep 1; i=$((i+1)); done
if [ -e /dev/wwan0qmi0 ]; then
    echo "[$(date)] QMI port ready (waited ${i}s)" >> "$LOG"
else
    echo "[$(date)] FAIL: no QMI port after 60s" >> "$LOG"
    exit 1
fi

# 2. 发现 USIM AID（最多 90s，等 USIM 初始化）
i=0
AID=""
while [ "$i" -lt 18 ]; do
    AID=$($QMI_BIN -d /dev/wwan0qmi0 --uim-get-card-status 2>/dev/null | \
          awk '/usim/{f=1} f&&/Application ID:/{getline; gsub(/[^0-9A-Fa-f]/,""); print; exit}')
    [ -n "$AID" ] && break
    sleep 5; i=$((i+1))
done
if [ -n "$AID" ]; then
    echo "[$(date)] AID=$AID (after ${i} tries)" >> "$LOG"
else
    echo "[$(date)] FAIL: USIM AID discovery failed (90s)" >> "$LOG"
    exit 1
fi

# 3. provision 直到 USIM ready（最多 5 次）
PASS=0
for i in 1 2 3 4 5; do
    $QMI_BIN -d /dev/wwan0qmi0 \
      --uim-change-provisioning-session="session-type=primary-gw-provisioning,activate=yes,slot=1,aid=$AID" \
      >/dev/null 2>&1
    sleep 5
    READY=$($QMI_BIN -d /dev/wwan0qmi0 --uim-get-card-status 2>/dev/null | grep -c "Application state: 'ready'")
    PASS=$i
    [ "$READY" -ge 1 ] && break
done
echo "[$(date)] provision done, USIM ready on pass $PASS" >> "$LOG"

# 4. 开 RF（CFUN=1，走 AT 口）
printf 'AT+CFUN=1\r' | timeout 8 microcom -t 6000 /dev/wwan0at0 >/dev/null 2>&1
echo "[$(date)] CFUN=1 sent" >> "$LOG"
sleep 5

# 5. 再 provision 一次推注册
$QMI_BIN -d /dev/wwan0qmi0 \
  --uim-change-provisioning-session="session-type=primary-gw-provisioning,activate=yes,slot=1,aid=$AID" \
  >/dev/null 2>&1

# 6. 等网络注册（最多 ~60s）
i=0
REG=0
while [ "$i" -lt 12 ]; do
    REG=$($QMI_BIN -d /dev/wwan0qmi0 --nas-get-serving-system 2>/dev/null | grep -c "Registration state: 'registered'")
    [ "$REG" -ge 1 ] && break
    sleep 5; i=$((i+1))
done
echo "[$(date)] registration wait done (${i} iters, reg=${REG})" >> "$LOG"

echo "[$(date)] === sp970-sim-activate end (MM 由 systemd 接管) ===" >> "$LOG"
exit 0
