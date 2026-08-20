#!/bin/bash
# Phase 09: pVM 간 DMA-BUF export/import 검증
# 참고 문서: docs/phase-09/README.md, docs/phase-09/VERIFICATION.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 09
require_prev_phase 08

require_file "${VERIFY_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image"
require_exec "${VERIFY_ROOT}/work/src/kvmtool/lkvm"
require_file "${VERIFY_ROOT}/work/src/tools/pvm-buffer/driver/pvm_dmabuf.c"

verify_log "EL2 primitive flat guest 회귀 (PHASE09=1)"
"${VERIFY_ROOT}/work/src/tools/pvm-framework/mkinitramfs.sh"
PRIM_LOG="${VERIFY_ROOT}/work/build/pvm-framework/console-phase09-primitive.log"
PHASE09=1 "${VERIFY_ROOT}/work/src/tools/pvm-framework/run.sh" "${PRIM_LOG}" 900

check_markers "${PRIM_LOG}" \
  "PVM_BUFFER_EXPORTED" \
  "PVM_BUFFER_IMPORTED" \
  "PVM_BUFFER_AI_READ_WRITE_OK" \
  "PVM_BUFFER_CAMERA_READ_OK" \
  "PVM_BUFFER_OWNER_ACCESS_BLOCKED" \
  "PVM_BUFFER_HOST_ACCESS_BLOCKED" \
  "Mlocked:"
check_no_kernel_fault "${PRIM_LOG}"

verify_log "Linux guest 통합 빌드 (camera/ai workload, pvm_dmabuf.ko, rootfs)"
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/build.sh"
require_exec "${VERIFY_ROOT}/work/build/pvm-buffer/camera"
require_exec "${VERIFY_ROOT}/work/build/pvm-buffer/ai"
require_file "${VERIFY_ROOT}/work/src/tools/pvm-buffer/driver/pvm_dmabuf.ko"
require_file "${VERIFY_ROOT}/work/build/pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz"
require_file "${VERIFY_ROOT}/work/build/pvm-buffer/initramfs-pvm-buffer-host.cpio.gz"

verify_log "Linux guest 통합 실행"
LOG="${VERIFY_ROOT}/work/build/pvm-buffer/console-pvm-buffer-manual.log"
"${VERIFY_ROOT}/work/src/tools/pvm-buffer/run.sh" "${LOG}" 300

check_markers "${LOG}" \
  "PVM_LINUX_AI_ID_GET" \
  "PVM_LINUX_AI_IMPORTED" \
  "PVM_LINUX_AI_READ_WRITE_OK" \
  "PVM_LINUX_AI_COMPLETED" \
  "PVM_LINUX_CAMERA_ID_GET" \
  "PVM_LINUX_CAMERA_EXPORTED" \
  "PVM_LINUX_CAMERA_READ_OK" \
  "PVM_LINUX_CAMERA_COMPLETED" \
  "PVM_BUFFER_HOST_RC" \
  "Mlocked:"
check_no_kernel_fault "${LOG}"

mark_done 09 "DMA-BUF logs: ${PRIM_LOG}, ${LOG}"
verify_log "Phase 09 완료"
