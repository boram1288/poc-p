#!/bin/bash
# SPDX-License-Identifier: MIT

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-buffer"
QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs-pvm-buffer-host.cpio.gz}
LOG=${1:-${OUTPUT_DIR}/console-pvm-vsock-smoke.log}
TIMEOUT=${2:-180}

"${SCRIPT_DIR}/build.sh"

timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine virt,virtualization=on,gic-version=3 -cpu cortex-a57 -smp 4 -m 3G \
	-nographic -nic none < /dev/null -no-reboot \
	-kernel "${KERNEL}" -initrd "${INITRD}" \
	-append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init pvmusmoke=1 pvmtransport=vsock" \
	> "${LOG}" 2>&1
rc=$?

echo "QEMU_RC=${rc}"
grep -E "PVM_USER_VSOCK_|Kernel panic|Oops|BUG:|WARNING:|Mlocked:" "${LOG}" || true

if [ "${rc}" -ne 0 ] || grep -q "Kernel panic\|Oops\|BUG:" "${LOG}"; then
	echo "PVM_USER_VSOCK_SMOKE_FAILED"
	exit 1
fi
for marker in PVM_USER_VSOCK_HOST_OK PVM_USER_VSOCK_GUEST_OK \
	PVM_USER_VSOCK_RC PVM_USER_VSOCK_SMOKE_COMPLETE; do
	if ! grep -q "${marker}" "${LOG}"; then
		echo "PVM_USER_VSOCK_SMOKE_FAILED: missing=${marker}"
		exit 1
	fi
done
if ! grep -q "PVM_USER_VSOCK_RC: host=0 guest=0" "${LOG}"; then
	echo "PVM_USER_VSOCK_SMOKE_FAILED: nonzero-rc"
	exit 1
fi
if ! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "PVM_USER_VSOCK_SMOKE_FAILED: resource-recovery"
	exit 1
fi

echo "PVM_USER_VSOCK_SMOKE_OK"
