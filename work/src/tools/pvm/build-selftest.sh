#!/bin/bash
# arm64 pKVM kernel selftest(pkvm, hello_el2)와 capcheck를 정적 크로스 빌드한다.
#
# tools/testing/selftests/kvm/arm64/pkvm.c는 최신 pKVM MMIO_GUARD/MEM_SHARE
# vendor hypercall 매크로를 사용하지만, kselftest 빌드가 참조하는
# tools/include/linux/arm-smccc.h 미러는 이를 아직 반영하지 않는다.
# 소스트리(work/src/pkvm-linux)는 수정하지 않고, 이 스크립트가 만드는 빌드
# 디렉터리 안의 override 헤더로 누락분만 보충한다. 값은
# work/src/pkvm-linux/include/linux/arm-smccc.h의 정의를 그대로 따른다.
set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
KERNEL_SRC=${KERNEL_SRC:-${PROJECT_ROOT}/work/src/pkvm-linux}
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pkvm-pvm"
KSELF="${KERNEL_SRC}/tools/testing/selftests/kvm"
KSELF_OUT="${OUTPUT_DIR}/kselftest-build"
KSELF_USR="${OUTPUT_DIR}/usr"
OVERRIDE_DIR="${OUTPUT_DIR}/override"
OVERRIDE_HDR="${OVERRIDE_DIR}/pkvm-smccc.h"
ARM_CC=${ARM_CC:-aarch64-linux-gnu-gcc-9}
JOBS=${JOBS:-$(nproc)}

mkdir -p "${KSELF_USR}" "${OVERRIDE_DIR}" "${OUTPUT_DIR}/bin"

echo "== UAPI 헤더 설치: ${KSELF_USR} =="
make -C "${KERNEL_SRC}" ARCH=arm64 INSTALL_HDR_PATH="${KSELF_USR}" headers_install

# kselftest의 Makefile.kvm은 INSTALL_HDR_PATH=$(top_srcdir)/usr로 고정되어 있어
# 소스트리 자체의 usr/include를 참조한다. 아래 kselftest 빌드가 이를 쓸 수
# 있도록, 소스트리 in-tree 잔재 정리(arch/arm64/include/generated,
# include/generated, usr/include)는 kselftest 빌드가 끝난 뒤로 미룬다.
# 이 정리는 이후 다른 Phase의 out-of-tree(O=...) 커널 빌드가 kbuild의
# outputmakefile 검사("source tree is not clean")에서 거부되지 않게 하기 위함이다.
make -C "${KERNEL_SRC}" ARCH=arm64 INSTALL_HDR_PATH="${KERNEL_SRC}/usr" headers_install

cat > "${OVERRIDE_HDR}" <<'EOF'
/* Phase 04 빌드 보충 헤더.
 * tools/testing/selftests/kvm이 참조하는 tools/include/linux/arm-smccc.h는
 * 커널 소스트리(include/linux/arm-smccc.h)가 이미 정의한 pKVM MMIO_GUARD/
 * MEM_SHARE 계열 vendor hypercall FUNC_ID를 미러링하지 않는다. 소스트리를
 * 수정하지 않고 빌드 디렉터리의 이 override 헤더로 누락분만 보충한다.
 * 값은 work/src/pkvm-linux/include/linux/arm-smccc.h를 그대로 따른다.
 */
#ifndef PKVM_SMCCC_OVERRIDE_H
#define PKVM_SMCCC_OVERRIDE_H

#include <linux/arm-smccc.h>

#ifndef ARM_SMCCC_KVM_FUNC_HYP_MEMINFO
#define ARM_SMCCC_KVM_FUNC_HYP_MEMINFO		2
#endif
#ifndef ARM_SMCCC_KVM_FUNC_MEM_SHARE
#define ARM_SMCCC_KVM_FUNC_MEM_SHARE		3
#endif
#ifndef ARM_SMCCC_KVM_FUNC_MEM_UNSHARE
#define ARM_SMCCC_KVM_FUNC_MEM_UNSHARE		4
#endif
#ifndef ARM_SMCCC_KVM_FUNC_MMIO_GUARD_INFO
#define ARM_SMCCC_KVM_FUNC_MMIO_GUARD_INFO	5
#endif
#ifndef ARM_SMCCC_KVM_FUNC_MMIO_GUARD_ENROLL
#define ARM_SMCCC_KVM_FUNC_MMIO_GUARD_ENROLL	6
#endif
#ifndef ARM_SMCCC_KVM_FUNC_MMIO_GUARD_MAP
#define ARM_SMCCC_KVM_FUNC_MMIO_GUARD_MAP	7
#endif
#ifndef ARM_SMCCC_KVM_FUNC_MMIO_GUARD_UNMAP
#define ARM_SMCCC_KVM_FUNC_MMIO_GUARD_UNMAP	8
#endif
#ifndef ARM_SMCCC_KVM_FUNC_MEM_RELINQUISH
#define ARM_SMCCC_KVM_FUNC_MEM_RELINQUISH	9
#endif

