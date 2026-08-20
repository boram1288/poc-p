#!/bin/bash
# Phase 07: 동적 pVM 수명주기 관리 (C VM 프레임워크 재수행) 검증
# 참고 문서: docs/phase-07/README.md, docs/phase-07/userspace-vm-framework-design.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 07
require_prev_phase 05
require_prev_phase 04

require_file "${VERIFY_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image"

verify_log "C binaries, guest workload, guest image build 및 KVM 경계 검사"
"${VERIFY_ROOT}/work/src/tools/pvm-framework/verify-static.sh"

verify_log "framework, image, C test application 포함 E-1 initramfs 생성"
"${VERIFY_ROOT}/work/src/tools/pvm-framework/mkinitramfs.sh"

LOG="${VERIFY_ROOT}/work/build/pvm-framework/console-pvm-framework-final.log"
verify_log "pkvm-full-clang kernel로 QEMU 실행"
"${VERIFY_ROOT}/work/src/tools/pvm-framework/run.sh" "${LOG}" 900

check_markers "${LOG}" \
  "PVM_FRAMEWORK_WORKLOAD_VERIFIED" \
  "PVM_FRAMEWORK_WORKLOAD_REJECTED" \
  "PVM_FRAMEWORK_PROTOCOL_NEGATIVE_OK" \
  "PVM_FRAMEWORK_AUTH_TEST_OK" \
  "PVM_FRAMEWORK_POLICY_TEST_OK" \
  "PVM_FRAMEWORK_IMAGE_REJECTION_OK" \
  "PVM_FRAMEWORK_NORMAL_LIFECYCLE_OK" \
  "PVM_FRAMEWORK_DAEMON_RECOVERY_OK" \
  "PVM_FRAMEWORK_OVERLAP" \
  "GUEST_WORKLOAD_STARTED" \
  "GUEST_WORKLOAD_COMPLETED" \
  "PVM_FRAMEWORK_FAULT_ISOLATION_OK" \
  "PVM_FRAMEWORK_RESOURCE_RECOVERY_OK" \
  "PVM_FRAMEWORK_VALIDATION_OK"

check_no_kernel_fault "${LOG}"

mark_done 07 "pvm-framework log: ${LOG}"
verify_log "Phase 07 완료"
