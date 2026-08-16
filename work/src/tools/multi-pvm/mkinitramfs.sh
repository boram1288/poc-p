#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/multi-pvm"
ROOT_DIR="${OUTPUT_DIR}/initramfs-root"
PKVM="${PROJECT_ROOT}/work/build/pkvm-pvm/kselftest-build/arm64/pkvm"
OUT="${OUTPUT_DIR}/initramfs-multi-pvm.cpio.gz"
BB_DEB_URL=${BB_DEB_URL:-http://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_arm64.deb}

test -x "${PKVM}"
mkdir -p "${OUTPUT_DIR}"
rm -rf "${ROOT_DIR}"
mkdir -p "${ROOT_DIR}"/{bin,proc,sys,dev,tmp}

if [ -z "${BUSYBOX:-}" ]; then
	TMPD=$(mktemp -d)
	trap 'rm -rf "${TMPD}"' EXIT
	curl -fsSL -o "${TMPD}/bb.deb" "${BB_DEB_URL}"
	dpkg-deb -x "${TMPD}/bb.deb" "${TMPD}/root"
	BUSYBOX=$(find "${TMPD}/root" -name busybox -type f | head -1)
fi

cp "${BUSYBOX}" "${ROOT_DIR}/bin/busybox"
cp "${PKVM}" "${ROOT_DIR}/bin/pkvm"
cp "${SCRIPT_DIR}/run-two-pvms.sh" "${ROOT_DIR}/bin/run-two-pvms.sh"
chmod 755 "${ROOT_DIR}/bin/"*
for applet in sh mkdir mount sed sleep readlink grep poweroff; do
	ln -sf busybox "${ROOT_DIR}/bin/${applet}"
done

cat > "${ROOT_DIR}/init" <<'INIT'
#!/bin/sh
/bin/mount -t proc proc /proc
/bin/mount -t sysfs sysfs /sys
/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null

/bin/run-two-pvms.sh
rc=$?
echo "MULTI_PVM_RUNNER_RC=${rc}"
/bin/grep '^Mlocked:' /proc/meminfo || true
echo "MULTI_PVM_TEST_COMPLETE"
/bin/poweroff -f
INIT
chmod 755 "${ROOT_DIR}/init"

(cd "${ROOT_DIR}" && find . | cpio -o -H newc --quiet | gzip -9) > "${OUT}"
echo "Created ${OUT}"
