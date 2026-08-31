#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
# RELEASE 固定 bookworm（Debian 12）: OpenStick 原始验证环境, 包名全匹配
# （stable 现为 trixie, libconfig9 等包名已漂移, 用 stable 会装包失败）
RELEASE=${RELEASE=bookworm}
HOST_NAME=${HOST_NAME=openstick-debian}

rm -rf ${CHROOT}

debootstrap --foreign --arch arm64 \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg ${RELEASE} ${CHROOT}

# 架构检测: arm64 原生 runner 无需 qemu 模拟; x86 runner 需 qemu-aarch64-static
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    QEMU=""
else
    QEMU="qemu-aarch64-static"
    cp "$(which qemu-aarch64-static)" ${CHROOT}/usr/bin
fi

chroot ${CHROOT} ${QEMU} /bin/bash /debootstrap/debootstrap --second-stage

cat << EOF > ${CHROOT}/etc/apt/sources.list
deb http://mirrors.tuna.tsinghua.edu.cn/debian ${RELEASE} main contrib non-free-firmware
deb http://mirrors.tuna.tsinghua.edu.cn/debian-security ${RELEASE}-security main contrib non-free-firmware
deb http://mirrors.tuna.tsinghua.edu.cn/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/
mount -o bind /run ${CHROOT}/run/

cp scripts/setup.sh ${CHROOT}
# SP970 fix 文件（sim-activate/led/nat）供 setup.sh 安装到系统
mkdir -p ${CHROOT}/sp970-fix
cp configs/system/sp970-*.sh ${CHROOT}/sp970-fix/
cp configs/system/sp970-*.service ${CHROOT}/sp970-fix/
chroot ${CHROOT} ${QEMU} /bin/sh -c /setup.sh

# cleanup
for a in proc sys dev/pts dev run; do
    umount ${CHROOT}/${a}
done;

rm -f ${CHROOT}/setup.sh
echo -n > ${CHROOT}/root/.bash_history

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup systemd services (exclude sp970 fix files — installed by setup.sh)
# -maxdepth 1: 只拷顶层实体 .service；configs/system/*/target.wants/ 里是路径文本文件
# （git 普通文件非软链），递归 find 会 basename 相同覆盖真实单元（usb-gadget.service 变 38B 垃圾）
find configs/system -maxdepth 1 -name '*.service' -type f ! -name 'sp970-sim-activate.service' -exec cp -a {} ${CHROOT}/etc/systemd/system \;
# also copy non-service system configs (override.conf, target wants, etc.)
for f in configs/system/*; do
    case "$f" in
        *.sh|*.service) continue ;;
        *target.wants) continue ;;  # 软链由下方 ln -sf 生成，勿拷路径文本文件
        *) cp -a "$f" ${CHROOT}/etc/systemd/system/ ;;
    esac
done
# enable critical services (usb-gadget/msm-firmware-loader 开机自启, 否则 USB NCM/WiFi 起不来)
for svc in usb-gadget.service msm-firmware-loader.service; do
    mkdir -p ${CHROOT}/etc/systemd/system/multi-user.target.wants
    ln -sf /etc/systemd/system/${svc} ${CHROOT}/etc/systemd/system/multi-user.target.wants/${svc}
done

cp -a scripts/msm-firmware-loader.sh ${CHROOT}/usr/sbin
cp -a configs/system/sp970-usb-ncm.sh ${CHROOT}/usr/sbin/sp970-usb-ncm.sh
chmod 0755 ${CHROOT}/usr/sbin/sp970-usb-ncm.sh

# setup NetworkManager
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
sed -i '/\[main\]/a dns=dnsmasq' ${CHROOT}/etc/NetworkManager/NetworkManager.conf

# enable autoconnect for usb0
cat << EOF > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# install kernel (6.12.1 = 与 sp970-alpine 同版本, DTB 兼容零风险; 阿里云镜像加速)
wget -O - https://mirrors.aliyun.com/postmarketOS/v25.12/aarch64/linux-postmarketos-qcom-msm8916-6.12.1-r2.apk \
    | tar xkzf - -C ${CHROOT} --exclude=.PKGINFO --exclude=.SIGN* 2>/dev/null

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# copy custom dtb's
mkdir -p ${CHROOT}/boot/dtbs/qcom
cp dtbs/* ${CHROOT}/boot/dtbs/qcom

# create missing directory
mkdir -p ${CHROOT}/lib/firmware/msm-firmware-loader

# SP970 WCNSS WiFi 固件 + NV 校准（可选注入，双保险）
# 源: sp970-alpine 仓 firmware/sp970/（由 SP970_FIRMWARE_DIR 提供，CI 从公开仓稀疏拉取）
if [ -n "${SP970_FIRMWARE_DIR}" ] && [ -d "${SP970_FIRMWARE_DIR}/sp970" ]; then
    mkdir -p ${CHROOT}/lib/firmware/wlan/prima
    for f in ${SP970_FIRMWARE_DIR}/sp970/WCNSS.B* ${SP970_FIRMWARE_DIR}/sp970/WCNSS.MDT; do
        [ -e "$f" ] || continue
        name=$(basename "$f" | tr 'A-Z' 'a-z')
        cp "$f" ${CHROOT}/lib/firmware/${name}
    done
    cp ${SP970_FIRMWARE_DIR}/sp970/WCNSS_qcom_wlan_nv.bin ${CHROOT}/lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin
    echo "SP970 WCNSS firmware injected (${SP970_FIRMWARE_DIR}/sp970)"
fi

# SP970 modem 固件（mss-pil: mba.mbn → modem.mdt + modem.bXX；缺失则 Boot failed -2）
# 源: sp970-alpine 仓 firmware/modem/sp970/
if [ -n "${SP970_FIRMWARE_DIR}" ] && [ -d "${SP970_FIRMWARE_DIR}/modem/sp970" ]; then
    mkdir -p ${CHROOT}/lib/firmware
    cp ${SP970_FIRMWARE_DIR}/modem/sp970/mba.mbn ${CHROOT}/lib/firmware/
    cp ${SP970_FIRMWARE_DIR}/modem/sp970/modem.mbn ${CHROOT}/lib/firmware/ 2>/dev/null || true
    cp ${SP970_FIRMWARE_DIR}/modem/sp970/modem.mdt ${CHROOT}/lib/firmware/
    cp ${SP970_FIRMWARE_DIR}/modem/sp970/modem.b* ${CHROOT}/lib/firmware/
    echo "SP970 modem firmware injected (${SP970_FIRMWARE_DIR}/modem/sp970)"
fi

# update fstab
echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults\t0 2" > ${CHROOT}/etc/fstab

# backup rootfs
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .
