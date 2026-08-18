#!/bin/bash
# SPDX-License-Identifier: MIT

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-framework"
QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs-pvm-framework.cpio.gz}
LOG=${1:-${OUTPUT_DIR}/console-pvm-framework.log}
TIMEOUT=${2:-900}

mkdir -p "${OUTPUT_DIR}"
timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine virt,virtualization=on,gic-version=3 -cpu cortex-a57 -smp 4 -m 3G \
	-nographic -nic none < /dev/null -no-reboot -kernel "${KERNEL}" -initrd "${INITRD}" \
	-append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init" > "${LOG}" 2>&1
rc=$?

echo "QEMU_RC=${rc}"
grep -E "Protected nVHE|PVM_FRAMEWORK_|GUEST_WORKLOAD_|Mlocked:|Kernel panic" "${LOG}" || true

required=(
	PVM_FRAMEWORK_WORKLOAD_VERIFIED PVM_FRAMEWORK_WORKLOAD_REJECTED
	PVM_FRAMEWORK_PROTOCOL_NEGATIVE_OK PVM_FRAMEWORK_PROTOCOL_TEST_RC=0
	PVM_FRAMEWORK_AUTH_TEST_OK PVM_FRAMEWORK_POLICY_TEST_OK
	PVM_FRAMEWORK_IMAGE_REJECTION_OK PVM_FRAMEWORK_NORMAL_LIFECYCLE_OK
	PVM_FRAMEWORK_DAEMON_RECOVERY_OK
	PVM_FRAMEWORK_OVERLAP GUEST_WORKLOAD_STARTED GUEST_WORKLOAD_COMPLETED
	PVM_FRAMEWORK_FAULT_ISOLATION_OK PVM_FRAMEWORK_RESOURCE_RECOVERY_OK
	PVM_FRAMEWORK_VALIDATION_OK PVM_FRAMEWORK_TEST_RC=0
)
if [ "${rc}" -ne 0 ] || grep -q "Kernel panic" "${LOG}"; then
	echo "PVM_FRAMEWORK_RUN_FAILED"
	exit 1
fi
for marker in "${required[@]}"; do
	if ! grep -q "${marker}" "${LOG}"; then
		echo "PVM_FRAMEWORK_RUN_FAILED: missing=${marker}"
		exit 1
	fi
done
if ! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "PVM_FRAMEWORK_RUN_FAILED: resource-recovery"
	exit 1
fi
echo "PVM_FRAMEWORK_RUN_OK"
