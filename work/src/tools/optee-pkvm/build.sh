#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
SOURCE_DIR=${SOURCE_DIR:-${PROJECT_ROOT}/work/src/optee-pkvm}
HOST_TOOLS=${PROJECT_ROOT}/work/build/host-tools
JOBS=${JOBS:-4}

test -f "${SOURCE_DIR}/build/qemu_v8.mk"

# OP-TEE's QEMU build needs pyelftools. Keep it local to work/build so the
# host's Python installation is not modified.
if [ ! -d "${HOST_TOOLS}/pyelftools/elftools" ]; then
	git clone --depth 1 --branch v0.32 \
		https://github.com/eliben/pyelftools.git "${HOST_TOOLS}/pyelftools"
fi

export PYTHONPATH="${HOST_TOOLS}/pyelftools${PYTHONPATH:+:${PYTHONPATH}}"
export PATH="${SOURCE_DIR}/u-boot/scripts/dtc:${PATH}"

make -C "${SOURCE_DIR}/build" aarch64-toolchain

common_args=(RUST_ENABLE=n MEASURED_BOOT_FTPM=n SPMC_AT_EL=1 \
	CFG_NS_VIRTUALIZATION=y CFG_VIRT_GUEST_COUNT=3)

make -C "${SOURCE_DIR}/build" -j"${JOBS}" "${common_args[@]}" optee-os

# The host-only EFI capsule utility needs libgnutls headers, but neither the
# QEMU boot chain nor its mkimage utility uses it.
cd "${SOURCE_DIR}/u-boot"
scripts/kconfig/merge_config.sh configs/qemu_arm64_defconfig \
	"${SOURCE_DIR}/build/kconfigs/u-boot_qemu_v8.conf" \
	"${SCRIPT_DIR}/u-boot-pkvm.conf"
cd - >/dev/null
make -C "${SOURCE_DIR}/u-boot" olddefconfig \
	CROSS_COMPILE="${SOURCE_DIR}/toolchains/aarch64/bin/aarch64-linux-gnu-"

make -C "${SOURCE_DIR}/build" -j"${JOBS}" "${common_args[@]}" \
	u-boot buildroot arm-tf uRootfs

echo "OPTEE_BASELINE_BUILD_OK"
