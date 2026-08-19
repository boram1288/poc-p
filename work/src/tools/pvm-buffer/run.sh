#!/bin/bash
# SPDX-License-Identifier: MIT

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-buffer"
QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs-pvm-buffer-host.cpio.gz}
LOG=${1:-${OUTPUT_DIR}/console-pvm-buffer-linux.log}
TIMEOUT=${2:-300}

"${SCRIPT_DIR}/build.sh"

timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine virt,virtualization=on,gic-version=3 -cpu cortex-a57 -smp 4 -m 3G \
	-nographic -nic none < /dev/null -no-reboot \
	-kernel "${KERNEL}" -initrd "${INITRD}" \
	-append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init" \
	> "${LOG}" 2>&1
rc=$?

echo "QEMU_RC=${rc}"
grep -E "PVM_BUFFER_|PVM_LINUX_|Kernel panic|Oops|BUG:|WARNING:|Mlocked:" "${LOG}" || true

if [ "${rc}" -ne 0 ] || grep -q "Kernel panic" "${LOG}"; then
	echo "PVM_BUFFER_LINUX_RUN_FAILED"
	exit 1
fi

required=(
	PVM_LINUX_CAMERA_EXPORTED PVM_LINUX_CAMERA_READ_OK PVM_LINUX_CAMERA_COMPLETED
	PVM_LINUX_AI_IMPORTED PVM_LINUX_AI_READ_WRITE_OK PVM_LINUX_AI_COMPLETED
	PVM_BUFFER_HOST_RC PVM_BUFFER_HOST_TEST_COMPLETE
)
for marker in "${required[@]}"; do
	if ! grep -q "${marker}" "${LOG}"; then
		echo "PVM_BUFFER_LINUX_RUN_FAILED: missing=${marker}"
		exit 1
	fi
done
if ! grep -q "PVM_BUFFER_HOST_RC: ai_rc=0 camera_rc=0" "${LOG}"; then
	echo "PVM_BUFFER_LINUX_RUN_FAILED: nonzero-guest-rc"
	exit 1
fi
if ! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "PVM_BUFFER_LINUX_RUN_FAILED: resource-recovery"
	exit 1
fi

echo "PVM_BUFFER_LINUX_RUN_OK"
