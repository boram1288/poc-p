#!/bin/bash
# Phase 09-b: Host/Camera/AI 사용자 공간 end-to-end 통신 검증
# 참고 문서: docs/phase-09-b/README.md, docs/phase-09-b/VERIFICATION.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 09b
require_prev_phase 09

KERNEL_OUT="${VERIFY_ROOT}/work/build/pkvm-full-clang"

verify_log "PV IOMMU kernel 설정 재확인 및 Image 재빌드"
"${VERIFY_ROOT}/work/src/tools/qemu/configure-pv-iommu-kernel.sh" "${KERNEL_OUT}"
make -C "${KERNEL_OUT}" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 \
  -j"$(nproc)" Image

verify_log "protocol/SHA256 unit test"
make -C "${VERIFY_ROOT}/work/src/tools/pvm-user-channel" test

# Each run-*.sh wrapper below prints its own "..._OK" summary line to its own
# stdout after re-reading the log it just produced; that line never lands in
# the log file itself. Under `set -eu`, the wrapper already exits non-zero
# (verified in each script) on failure, so reaching the next line already
# means it passed — check only the markers the guest/host actually write
# into the log file.
VSOCK_LOG="${VERIFY_ROOT}/work/build/pvm-buffer/console-pvm-vsock-release.log"
verify_log "AF_VSOCK smoke test"
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/run-vsock-smoke.sh" "${VSOCK_LOG}" 240
check_markers "${VSOCK_LOG}" "PVM_USER_VSOCK_RC: host=0 guest=0"

E2E_LOG="${VERIFY_ROOT}/work/build/pvm-buffer/console-user-channel-e2e-final.log"
verify_log "10회 end-to-end 통신 시험"
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/run-user-channel-e2e.sh" "${E2E_LOG}" 300

FAULT_LOG="${VERIFY_ROOT}/work/build/pvm-buffer/console-user-channel-fault-final2.log"
verify_log "negative/fault 시험"
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/run-user-channel-fault.sh" "${FAULT_LOG}" 240
check_markers "${FAULT_LOG}" "PVM_USER_FAULT_VALIDATION_OK"

PRIM_LOG="${VERIFY_ROOT}/work/build/pvm-framework/console-phase09b-primitive-final.log"
verify_log "EL2 DMA-BUF primitive 회귀 (PHASE09_ONLY=1)"
PHASE09=1 PHASE09_ONLY=1 \
  "${VERIFY_ROOT}/work/src/tools/pvm-framework/run.sh" "${PRIM_LOG}" 900
check_markers "${PRIM_LOG}" "Mlocked:"

check_no_kernel_fault "${VSOCK_LOG}" "${E2E_LOG}" "${FAULT_LOG}" "${PRIM_LOG}"

mark_done 09b "phase09-b logs: ${VSOCK_LOG}, ${E2E_LOG}, ${FAULT_LOG}, ${PRIM_LOG}"
verify_log "Phase 09-B 완료"
