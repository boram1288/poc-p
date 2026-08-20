#!/bin/bash
# Phase 06-B: pVM 내부 OP-TEE TA 호출 (FF-A 직접 경로) 검증
# 참고 문서: docs/phase-06-b/README.md, docs/phase-06-b/VERIFICATION.md
# 이 스크립트는 VERIFICATION.md의 수동 절차를 그대로 자동화한 것이다.
set -eu
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

skip_if_done 06b
require_prev_phase 06
require_prev_phase 04

SOURCE_DIR="${VERIFY_ROOT}/work/src/optee-pkvm"
KERNEL="${VERIFY_ROOT}/work/build/pkvm-full-clang/arch/arm64/boot/Image"
PKVM_BIN="${VERIFY_ROOT}/work/build/pkvm-pvm/kselftest-build/arm64/pkvm"
LKVM="${VERIFY_ROOT}/work/src/kvmtool/lkvm"
GUEST_OUT="${VERIFY_ROOT}/work/build/optee-pkvm-guest"
HOST_OUT="${VERIFY_ROOT}/work/build/optee-pkvm"
HOST_ROOT="${HOST_OUT}/initramfs-root"

require_file "${KERNEL}"
require_file "${PKVM_BIN}"
require_file "${SOURCE_DIR}/build/qemu_v8.mk" "(work/src/tools/optee-pkvm/build.sh 선행 필요)"

# Phase 06이 이미 arm64 kvmtool과 guest rootfs를 빌드해 두었다 (동일 산출물을
# work/src/tools/optee-pkvm/mkrootfs.sh도 요구하므로). 여기서는 재사용한다.
require_exec "${LKVM}"
GUEST_ROOTFS="${GUEST_OUT}/rootfs-optee-pkvm-guest.cpio.gz"
require_file "${GUEST_ROOTFS}"

verify_log "Host rootfs 조립 (pkvm selftest + lkvm + guest image)"
rm -rf "${HOST_ROOT}"
mkdir -p "${HOST_ROOT}"
cp -a "${SOURCE_DIR}/out-br/target/." "${HOST_ROOT}/"
install -m 755 "${VERIFY_ROOT}/work/src/tools/optee-pkvm/init.sh" "${HOST_ROOT}/init"
install -m 755 "${PKVM_BIN}" "${HOST_ROOT}/usr/bin/pkvm"
install -m 755 "${LKVM}" "${HOST_ROOT}/usr/bin/lkvm"
install -m 755 "${VERIFY_ROOT}/work/src/tools/optee-pkvm/coexist-test.sh" \
  "${HOST_ROOT}/usr/bin/optee-pkvm-coexist"
mkdir -p "${HOST_ROOT}/opt/pvm"
install -m 644 "${KERNEL}" "${HOST_ROOT}/opt/pvm/Image"
install -m 644 "${GUEST_ROOTFS}" "${HOST_ROOT}/opt/pvm/rootfs.cpio.gz"

# 자동(비대화형) 검증이므로 VERIFICATION.md의 수동 로그인 절차 대신
# work/src/tools/optee-pkvm/mkrootfs.sh와 동일하게 부팅 시 자동으로
# coexist-test.sh(PVM_LINUX_BOOT_OK, COEX_TWO_PVM_ISOLATION_OK 등 포함)를
# 실행하고 종료하도록 한다.
cat > "${HOST_ROOT}/etc/init.d/S99optee-pkvm" <<'INIT'
#!/bin/sh
echo "OPTEE_PKVM_INIT_START"
/usr/bin/optee-pkvm-coexist
rc=$?
echo "OPTEE_PKVM_INIT_RC=${rc}"
poweroff -f
INIT
chmod 755 "${HOST_ROOT}/etc/init.d/S99optee-pkvm"

HOST_ROOTFS="${HOST_OUT}/rootfs-optee-pkvm-manual.cpio.gz"
(cd "${HOST_ROOT}" && find . | cpio -o -H newc --quiet | gzip -9) > "${HOST_ROOTFS}"
require_file "${HOST_ROOTFS}"

verify_log "TF-A bl1.bin으로 E-2 QEMU 부팅"
SECURE_LOG="${HOST_OUT}/secure-phase06b.log"
NORMAL_LOG="${HOST_OUT}/console-phase06b.log"
BL1="${SOURCE_DIR}/out/bin/bl1.bin"
MKIMAGE="${SOURCE_DIR}/u-boot/tools/mkimage"
require_file "${BL1}"
require_exec "${MKIMAGE}"

