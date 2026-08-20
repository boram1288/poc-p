#!/bin/bash
# Phase 02: 소스 통합과 커널 빌드 (clang) 검증
# 참고 문서: docs/phase-02/README.md, docs/phase-02/VERIFICATION.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 02

KERNEL_SRC="${VERIFY_ROOT}/work/src/pkvm-linux"
OUT="${VERIFY_ROOT}/work/build/pkvm-full-clang"
LOG_DIR="${VERIFY_LOG_DIR}/phase-02"
mkdir -p "${LOG_DIR}" "${OUT}"

require_file "${KERNEL_SRC}/Makefile" "(pkvm-linux submodule 초기화 필요)"

verify_log "clang 커널 defconfig 생성"
make -C "${KERNEL_SRC}" O="${OUT}" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 \
  defconfig 2>&1 | tee "${LOG_DIR}/defconfig.log"

verify_log "pKVM / S2MPU 관련 Kconfig 심볼 적용"
"${KERNEL_SRC}/scripts/config" --file "${OUT}/.config" \
  -e KVM -e PKVM_DEBUG -e PKVM_DISABLE_STAGE2_ON_PANIC -e PKVM_STACKTRACE \
  -d ARM_SMMU_V3 -d ARM_SMMU_V3_PKVM -e ARM_SMMU_V3_PKVM_PV \
  -e PKVM_PVIOMMU -e VFIO_PKVM_IOMMU
"${KERNEL_SRC}/scripts/config" --file "${OUT}/.config" \
  -m PKVM_SMC_FILTER -m PKVM_IOMMU_TEMPLATE

make -C "${KERNEL_SRC}" O="${OUT}" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 \
  olddefconfig 2>&1 | tee "${LOG_DIR}/olddefconfig.log"

verify_log "clang 전체 빌드 시작 (-j$(nproc))"
make -C "${KERNEL_SRC}" O="${OUT}" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 \
  -j"$(nproc)" 2>&1 | tee "${OUT}/build.log"

verify_log "완료 조건 파일 확인"
require_file "${OUT}/arch/arm64/boot/Image"
require_file "${OUT}/vmlinux"
require_file "${OUT}/arch/arm64/kvm/hyp/nvhe/kvm_nvhe.o"
require_file "${OUT}/drivers/misc/pkvm-smc/pkvm_smc.ko"
require_file "${OUT}/drivers/misc/pkvm-iommu-temp/pkvm_iommu_temp.ko"

verify_log "빌드 오류/경고 없음 확인"
if grep -qE '\berror:|\bwarning:' "${OUT}/build.log"; then
  verify_fail "빌드 로그에 error/warning이 있습니다: ${OUT}/build.log"
fi

sha256sum "${OUT}/arch/arm64/boot/Image" | tee "${LOG_DIR}/image.sha256"

mark_done 02 "clang kernel build: ${OUT}"
verify_log "Phase 02 완료"
