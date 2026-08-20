#!/bin/bash
# Phase 10: 공개 fixture 기반 Reference Scenario 통합 검증
# 참고 문서: docs/phase-10/README.md, docs/phase-10/VERIFICATION.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 10
require_prev_phase 09b
require_prev_phase 08

QEMU_BIN="${VERIFY_ROOT}/work/build/qemu-v10-aarch64/qemu-system-aarch64"
require_exec "${QEMU_BIN}"

FIX_DIR="${VERIFY_ROOT}/work/build/vision-pipeline/fixtures"
if [ ! -f "${FIX_DIR}/frames.bin" ] || [ ! -f "${FIX_DIR}/oracle.bin" ]; then
  verify_log "공개 fixture 생성 (네트워크 필요, 최초 1회)"
  "${VERIFY_ROOT}/work/src/tools/vision-pipeline/prepare-fixture.sh"
fi
require_file "${FIX_DIR}/frames.bin"
require_file "${FIX_DIR}/oracle.bin"
make -C "${VERIFY_ROOT}/work/src/tools/vision-pipeline" verify

verify_log "userspace protocol/runtime build"
make -C "${VERIFY_ROOT}/work/src/tools/pvm-user-channel" clean all test
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/build.sh"
require_exec "${VERIFY_ROOT}/work/build/pvm-buffer/pvm_vision"
require_file "${VERIFY_ROOT}/work/src/tools/pvm-buffer/driver/pvm_dmabuf.ko"
require_file "${VERIFY_ROOT}/work/src/tools/pvm-user-channel/driver/pvm_message.ko"
require_file "${VERIFY_ROOT}/work/build/pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz"
require_file "${VERIFY_ROOT}/work/build/pvm-buffer/initramfs-pvm-buffer-host.cpio.gz"

E3_ENV=(
  VISION_E3=1
  QEMU="${QEMU_BIN}"
  MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on'
  CPU=max HYP_IOMMU_PAGES=4096
  CMDLINE_EXTRA='vfio_platform.reset_required=0'
  QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3'
)

PIPE_LOG="${VERIFY_ROOT}/work/build/vision-pipeline/console-vision-pipeline-local.log"
verify_log "E-3 정상 pipeline 실행 (30 frame)"
env "${E3_ENV[@]}" "${VERIFY_ROOT}/work/src/tools/pvm-buffer/run-vision-pipeline.sh" \
  "${PIPE_LOG}" 360

check_markers "${PIPE_LOG}" \
  "Found 2 assignable devices" \
  "PVM_VISION_CAMERA_REPLAY" \
  "PVM_VISION_ORACLE_LOOKUP" \
  "PVM_VISION_RESULTS_MATCH" \
  "PVM_VISION_HOST_ALLOWLIST_OK" \
  "PVM_VISION_EOS" \
  "PVM_VISION_LAYOUT_REJECT_OK" \
  "PVM_VISION_MUTATION_REJECT_OK" \
  "PVM_VISION_HASH_REJECT_OK" \
  "PVM_VISION_MISMATCH_REJECT_OK" \
  "PVM_VISION_DUPLICATE_REPLAY_REJECT_OK" \
  "PVM_VISION_E3_ENVIRONMENT_OK" \
  "PVM_VISION_PIPELINE_OK"

for marker in PVM_VISION_CAMERA_FRAME_OK PVM_VISION_AI_FRAME_OK PVM_VISION_HOST_FRAME_OK; do
  count=$(grep -c "${marker}" "${PIPE_LOG}")
  if [ "${count}" -ne 30 ]; then
    verify_fail "${marker} 개수가 30이 아닙니다 (실제 ${count})"
  fi
done

FAULT_LOG="${VERIFY_ROOT}/work/build/vision-pipeline/console-vision-fault-local.log"
verify_log "E-3 장애 주입과 자원 회수 실행"
env "${E3_ENV[@]}" "${VERIFY_ROOT}/work/src/tools/pvm-buffer/run-vision-fault.sh" \
  "${FAULT_LOG}" 300
check_markers "${FAULT_LOG}" \
  "PVM_VISION_CAMERA_FAILURE" \
  "PVM_VISION_AI_FAILURE" \
  "PVM_VISION_HOST_FAILURE" \
  "PVM_VISION_FAULT_RC: host=0 ai=0 camera=0" \
  "PVM_VISION_FAULT_OK"
check_mlocked_zero "${FAULT_LOG}"

verify_log "Phase 09-b 전체 회귀 재실행"
make -C "${VERIFY_ROOT}/work/src/tools/pvm-user-channel" test
VSOCK_LOG="${VERIFY_ROOT}/work/build/pvm-buffer/console-phase10-vsock-regression.log"
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/run-vsock-smoke.sh" "${VSOCK_LOG}" 240
E2E_LOG="${VERIFY_ROOT}/work/build/pvm-buffer/console-phase10-user-channel-e2e.log"
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/run-user-channel-e2e.sh" "${E2E_LOG}" 300
UFAULT_LOG="${VERIFY_ROOT}/work/build/pvm-buffer/console-phase10-user-channel-fault.log"
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/run-user-channel-fault.sh" "${UFAULT_LOG}" 240
PRIM_LOG="${VERIFY_ROOT}/work/build/pvm-framework/console-phase10-phase09b-primitive.log"
PHASE09=1 PHASE09_ONLY=1 \
  "${VERIFY_ROOT}/work/src/tools/pvm-framework/run.sh" "${PRIM_LOG}" 900

check_markers "${VSOCK_LOG}" "PVM_USER_VSOCK_SMOKE_OK"
check_markers "${E2E_LOG}" "PVM_USER_CHANNEL_E2E_OK"
check_markers "${UFAULT_LOG}" "PVM_USER_CHANNEL_FAULT_OK"
check_markers "${PRIM_LOG}" "PVM_FRAMEWORK_RUN_OK" \
  "PVM_BUFFER_RESOURCE_RECOVERY_OK" "Mlocked:"

verify_log "최종 kernel 오류 검사"
check_no_kernel_fault "${PIPE_LOG}" "${FAULT_LOG}" "${VSOCK_LOG}" \
  "${E2E_LOG}" "${UFAULT_LOG}" "${PRIM_LOG}"

mark_done 10 "vision pipeline log: ${PIPE_LOG}"
verify_log "Phase 10 완료 — Reference Scenario 통합 검증 성공"
