#!/bin/sh -e

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true

echo 'tzdata tzdata/Areas select Etc' | debconf-set-selections
echo 'tzdata tzdata/Zones/Etc select UTC' | debconf-set-selections
echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
rm -f "/etc/locale.gen"

apt update -qqy
# NOTE: 跳过 apt upgrade —— debootstrap 基础系统直接装目标包，避免全量升级耗时/卡死
apt install -qqy --no-install-recommends \
    bridge-utils \
    dnsmasq \
    hostapd \
    iptables \
    libconfig9 \
    libqmi-utils \
    locales \
    modemmanager \
    netcat-traditional \
    net-tools \
    network-manager \
    openssh-server \
    qrtr-tools \
    rmtfs \
    sudo \
    systemd-timesyncd \
    tzdata \
    wireguard-tools \
    wpasupplicant
apt clean
rm -rf /var/lib/apt/lists/*

passwd -d root

echo user:1::::/home/user:/bin/bash | newusers
echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/user

# ---- SP970 fixes (移植自 sp970-alpine) ----
# sim-activate: N958St Get Slot Status bug 兜底（MM 启动前 qmicli 激活 SIM）
install -m 0755 /sp970-fix/sp970-sim-activate.sh /usr/libexec/sp970-sim-activate.sh
install -m 0644 /sp970-fix/sp970-sim-activate.service /etc/systemd/system/sp970-sim-activate.service
systemctl enable sp970-sim-activate.service

# led: 红 off / 绿 heartbeat / 蓝 phy0tx（DTS 已配 trigger）
install -m 0755 /sp970-fix/sp970-led.sh /usr/libexec/sp970-led.sh
install -m 0644 /sp970-fix/sp970-led.service /etc/systemd/system/sp970-led.service
systemctl enable sp970-led.service

# nat: WiFi(192.168.4.x) -> wwan0 MASQUERADE
install -m 0755 /sp970-fix/sp970-nat.sh /usr/libexec/sp970-nat.sh
install -m 0644 /sp970-fix/sp970-nat.service /etc/systemd/system/sp970-nat.service
systemctl enable sp970-nat.service
