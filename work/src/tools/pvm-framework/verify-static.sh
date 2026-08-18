#!/bin/bash
# SPDX-License-Identifier: MIT

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-framework"
ARM_OUT="${OUTPUT_DIR}/arm64"
IMAGE_OUT="${OUTPUT_DIR}/images"

"${SCRIPT_DIR}/build.sh"

if rg -n '<linux/kvm.h>|/dev/kvm|ioctl\(|\bKVM_[A-Z0-9_]+' \
	"${SCRIPT_DIR}/include" "${SCRIPT_DIR}/lib" "${SCRIPT_DIR}/common" \
	"${SCRIPT_DIR}/cli" "${SCRIPT_DIR}/daemon" "${SCRIPT_DIR}/tests" \
	"${SCRIPT_DIR}/runner"; then
	echo "KVM boundary violation outside private backend" >&2
	exit 1
fi
grep -q 'pvm_kvm_arm64.o' "${ARM_OUT}/pvm-runner.map"
for map in "${ARM_OUT}/pvmd.map" "${ARM_OUT}/pvmctl.map" "${ARM_OUT}/phase07-app.map"; do
	if grep -q 'pvm_kvm_arm64.o' "${map}"; then
		echo "KVM backend linked into ${map}" >&2
		exit 1
	fi
done
echo "PVM_FRAMEWORK_KVM_BOUNDARY_OK"

for binary in pvmd pvm-runner pvmctl phase07-app protocol-negative; do
	file "${ARM_OUT}/${binary}" | grep -q 'ARM aarch64.*statically linked'
done
echo "PVM_FRAMEWORK_STATIC_BUILD_OK"

expected_workload=$(awk '$2 == "phase07-guest-workload.bin" { print $1 }' "${IMAGE_OUT}/SHA256SUMS")
expected_image=$(awk '$2 == "phase07-guest.img" { print $1 }' "${IMAGE_OUT}/SHA256SUMS")
test "$(sha256sum "${IMAGE_OUT}/phase07-guest-workload.bin" | awk '{print $1}')" = "${expected_workload}"
test "$(sha256sum "${IMAGE_OUT}/phase07-guest.img" | awk '{print $1}')" = "${expected_image}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
dd if="${IMAGE_OUT}/phase07-guest.img" of="${TMP_DIR}/embedded-workload.bin" \
	bs=1 skip=64 status=none
cmp "${IMAGE_OUT}/phase07-guest-workload.bin" "${TMP_DIR}/embedded-workload.bin"
printf abc > "${TMP_DIR}/abc"
test "$(sha256sum "${TMP_DIR}/abc" | awk '{print $1}')" = \
	ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
echo "PVM_FRAMEWORK_ARTIFACT_LAYOUT_OK"