#ifndef ARM_SMCCC_VENDOR_HYP_KVM_HYP_MEMINFO_FUNC_ID
#define ARM_SMCCC_VENDOR_HYP_KVM_HYP_MEMINFO_FUNC_ID			\
	ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL,			\
			   ARM_SMCCC_SMC_64,				\
			   ARM_SMCCC_OWNER_VENDOR_HYP,			\
			   ARM_SMCCC_KVM_FUNC_HYP_MEMINFO)
#endif

#ifndef ARM_SMCCC_VENDOR_HYP_KVM_MEM_SHARE_FUNC_ID
#define ARM_SMCCC_VENDOR_HYP_KVM_MEM_SHARE_FUNC_ID			\
	ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL,			\
			   ARM_SMCCC_SMC_64,				\
			   ARM_SMCCC_OWNER_VENDOR_HYP,			\
			   ARM_SMCCC_KVM_FUNC_MEM_SHARE)
#endif

#ifndef ARM_SMCCC_VENDOR_HYP_KVM_MEM_UNSHARE_FUNC_ID
#define ARM_SMCCC_VENDOR_HYP_KVM_MEM_UNSHARE_FUNC_ID			\
	ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL,			\
			   ARM_SMCCC_SMC_64,				\
			   ARM_SMCCC_OWNER_VENDOR_HYP,			\
			   ARM_SMCCC_KVM_FUNC_MEM_UNSHARE)
#endif

#ifndef ARM_SMCCC_VENDOR_HYP_KVM_MEM_RELINQUISH_FUNC_ID
#define ARM_SMCCC_VENDOR_HYP_KVM_MEM_RELINQUISH_FUNC_ID		\
	ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL,			\
			   ARM_SMCCC_SMC_64,				\
			   ARM_SMCCC_OWNER_VENDOR_HYP,			\
			   ARM_SMCCC_KVM_FUNC_MEM_RELINQUISH)
#endif

#ifndef ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_INFO_FUNC_ID
#define ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_INFO_FUNC_ID		\
	ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL,			\
			   ARM_SMCCC_SMC_64,				\
			   ARM_SMCCC_OWNER_VENDOR_HYP,			\
			   ARM_SMCCC_KVM_FUNC_MMIO_GUARD_INFO)
#endif

#ifndef ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_ENROLL_FUNC_ID
#define ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_ENROLL_FUNC_ID		\
	ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL,			\
			   ARM_SMCCC_SMC_64,				\
			   ARM_SMCCC_OWNER_VENDOR_HYP,			\
			   ARM_SMCCC_KVM_FUNC_MMIO_GUARD_ENROLL)
#endif

#ifndef ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_MAP_FUNC_ID
#define ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_MAP_FUNC_ID		\
	ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL,			\
			   ARM_SMCCC_SMC_64,				\
			   ARM_SMCCC_OWNER_VENDOR_HYP,			\
			   ARM_SMCCC_KVM_FUNC_MMIO_GUARD_MAP)
#endif

#ifndef ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_UNMAP_FUNC_ID
#define ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_UNMAP_FUNC_ID		\
	ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL,			\
			   ARM_SMCCC_SMC_64,				\
			   ARM_SMCCC_OWNER_VENDOR_HYP,			\
			   ARM_SMCCC_KVM_FUNC_MMIO_GUARD_UNMAP)
#endif

#endif /* PKVM_SMCCC_OVERRIDE_H */
EOF

echo "== arm64 kselftest 정적 빌드 (pkvm, hello_el2 등) =="
rm -rf "${KSELF_OUT}"
mkdir -p "${KSELF_OUT}"
make -C "${KSELF}" OUTPUT="${KSELF_OUT}" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- CC="${ARM_CC}" \
    USERCFLAGS="-include ${OVERRIDE_HDR}" USERLDFLAGS=-static \
    -j"${JOBS}"

file "${KSELF_OUT}/arm64/pkvm" | grep -q "statically linked"
file "${KSELF_OUT}/arm64/hello_el2" | grep -q "statically linked"

# UAPI 헤더는 이미 ${KSELF_USR}에 설치했으므로, kselftest 빌드가 끝난 지금
# 소스트리의 in-tree 잔재만 정리한다.
rm -rf "${KERNEL_SRC}/arch/arm64/include/generated" \
       "${KERNEL_SRC}/include/generated" "${KERNEL_SRC}/usr/include"

echo "== capcheck 정적 빌드 =="
"${ARM_CC}" -static -O2 -isystem "${KSELF_USR}/include" \
    -o "${OUTPUT_DIR}/bin/capcheck" "${SCRIPT_DIR}/capcheck.c"
file "${OUTPUT_DIR}/bin/capcheck" | grep -q "statically linked"

echo "PVM_SELFTEST_BUILD_OK: ${KSELF_OUT}/arm64"
