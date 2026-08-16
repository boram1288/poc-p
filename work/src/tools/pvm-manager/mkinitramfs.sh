#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-manager"
ROOT_DIR="${OUTPUT_DIR}/initramfs-root"
PKVM="${PROJECT_ROOT}/work/build/pkvm-pvm/kselftest-build/arm64/pkvm"
OUT="${OUTPUT_DIR}/initramfs-pvm-manager.cpio.gz"
BB_DEB_URL=${BB_DEB_URL:-http://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_arm64.deb}

test -x "${PKVM}"
mkdir -p "${OUTPUT_DIR}"
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
cp "${PKVM}" "${ROOT_DIR}/images/pkvm.bin"
cp "${PKVM}" "${ROOT_DIR}/images/pkvm-tampered.bin"
printf 'tampered\n' >> "${ROOT_DIR}/images/pkvm-tampered.bin"
(cd "${ROOT_DIR}/images" && sha256sum pkvm.bin > SHA256SUMS)
cp "${SCRIPT_DIR}/pvm-manager.sh" "${ROOT_DIR}/bin/"
cp "${SCRIPT_DIR}/lifecycle-test.sh" "${ROOT_DIR}/bin/"
chmod 755 "${ROOT_DIR}/bin/"* "${ROOT_DIR}/images/"*.bin
for applet in sh mkdir mount stat sha256sum sed sleep readlink grep poweroff chown cat; do
	ln -sf busybox "${ROOT_DIR}/bin/${applet}"
done

cat > "${ROOT_DIR}/init" <<'INIT'
#!/bin/sh
/bin/mount -t proc proc /proc
/bin/mount -t sysfs sysfs /sys
/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null
/bin/lifecycle-test.sh
rc=$?
echo "PVM_MANAGER_RUNNER_RC=${rc}"
/bin/grep '^Mlocked:' /proc/meminfo || true
echo "PVM_MANAGER_TEST_COMPLETE"
/bin/poweroff -f
INIT
chmod 755 "${ROOT_DIR}/init"

(cd "${ROOT_DIR}" && find . | cpio -o -H newc --quiet | gzip -9) > "${OUT}"
echo "Created ${OUT}"
