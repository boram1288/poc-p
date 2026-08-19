#!/bin/bash
# SPDX-License-Identifier: MIT
set -u
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-buffer"
LOG=${1:-${OUTPUT_DIR}/console-user-channel-e2e.log}
TIMEOUT=${2:-240}
"${SCRIPT_DIR}/build.sh"
timeout --signal=KILL "${TIMEOUT}" qemu-system-aarch64 \
	-machine virt,virtualization=on,gic-version=3 -cpu cortex-a57 -smp 4 -m 3G \
	-nographic -nic none < /dev/null -no-reboot \
	-kernel "${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image" \
	-initrd "${OUTPUT_DIR}/initramfs-pvm-buffer-host.cpio.gz" \
	-append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init pvme2e=1" \
	> "${LOG}" 2>&1
rc=$?
echo "QEMU_RC=${rc}"
grep -E "PVM_USER_|Mlocked:|Kernel panic|Oops|BUG:" "${LOG}" || true
if [ "${rc}" -ne 0 ] || ! grep -q "PVM_USER_CHANNEL_VALIDATION_OK" "${LOG}"; then
	echo "PVM_USER_CHANNEL_VALIDATION_FAILED"; exit 1
fi
if grep -q "Kernel panic\|Oops\|BUG:" "${LOG}"; then exit 1; fi
echo "PVM_USER_CHANNEL_E2E_OK"
