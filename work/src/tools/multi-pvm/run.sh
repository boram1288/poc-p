#!/bin/bash

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/multi-pvm"

QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs-multi-pvm.cpio.gz}
CPU=${CPU:-cortex-a57}
LOG=${1:-${OUTPUT_DIR}/console-multi-pvm.log}
TIMEOUT=${2:-900}

mkdir -p "${OUTPUT_DIR}"
timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine virt,virtualization=on,gic-version=3 \
	-cpu "${CPU}" -smp 4 -m 3G -nographic -nic none \
	< /dev/null -no-reboot -kernel "${KERNEL}" -initrd "${INITRD}" \
	-append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init" \
	> "${LOG}" 2>&1
rc=$?

echo "QEMU_RC=${rc}"
grep -E "Protected nVHE|MULTI_(KVM_OVERLAP|NORMAL_RESULT|FAULT_RESULT|PVM_ALL_OK|PVM_RUNNER_RC|PVM_TEST_COMPLETE)|Mlocked:|Kernel panic" "${LOG}" || true

if [ "${rc}" -ne 0 ] ||
   ! grep -q "MULTI_KVM_OVERLAP:" "${LOG}" ||
   ! grep -q "MULTI_NORMAL_RESULT: camera_rc=0 ai_rc=0" "${LOG}" ||
   ! grep -q "MULTI_FAULT_RESULT: camera_rc=137 ai_rc=0" "${LOG}" ||
   ! grep -q "AI_SURVIVOR: All ok!" "${LOG}" ||
   ! grep -q "MULTI_PVM_RUNNER_RC=0" "${LOG}" ||
   ! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "MULTI_PVM_VALIDATION_FAILED"
	exit 1
fi

echo "MULTI_PVM_VALIDATION_OK"
