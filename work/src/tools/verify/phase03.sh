#!/bin/bash
# Phase 03: QEMU protected 부팅 검증
# 참고 문서: docs/phase-03/README.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 03
require_prev_phase 02

require_file "${VERIFY_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image"

if [ ! -f "${VERIFY_ROOT}/work/build/pkvm-qemu/initramfs.cpio.gz" ]; then
  verify_log "정적 BusyBox initramfs 생성"
  "${VERIFY_ROOT}/work/src/tools/qemu/mkinitramfs.sh"
fi
require_file "${VERIFY_ROOT}/work/build/pkvm-qemu/initramfs.cpio.gz"

LOG="${VERIFY_ROOT}/work/build/pkvm-qemu/console-protected.log"
verify_log "protected 부팅 실행 (CPU=cortex-a57, nVHE 경로 강제): work/src/tools/qemu/run.sh protected"
# 호스트 QEMU가 8.x 이상이면 기본 CPU=max가 hVHE를 노출해
# "Protected hVHE mode initialized successfully"가 나온다. 완료 조건의
# nVHE marker를 재현하려면 cortex-a57을 명시해야 한다 (docs/phase-03/README.md).
CPU=${CPU:-cortex-a57} "${VERIFY_ROOT}/work/src/tools/qemu/run.sh" protected

check_markers "${LOG}" \
  "CPU: All CPU(s) started at EL2" \
  "CPU features: detected: Protected KVM" \
  "Protected nVHE mode initialized successfully" \
  "PKVM_QEMU_BOOT_OK"

check_no_kernel_fault "${LOG}"

mark_done 03 "protected boot log: ${LOG}"
verify_log "Phase 03 완료"
