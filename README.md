# sp970-debian

SP970（创景 / 高通 MSM8916）随身 WiFi 的**干净 Debian 固件项目**。

基于 [OpenStick-Builder](https://github.com/kinsamanka/OpenStick-Builder)（main = debian 分支）构建，
移植本项目（sp970-alpine）已验证的硬件 fix，目标是 **SimAdmin 原生跑通**的 Debian 平台。

## 与 OpenStick-Builder 的关系

- **上游**：OpenStick-Builder（debootstrap + pmOS MSM8916 内核 + lk2nd，14 区 GPT）
- **本项目增量**（相对上游）：
  1. `dtbs/msm8916-handsome-openstick-sp970.dtb` —— SP970 专属 DTB（**sim-sel gpio114** + LED 定义，源自 sp970-firmware DTS）
  2. `configs/extlinux.conf` —— fdt 指向 SP970
  3. （待加）SIM 激活 systemd unit、LED、NAT（移植自 sp970-alpine）

## 硬件 fix 移植清单

| Fix | 来源（sp970-alpine）| 状态 |
|---|---|---|
| DTS sim-sel gpio114（LOW=物理 SIM）| `sp970-firmware/dts/msm8916-handsome-openstick-sp970.dts` | ✅ 已接入 DTB |
| SIM 激活（N958St Get Slot Status bug）| `sim-activate.start`（qmicli AID→provision→CFUN→注册）| ⏳ 待做（systemd unit）|
| LED 状态（red off/blue phy0tx/green heartbeat）| `led-daemon.start` | ⏳ 待做 |
| NAT（WiFi→4G）| `nat.start` | ⏳ 待做 |
| NV 保护（刷机不刷 modemst）| 项目铁律 | ✅ OpenStick 流程已内置 |

## 构建

```sh
# 本地（Ubuntu 22.04）
git clone --recurse-submodules https://github.com/antnesswcm/sp970-debian.git
cd sp970-debian
sudo ./build.sh          # 产物在 files/

# 或 GitHub Actions（fork 后 workflow_dispatch）
```

构建产物：`files/boot.bin` + `files/rootfs.bin` + `files/gpt_both0.bin` 等。

## 刷机（保护 NV）

> 铁律：**不刷 modemst1/2（NV）**。只刷 GPT + bootloader + boot + rootfs。

```sh
# 设备进 fastboot（reset 键）后：
fastboot flash partition gpt_both0.bin   # 仅首次/换系统
fastboot flash aboot aboot.mbn
fastboot flash hyp hyp.mbn
fastboot flash rpm rpm.mbn
fastboot flash sbl1 sbl1.mbn
fastboot flash tz tz.mbn
fastboot flash boot boot.bin
fastboot -S 256M flash rootfs rootfs.bin
fastboot reboot
# modemst1/2（NV）不刷——从原厂备份用 dd 恢复（见 docs/SP970-Alpine刷机指南.md 步骤四）
```

> **⚠️ M2 刷机建议（2026-08-31 确认）**：OpenStick 的 aboot 用 `LK2ND_COMPATIBLE=yiming,uz801-v3`（UZ801 专用），
> 而我们 Alpine 用 `thwc,ufi001c`（**已验证能 boot SP970**）。**首次 M2 建议只刷 boot.bin + rootfs.bin**（保留 Alpine 的 aboot 引导），
> 避免 lk2nd compatible 不匹配导致无法引导。aboot 差异影响评估后再决定是否换。
>
> 已确认：hyp/rpm/sbl1/tz/gpt_both0.bin 与 Alpine **hash 完全一致**（同源），只有 aboot 因 compatible 串不同。

## 默认配置

| 项 | 值 |
|---|---|
| WiFi 热点 | SSID `Openstick` / 密码 `openstick` / 192.168.4.1 |
| USB NCM | 192.168.5.1 |
| SSH | user / 1 |

## SimAdmin 部署（M4）

Debian 是 SimAdmin 原生环境（systemd/glibc/NM 全满足），一条命令安装：

```sh
# WFC 版（WiFi Calling，推荐——本项目的 VoWiFi 研究用）
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/3899/SimAdmin/main/install_latest.sh | sh -s -- --wfc

# 或标准版
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/3899/SimAdmin/main/install_latest.sh | sh

# 访问: http://192.168.4.1:3000 （首次设置密码）
# 注意: 启动后需在 WebUI/API 开启蜂窝数据（POST /api/data {"active":true}），
#       否则 SimAdmin watchdog 会断开 lte（见 docs/SP970-参考资产与短信研究.md §7.8）
```

依赖说明：install_latest.sh 自动装 ModemManager/NetworkManager/QMI/PCSC + 启服务；
本项目的 `sp970-sim-activate.service`（N958St bug 兜底）会与 SimAdmin 并存——
若 SimAdmin 的 QMI auto-activate 覆盖了 bug，可 `systemctl disable sp970-sim-activate`。

## 相关文档

- `docs/SP970-debian移植计划.md`（完整计划：可行性/风险/里程碑）
- `docs/SP970-参考资产与短信研究.md`（SimAdmin 分析 §7）
- `reference/OpenStick-Builder/`（上游副本，含 SP970 适配 commit d4898ce）
