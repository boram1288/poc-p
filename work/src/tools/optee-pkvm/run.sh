#!/bin/bash

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
SOURCE_DIR=${SOURCE_DIR:-${PROJECT_ROOT}/work/src/optee-pkvm}
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_ROOT}/work/build/optee-pkvm}
QEMU=${QEMU:-qemu-system-aarch64}
CPU=${CPU:-cortex-a57}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
ROOTFS=${ROOTFS:-${OUTPUT_DIR}/rootfs-optee-pkvm.cpio.gz}
UIMAGE=${UIMAGE:-${OUTPUT_DIR}/uImage}
UROOTFS=${UROOTFS:-${OUTPUT_DIR}/rootfs.cpio.uboot}
BL1=${BL1:-${SOURCE_DIR}/out/bin/bl1.bin}
LOG=${1:-${OUTPUT_DIR}/console-optee-pkvm.log}
SECURE_LOG=${SECURE_LOG:-${OUTPUT_DIR}/secure-optee.log}
TIMEOUT=${2:-1200}

test -f "${KERNEL}"
test -f "${ROOTFS}"
test -f "${UIMAGE}"
test -f "${UROOTFS}"
test -f "${BL1}"
mkdir -p "${OUTPUT_DIR}"
LOG=$(realpath -m "${LOG}")
SECURE_LOG=$(realpath -m "${SECURE_LOG}")
ln -sf "${UIMAGE}" "${SOURCE_DIR}/out/bin/uImage"
ln -sf "${UROOTFS}" "${SOURCE_DIR}/out/bin/rootfs.cpio.uboot"

(cd "${SOURCE_DIR}/out/bin" && timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine virt,acpi=off,secure=on,virtualization=on,gic-version=3 \
	-cpu "${CPU}" -smp 4 -m 3G -nographic -nic none -no-reboot \
	-semihosting-config enable=on,target=native \
	-bios "${BL1}" -kernel "${KERNEL}" -initrd "${ROOTFS}" \
	-append "console=ttyAMA0,38400 keep_bootcon kvm-arm.mode=protected" \
	-serial mon:stdio -serial "file:${SECURE_LOG}" \
	>"${LOG}" 2>&1)
rc=$?

echo "QEMU_RC=${rc}"
grep -E "Booting Trusted Firmware|OP-TEE version|Initialized driver|Protected nVHE|COEX_|OPTEE_PKVM_|Mlocked:|Kernel panic" \
	"${LOG}" "${SECURE_LOG}" 2>/dev/null || true

if [ "${rc}" -ne 0 ] ||
   ! grep -q "Booting Trusted Firmware" "${LOG}" ||
   ! grep -q "OP-TEE version: 4.7.0" "${SECURE_LOG}" ||
   ! grep -q "optee: initialized driver" "${LOG}" ||
   ! grep -q "Protected nVHE mode initialized successfully" "${LOG}" ||
   ! grep -Eq "COEX_KVM_ACTIVE: .* kvm_fds=[3-9]" "${LOG}" ||
   ! grep -q "COEX_AES_DURING_PVM_OK" "${LOG}" ||
   [ "$(grep -c "Clear text and decoded text match" "${LOG}")" -lt 2 ] ||
   ! grep -q "COEX_PVM_OK: rc=0" "${LOG}" ||
   ! grep -q "COEX_AES_REOPEN_OK" "${LOG}" ||
   ! grep -q "OPTEE_PKVM_COEX_ALL_OK" "${LOG}" ||
   ! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "OPTEE_PKVM_VALIDATION_FAILED" | tee -a "${LOG}"
	exit 1
fi

echo "OPTEE_PKVM_VALIDATION_OK" | tee -a "${LOG}"
