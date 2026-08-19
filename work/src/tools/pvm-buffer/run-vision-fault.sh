#!/bin/bash
# SPDX-License-Identifier: MIT

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/vision-pipeline"
LOG=${1:-${OUTPUT_DIR}/console-vision-fault.log}
TIMEOUT=${2:-240}
QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
MACHINE=${MACHINE:-virt,virtualization=on,gic-version=3}
CPU=${CPU:-cortex-a57}
HYP_IOMMU_PAGES=${HYP_IOMMU_PAGES:-}
CMDLINE_EXTRA=${CMDLINE_EXTRA:-}
QEMU_EXTRA_ARGS=${QEMU_EXTRA_ARGS:-}
VISION_E3=${VISION_E3:-0}
read -r -a QEMU_EXTRA_ARGV <<< "${QEMU_EXTRA_ARGS}"

"${SCRIPT_DIR}/build.sh"
INITRD=${INITRD:-${PROJECT_ROOT}/work/build/pvm-buffer/initramfs-pvm-buffer-host.cpio.gz}
CMDLINE="console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init pvmvisionfault=1"
if [ -n "${HYP_IOMMU_PAGES}" ]; then
	CMDLINE="${CMDLINE} kvm-arm.hyp_iommu_pages=${HYP_IOMMU_PAGES}"
fi
if [ -n "${CMDLINE_EXTRA}" ]; then
	CMDLINE="${CMDLINE} ${CMDLINE_EXTRA}"
fi

timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine "${MACHINE}" -cpu "${CPU}" -smp 4 -m 3G \
	-nographic -nic none < /dev/null -no-reboot \
	-kernel "${KERNEL}" -initrd "${INITRD}" \
	-append "${CMDLINE}" "${QEMU_EXTRA_ARGV[@]}" > "${LOG}" 2>&1
rc=$?
echo "QEMU_RC=${rc}"
grep -E "PVM_VISION_|Mlocked:|Kernel panic|Oops|BUG:" "${LOG}" || true
if [ "${rc}" -ne 0 ] || grep -q "Kernel panic\|Oops\|BUG:" "${LOG}"; then
	echo "PVM_VISION_FAULT_FAILED"
	exit 1
fi
required=(
	PVM_VISION_CAMERA_FAILURE_RECOVERY_OK
	PVM_VISION_AI_FAILURE_RECOVERY_OK
	PVM_VISION_HOST_FAILURE_INJECTED_OK
	PVM_VISION_CAMERA_HOST_FAILURE_RECOVERY_OK
	PVM_VISION_AI_HOST_FAILURE_RECOVERY_OK
	PVM_VISION_FAULT_VALIDATION_OK
)
for marker in "${required[@]}"; do
	if ! grep -q "${marker}" "${LOG}"; then
		echo "PVM_VISION_FAULT_FAILED: missing=${marker}"
		exit 1
	fi
done
if ! grep -q "PVM_VISION_FAULT_RC: host=0 ai=0 camera=0" "${LOG}" ||
	! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "PVM_VISION_FAULT_FAILED: status-or-recovery"
	exit 1
fi
if [ "${VISION_E3}" = 1 ]; then
	if ! grep -q "Found 2 assignable devices" "${LOG}" ||
		! grep -q "kvm-arm-smmu-v3 .*ias .*oas" "${LOG}"; then
		echo "PVM_VISION_FAULT_FAILED: e3-environment"
		exit 1
	fi
	echo "PVM_VISION_FAULT_E3_ENVIRONMENT_OK"
fi
echo "PVM_VISION_FAULT_OK"
