#!/bin/bash
# SPDX-License-Identifier: MIT

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-framework"
QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${OUTPUT_DIR}/initramfs-pvm-framework.cpio.gz}
LOG=${1:-${OUTPUT_DIR}/console-pvm-framework.log}
TIMEOUT=${2:-900}
MACHINE=${MACHINE:-virt,virtualization=on,gic-version=3}
CPU=${CPU:-cortex-a57}
HYP_IOMMU_PAGES=${HYP_IOMMU_PAGES:-}
QEMU_EXTRA_ARGS=${QEMU_EXTRA_ARGS:-}
CMDLINE_EXTRA=${CMDLINE_EXTRA:-}
PHASE08=${PHASE08:-0}
read -r -a QEMU_EXTRA_ARGV <<< "${QEMU_EXTRA_ARGS}"

CMDLINE="console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init"
if [ -n "${HYP_IOMMU_PAGES}" ]; then
	CMDLINE="${CMDLINE} kvm-arm.hyp_iommu_pages=${HYP_IOMMU_PAGES}"
fi
if [ -n "${CMDLINE_EXTRA}" ]; then
	CMDLINE="${CMDLINE} ${CMDLINE_EXTRA}"
fi

mkdir -p "${OUTPUT_DIR}"
timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine "${MACHINE}" -cpu "${CPU}" -smp 4 -m 3G \
	-nographic -nic none < /dev/null -no-reboot -kernel "${KERNEL}" -initrd "${INITRD}" \
	-append "${CMDLINE}" "${QEMU_EXTRA_ARGV[@]}" > "${LOG}" 2>&1
rc=$?

echo "QEMU_RC=${rc}"
grep -E "Protected nVHE|PVM_FRAMEWORK_|GUEST_WORKLOAD_|Mlocked:|Kernel panic" "${LOG}" || true

required=(
	PVM_FRAMEWORK_WORKLOAD_VERIFIED PVM_FRAMEWORK_WORKLOAD_REJECTED
	PVM_FRAMEWORK_PROTOCOL_NEGATIVE_OK PVM_FRAMEWORK_PROTOCOL_TEST_RC=0
	PVM_FRAMEWORK_AUTH_TEST_OK PVM_FRAMEWORK_POLICY_TEST_OK
	PVM_FRAMEWORK_IMAGE_REJECTION_OK PVM_FRAMEWORK_NORMAL_LIFECYCLE_OK
	PVM_FRAMEWORK_DAEMON_RECOVERY_OK
	PVM_FRAMEWORK_OVERLAP GUEST_WORKLOAD_STARTED GUEST_WORKLOAD_COMPLETED
	PVM_FRAMEWORK_FAULT_ISOLATION_OK PVM_FRAMEWORK_RESOURCE_RECOVERY_OK
	PVM_FRAMEWORK_VALIDATION_OK PVM_FRAMEWORK_TEST_RC=0
)
if [ "${rc}" -ne 0 ] || grep -q "Kernel panic" "${LOG}"; then
	echo "PVM_FRAMEWORK_RUN_FAILED"
	exit 1
fi
for marker in "${required[@]}"; do
	if ! grep -q "${marker}" "${LOG}"; then
		echo "PVM_FRAMEWORK_RUN_FAILED: missing=${marker}"
		exit 1
	fi
done
if [ "${PHASE08}" = 1 ]; then
	phase08_required=(
		PVM_DEVICE_DRIVER_OK PVM_DEVICE_NONOWNER_BLOCKED
		PVM_DEVICE_HOST_ACCESS_BLOCKED PVM_DEVICE_DMA_NORMAL_OK
		PVM_DEVICE_DMA_RANGE_BLOCKED PVM_DMA_SHARE_GRANTED
		PVM_DMA_SHARE_UNAPPROVED_BLOCKED PVM_DMA_SHARE_ACCEPTED
		PVM_DMA_SHARE_READ_OK
		PVM_DMA_SHARE_REVOKE_BLOCKED PVM_DEVICE_REASSIGN_OK
	)
	for marker in "${phase08_required[@]}"; do
		if ! grep -q "${marker}" "${LOG}"; then
			echo "PVM_FRAMEWORK_RUN_FAILED: phase08-missing=${marker}"
			exit 1
		fi
	done
	if [ "$(grep -c 'PVM_DEVICE_ASSIGNED: role=camera' "${LOG}")" -lt 3 ] ||
	   [ "$(grep -c 'PVM_DEVICE_ASSIGNED: role=ai' "${LOG}")" -lt 1 ]; then
		echo "PVM_FRAMEWORK_RUN_FAILED: phase08-reassignment-count"
		exit 1
	fi
fi
if ! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "PVM_FRAMEWORK_RUN_FAILED: resource-recovery"
	exit 1
fi
echo "PVM_FRAMEWORK_RUN_OK"
