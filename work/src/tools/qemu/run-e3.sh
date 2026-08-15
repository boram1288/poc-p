#!/bin/bash
# E-3 스모크 테스트: virt,iommu=smmuv3 로 pKVM protected 부팅
# Usage: ./run-e3.sh [logfile] [timeout_seconds]
#
# Phase 03의 run.sh와 다른 점은 머신 옵션에 iommu=smmuv3 를 추가하는 것뿐이다.
# 목적은 `Found N assignable devices` 의 N이 0이 아닌 값이 되는지 확인하는 것이다.

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pkvm-qemu"

QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs.cpio.gz}
LOG=${1:-${OUTPUT_DIR}/console-e3-smmuv3.log}
TIMEOUT=${2:-600}

mkdir -p "${OUTPUT_DIR}"

MACHINE="virt,virtualization=on,gic-version=3,iommu=smmuv3"
CPU="max"
SMP=2
MEM=2G
# EL2 IOMMU 풀 페이지 수. 지정하지 않으면 커널이
# `Missing memory for the IOMMU pool, need 0x609 pages` 로 경고하고
# EL2 iommu 드라이버 초기화가 -19 로 실패한다 (2026-08-15 실측).
#
# 주의: 커널 경고는 필요량을 16진수(0x609 = 1545)로 출력하지만,
# 파서는 10진수만 받는다. arch/arm64/kvm/iommu.c 의
# early_hyp_iommu_pages() 가 kstrtoul(arg, 10, ...) 를 쓴다.
# `0x609` 를 그대로 넘기면 파싱에 실패하고 파라미터가 무시된다.
# 값은 요구량 1545에 여유를 더한 2048이다.
HYP_IOMMU_PAGES=${HYP_IOMMU_PAGES:-2048}

CMDLINE="console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init"
if [ -n "${HYP_IOMMU_PAGES}" ]; then
    CMDLINE="${CMDLINE} kvm-arm.hyp_iommu_pages=${HYP_IOMMU_PAGES}"
fi

echo "== E-3 smoke test =="
echo "== qemu:   $(${QEMU} --version | head -1) =="
echo "== machine: ${MACHINE} =="
echo "== kernel: ${KERNEL} =="
echo "== log:    ${LOG} (timeout ${TIMEOUT}s) =="

# stdin 을 /dev/null 로 끊는 이유는 run.sh 와 같다 (job control 정지 방지).
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

echo "== Phase 03 마커 =="
grep -E "CPU: All CPU\(s\) started|Protected KVM|Protected nVHE mode initialized|PKVM_QEMU_BOOT_OK|Kernel panic" ${LOG} || echo "(none found)"

echo "== S2MPU 관련 =="
grep -iE "assignable|iommu|smmu" ${LOG} || echo "(none found)"

exit ${RC}
