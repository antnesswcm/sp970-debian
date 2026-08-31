#!/bin/sh
# flash_sp970_debian.sh - 刷入 sp970-debian 构建产物（保护 NV）
#
# 用法: sh flash_sp970_debian.sh <files目录>
# 前置: 设备已进 fastboot（reset 键 + USB）
#
# ⚠️ 铁律: 不刷 modemst1/modemst2（NV）——避免 IMEI 丢失
# 首次从安卓/其他系统换到 Debian 时需刷 GPT；已刷过 OpenStick 分区表则跳过 GPT
#
# 对照: docs/SP970-Alpine刷机指南.md 的刷机流程（同分区表/同 NV 保护）

set -e
FILES="${1:?用法: $0 <files目录>}"
FB="${FASTBOOT:-fastboot}"

[ -f "$FILES/gpt_both0.bin" ] || { echo "❌ 找不到 $FILES/gpt_both0.bin"; exit 1; }

echo "== 确认设备在 fastboot =="
$FB devices || { echo "❌ 无 fastboot 设备"; exit 1; }

# 可选：GPT（仅首次/换系统时）
if [ "${FLASH_GPT:-0}" = "1" ]; then
    echo "== 刷 GPT（清 modemst NV，需恢复）=="
    $FB flash partition "$FILES/gpt_both0.bin"
fi

echo "== 刷 bootloader =="
$FB flash aboot "$FILES/aboot.mbn"
$FB flash hyp "$FILES/hyp.mbn"
$FB flash rpm "$FILES/rpm.mbn"
$FB flash sbl1 "$FILES/sbl1.mbn"
$FB flash tz "$FILES/tz.mbn"

echo "== 刷 boot + rootfs =="
$FB flash boot "$FILES/boot.bin"
$FB -S 256M flash rootfs "$FILES/rootfs.bin"

echo "== 重启 =="
$FB reboot

echo ""
echo "✅ 刷机完成。注意："
echo "  - modemst1/2（NV）未动（保护 IMEI）"
echo "  - 若首次刷（FLASH_GPT=1 已刷 GPT），NV 需恢复（dd 写回备份）"
echo "  - 重启后等 ~2min，SSH user@192.168.4.1 (密码 1)"
