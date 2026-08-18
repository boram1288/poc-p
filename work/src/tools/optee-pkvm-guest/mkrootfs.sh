#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
SOURCE_ROOT=${SOURCE_ROOT:-${PROJECT_ROOT}/work/src/optee-pkvm/out-br/target}
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_ROOT}/work/build/optee-pkvm-guest}
ROOT_DIR=${OUTPUT_DIR}/initramfs-root
OUT=${OUTPUT_DIR}/rootfs-optee-pkvm-guest.cpio.gz

test -d "${SOURCE_ROOT}/etc"
mkdir -p "${OUTPUT_DIR}"
rm -rf "${ROOT_DIR}"
mkdir -p "${ROOT_DIR}"

cp -a "${SOURCE_ROOT}/." "${ROOT_DIR}/"
install -m 755 "${SCRIPT_DIR}/init.sh" "${ROOT_DIR}/init"
rm -f "${ROOT_DIR}/etc/init.d/S99optee-pkvm"

(cd "${ROOT_DIR}" && find . | cpio -o -H newc --quiet | gzip -9) >"${OUT}"
echo "OPTEE_PKVM_GUEST_ROOTFS_READY: ${OUT}"
