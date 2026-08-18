#!/bin/bash
# SPDX-License-Identifier: MIT

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-framework"
ROOT_DIR="${OUTPUT_DIR}/initramfs-root"
OUT="${OUTPUT_DIR}/initramfs-pvm-framework.cpio.gz"
BB_DEB_URL=${BB_DEB_URL:-http://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_arm64.deb}

"${SCRIPT_DIR}/build.sh"
rm -rf "${ROOT_DIR}"
mkdir -p "${ROOT_DIR}"/{bin,proc,sys,dev,run,images}

if [ -z "${BUSYBOX:-}" ]; then
	TMPD=$(mktemp -d)
	trap 'rm -rf "${TMPD}"' EXIT
	curl -fsSL -o "${TMPD}/bb.deb" "${BB_DEB_URL}"
	dpkg-deb -x "${TMPD}/bb.deb" "${TMPD}/root"
	BUSYBOX=$(find "${TMPD}/root" -name busybox -type f | head -1)
fi
cp "${BUSYBOX}" "${ROOT_DIR}/bin/busybox"
cp "${OUTPUT_DIR}/arm64/pvmd" "${OUTPUT_DIR}/arm64/pvm-runner" \
	"${OUTPUT_DIR}/arm64/pvmctl" "${OUTPUT_DIR}/arm64/phase07-app" \
	"${OUTPUT_DIR}/arm64/protocol-negative" "${ROOT_DIR}/bin/"
cp "${OUTPUT_DIR}/images/phase07-guest.img" \
	"${OUTPUT_DIR}/images/phase07-guest-tampered.img" \
	"${OUTPUT_DIR}/images/SHA256SUMS" \
	"${OUTPUT_DIR}/images/workload-verification.log" "${ROOT_DIR}/images/"
chmod 755 "${ROOT_DIR}/bin/"*
for applet in sh mount poweroff cat sleep kill grep; do
	ln -sf busybox "${ROOT_DIR}/bin/${applet}"
done

cat > "${ROOT_DIR}/init" <<'INIT'
#!/bin/sh
/bin/mount -t proc proc /proc
/bin/mount -t sysfs sysfs /sys
/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null
/bin/cat /images/workload-verification.log
for device in 10000000.pkvm-edu 10100000.pkvm-edu; do
	if [ -e "/sys/bus/platform/devices/${device}/driver_override" ]; then
		echo vfio-platform > "/sys/bus/platform/devices/${device}/driver_override"
		echo "${device}" > /sys/bus/platform/drivers/vfio-platform/bind
		group=$(/bin/busybox basename "$(/bin/busybox readlink "/sys/bus/platform/devices/${device}/iommu_group")")
		if [ -e "/dev/vfio/${group}" ]; then
			echo "PVM_FRAMEWORK_VFIO_READY: device=${device} group=${group}"
		else
			echo "PVM_FRAMEWORK_VFIO_FAILED: device=${device} group=${group}"
		fi
	fi
done
/bin/pvmd &
daemon_pid=$!
attempt=0
while [ ! -S /run/pvm-framework/pvmd.sock ] && [ "${attempt}" -lt 200 ]; do
	/bin/sleep 0.01
	attempt=$((attempt + 1))
done
/bin/protocol-negative
protocol_rc=$?
echo "PVM_FRAMEWORK_PROTOCOL_TEST_RC=${protocol_rc}"
/bin/phase07-app "${daemon_pid}"
rc=$?
echo "PVM_FRAMEWORK_TEST_RC=${rc}"
/bin/kill "${daemon_pid}" 2>/dev/null || true
wait "${daemon_pid}" 2>/dev/null || true
/bin/grep '^Mlocked:' /proc/meminfo || true
echo "PVM_FRAMEWORK_TEST_COMPLETE"
/bin/poweroff -f
INIT
chmod 755 "${ROOT_DIR}/init"

(cd "${ROOT_DIR}" && find . | cpio -o -H newc --quiet | gzip -9) > "${OUT}"
echo "Created ${OUT}"
