#!/bin/bash
# Configure an existing arm64 kernel output directory for the pKVM PV IOMMU.

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
KERNEL_SRC=${KERNEL_SRC:-${PROJECT_ROOT}/work/src/pkvm-linux}
KERNEL_OUT=${1:-${PROJECT_ROOT}/work/build/pkvm-full-clang}
KERNEL_SRC=$(realpath "${KERNEL_SRC}")
KERNEL_OUT=$(realpath "${KERNEL_OUT}")

if [ ! -f "${KERNEL_OUT}/.config" ]; then
    echo "missing kernel config: ${KERNEL_OUT}/.config" >&2
    exit 1
fi

# The generic and nested drivers must not compete with the PV platform driver
# for the same arm,smmu-v3 device.
"${KERNEL_SRC}/scripts/config" --file "${KERNEL_OUT}/.config" \
    --disable ARM_SMMU_V3 \
    --disable ARM_SMMU_V3_PKVM \
    --enable ARM_SMMU_V3_PKVM_PV \
    --enable PKVM_PVIOMMU \
    --enable VFIO_PLATFORM \
    --enable PKVM_QEMU_EDU \
    --enable PKVM_PVM_DMA_SHARE

# Resolve dependencies using the arm64 Kconfig graph.
make -C "${KERNEL_SRC}" O="${KERNEL_OUT}" ARCH=arm64 LLVM=1 \
    CC=clang-18 LD=ld.lld-18 olddefconfig

# Fail early if Kconfig changed the requested PV-only selection.
grep -qx '# CONFIG_ARM_SMMU_V3 is not set' "${KERNEL_OUT}/.config"
! grep -q '^CONFIG_ARM_SMMU_V3_PKVM=' "${KERNEL_OUT}/.config"
grep -qx 'CONFIG_ARM_SMMU_V3_PKVM_PV=y' "${KERNEL_OUT}/.config"
grep -qx 'CONFIG_PKVM_PVIOMMU=y' "${KERNEL_OUT}/.config"
grep -qx 'CONFIG_VFIO_PLATFORM=y' "${KERNEL_OUT}/.config"
grep -qx 'CONFIG_PKVM_QEMU_EDU=y' "${KERNEL_OUT}/.config"
grep -qx 'CONFIG_PKVM_PVM_DMA_SHARE=y' "${KERNEL_OUT}/.config"

echo "pKVM PV IOMMU kernel configuration is valid: ${KERNEL_OUT}"
