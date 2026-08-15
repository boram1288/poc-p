#!/bin/bash
# arm64 initramfs 생성 (정적 BusyBox 기반)
# Usage: BUSYBOX=/path/to/arm64-static-busybox ./mkinitramfs.sh
#
# BusyBox를 지정하지 않으면 Ubuntu ports의 busybox-static arm64 패키지를
# 내려받아 사용한다. /bin/sh -> busybox 링크가 없으면 커널이
# `No working init found`로 패닉하므로 반드시 생성한다.

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pkvm-qemu"
WORK_DIR="${OUTPUT_DIR}/initramfs-root"
OUT="${OUTPUT_DIR}/initramfs.cpio.gz"

BB_DEB_URL=${BB_DEB_URL:-http://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_arm64.deb}

mkdir -p "${OUTPUT_DIR}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"/{bin,sbin,proc,sys,dev,tmp}

if [ -z "${BUSYBOX:-}" ]; then
    echo "== BusyBox 내려받기: ${BB_DEB_URL} =="
    TMPD=$(mktemp -d)
    trap 'rm -rf "${TMPD}"' EXIT
    curl -fsSL -o "${TMPD}/bb.deb" "${BB_DEB_URL}"
    dpkg-deb -x "${TMPD}/bb.deb" "${TMPD}/root"
    BUSYBOX=$(find "${TMPD}/root" -name busybox -type f | head -1)
fi

echo "== BusyBox: ${BUSYBOX} =="
file "${BUSYBOX}" | grep -q "ARM aarch64" || { echo "ERROR: arm64 바이너리가 아니다"; exit 1; }
file "${BUSYBOX}" | grep -q "statically linked" || { echo "ERROR: 정적 링크가 아니다"; exit 1; }

cp "${BUSYBOX}" "${WORK_DIR}/bin/busybox"
chmod 755 "${WORK_DIR}/bin/busybox"
ln -sf busybox "${WORK_DIR}/bin/sh"

cat > "${WORK_DIR}/init" <<'INIT'
#!/bin/sh
/bin/busybox mkdir -p /proc /sys /dev
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null

echo "PKVM_QEMU_BOOT_OK"

echo "== pKVM / S2MPU 관련 커널 로그 =="
/bin/busybox dmesg | /bin/busybox grep -iE "pkvm|smmu|iommu|assignable" || echo "(no match)"

echo "== IOMMU sysfs =="
if [ -d /sys/class/iommu ]; then
    /bin/busybox ls /sys/class/iommu
else
    echo "(no /sys/class/iommu)"
fi

echo "PKVM_QEMU_PROBE_DONE"
/bin/busybox poweroff -f
INIT
chmod 755 "${WORK_DIR}/init"

( cd "${WORK_DIR}" && find . | cpio -o -H newc --quiet | gzip -9 ) > "${OUT}"

echo "== 생성 완료: ${OUT} =="
ls -la "${OUT}"
