#!/bin/bash
# SPDX-License-Identifier: MIT

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-buffer"
KERNEL_SRC="${PROJECT_ROOT}/work/src/pkvm-linux"
KDIR="${PROJECT_ROOT}/work/build/pkvm-full-clang"
LKVM="${PROJECT_ROOT}/work/src/kvmtool/lkvm"
ARM_CC=${ARM_CC:-aarch64-linux-gnu-gcc-9}
ARM_SYSROOT_LIB=${ARM_SYSROOT_LIB:-/usr/aarch64-linux-gnu/lib}
BB_DEB_URL=${BB_DEB_URL:-http://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_arm64.deb}

GUEST_ROOT="${OUTPUT_DIR}/guest-initramfs-root"
HOST_ROOT="${OUTPUT_DIR}/host-initramfs-root"

test -f "${KDIR}/arch/arm64/boot/Image"
test -x "${LKVM}"

mkdir -p "${OUTPUT_DIR}"

"${ARM_CC}" -static -O2 -g -Wall -Wextra -Werror -std=gnu11 \
	-I "${SCRIPT_DIR}" "${SCRIPT_DIR}/camera.c" -o "${OUTPUT_DIR}/camera"
"${ARM_CC}" -static -O2 -g -Wall -Wextra -Werror -std=gnu11 \
	-I "${SCRIPT_DIR}" "${SCRIPT_DIR}/ai.c" -o "${OUTPUT_DIR}/ai"

make -C "${SCRIPT_DIR}/driver" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 \
	KDIR="${KDIR}" M="${SCRIPT_DIR}/driver" -C "${KDIR}" modules

fetch_busybox() {
	local dest=$1
	if [ -n "${BUSYBOX:-}" ]; then
		cp "${BUSYBOX}" "${dest}"
		return
	fi
	local tmpd
	tmpd=$(mktemp -d)
	curl -fsSL -o "${tmpd}/bb.deb" "${BB_DEB_URL}"
	dpkg-deb -x "${tmpd}/bb.deb" "${tmpd}/root"
	cp "$(find "${tmpd}/root" -name busybox -type f | head -1)" "${dest}"
	rm -rf "${tmpd}"
}

# Guest rootfs: pvm_dmabuf.ko + camera/ai binaries. A single image serves
# both roles; /init picks camera or ai from the "pvmrole=" kernel param.
rm -rf "${GUEST_ROOT}"
mkdir -p "${GUEST_ROOT}"/{bin,proc,sys,dev,run}
fetch_busybox "${GUEST_ROOT}/bin/busybox"
chmod 755 "${GUEST_ROOT}/bin/busybox"
for applet in sh mount poweroff cat sleep insmod grep cut; do
	ln -sf busybox "${GUEST_ROOT}/bin/${applet}"
done
cp "${OUTPUT_DIR}/camera" "${OUTPUT_DIR}/ai" "${GUEST_ROOT}/bin/"
chmod 755 "${GUEST_ROOT}/bin/camera" "${GUEST_ROOT}/bin/ai"
cp "${SCRIPT_DIR}/driver/pvm_dmabuf.ko" "${GUEST_ROOT}/pvm_dmabuf.ko"

cat > "${GUEST_ROOT}/init" <<'GUEST_INIT'
#!/bin/sh
set -u

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null

echo "PVM_LINUX_BOOT_OK"

insmod /pvm_dmabuf.ko
if [ "$?" -ne 0 ]; then
	echo "PVM_LINUX_MODULE_LOAD_FAILED"
	poweroff -f
fi

attempt=0
while [ ! -e /dev/pvm-dmabuf ] && [ "${attempt}" -lt 200 ]; do
	sleep 0.01
	attempt=$((attempt + 1))
done
if [ ! -e /dev/pvm-dmabuf ]; then
	echo "PVM_LINUX_DEVICE_MISSING"
	poweroff -f
fi

role=$(cat /proc/cmdline | grep -o 'pvmrole=[a-z]*' | cut -d= -f2)
case "${role}" in
camera)
	/bin/camera
	rc=$?
	;;