# TF-A's BL33 (U-Boot) boots via CONFIG_BOOTCOMMAND's
# "load hostfs - ... uImage / rootfs.cpio.uboot" (see
# work/src/tools/optee-pkvm/u-boot-pkvm.conf), i.e. QEMU semihosting reads
# files named uImage/rootfs.cpio.uboot from the working directory — QEMU's
# own -kernel/-initrd/-append flags are never consulted on this boot path, and
# U-Boot sets its own bootargs via CONFIG_BOOTCOMMAND. Wrap this Phase's
# Image/rootfs the same way work/src/tools/optee-pkvm/mkrootfs.sh does for
# plain Phase 06. QEMU's semihosting "hostfs" does not reliably follow
# symlinks (confirmed by reproduction: a symlink kept resolving to a stale
# rootfs left behind by a previous phase06.sh run even though `readlink -f`
# and `stat` showed it pointing at the new file) — copy the images into place
# instead of symlinking them.
UIMAGE="${HOST_OUT}/uImage-phase06b"
UROOTFS="${HOST_OUT}/rootfs-phase06b.cpio.uboot"
"${MKIMAGE}" -A arm64 -O linux -T kernel -C none \
  -a 0x42200000 -e 0x42200000 -n 'Linux pKVM kernel' \
  -d "${KERNEL}" "${UIMAGE}"
"${MKIMAGE}" -A arm64 -T ramdisk -C gzip \
  -a 0x45000000 -e 0x45000000 -n 'OP-TEE pKVM Phase 06-B rootfs' \
  -d "${HOST_ROOTFS}" "${UROOTFS}"
cp -f "${UIMAGE}" "${SOURCE_DIR}/out/bin/uImage"
cp -f "${UROOTFS}" "${SOURCE_DIR}/out/bin/rootfs.cpio.uboot"

# TF-A locates its FIP-referenced images (BL2/BL31/BL32/BL33) relative to the
# working directory, so this must run from out/bin like work/src/tools/optee-pkvm/run.sh does.
# No -kernel/-initrd/-append: U-Boot's own CONFIG_BOOTCOMMAND loads and boots
# the images above, so those QEMU flags would be inert (and -append requires
# -kernel to be accepted at all).
(cd "${SOURCE_DIR}/out/bin" && timeout --signal=KILL 1200 qemu-system-aarch64 \
  -machine virt,acpi=off,secure=on,virtualization=on,gic-version=3 \
  -cpu cortex-a57 -smp 4 -m 3G -nographic -nic none -no-reboot \
  -monitor none \
  -semihosting-config enable=on,target=native \
  -bios "${BL1}" \
  -serial "file:${NORMAL_LOG}" -serial "file:${SECURE_LOG}" \
  < /dev/null)

check_markers "${NORMAL_LOG}" \
  "PVM_LINUX_BOOT_OK" \
  "PVM_OPTEE_PROBE_OK" \
  "PVM_TA_AES_4K_OK" \
  "PVM_FFA_NEGATIVE_OK" \
  "COEX_KVM_ACTIVE" \
  "COEX_AES_DURING_PVM_OK" \
  "COEX_PVM_OK" \
  "COEX_AES_REOPEN_OK" \
  "COEX_TWO_PVM_ISOLATION_OK" \
  "OPTEE_PKVM_INIT_RC=0"
check_mlocked_zero "${NORMAL_LOG}"

check_markers "${SECURE_LOG}" "OP-TEE version"

# "panic" alone also matches benign OP-TEE init call names like
# init_multi_core_panic_handler(), so require a real panic report line
# ("Panic '...'") rather than a bare substring.
hit=$(grep -E "Panic '|Kernel panic|BRK|Unhandled fault" "${SECURE_LOG}" 2>/dev/null || true)
if [ -n "${hit}" ]; then
  echo "${hit}" >&2
  verify_fail "Secure World 로그에서 panic/BRK/fault 문자열이 발견됐습니다."
fi
check_no_kernel_fault "${NORMAL_LOG}"

mark_done 06b "phase06b logs: ${NORMAL_LOG}, ${SECURE_LOG}"
verify_log "Phase 06-B 완료"
