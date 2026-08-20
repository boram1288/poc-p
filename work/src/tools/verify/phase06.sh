#!/bin/bash
# Phase 06: OP-TEE 공존 (E-2) 검증
# 참고 문서: docs/phase-06/README.md
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 06
require_prev_phase 02

KERNEL_OUT="${VERIFY_ROOT}/work/build/pkvm-full-clang"
require_file "${KERNEL_OUT}/arch/arm64/boot/Image"

# Phase 06-B의 OP-TEE는 SPMC_AT_EL=1(FF-A 기반 SPMC)로 빌드된다. Host Linux
# optee 드라이버는 ARM_FFA_TRANSPORT가 없으면 FF-A로 SPMC를 찾지 못해
# /dev/tee0가 생성되지 않는다. Phase 02의 base defconfig는 이 옵션을 켜지
# 않으므로 여기서 활성화하고 Image를 다시 만든다.
# .config에 플래그가 있어도 그 상태로 Image를 실제로 다시 빌드했는지는
# 보장되지 않으므로(예: 이전 실행이 olddefconfig 단계에서 실패한 경우)
# 설정과 빌드를 매번 함께 수행한다. make는 증분 빌드이므로 이미 최신이면
# 빠르게 끝난다.
verify_log "CONFIG_ARM_FFA_TRANSPORT 활성화 및 Image 재빌드"
"${VERIFY_ROOT}/work/src/pkvm-linux/scripts/config" --file "${KERNEL_OUT}/.config" \
  -e ARM_FFA_TRANSPORT
make -C "${VERIFY_ROOT}/work/src/pkvm-linux" O="${KERNEL_OUT}" \
  ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 olddefconfig
make -C "${VERIFY_ROOT}/work/src/pkvm-linux" O="${KERNEL_OUT}" \
  ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 -j"$(nproc)" Image
grep -qx 'CONFIG_ARM_FFA_TRANSPORT=y' "${KERNEL_OUT}/.config"

verify_log "OP-TEE 4.7.0 manifest bootstrap (네트워크 필요, 최초 1회)"
"${VERIFY_ROOT}/work/src/tools/optee-pkvm/bootstrap.sh"

verify_log "OP-TEE/TF-A/U-Boot/Buildroot 빌드 (SPMC_AT_EL=1)"
"${VERIFY_ROOT}/work/src/tools/optee-pkvm/build.sh"

# work/src/tools/optee-pkvm/mkrootfs.sh는 Phase 06-B 작업 이후 arm64 lkvm과
# guest rootfs를 항상 요구하도록 확장됐다. Phase 06 단독 재현에도 이 두
# 산출물이 선행돼야 한다. Phase 06-B는 이 결과를 그대로 재사용한다.
if [ ! -x "${VERIFY_ROOT}/work/src/kvmtool/lkvm" ]; then
  verify_log "arm64 kvmtool (protected-FFA) 빌드"
  TOOLCHAIN="${VERIFY_ROOT}/work/src/optee-pkvm/toolchains/aarch64/bin/aarch64-linux-gnu-" \
    "${VERIFY_ROOT}/work/src/tools/optee-pkvm-guest/build-kvmtool.sh"
fi
require_exec "${VERIFY_ROOT}/work/src/kvmtool/lkvm"

GUEST_ROOTFS="${VERIFY_ROOT}/work/build/optee-pkvm-guest/rootfs-optee-pkvm-guest.cpio.gz"
if [ ! -f "${GUEST_ROOTFS}" ]; then
  verify_log "guest rootfs 조립 (OP-TEE client + TA)"
  "${VERIFY_ROOT}/work/src/tools/optee-pkvm-guest/mkrootfs.sh"
fi
require_file "${GUEST_ROOTFS}"

verify_log "E-2 rootfs에 pKVM selftest와 공존 오케스트레이터 주입"
"${VERIFY_ROOT}/work/src/tools/optee-pkvm/mkrootfs.sh"

LOG="${VERIFY_ROOT}/work/build/optee-pkvm/console-optee-pkvm.log"
SECURE_LOG="${VERIFY_ROOT}/work/build/optee-pkvm/secure-optee.log"
verify_log "E-2 부팅 및 공존 시험 실행"
"${VERIFY_ROOT}/work/src/tools/optee-pkvm/run.sh"

# "NOTICE:  Booting..."는 콜론 뒤 공백 두 칸(TF-A 배너 원문 그대로),
# "OP-TEE version: 4.7.0"은 Secure World 전용 UART(secure-optee.log)에만 출력된다.
check_markers "${LOG}" "NOTICE:  Booting Trusted Firmware"
check_markers "${SECURE_LOG}" "OP-TEE version: 4.7.0"
check_markers "${LOG}" \
  "optee: initialized driver" \
  "Protected nVHE mode initialized successfully" \
  "COEX_KVM_ACTIVE" \
  "COEX_AES_DURING_PVM_OK" \
  "Clear text and decoded text match" \
  "All ok!" \
  "COEX_PVM_OK: rc=0" \
  "COEX_AES_REOPEN_OK" \
  "Host VmLck after teardown: 0" \
  "OPTEE_PKVM_COEX_ALL_OK"
check_mlocked_zero "${LOG}"

check_no_kernel_fault "${LOG}"

mark_done 06 "OP-TEE coexistence log: ${LOG}"
verify_log "Phase 06 완료"