ai)
	/bin/ai
	rc=$?
	;;
*)
	echo "PVM_LINUX_ROLE_MISSING"
	rc=1
	;;
esac
echo "PVM_LINUX_ROLE_RC: role=${role} rc=${rc}"

poweroff -f
GUEST_INIT
chmod 755 "${GUEST_ROOT}/init"
(cd "${GUEST_ROOT}" && find . | cpio -o -H newc --quiet | gzip -9) \
	> "${OUTPUT_DIR}/rootfs-pvm-buffer-guest.cpio.gz"

# Host (outer QEMU-booted) rootfs: lkvm plus the same kernel Image reused as
# the protected-guest kernel, and the guest rootfs built above.
rm -rf "${HOST_ROOT}"
mkdir -p "${HOST_ROOT}"/{bin,lib,proc,sys,dev,run,opt/pvm}
fetch_busybox "${HOST_ROOT}/bin/busybox"
chmod 755 "${HOST_ROOT}/bin/busybox"
for applet in sh mount poweroff cat sleep grep kill; do
	ln -sf busybox "${HOST_ROOT}/bin/${applet}"
done
cp "${LKVM}" "${HOST_ROOT}/bin/lkvm"
chmod 755 "${HOST_ROOT}/bin/lkvm"
cp "${ARM_SYSROOT_LIB}/libc.so.6" "${ARM_SYSROOT_LIB}/ld-linux-aarch64.so.1" "${HOST_ROOT}/lib/"
cp "${KDIR}/arch/arm64/boot/Image" "${HOST_ROOT}/opt/pvm/Image"
cp "${OUTPUT_DIR}/rootfs-pvm-buffer-guest.cpio.gz" "${HOST_ROOT}/opt/pvm/rootfs.cpio.gz"

cat > "${HOST_ROOT}/init" <<'HOST_INIT'
#!/bin/sh
set -u

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mkdir -p /tmp

echo "PVM_BUFFER_HOST_BOOT_OK"

# AI must be created first: pKVM assigns endpoint id by pVM creation order
# (first pVM = endpoint 1, second = endpoint 2), and camera.c/ai.c require
# AI=1, camera=2.
/bin/lkvm run --name pvm-buffer-ai --protected --cpus 1 --mem 256 \
	--network mode=none --console serial \
	--kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
	--params "earlycon rdinit=/init pvmrole=ai" >/tmp/ai.log 2>&1 &
ai_pid=$!

sleep 3

/bin/lkvm run --name pvm-buffer-camera --protected --cpus 1 --mem 256 \
	--network mode=none --console serial \
	--kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
	--params "earlycon rdinit=/init pvmrole=camera" >/tmp/camera.log 2>&1 &
camera_pid=$!

wait "${ai_pid}"
ai_rc=$?
wait "${camera_pid}"
camera_rc=$?

echo "PVM_BUFFER_HOST_AI_LOG_BEGIN"
cat /tmp/ai.log
echo "PVM_BUFFER_HOST_AI_LOG_END"
echo "PVM_BUFFER_HOST_CAMERA_LOG_BEGIN"
cat /tmp/camera.log
echo "PVM_BUFFER_HOST_CAMERA_LOG_END"
echo "PVM_BUFFER_HOST_RC: ai_rc=${ai_rc} camera_rc=${camera_rc}"

grep '^Mlocked:' /proc/meminfo || true
echo "PVM_BUFFER_HOST_TEST_COMPLETE"
poweroff -f
HOST_INIT
chmod 755 "${HOST_ROOT}/init"
(cd "${HOST_ROOT}" && find . | cpio -o -H newc --quiet | gzip -9) \
	> "${OUTPUT_DIR}/initramfs-pvm-buffer-host.cpio.gz"

echo "PVM_BUFFER_BUILD_OK: ${OUTPUT_DIR}"
