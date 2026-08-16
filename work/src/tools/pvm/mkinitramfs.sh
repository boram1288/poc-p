#!/bin/bash
# Build the arm64 initramfs used by the protected-VM selftest.

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pkvm-pvm"
ROOT_DIR="${OUTPUT_DIR}/initramfs-root"
SELFTEST_DIR="${OUTPUT_DIR}/kselftest-build/arm64"
OUT="${OUTPUT_DIR}/initramfs-pvm.cpio.gz"
BB_DEB_URL=${BB_DEB_URL:-http://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_arm64.deb}

test -x "${SELFTEST_DIR}/pkvm"
test -x "${SELFTEST_DIR}/hello_el2"
test -x "${OUTPUT_DIR}/bin/capcheck"

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
cp "${OUTPUT_DIR}/bin/capcheck" "${ROOT_DIR}/bin/capcheck"
cp "${SELFTEST_DIR}/hello_el2" "${ROOT_DIR}/bin/hello_el2"
cp "${SELFTEST_DIR}/pkvm" "${ROOT_DIR}/bin/pkvm"
chmod 755 "${ROOT_DIR}/bin/"*
ln -sf busybox "${ROOT_DIR}/bin/sh"

cat > "${ROOT_DIR}/init" <<'INIT'
#!/bin/sh
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null

/bin/capcheck
echo "PVM_TEST_CAPCHECK: rc=$?"
/bin/hello_el2
echo "PVM_TEST_HELLO_EL2: rc=$?"
/bin/pkvm
echo "PVM_TEST_PKVM: rc=$?"
/bin/busybox grep '^Mlocked:' /proc/meminfo || true
echo "PVM_TEST_COMPLETE"
/bin/busybox poweroff -f
INIT
chmod 755 "${ROOT_DIR}/init"

(cd "${ROOT_DIR}" && find . | cpio -o -H newc --quiet | gzip -9) > "${OUT}"
echo "Created ${OUT}"
