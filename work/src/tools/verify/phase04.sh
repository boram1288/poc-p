#!/bin/bash
# Phase 04: 단일 pVM과 메모리 격리 검증
# 참고 문서: docs/phase-04/README.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 04
require_prev_phase 03

require_file "${VERIFY_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image"

verify_log "pKVM selftest(pkvm, hello_el2)와 capcheck 정적 빌드"
"${VERIFY_ROOT}/work/src/tools/pvm/build-selftest.sh"

verify_log "pKVM selftest initramfs 준비"
"${VERIFY_ROOT}/work/src/tools/pvm/mkinitramfs.sh"

LOG="${VERIFY_ROOT}/work/build/pkvm-pvm/console-pvm-protected.log"
verify_log "단일 pVM 실행 (CPU=cortex-a57, nVHE 경로 강제): work/src/tools/pvm/run-pvm.sh protected"
CPU=${CPU:-cortex-a57} "${VERIFY_ROOT}/work/src/tools/pvm/run-pvm.sh" protected

check_markers "${LOG}" \
  "PVM_TEST_KVM_DEV: PRESENT" \
  "KVM_CAP_ARM_PROTECTED_VM -> 1" \
  "KVM_CREATE_VM(type=PROTECTED 1<<31) -> OK" \
  "KVM_CREATE_VCPU -> OK" \
  "Guest heartbeat" \
  "Guest done" \
  "All ok!" \
  "Caught expected segfault" \
  "PVM_TEST_PKVM: rc=0"

check_no_kernel_fault "${LOG}"

mark_done 04 "single pVM log: ${LOG}"
verify_log "Phase 04 완료"
