#!/bin/bash
# SPDX-License-Identifier: MIT

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
OUTPUT_DIR="${PROJECT_ROOT}/work/build/pvm-framework"
ARM_OUT="${OUTPUT_DIR}/arm64"
HOST_OUT="${OUTPUT_DIR}/host"
IMAGE_OUT="${OUTPUT_DIR}/images"
KERNEL="${PROJECT_ROOT}/work/src/pkvm-linux"
KSELF="${KERNEL}/tools/testing/selftests/kvm"
KSELF_OUT="${PROJECT_ROOT}/work/build/pkvm-pvm/kselftest-build"
KSELF_USR="${PROJECT_ROOT}/work/build/pkvm-pvm/usr"
OVERRIDE="${PROJECT_ROOT}/work/build/pkvm-pvm/override"
ARM_CC=${ARM_CC:-aarch64-linux-gnu-gcc-9}
ARM_OBJCOPY=${ARM_OBJCOPY:-aarch64-linux-gnu-objcopy}
HOST_CC=${HOST_CC:-cc}

mkdir -p "${ARM_OUT}" "${HOST_OUT}" "${IMAGE_OUT}"

COMMON_CFLAGS=(-O2 -g -Wall -Wextra -Werror -std=gnu11 -I"${SCRIPT_DIR}/include" -I"${SCRIPT_DIR}/common")
ARM_COMMON=(-static "${COMMON_CFLAGS[@]}")

"${HOST_CC}" "${COMMON_CFLAGS[@]}" \
	"${SCRIPT_DIR}/common/sha256.c" "${SCRIPT_DIR}/tools/pvm_image_pack.c" \
	-o "${HOST_OUT}/pvm-image-pack"

"${ARM_CC}" "${ARM_COMMON[@]}" -c "${SCRIPT_DIR}/lib/pvm_client.c" -o "${ARM_OUT}/pvm_client.o"
"${ARM_CC}" "${ARM_COMMON[@]}" -c "${SCRIPT_DIR}/common/sha256.c" -o "${ARM_OUT}/sha256.o"
"${ARM_CC}" "${ARM_COMMON[@]}" -c "${SCRIPT_DIR}/common/pvm_image.c" -o "${ARM_OUT}/pvm_image.o"
aarch64-linux-gnu-ar rcs "${ARM_OUT}/libpvm.a" "${ARM_OUT}/pvm_client.o"

"${ARM_CC}" "${ARM_COMMON[@]}" "${SCRIPT_DIR}/daemon/pvmd.c" \
	"${ARM_OUT}/pvm_client.o" "${ARM_OUT}/sha256.o" \
	-Wl,-Map="${ARM_OUT}/pvmd.map" -o "${ARM_OUT}/pvmd"
"${ARM_CC}" "${ARM_COMMON[@]}" "${SCRIPT_DIR}/cli/pvmctl.c" \
	"${ARM_OUT}/libpvm.a" -Wl,-Map="${ARM_OUT}/pvmctl.map" -o "${ARM_OUT}/pvmctl"
"${ARM_CC}" "${ARM_COMMON[@]}" "${SCRIPT_DIR}/tests/phase07_app.c" \
	"${ARM_OUT}/libpvm.a" -Wl,-Map="${ARM_OUT}/phase07-app.map" -o "${ARM_OUT}/phase07-app"
"${ARM_CC}" "${ARM_COMMON[@]}" "${SCRIPT_DIR}/tests/phase09_app.c" \
	"${ARM_OUT}/libpvm.a" -Wl,-Map="${ARM_OUT}/phase09-app.map" -o "${ARM_OUT}/phase09-app"
"${ARM_CC}" "${ARM_COMMON[@]}" "${SCRIPT_DIR}/tests/protocol_negative.c" \
	-Wl,-Map="${ARM_OUT}/protocol-negative.map" -o "${ARM_OUT}/protocol-negative"

