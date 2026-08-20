#!/bin/bash
# Phase 08: 장치 직접 할당과 DMA 격리 (E-3) 검증
# 참고 문서: docs/phase-08/README.md, docs/phase-08/validation-results.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 08
require_prev_phase 07
require_prev_phase 05

KERNEL_OUT="${VERIFY_ROOT}/work/build/pkvm-full-clang"
QEMU_SRC="${VERIFY_ROOT}/work/src/qemu-phase08"
QEMU_OUT="${VERIFY_ROOT}/work/build/qemu-v10-aarch64"
QEMU_BIN="${QEMU_OUT}/qemu-system-aarch64"

require_file "${KERNEL_OUT}/.config"

verify_log "PV IOMMU / edu assignment / DMA share / VSOCK kernel 설정 적용"
"${VERIFY_ROOT}/work/src/tools/qemu/configure-pv-iommu-kernel.sh" "${KERNEL_OUT}"

verify_log "재구성된 설정으로 Image 재빌드"
make -C "${VERIFY_ROOT}/work/src/pkvm-linux" O="${KERNEL_OUT}" \
  ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 -j"$(nproc)"

require_file "${KERNEL_OUT}/arch/arm64/boot/Image"
require_file "${KERNEL_OUT}/vmlinux"
require_file "${KERNEL_OUT}/Module.symvers"

if [ ! -x "${QEMU_BIN}" ]; then
  verify_log "E-3 QEMU (qemu-phase08 submodule) 빌드"
  require_file "${QEMU_SRC}/configure" "(qemu-phase08 submodule 초기화 필요)"
  mkdir -p "${QEMU_OUT}"
  ( cd "${QEMU_OUT}" && \
    "${QEMU_SRC}/configure" --target-list=aarch64-softmmu --enable-slirp \
      --disable-docs --prefix="${QEMU_OUT}/install" )
  make -C "${QEMU_OUT}" -j"$(nproc)"
fi
require_exec "${QEMU_BIN}"
"${QEMU_BIN}" --version

verify_log "E-3 환경 자체 smoke test"
"${VERIFY_ROOT}/work/src/tools/qemu/mkinitramfs.sh"
SMOKE_LOG="${VERIFY_ROOT}/work/build/pkvm-qemu/console-phase08-e3-smoke.log"
QEMU="${QEMU_BIN}" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
HYP_IOMMU_PAGES=4096 \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
  "${VERIFY_ROOT}/work/src/tools/qemu/run-e3.sh" "${SMOKE_LOG}" 600

check_markers "${SMOKE_LOG}" "Found 2 assignable devices"

verify_log "장치 할당/DMA 격리 시나리오 실행 (PHASE08=1)"
LOG="${VERIFY_ROOT}/work/build/pvm-framework/console-phase08-share-final.log"
# vfio-platform은 기본적으로 device의 reset function이 등록돼 있어야 probe에
# 성공한다. QEMU edu 장치는 그런 reset 콜백이 없어 "-2" 오류로 probe가
# 실패하므로 reset 요구를 끈다 (README의 최종 E-3 pipeline 명령과 동일).
QEMU="${QEMU_BIN}" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
CPU=max HYP_IOMMU_PAGES=4096 \
CMDLINE_EXTRA='vfio_platform.reset_required=0' \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
PHASE08=1 "${VERIFY_ROOT}/work/src/tools/pvm-framework/run.sh" "${LOG}" 900
# run.sh itself exits non-zero (under `set -eu` above, aborting this script)
# when its own required-marker check fails, so reaching this point already
# means it printed PVM_FRAMEWORK_RUN_OK — but that line is run.sh's own
# stdout summary, not something it writes into ${LOG}, so don't re-check it
# against the log file here.

check_markers "${LOG}" \
  "PVM_FRAMEWORK_VFIO_READY" \
  "PVM_DEVICE_ASSIGNED" \
  "PVM_DEVICE_HOST_ACCESS_BLOCKED" \
  "PVM_DEVICE_NONOWNER_BLOCKED" \
  "PVM_DEVICE_DMA_NORMAL_OK" \
  "PVM_DEVICE_DMA_RANGE_BLOCKED" \
  "PVM_DMA_SHARE_GRANTED" \
  "PVM_DMA_SHARE_ACCEPTED" \
  "PVM_DMA_SHARE_READ_OK" \
  "PVM_DMA_SHARE_UNAPPROVED_BLOCKED" \
  "PVM_DMA_SHARE_REVOKE_BLOCKED" \
  "PVM_DEVICE_DRIVER_OK" \
  "PVM_DEVICE_REASSIGN_OK"
check_mlocked_zero "${LOG}"

check_no_kernel_fault "${LOG}"

mark_done 08 "device assignment/DMA isolation log: ${LOG}"
verify_log "Phase 08 완료"
