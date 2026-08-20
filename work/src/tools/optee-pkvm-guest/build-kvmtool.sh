#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
DEFAULT_KVMTOOL_DIR=${PROJECT_ROOT}/work/src/kvmtool
DEFAULT_DTC_DIR=${PROJECT_ROOT}/work/src/dtc
KVMTOOL_DIR=${KVMTOOL_DIR:-${DEFAULT_KVMTOOL_DIR}}
DTC_DIR=${DTC_DIR:-${DEFAULT_DTC_DIR}}
TOOLCHAIN=${TOOLCHAIN:-${PROJECT_ROOT}/work/src/optee-pkvm/toolchains/aarch64/bin/aarch64-linux-gnu-}
JOBS=${JOBS:-8}

SUBMODULE_PATHS=()
if [ "${DTC_DIR}" = "${DEFAULT_DTC_DIR}" ]; then
	SUBMODULE_PATHS+=(work/src/dtc)
fi
if [ "${KVMTOOL_DIR}" = "${DEFAULT_KVMTOOL_DIR}" ]; then
	SUBMODULE_PATHS+=(work/src/kvmtool)
fi
if [ "${#SUBMODULE_PATHS[@]}" -gt 0 ]; then
	git -C "${PROJECT_ROOT}" submodule update --init --filter=blob:none -- \
		"${SUBMODULE_PATHS[@]}"
fi

git -C "${DTC_DIR}" rev-parse --verify HEAD >/dev/null
git -C "${KVMTOOL_DIR}" rev-parse --verify HEAD >/dev/null

if ! grep -q 'protected_ffa' "${KVMTOOL_DIR}/arm64/include/kvm/kvm-config-arch.h"; then
	git -C "${KVMTOOL_DIR}" apply "${SCRIPT_DIR}/kvmtool-protected-ffa.patch"
fi

# work/src/dtc is also built in-place as a host tool (dtc itself, used by
# OP-TEE's device-tree build). Without CC/AR overrides `make libfdt` here
# would reuse or produce host-arch objects and fail to link into the arm64
# lkvm binary, so force an arm64 rebuild and clean any stale host objects
# first.
make -C "${DTC_DIR}" clean-libfdt >/dev/null 2>&1 || true
rm -f "${DTC_DIR}"/libfdt/*.o "${DTC_DIR}"/libfdt/libfdt.a
make -C "${DTC_DIR}" -j"${JOBS}" \
	CC="${TOOLCHAIN}gcc" AR="${TOOLCHAIN}ar" libfdt
make -C "${KVMTOOL_DIR}" ARCH=arm64 CROSS_COMPILE="${TOOLCHAIN}" \
	CC="${TOOLCHAIN}gcc" LIBFDT_DIR="${DTC_DIR}/libfdt" -j"${JOBS}"

echo "PVM_KVMTOOL_READY: ${KVMTOOL_DIR}/lkvm"