"${ARM_CC}" -nostdlib -fno-pie -c "${SCRIPT_DIR}/guest/phase07_guest.S" \
	-o "${IMAGE_OUT}/phase07-guest-workload.o"
"${ARM_CC}" -nostdlib -static -no-pie -Wl,--build-id=none -Wl,-Ttext=0x40000000 \
	"${IMAGE_OUT}/phase07-guest-workload.o" -o "${IMAGE_OUT}/phase07-guest-workload.elf"
"${ARM_OBJCOPY}" -O binary -j .text "${IMAGE_OUT}/phase07-guest-workload.elf" \
	"${IMAGE_OUT}/phase07-guest-workload.bin"

"${ARM_CC}" -nostdlib -fno-pie -c "${SCRIPT_DIR}/guest/phase09_guest.S" \
	-o "${IMAGE_OUT}/phase09-guest-workload.o"
"${ARM_CC}" -nostdlib -static -no-pie -Wl,--build-id=none -Wl,-Ttext=0x40000000 \
	"${IMAGE_OUT}/phase09-guest-workload.o" -o "${IMAGE_OUT}/phase09-guest-workload.elf"
"${ARM_OBJCOPY}" -O binary -j .text "${IMAGE_OUT}/phase09-guest-workload.elf" \
	"${IMAGE_OUT}/phase09-guest-workload.bin"

workload_sha=$(sha256sum "${IMAGE_OUT}/phase07-guest-workload.bin" | awk '{print $1}')
"${HOST_OUT}/pvm-image-pack" "${IMAGE_OUT}/phase07-guest-workload.bin" "${workload_sha}" \
	"${IMAGE_OUT}/phase07-guest.img" > "${IMAGE_OUT}/workload-verification.log"
phase09_workload_sha=$(sha256sum "${IMAGE_OUT}/phase09-guest-workload.bin" | awk '{print $1}')
"${HOST_OUT}/pvm-image-pack" "${IMAGE_OUT}/phase09-guest-workload.bin" \
	"${phase09_workload_sha}" "${IMAGE_OUT}/phase09-guest.img" \
	>> "${IMAGE_OUT}/workload-verification.log"
"${HOST_OUT}/pvm-image-pack" "${IMAGE_OUT}/phase09-guest-workload.bin" \
	"${phase09_workload_sha}" "${IMAGE_OUT}/phase09-owner-fault.img" \
	>> "${IMAGE_OUT}/workload-verification.log"
"${HOST_OUT}/pvm-image-pack" "${IMAGE_OUT}/phase09-guest-workload.bin" \
	"${phase09_workload_sha}" "${IMAGE_OUT}/phase09-receiver-teardown.img" \
	>> "${IMAGE_OUT}/workload-verification.log"
"${HOST_OUT}/pvm-image-pack" "${IMAGE_OUT}/phase09-guest-workload.bin" \
	"${phase09_workload_sha}" "${IMAGE_OUT}/phase09-timeout.img" \
	>> "${IMAGE_OUT}/workload-verification.log"
cp "${IMAGE_OUT}/phase07-guest-workload.bin" "${IMAGE_OUT}/phase07-guest-workload-tampered.bin"
printf 'tampered\n' >> "${IMAGE_OUT}/phase07-guest-workload-tampered.bin"
if "${HOST_OUT}/pvm-image-pack" "${IMAGE_OUT}/phase07-guest-workload-tampered.bin" \
	"${workload_sha}" "${IMAGE_OUT}/rejected.img" >> "${IMAGE_OUT}/workload-verification.log"; then
	echo "tampered guest workload was accepted" >&2
	exit 1
fi
rm -f "${IMAGE_OUT}/rejected.img"
image_sha=$(sha256sum "${IMAGE_OUT}/phase07-guest.img" | awk '{print $1}')
phase09_image_sha=$(sha256sum "${IMAGE_OUT}/phase09-guest.img" | awk '{print $1}')
phase09_owner_fault_sha=$(sha256sum "${IMAGE_OUT}/phase09-owner-fault.img" |
	awk '{print $1}')
