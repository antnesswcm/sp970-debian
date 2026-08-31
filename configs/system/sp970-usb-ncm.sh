#!/bin/sh -e
# sp970-usb-ncm — SP970 USB NCM gadget 脚本（移植自 sp970-alpine setup_ncm_gadget.sh）
#
# 背景: OpenStick 原版 usb-gadget.service 用 RNDIS scheme（rndis-os-desc.scheme），
#       主机端识别为 RNDIS（Windows 需装驱动 / Linux 需 rndis_host），
#       而 SP970 Alpine 实机验证可用的是 **NCM**（cdc_ncm，192.168.5.1）。
#       本脚本用 configfs 直接构建 NCM gadget + MS OS 描述符（WINNCM/NCM），
#       Windows 10/11 免驱自动加载。
#
# 由 usb-gadget.service 调用（multi-user.target 启动链）。
# 幂等: configfs 条目已存在则直接退出。

CONFIGFS="/sys/kernel/config/usb_gadget"
NAME="openstick"

# configfs 自挂载保险（udev 触发时可能早于 systemd 的 sys-kernel-config.mount）
[ -d /sys/kernel/config ] || mount -t configfs configfs /sys/kernel/config 2>/dev/null || true

DIR="${CONFIGFS}/${NAME}"

NCM_HOST_ADDR="2a:85:da:41:eb:f9"
NCM_DEV_ADDR="8a:b1:27:16:8e:a7"

[ -d "${CONFIGFS}" ] || { echo "USB Gadget configfs entry missing!"; exit 1; }
[ -d "${DIR}" ] && { echo "USB Gadget already configured"; exit 0; }

# create gadget entry
mkdir -p "${DIR}/functions/ncm.1"

# setup

echo "0x0200"        > "${DIR}/bcdUSB"          # USB 2.0
echo "0x0104"        > "${DIR}/idProduct"       # Multifunction Composite Gadget
echo "0x1d6b"        > "${DIR}/idVendor"        # Linux Foundation
echo "0x40"          > "${DIR}/bMaxPacketSize0" # 64 bytes

mkdir -p "${DIR}/strings/0x409"
echo "4G LTE Dongle" > "${DIR}/strings/0x409/product"
echo "Openstick"     > "${DIR}/strings/0x409/manufacturer"
echo "0123456789"    > "${DIR}/strings/0x409/serialnumber"

# setup config
mkdir "${DIR}/configs/c.1"

echo "0x80" > "${DIR}/configs/c.1/bmAttributes" # bus powered
echo "250"  > "${DIR}/configs/c.1/MaxPower"     # 500 mA

# setup NCM
echo "${NCM_HOST_ADDR}" > "${DIR}/functions/ncm.1/host_addr"
echo "${NCM_DEV_ADDR}"  > "${DIR}/functions/ncm.1/dev_addr"

# Enable use of OS descriptors
# This enables windows 10/11 to auto load drivers

echo "MSFT100" > "${DIR}/os_desc/qw_sign"
echo "0xbc"    > "${DIR}/os_desc/b_vendor_code"
echo "1"       > "${DIR}/os_desc/use"

# gt templates cannot set these values

echo "WINNCM"  > "${DIR}/functions/ncm.1/os_desc/interface.ncm/compatible_id"
echo "NCM"     > "${DIR}/functions/ncm.1/os_desc/interface.ncm/sub_compatible_id"

# Windows extension to use IAD (Interface Association Descriptor)

echo "0x0100" > "${DIR}/bcdDevice"
echo "0x01"   > "${DIR}/bDeviceProtocol"
echo "0x02"   > "${DIR}/bDeviceSubClass"
echo "0xef"   > "${DIR}/bDeviceClass"

# activate
ln -s "${DIR}/functions/ncm.1" "${DIR}/configs/c.1"
ln -s "${DIR}/configs/c.1" "${DIR}/os_desc"
echo $(ls /sys/class/udc) > "${DIR}/UDC"
