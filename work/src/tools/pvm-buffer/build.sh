#!/bin/bash
# SPDX-License-Identifier: MIT

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-buffer"
USER_CHANNEL_DIR="${PROJECT_ROOT}/work/src/tools/pvm-user-channel"
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
"${ARM_CC}" -static -O2 -g -Wall -Wextra -Werror -std=gnu11 \
	-I "${USER_CHANNEL_DIR}" "${USER_CHANNEL_DIR}/pvm_user_channel.c" \
	"${USER_CHANNEL_DIR}/vsock_smoke.c" -o "${OUTPUT_DIR}/pvm_vsock_smoke"
"${ARM_CC}" -static -O2 -g -Wall -Wextra -Werror -std=gnu11 \
	-I "${USER_CHANNEL_DIR}" "${USER_CHANNEL_DIR}/pvm_user_channel.c" \
	"${USER_CHANNEL_DIR}/pvm_message.c" "${USER_CHANNEL_DIR}/pvm_e2e.c" \
	-o "${OUTPUT_DIR}/pvm_e2e"

make -C "${SCRIPT_DIR}/driver" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 \
	KDIR="${KDIR}" M="${SCRIPT_DIR}/driver" -C "${KDIR}" modules
make -C "${USER_CHANNEL_DIR}/driver" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 \
	KDIR="${KDIR}" M="${USER_CHANNEL_DIR}/driver" -C "${KDIR}" modules

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
cp "${OUTPUT_DIR}/camera" "${OUTPUT_DIR}/ai" "${OUTPUT_DIR}/pvm_vsock_smoke" \
	"${OUTPUT_DIR}/pvm_e2e" "${GUEST_ROOT}/bin/"
chmod 755 "${GUEST_ROOT}/bin/camera" "${GUEST_ROOT}/bin/ai"
chmod 755 "${GUEST_ROOT}/bin/pvm_vsock_smoke"
cp "${SCRIPT_DIR}/driver/pvm_dmabuf.ko" "${GUEST_ROOT}/pvm_dmabuf.ko"
cp "${USER_CHANNEL_DIR}/driver/pvm_message.ko" "${GUEST_ROOT}/pvm_message.ko"

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
insmod /pvm_message.ko
if [ "$?" -ne 0 ]; then echo "PVM_USER_MESSAGE_MODULE_LOAD_FAILED"; poweroff -f; fi

attempt=0
while [ ! -e /dev/pvm-dmabuf ] && [ "${attempt}" -lt 200 ]; do
	sleep 0.01
	attempt=$((attempt + 1))
done
if [ ! -e /dev/pvm-dmabuf ]; then
	echo "PVM_LINUX_DEVICE_MISSING"
	poweroff -f
fi
transport=$(cat /proc/cmdline | grep -o 'pvmtransport=[a-z]*' | cut -d= -f2)

role=$(cat /proc/cmdline | grep -o 'pvmrole=[a-z]*' | cut -d= -f2)
case "${role}" in
camera)
	if [ "${transport}" = "vsock" ]; then /bin/pvm_e2e camera; else /bin/camera; fi
	rc=$?
	;;
ai)
	if [ "${transport}" = "vsock" ]; then /bin/pvm_e2e ai; else /bin/ai; fi
	rc=$?
	;;
faultcamera)
	/bin/pvm_e2e fault-camera; rc=$?
	;;
faultai)
	/bin/pvm_e2e fault-ai; rc=$?
	;;
smoke)
	/bin/pvm_vsock_smoke guest
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
cp "${OUTPUT_DIR}/pvm_vsock_smoke" "${OUTPUT_DIR}/pvm_e2e" "${HOST_ROOT}/bin/"
chmod 755 "${HOST_ROOT}/bin/pvm_vsock_smoke"
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

