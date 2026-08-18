#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
KVMTOOL_DIR=${KVMTOOL_DIR:-${PROJECT_ROOT}/work/src/kvmtool}
DTC_DIR=${DTC_DIR:-${PROJECT_ROOT}/work/src/dtc}
TOOLCHAIN=${TOOLCHAIN:-${PROJECT_ROOT}/work/src/optee-pkvm/toolchains/aarch64/bin/aarch64-linux-gnu-}
JOBS=${JOBS:-8}

if [ ! -d "${DTC_DIR}/.git" ]; then
	git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git "${DTC_DIR}"
	git -C "${DTC_DIR}" checkout 89c99ce78ac8e5ff10e829e21e6cffa12a6e1416
fi

if [ ! -d "${KVMTOOL_DIR}/.git" ]; then
	git clone https://git.kernel.org/pub/scm/linux/kernel/git/will/kvmtool.git \
		"${KVMTOOL_DIR}"
	git -C "${KVMTOOL_DIR}" checkout f67bc0bdae9433a9cfd05e65ea2c1bb6102566d9
fi

if ! grep -q 'protected_ffa' "${KVMTOOL_DIR}/arm64/include/kvm/kvm-config-arch.h"; then
	git -C "${KVMTOOL_DIR}" apply "${SCRIPT_DIR}/kvmtool-protected-ffa.patch"
fi

make -C "${DTC_DIR}" -j"${JOBS}" libfdt
make -C "${KVMTOOL_DIR}" ARCH=arm64 CROSS_COMPILE="${TOOLCHAIN}" \
	CC="${TOOLCHAIN}gcc" LIBFDT_DIR="${DTC_DIR}/libfdt" -j"${JOBS}"

echo "PVM_KVMTOOL_READY: ${KVMTOOL_DIR}/lkvm"