phase09_receiver_teardown_sha=$(sha256sum \
	"${IMAGE_OUT}/phase09-receiver-teardown.img" | awk '{print $1}')
phase09_timeout_sha=$(sha256sum "${IMAGE_OUT}/phase09-timeout.img" |
	awk '{print $1}')
{
	printf '%s  %s\n' "${workload_sha}" phase07-guest-workload.bin
	printf '%s  %s\n' "${image_sha}" phase07-guest.img
	printf '%s  %s\n' "${phase09_workload_sha}" phase09-guest-workload.bin
	printf '%s  %s\n' "${phase09_image_sha}" phase09-guest.img
	printf '%s  %s\n' "${phase09_owner_fault_sha}" phase09-owner-fault.img
	printf '%s  %s\n' "${phase09_receiver_teardown_sha}" phase09-receiver-teardown.img
	printf '%s  %s\n' "${phase09_timeout_sha}" phase09-timeout.img
} > "${IMAGE_OUT}/SHA256SUMS"
cp "${IMAGE_OUT}/phase07-guest.img" "${IMAGE_OUT}/phase07-guest-tampered.img"
printf 'tampered\n' >> "${IMAGE_OUT}/phase07-guest-tampered.img"

KSELF_CFLAGS=(
	-include "${OVERRIDE}/pkvm-smccc.h" -D_GNU_SOURCE -Wall -Wstrict-prototypes
	-Wno-unused-parameter -Werror -O2 -g
	-std=gnu11 -DCONFIG_64BIT -fno-builtin-memcmp -fno-builtin-memcpy
	-fno-builtin-memset -fno-builtin-strnlen -fno-stack-protector -fno-PIE
	-fno-strict-aliasing -I"${SCRIPT_DIR}/common" -I"${SCRIPT_DIR}/backend"
	-I"${KERNEL}/tools/include" -I"${KERNEL}/tools/arch/arm64/include"
	-I"${KERNEL}/usr/include" -I"${KSELF}/include" -I"${KSELF}/arm64"
	-I"${KSELF}/include/arm64" -I"${KERNEL}/tools/testing/selftests/rseq"
	-I"${KERNEL}/tools/testing/selftests" -isystem "${KSELF_USR}/include"
	-I"${KERNEL}/tools/arch/arm64/include/generated"
)
"${ARM_CC}" "${KSELF_CFLAGS[@]}" -c "${SCRIPT_DIR}/runner/pvm_runner.c" \
	-o "${ARM_OUT}/pvm_runner.o"
"${ARM_CC}" "${KSELF_CFLAGS[@]}" -c "${SCRIPT_DIR}/backend/pvm_kvm_arm64.c" \
	-o "${ARM_OUT}/pvm_kvm_arm64.o"
"${ARM_CC}" "${KSELF_CFLAGS[@]}" -D__ASSEMBLY__ -c "${KSELF}/arm64/pvm-entry.S" \
	-o "${ARM_OUT}/pvm-entry.o"

mapfile -t KSELF_LIBS < <(find "${KSELF_OUT}/lib" -name '*.o' -type f | sort)
"${ARM_CC}" -static -fno-PIE "${ARM_OUT}/pvm_runner.o" "${ARM_OUT}/pvm_kvm_arm64.o" \
	"${ARM_OUT}/pvm-entry.o" "${ARM_OUT}/pvm_image.o" "${ARM_OUT}/sha256.o" \
	"${KSELF_LIBS[@]}" -ldl -Wl,-Map="${ARM_OUT}/pvm-runner.map" \
	-o "${ARM_OUT}/pvm-runner"

echo "PVM_FRAMEWORK_BUILD_OK: ${OUTPUT_DIR}"
