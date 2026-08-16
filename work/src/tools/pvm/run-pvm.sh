#!/bin/bash
# pKVM pVM (protected guest) QEMU test
# Usage: ./run-pvm.sh [mode] [logfile] [timeout_seconds]
#   mode: protected | nvhe
#
# 자가진단 강화 (2026-08-08):
#   - 실행 시각 / 이전 로그 크기 / QEMU 시작 직후 상태 / 종료 시각을 시작~종료
#     마커로 기록해, "로그 0바이트" 실패가 (a) QEMU 즉시 실패인지
#     (b) 리다이렉트만 되고 QEMU가 실행조차 안 됐는지 구분할 수 있게 한다.
#   - 실패 시 stderr 캡처와 로그 head/tail 을 화면에도 출력한다.

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pkvm-pvm"

QEMU=${QEMU:-/usr/bin/qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs-pvm.cpio.gz}
MODE=${1:-protected}
LOG=${2:-${OUTPUT_DIR}/console-pvm-protected.log}
TIMEOUT=${3:-900}

mkdir -p "${OUTPUT_DIR}"

MACHINE="virt,virtualization=on,gic-version=3"
CPU=${CPU:-max}
SMP=2
MEM=2G
CMDLINE="console=ttyAMA0 kvm-arm.mode=${MODE} earlycon rdinit=/init"

echo "== pKVM pVM QEMU test: mode=${MODE} =="
echo "== kernel: ${KERNEL} =="
echo "== initrd: ${INITRD} (pVM selftest initramfs) =="
echo "== log: ${LOG} (timeout ${TIMEOUT}s) =="
echo "== START: $(date '+%F %T') prior_log_size=$(stat -c%s "${LOG}" 2>/dev/null || echo 0) =="

# 1) QEMU stderr/stdout 은 로그로, exit code 는 별도 파일로 보존
#    stdin: -nographic 은 stdin 을 시리얼 콘솔로 사용하므로, 터미널(tty)에서
#    실행하면 QEMU 가 SIGTTIN(job control) 으로 정지해 로그가 0바이트로 남는다.
#    반드시 < /dev/null 로 stdin 을 끊는다 (2026-08-08 재현 확인).
ERRTMP=$(mktemp /tmp/run-pvm-err.XXXXXX)
timeout --signal=KILL ${TIMEOUT} ${QEMU} \
    -machine ${MACHINE} \
    -cpu ${CPU} \
    -smp ${SMP} \
    -m ${MEM} \
    -nographic \
    -nic none \
    < /dev/null \
    -no-reboot \
    -kernel ${KERNEL} \
    -initrd ${INITRD} \
    -append "${CMDLINE}" \
    > ${LOG} 2> ${ERRTMP}
RC=$?
echo "== QEMU exit code: ${RC} at $(date '+%F %T') =="
echo "== stderr 캡처 (${ERRTMP}) =="
if [ -s "${ERRTMP}" ]; then
    cat "${ERRTMP}"
else
    echo "(stderr 없음)"
fi
rm -f "${ERRTMP}"

# 2) 중단/타임아웃 여부
if [ ${RC} -eq 137 ] || [ ${RC} -eq 124 ]; then
    echo "== WARNING: timed out (SIGKILL) - guest may have hung =="
fi

# 3) 로그 진단: 0바이트 실패의 원인 구분
echo "== log 검사: after_size=$(stat -c%s "${LOG}" 2>/dev/null || echo 0), RC=${RC} =="
if [ ! -s "${LOG}" ]; then
    echo "!! 로그가 비어 있음 (0바이트). 원인 후보:"
    echo "   - QEMU 시작 직전 실패 (RC=${RC}) → stderr 캡처 참고"
    echo "   - QEMU 바이너리/커널/initrd 경로 문제"
    echo "   - 시작 직후 즉시 SIGKILL (RC=137)"
fi

echo "== key markers =="
grep -E "Protected nVHE mode initialized|PVM_TEST_KVM_DEV|KVM_CAP_ARM_PROTECTED_VM|KVM_CREATE_VM|KVM_CREATE_VCPU|PVM_TEST_CAPCHECK|PVM_TEST_HELLO_EL2|Guest heartbeat|Guest done|All ok|Caught expected segfault|PVM_TEST_PKVM|PVM_TEST_COMPLETE|Kernel panic" ${LOG} || echo "(none found)"
echo "== log head =="
head -3 ${LOG} 2>/dev/null
echo "== log tail =="
tail -3 ${LOG} 2>/dev/null
echo "== END: $(date '+%F %T') =="
exit ${RC}
