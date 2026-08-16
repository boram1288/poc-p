#!/bin/bash

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-manager"
QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs-pvm-manager.cpio.gz}
LOG=${1:-${OUTPUT_DIR}/console-pvm-manager.log}
TIMEOUT=${2:-900}

mkdir -p "${OUTPUT_DIR}"
timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine virt,virtualization=on,gic-version=3 -cpu cortex-a57 -smp 4 -m 3G \
	-nographic -nic none < /dev/null -no-reboot -kernel "${KERNEL}" -initrd "${INITRD}" \
	-append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init" > "${LOG}" 2>&1
rc=$?

echo "QEMU_RC=${rc}"
grep -E "Protected nVHE|LIFECYCLE_|PVM_MANAGER_(AUTH_DENIED|IMAGE_REJECTED|CREATED|STOPPED|RUNNER_RC|TEST_COMPLETE)|Mlocked:|Kernel panic" "${LOG}" || true

if [ "${rc}" -ne 0 ] ||
   ! grep -q "LIFECYCLE_AUTH_DENIAL_OK" "${LOG}" ||
   ! grep -q "LIFECYCLE_IMAGE_REJECTION_OK" "${LOG}" ||
   ! grep -q "LIFECYCLE_RUNNING:" "${LOG}" ||
   ! grep -q "LIFECYCLE_NORMAL_STOP_OK" "${LOG}" ||
   ! grep -q "LIFECYCLE_FAULT_ISOLATION_OK" "${LOG}" ||
   ! grep -q "PVM_MANAGER_RUNNER_RC=0" "${LOG}" ||
   ! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "PVM_MANAGER_VALIDATION_FAILED"
	exit 1
fi
echo "PVM_MANAGER_VALIDATION_OK"
