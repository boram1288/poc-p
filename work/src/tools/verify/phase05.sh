#!/bin/bash
# Phase 05: 다중 pVM 운용 검증
# 참고 문서: docs/phase-05/README.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 05
require_prev_phase 04

require_file "${VERIFY_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image"

verify_log "다중 pVM initramfs 준비"
"${VERIFY_ROOT}/work/src/tools/multi-pvm/mkinitramfs.sh"

LOG="${VERIFY_ROOT}/work/build/multi-pvm/console-multi-pvm.log"
verify_log "Camera/AI 역할 pVM 동시 실행: work/src/tools/multi-pvm/run.sh"
"${VERIFY_ROOT}/work/src/tools/multi-pvm/run.sh"

check_markers "${LOG}" \
  "Protected nVHE mode initialized successfully" \
  "MULTI_KVM_OVERLAP" \
  "CAMERA: Guest heartbeat." \
  "AI: Guest heartbeat." \
  "MULTI_NORMAL_RESULT" \
  "MULTI_FAULT_RESULT" \
  "AI_SURVIVOR: All ok!" \
  "MULTI_PVM_ALL_OK"
check_mlocked_zero "${LOG}"

check_no_kernel_fault "${LOG}"

mark_done 05 "multi-pVM log: ${LOG}"
verify_log "Phase 05 완료"
