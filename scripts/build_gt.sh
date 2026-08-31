#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
SRCDIR=$(pwd)/src

# 架构自适应: arm64 原生 runner 直接 chroot; x86 runner 用 qemu-aarch64-static
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    QEMU=""
else
    QEMU="qemu-aarch64-static"
    cp "$(which qemu-aarch64-static)" ${CHROOT}/usr/bin 2>/dev/null || true
fi

# install gt dependencies (rootfs 当 sysroot, 需要 dev 头文件)
chroot ${CHROOT} ${QEMU} /bin/sh \
    -c " apt update; apt install -y libconfig-dev libc6-dev"

# build and install gt
(
cd src/libusbgx/
autoreconf -i
)

mkdir -p build
(
cd build
PKG_CONFIG_PATH=${CHROOT}/usr/lib/aarch64-linux-gnu/pkgconfig \
    ${SRCDIR}/libusbgx/configure \
        --host aarch64-linux-gnu \
        --prefix=/usr \
        --with-sysroot=${CHROOT}
)
make -C build DESTDIR=$(pwd)/dist CFLAGS="--sysroot=${CHROOT}" install
make -C build CFLAGS="--sysroot=${CHROOT}" install

rm -rf build/*
PKG_CONFIG_PATH=${CHROOT}/usr/lib/pkgconfig:${CHROOT}/usr/lib/aarch64-linux-gnu/pkgconfig \
    cmake -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
        -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
        -DCMAKE_C_FLAGS=-I$(pwd)/dist/usr/include \
        -DCMAKE_C_FLAGS=-L$(pwd)/dist/usr/lib \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_SYSROOT=${CHROOT} \
        -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
        -S ${SRCDIR}/gt/source \
        -B build

make -C build DESTDIR=$(pwd)/dist install

rm -rf dist/usr/share dist/usr/lib/cmake dist/usr/lib/pkgconfig \
    dist/usr/lib/*a dist/usr/bin/ga* dist/usr/bin/s* dist/usr/include

cp -a configs/templates dist/etc/gt
