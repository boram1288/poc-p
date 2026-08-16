#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
SOURCE_DIR=${SOURCE_DIR:-${PROJECT_ROOT}/work/src/optee-pkvm}
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_ROOT}/work/build/optee-pkvm}
SOURCE_ROOT=${SOURCE_ROOT:-${SOURCE_DIR}/out-br/target}
PKVM=${PKVM:-${PROJECT_ROOT}/work/build/pkvm-pvm/kselftest-build/arm64/pkvm}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
ROOT_DIR=${OUTPUT_DIR}/initramfs-root
OUT=${OUTPUT_DIR}/rootfs-optee-pkvm.cpio.gz
UIMAGE=${OUTPUT_DIR}/uImage
UROOTFS=${OUTPUT_DIR}/rootfs.cpio.uboot
MKIMAGE=${SOURCE_DIR}/u-boot/tools/mkimage

test -d "${SOURCE_ROOT}/etc/init.d"
test -x "${PKVM}"
test -f "${KERNEL}"
test -x "${MKIMAGE}"
mkdir -p "${OUTPUT_DIR}"
rm -rf "${ROOT_DIR}"
mkdir -p "${ROOT_DIR}"

cp -a "${SOURCE_ROOT}/." "${ROOT_DIR}/"
install -m 755 "${SCRIPT_DIR}/init.sh" "${ROOT_DIR}/init"
install -m 755 "${PKVM}" "${ROOT_DIR}/usr/bin/pkvm"
install -m 755 "${SCRIPT_DIR}/coexist-test.sh" \
	"${ROOT_DIR}/usr/bin/optee-pkvm-coexist"

cat >"${ROOT_DIR}/etc/init.d/S99optee-pkvm" <<'INIT'
#!/bin/sh
echo "OPTEE_PKVM_INIT_START"
/usr/bin/optee-pkvm-coexist
rc=$?
echo "OPTEE_PKVM_INIT_RC=${rc}"
poweroff -f
INIT
chmod 755 "${ROOT_DIR}/etc/init.d/S99optee-pkvm"

(cd "${ROOT_DIR}" && find . | cpio -o -H newc --quiet | gzip -9) >"${OUT}"
"${MKIMAGE}" -A arm64 -O linux -T kernel -C none \
	-a 0x42200000 -e 0x42200000 -n "Linux pKVM kernel" \
	-d "${KERNEL}" "${UIMAGE}"
"${MKIMAGE}" -A arm64 -T ramdisk -C gzip \
	-a 0x45000000 -e 0x45000000 -n "OP-TEE pKVM rootfs" \
	-d "${OUT}" "${UROOTFS}"
echo "OPTEE_PKVM_ROOTFS_READY: ${OUT}"