fault=$(cat /proc/cmdline | grep -o 'pvmfault=[01]' | cut -d= -f2 || true)
if [ "${fault}" = "1" ]; then
	/bin/pvm_e2e fault-host >/tmp/fault-host.log 2>&1 & host_pid=$!
	sleep 1
	/bin/lkvm run --name pvm-fault-ai --protected --vsock 4101 --cpus 1 --mem 256 \
		--network mode=none --console serial --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
		--params "earlycon rdinit=/init pvmrole=faultai pvmtransport=vsock" >/tmp/fault-ai.log 2>&1 & ai_pid=$!
	sleep 2
	/bin/lkvm run --name pvm-fault-camera --protected --vsock 4102 --cpus 1 --mem 256 \
		--network mode=none --console serial --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
		--params "earlycon rdinit=/init pvmrole=faultcamera pvmtransport=vsock" >/tmp/fault-camera.log 2>&1 & camera_pid=$!
	wait "${camera_pid}"; camera_rc=$?; wait "${ai_pid}"; ai_rc=$?; wait "${host_pid}"; host_rc=$?
	cat /tmp/fault-host.log /tmp/fault-ai.log /tmp/fault-camera.log
	echo "PVM_USER_FAULT_RC: host=${host_rc} ai=${ai_rc} camera=${camera_rc}"
	grep '^Mlocked:' /proc/meminfo || true
	if [ "${host_rc}" = 0 ] && [ "${ai_rc}" = 0 ] && [ "${camera_rc}" = 0 ]; then echo "PVM_USER_FAULT_VALIDATION_OK"; fi
	poweroff -f
fi

e2e=$(cat /proc/cmdline | grep -o 'pvme2e=[01]' | cut -d= -f2 || true)
if [ "${e2e}" = "1" ]; then
	/bin/pvm_e2e host >/tmp/e2e-host.log 2>&1 &
	e2e_host_pid=$!
	sleep 1
	/bin/lkvm run --name pvm-e2e-ai --protected --vsock 4101 --cpus 1 --mem 256 \
		--network mode=none --console serial --kernel /opt/pvm/Image \
		--initrd /opt/pvm/rootfs.cpio.gz \
		--params "earlycon rdinit=/init pvmrole=ai pvmtransport=vsock" >/tmp/e2e-ai.log 2>&1 &
	ai_pid=$!
	sleep 2
	/bin/lkvm run --name pvm-e2e-camera --protected --vsock 4102 --cpus 1 --mem 256 \
		--network mode=none --console serial --kernel /opt/pvm/Image \
		--initrd /opt/pvm/rootfs.cpio.gz \
		--params "earlycon rdinit=/init pvmrole=camera pvmtransport=vsock" >/tmp/e2e-camera.log 2>&1 &
	camera_pid=$!
	wait "${camera_pid}"; camera_rc=$?
	wait "${ai_pid}"; ai_rc=$?
	wait "${e2e_host_pid}"; host_rc=$?
	cat /tmp/e2e-host.log /tmp/e2e-ai.log /tmp/e2e-camera.log
	echo "PVM_USER_E2E_RC: host=${host_rc} ai=${ai_rc} camera=${camera_rc}"
	grep '^Mlocked:' /proc/meminfo || true
	if [ "${host_rc}" = "0" ] && [ "${ai_rc}" = "0" ] && [ "${camera_rc}" = "0" ]; then
		echo "PVM_USER_CHANNEL_VALIDATION_OK"
	fi
	poweroff -f
fi

host_smoke=$(cat /proc/cmdline | grep -o 'pvmusmoke=[01]' | cut -d= -f2 || true)
if [ "${host_smoke}" = "1" ]; then
	transport=$(cat /proc/cmdline | grep -o 'pvmtransport=[a-z]*' | cut -d= -f2)
	transport_upper=VSOCK
	if [ -e /dev/vhost-vsock ]; then echo "PVM_USER_VHOST_DEVICE_OK"; else echo "PVM_USER_VHOST_DEVICE_MISSING"; fi
	/bin/pvm_vsock_smoke host >/tmp/vsock-host.log 2>&1 &
	host_smoke_pid=$!
	sleep 1
	channel_args="--vsock 4102"
	echo "PVM_USER_${transport_upper}_LKVM_START"
	/bin/lkvm run --name pvm-buffer-${transport}-smoke --protected ${channel_args} \
		--cpus 1 --mem 256 --network mode=none --console serial \
		--kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
		--params "earlycon rdinit=/init pvmrole=smoke pvmtransport=${transport}" >/tmp/${transport}-guest.log 2>&1
	guest_smoke_rc=$?
	echo "PVM_USER_${transport_upper}_LKVM_DONE: rc=${guest_smoke_rc}"
	wait "${host_smoke_pid}"
	host_smoke_rc=$?
	if [ "${transport}" = "vsock" ]; then cat /tmp/vsock-host.log /tmp/vsock-guest.log 2>/dev/null || true; fi
	echo "PVM_USER_${transport_upper}_RC: host=${host_smoke_rc} guest=${guest_smoke_rc}"
	grep '^Mlocked:' /proc/meminfo || true
	echo "PVM_USER_${transport_upper}_SMOKE_COMPLETE"
	poweroff -f
fi

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
