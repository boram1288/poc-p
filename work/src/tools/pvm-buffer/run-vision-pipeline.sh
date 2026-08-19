#!/bin/bash
# SPDX-License-Identifier: MIT

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/vision-pipeline"
LOG=${1:-${OUTPUT_DIR}/console-vision-pipeline.log}
TIMEOUT=${2:-300}
QEMU=${QEMU:-qemu-system-aarch64}
KERNEL=${KERNEL:-${PROJECT_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image}
INITRD=${INITRD:-${PROJECT_ROOT}/work/build/pvm-buffer/initramfs-pvm-buffer-host.cpio.gz}
MACHINE=${MACHINE:-virt,virtualization=on,gic-version=3}
CPU=${CPU:-cortex-a57}
HYP_IOMMU_PAGES=${HYP_IOMMU_PAGES:-}
CMDLINE_EXTRA=${CMDLINE_EXTRA:-}
QEMU_EXTRA_ARGS=${QEMU_EXTRA_ARGS:-}
VISION_E3=${VISION_E3:-0}
read -r -a QEMU_EXTRA_ARGV <<< "${QEMU_EXTRA_ARGS}"

"${PROJECT_ROOT}/work/src/tools/vision-pipeline/prepare-fixture.sh"
"${SCRIPT_DIR}/build.sh"

CMDLINE="console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init pvmvision=1"
if [ -n "${HYP_IOMMU_PAGES}" ]; then
	CMDLINE="${CMDLINE} kvm-arm.hyp_iommu_pages=${HYP_IOMMU_PAGES}"
fi
if [ -n "${CMDLINE_EXTRA}" ]; then
	CMDLINE="${CMDLINE} ${CMDLINE_EXTRA}"
fi

timeout --signal=KILL "${TIMEOUT}" "${QEMU}" \
	-machine "${MACHINE}" -cpu "${CPU}" -smp 4 -m 3G \
	-nographic -nic none < /dev/null -no-reboot \
	-kernel "${KERNEL}" \
	-initrd "${INITRD}" \
	-append "${CMDLINE}" "${QEMU_EXTRA_ARGV[@]}" \
	> "${LOG}" 2>&1
rc=$?
echo "QEMU_RC=${rc}"
grep -E "PVM_VISION_|Mlocked:|Kernel panic|Oops|BUG:" "${LOG}" || true
if [ "${rc}" -ne 0 ] || grep -q "Kernel panic\|Oops\|BUG:" "${LOG}"; then
	echo "PVM_VISION_PIPELINE_FAILED"
	exit 1
fi

required=(
	PVM_VISION_NEGATIVE_OK
	PVM_VISION_LAYOUT_REJECT_OK
	PVM_VISION_MUTATION_REJECT_OK
	PVM_VISION_HASH_REJECT_OK
	PVM_VISION_MISMATCH_REJECT_OK
	PVM_VISION_DUPLICATE_REPLAY_REJECT_OK
	PVM_VISION_CAMERA_REPLAY_OK
	PVM_VISION_ORACLE_LOOKUP_OK
	PVM_VISION_RESULTS_MATCH_OK
	PVM_VISION_HOST_ALLOWLIST_OK
	PVM_VISION_EOS_OK
	PVM_VISION_RUNTIME_RECOVERY_OK
	PVM_VISION_PIPELINE_VALIDATION_OK
)
for marker in "${required[@]}"; do
	if ! grep -q "${marker}" "${LOG}"; then
		echo "PVM_VISION_PIPELINE_FAILED: missing=${marker}"
		exit 1
	fi
done
for role_marker in PVM_VISION_HOST_FRAME_OK PVM_VISION_AI_FRAME_OK PVM_VISION_CAMERA_FRAME_OK; do
	if [ "$(grep -c "${role_marker}" "${LOG}")" -ne 30 ]; then
		echo "PVM_VISION_PIPELINE_FAILED: frame-count=${role_marker}"
		exit 1
	fi
done
for class_id in 0 1 2; do
	if ! grep -q "PVM_VISION_DETECTION: .* class=${class_id} " "${LOG}"; then
		echo "PVM_VISION_PIPELINE_FAILED: class=${class_id}"
		exit 1
	fi
done
if ! grep -q "PVM_VISION_RC: host=0 ai=0 camera=0" "${LOG}" ||
	! grep -Eq "Mlocked:[[:space:]]+0 kB" "${LOG}"; then
	echo "PVM_VISION_PIPELINE_FAILED: status-or-recovery"
	exit 1
fi
if [ "${VISION_E3}" = 1 ]; then
	if ! grep -q "Found 2 assignable devices" "${LOG}" ||
		! grep -q "kvm-arm-smmu-v3 .*ias .*oas" "${LOG}"; then
		echo "PVM_VISION_PIPELINE_FAILED: e3-environment"
		exit 1
	fi
	echo "PVM_VISION_E3_ENVIRONMENT_OK"
fi
echo "PVM_VISION_PIPELINE_OK"
