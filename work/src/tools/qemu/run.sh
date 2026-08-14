#!/bin/bash
# pKVM QEMU boot test (protected mode)
# Usage: ./run.sh [mode] [logfile] [timeout_seconds]

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pkvm-qemu"

QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs.cpio.gz}
MODE=${1:-protected}
LOG=${2:-${OUTPUT_DIR}/console-protected.log}
TIMEOUT=${3:-400}

mkdir -p "${OUTPUT_DIR}"

MACHINE="virt,virtualization=on,gic-version=3"
CPU="max"
SMP=2
MEM=2G
CMDLINE="console=ttyAMA0 kvm-arm.mode=${MODE} earlycon rdinit=/init"

echo "== pKVM QEMU boot test: mode=${MODE} =="
echo "== kernel: ${KERNEL} =="
echo "== initrd: ${INITRD} =="
echo "== log: ${LOG} (timeout ${TIMEOUT}s) =="

# stdin: -nographic 은 stdin 을 시리얼 콘솔로 사용하므로, 터미널(tty)에서
# 실행하면 QEMU 가 SIGTTIN(job control) 으로 정지해 로그가 0바이트로 남는다.
# 반드시 < /dev/null 로 stdin 을 끊는다 (2026-08-08 재현 확인).
timeout --signal=KILL ${TIMEOUT} ${QEMU} \
    -machine ${MACHINE} \
    -cpu ${CPU} \
    -smp ${SMP} \
    -m ${MEM} \
    -nographic \
    < /dev/null \
    -no-reboot \
    -kernel ${KERNEL} \
    -initrd ${INITRD} \
    -append "${CMDLINE}" \
    > ${LOG} 2>&1

RC=$?
echo "== QEMU exit code: ${RC} =="
if [ ${RC} -eq 137 ] || [ ${RC} -eq 124 ]; then
    echo "== WARNING: timed out (SIGKILL) - guest may have hung =="
fi

echo "== key markers =="
grep -E "CPU: All CPU\(s\) started|Protected KVM|Protected nVHE mode initialized|PKVM_QEMU_BOOT_OK|Kernel panic" ${LOG} || echo "(none found)"
exit ${RC}
