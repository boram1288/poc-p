# Phase 06-B 수동 검증 How-to

이 문서는 처음 저장소를 실행하는 개발자가 protected Linux pVM의 표준 OP-TEE
client/TA 경로를 직접 검증하는 절차다. Trusted Access 전용 기능과
`pkvm-full-gcc`는 사용하지 않는다. 별도 설명이 없으면 저장소 루트에서 명령을 실행한다.

## 1. 작업 위치와 필수 파일 확인

```bash
pwd
test -f work/build/pkvm-full-clang/arch/arm64/boot/Image
test -f work/build/pkvm-pvm/kselftest-build/arm64/pkvm
test -f work/src/optee-pkvm/build/qemu_v8.mk
test -x work/src/optee-pkvm/toolchains/aarch64/bin/aarch64-linux-gnu-gcc
```

`pwd`는 저장소 루트를 가리켜야 한다. `test` 명령은 성공하면 아무것도 출력하지 않는다.
하나라도 실패하면 이후 단계로 진행하지 말고 해당 커널, selftest 또는 OP-TEE checkout을
먼저 준비한다. Phase 06-B의 커널 기준은 `pkvm-full-clang` 하나다.

## 2. OP-TEE, TF-A, U-Boot와 Buildroot 빌드

```bash
PROJECT_ROOT=$PWD
SOURCE_DIR=$PROJECT_ROOT/work/src/optee-pkvm
HOST_TOOLS=$PROJECT_ROOT/work/build/host-tools
JOBS=8

test -d "$HOST_TOOLS/pyelftools/elftools" || \
  git clone --depth 1 --branch v0.32 \
  https://github.com/eliben/pyelftools.git "$HOST_TOOLS/pyelftools"

export PYTHONPATH="$HOST_TOOLS/pyelftools${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$SOURCE_DIR/u-boot/scripts/dtc:$PATH"

make -C "$SOURCE_DIR/build" aarch64-toolchain
make -C "$SOURCE_DIR/build" -j"$JOBS" \
  RUST_ENABLE=n MEASURED_BOOT_FTPM=n SPMC_AT_EL=1 \
  CFG_NS_VIRTUALIZATION=y CFG_VIRT_GUEST_COUNT=3 optee-os

cd "$SOURCE_DIR/u-boot"
scripts/kconfig/merge_config.sh configs/qemu_arm64_defconfig \
  "$SOURCE_DIR/build/kconfigs/u-boot_qemu_v8.conf" \
  "$PROJECT_ROOT/work/src/tools/optee-pkvm/u-boot-pkvm.conf"
make olddefconfig \
  CROSS_COMPILE="$SOURCE_DIR/toolchains/aarch64/bin/aarch64-linux-gnu-"
cd "$PROJECT_ROOT"

make -C "$SOURCE_DIR/build" -j"$JOBS" \
  RUST_ENABLE=n MEASURED_BOOT_FTPM=n SPMC_AT_EL=1 \
  CFG_NS_VIRTUALIZATION=y CFG_VIRT_GUEST_COUNT=3 \
  u-boot buildroot arm-tf uRootfs
```

이 단계는 `build.sh`의 내부 동작을 수동으로 수행한다. 핵심 설정은 OP-TEE를 S-EL1
SPMC로 빌드하고 Host와 두 pVM을 위한 세 개의 NS virtualization context를 확보하는
것이다. 빌드 오류가 없어야 다음 단계로 진행한다.

## 3. protected-FFA kvmtool 빌드

```bash
PROJECT_ROOT=$PWD
KVMTOOL_DIR=$PROJECT_ROOT/work/src/kvmtool
DTC_DIR=$PROJECT_ROOT/work/src/dtc
TOOLCHAIN=$PROJECT_ROOT/work/src/optee-pkvm/toolchains/aarch64/bin/aarch64-linux-gnu-

test -d "$DTC_DIR/.git" || git clone \
  https://git.kernel.org/pub/scm/utils/dtc/dtc.git "$DTC_DIR"
git -C "$DTC_DIR" checkout 89c99ce78ac8e5ff10e829e21e6cffa12a6e1416

test -d "$KVMTOOL_DIR/.git" || git clone \
  https://git.kernel.org/pub/scm/linux/kernel/git/will/kvmtool.git "$KVMTOOL_DIR"
git -C "$KVMTOOL_DIR" checkout f67bc0bdae9433a9cfd05e65ea2c1bb6102566d9

grep -q protected_ffa "$KVMTOOL_DIR/arm64/include/kvm/kvm-config-arch.h" || \
  git -C "$KVMTOOL_DIR" apply \
  "$PROJECT_ROOT/work/src/tools/optee-pkvm-guest/kvmtool-protected-ffa.patch"

make -C "$DTC_DIR" -j8 libfdt
make -C "$KVMTOOL_DIR" -j8 ARCH=arm64 \
  CROSS_COMPILE="$TOOLCHAIN" CC="${TOOLCHAIN}gcc" \
  LIBFDT_DIR="$DTC_DIR/libfdt"
test -x "$KVMTOOL_DIR/lkvm"
```

`lkvm`은 `--protected-ffa` 옵션으로 protected VM에 virtual FF-A instance를 연결한다.
Host rootfs와 libc ABI를 맞추기 위해 OP-TEE 빌드와 동일한 AArch64 toolchain을 사용한다.

## 4. guest rootfs를 수동으로 조립

```bash
PROJECT_ROOT=$PWD
SOURCE_ROOT=$PROJECT_ROOT/work/src/optee-pkvm/out-br/target
GUEST_OUT=$PROJECT_ROOT/work/build/optee-pkvm-guest
GUEST_ROOT=$GUEST_OUT/initramfs-root

mkdir -p "$GUEST_OUT"
rm -rf "$GUEST_ROOT"
mkdir -p "$GUEST_ROOT"
cp -a "$SOURCE_ROOT/." "$GUEST_ROOT/"
install -m 755 work/src/tools/optee-pkvm-guest/init.sh "$GUEST_ROOT/init"
rm -f "$GUEST_ROOT/etc/init.d/S99optee-pkvm"

(cd "$GUEST_ROOT" && find . | cpio -o -H newc --quiet | gzip -9) \
  >"$GUEST_OUT/rootfs-optee-pkvm-guest.cpio.gz"
test -f "$GUEST_OUT/rootfs-optee-pkvm-guest.cpio.gz"
```

Buildroot target을 복사한 뒤 guest 전용 `/init`을 넣는다. rootfs에는 `libteec`,
`tee-supplicant`, `optee_example_aes`와 AES TA가 포함된다. Host 자동 검증 서비스는
guest에서 제거한다.

## 5. Host rootfs를 수동으로 조립

```bash
PROJECT_ROOT=$PWD
SOURCE_DIR=$PROJECT_ROOT/work/src/optee-pkvm
SOURCE_ROOT=$SOURCE_DIR/out-br/target
HOST_OUT=$PROJECT_ROOT/work/build/optee-pkvm
HOST_ROOT=$HOST_OUT/initramfs-root
KERNEL=$PROJECT_ROOT/work/build/pkvm-full-clang/arch/arm64/boot/Image
PKVM=$PROJECT_ROOT/work/build/pkvm-pvm/kselftest-build/arm64/pkvm
LKVM=$PROJECT_ROOT/work/src/kvmtool/lkvm
GUEST_ROOTFS=$PROJECT_ROOT/work/build/optee-pkvm-guest/rootfs-optee-pkvm-guest.cpio.gz
MKIMAGE=$SOURCE_DIR/u-boot/tools/mkimage

rm -rf "$HOST_ROOT"
mkdir -p "$HOST_ROOT"
cp -a "$SOURCE_ROOT/." "$HOST_ROOT/"
install -m 755 work/src/tools/optee-pkvm/init.sh "$HOST_ROOT/init"
install -m 755 "$PKVM" "$HOST_ROOT/usr/bin/pkvm"
install -m 755 "$LKVM" "$HOST_ROOT/usr/bin/lkvm"
mkdir -p "$HOST_ROOT/opt/pvm"
install -m 644 "$KERNEL" "$HOST_ROOT/opt/pvm/Image"
install -m 644 "$GUEST_ROOTFS" "$HOST_ROOT/opt/pvm/rootfs.cpio.gz"

# 수동 검증이므로 S99optee-pkvm 자동 실행 파일은 만들지 않는다.
rm -f "$HOST_ROOT/etc/init.d/S99optee-pkvm"

(cd "$HOST_ROOT" && find . | cpio -o -H newc --quiet | gzip -9) \
  >"$HOST_OUT/rootfs-optee-pkvm-manual.cpio.gz"

"$MKIMAGE" -A arm64 -O linux -T kernel -C none \
  -a 0x42200000 -e 0x42200000 -n 'Linux pKVM kernel' \
  -d "$KERNEL" "$HOST_OUT/uImage"
"$MKIMAGE" -A arm64 -T ramdisk -C gzip \
  -a 0x45000000 -e 0x45000000 -n 'OP-TEE pKVM manual rootfs' \
  -d "$HOST_OUT/rootfs-optee-pkvm-manual.cpio.gz" \
  "$HOST_OUT/rootfs-manual.cpio.uboot"
```

자동 하네스가 실행되지 않는 별도 Host rootfs를 만든다. 기존 자동 검증 rootfs를
덮어쓰지 않으므로 자동 시험과 수동 시험을 서로 독립적으로 유지할 수 있다.

## 6. QEMU를 직접 실행

```bash
PROJECT_ROOT=$PWD
SOURCE_DIR=$PROJECT_ROOT/work/src/optee-pkvm
HOST_OUT=$PROJECT_ROOT/work/build/optee-pkvm

ln -sf "$HOST_OUT/uImage" "$SOURCE_DIR/out/bin/uImage"
ln -sf "$HOST_OUT/rootfs-manual.cpio.uboot" \
  "$SOURCE_DIR/out/bin/rootfs.cpio.uboot"

cd "$SOURCE_DIR/out/bin"
qemu-system-aarch64 \
  -machine virt,acpi=off,secure=on,virtualization=on,gic-version=3 \
  -cpu cortex-a57 -smp 4 -m 3G -nographic -nic none -no-reboot \
  -semihosting-config enable=on,target=native \
  -bios bl1.bin \
  -kernel "$PROJECT_ROOT/work/build/pkvm-full-clang/arch/arm64/boot/Image" \
  -initrd "$HOST_OUT/rootfs-optee-pkvm-manual.cpio.gz" \
  -append 'console=ttyAMA0,38400 keep_bootcon kvm-arm.mode=protected' \
  -serial mon:stdio -serial "file:$HOST_OUT/secure-manual.log"
```

이 명령은 QEMU console을 터미널에 연결한다. Buildroot login prompt가 나타나면 `root`로
로그인한다. 별도 터미널에서는 `secure-manual.log`를 확인할 수 있다. 종료는 guest에서
`poweroff -f`를 실행한다.

## 7. Host OP-TEE와 최소 pVM을 수동 검증

아래 명령은 QEMU 안의 Host Linux shell에서 실행한다.

```sh
chmod 0600 /dev/tee0 /dev/teepriv0
/usr/sbin/tee-supplicant -d /dev/teepriv0

/usr/bin/pkvm >/tmp/pkvm-manual.log 2>&1 &
pkvm_pid=$!

# VM/vCPU fd가 생성된 뒤 한 번만 정지한다.
while kill -0 "$pkvm_pid" 2>/dev/null; do
  kvm_fds=$(ls -l /proc/$pkvm_pid/fd 2>/dev/null | \
    grep -Ec '/dev/kvm|anon_inode:.*kvm')
  if [ "$kvm_fds" -ge 3 ]; then
    kill -STOP "$pkvm_pid"
    break
  fi
done
echo "KVM fd count: $kvm_fds"

/usr/bin/optee_example_aes >/tmp/aes-during-pvm.log 2>&1 &
aes_pid=$!
kill -CONT "$pkvm_pid"
wait "$aes_pid"
grep 'Clear text and decoded text match' /tmp/aes-during-pvm.log

wait $pkvm_pid
grep -E 'PVM_FFA_MINIMAL_OK|PVM_FFA_NEGATIVE_OK|Caught expected segfault|All ok!' \
  /tmp/pkvm-manual.log

/usr/bin/optee_example_aes >/tmp/aes-after-pvm.log 2>&1
grep 'Clear text and decoded text match' /tmp/aes-after-pvm.log
grep '^Mlocked:' /proc/meminfo
```

KVM fd가 보여야 protected VM과 vCPU가 생성된 것이다. 두 AES 호출은 각각 pVM 실행 중
Host OP-TEE 호출과 teardown 후 재호출을 검증한다. selftest 로그에는 정상 FF-A,
잘못된 RX/TX map/share/endpoint 거부, Host private-page 접근 차단과 `All ok!`이 있어야
한다. 마지막 `Mlocked` 값은 `0 kB`여야 한다.

## 8. Linux pVM의 OP-TEE TA를 수동 검증

Host Linux shell에서 guest를 `/bin/sh`로 부팅한다.

```sh
/usr/bin/lkvm run --name optee-pvm-manual --protected --protected-ffa \
  --cpus 1 --mem 512 --network mode=none --console serial \
  --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
  --params 'earlycon rdinit=/bin/sh'
```

guest shell이 나타나면 다음 명령을 guest 안에서 실행한다.

```sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
test -e /dev/teepriv0
chmod 0600 /dev/tee0 /dev/teepriv0
/usr/sbin/tee-supplicant -d /dev/teepriv0
/usr/bin/optee_example_aes
poweroff -f
```

kernel log에 `ARM FF-A: Firmware version 1.2 found`와 `optee: initialized driver`가
있어야 한다. AES client는 encode/decode 뒤 `Clear text and decoded text match`를
출력해야 한다. 이 client의 `AES_TEST_BUFFER_SIZE`는 4096이므로 정확히 4 KiB를
검증한다.

## 9. 두 pVM endpoint/session 분리 검증

Host Linux shell에서 두 VMM을 동시에 시작한다.

```sh
/usr/bin/lkvm run --name optee-pvm-a --protected --protected-ffa \
  --cpus 1 --mem 384 --network mode=none --console serial \
  --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
  --params 'earlycon rdinit=/init' >/tmp/optee-pvm-a.log 2>&1 &
a_pid=$!

/usr/bin/lkvm run --name optee-pvm-b --protected --protected-ffa \
  --cpus 1 --mem 384 --network mode=none --console serial \
  --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
  --params 'earlycon rdinit=/init' >/tmp/optee-pvm-b.log 2>&1 &
b_pid=$!

wait $a_pid; a_rc=$?
wait $b_pid; b_rc=$?
grep 'PVM_TA_AES_4K_OK' /tmp/optee-pvm-a.log
grep 'PVM_TA_AES_4K_OK' /tmp/optee-pvm-b.log
echo "pVM-A rc=$a_rc, pVM-B rc=$b_rc"
```

두 로그 모두 4 KiB 성공 marker를 포함하고 반환값이 0이어야 한다. secure log에는 서로
다른 guest 생성과 제거가 쌍으로 나타난다.

## 10. 최종 결과 판정

QEMU 종료 후 개발 Host에서 확인한다.

```bash
grep -E 'Added guest|Removing guest|OP-TEE version' \
  work/build/optee-pkvm/secure-manual.log
grep -E 'panic|Kernel panic|BRK|Unhandled fault' \
  work/build/optee-pkvm/secure-manual.log || true
```

다음 조건을 모두 만족하면 성공이다.

| 검사 | 수동 확인 결과 |
|---|---|
| Host OP-TEE | AES encode/decode 및 원본 일치 |
| 최소 pVM FF-A | `PVM_FFA_MINIMAL_OK` |
| 잘못된 FF-A 요청 | `PVM_FFA_NEGATIVE_OK: bad_rxtx bad_share bad_endpoint` |
| Host private-page 접근 | `Caught expected segfault` |
| guest OP-TEE | FF-A 1.2 및 OP-TEE driver 초기화 |
| guest TA | 4096-byte AES encode/decode 원본 일치 |
| 두 pVM | 두 로그 모두 `PVM_TA_AES_4K_OK`, rc=0 |
| teardown | `Mlocked: 0 kB` |
| secure side | guest 생성/제거 쌍 존재, panic/BRK 없음 |

## 11. 결과 기록 양식

```text
Date:
Kernel Image:
Host AES during pVM: pass/fail
PVM_FFA_MINIMAL_OK: yes/no
PVM_FFA_NEGATIVE_OK: yes/no
Guest FF-A 1.2 / OP-TEE probe: pass/fail
Guest 4096-byte AES: pass/fail
Two-pVM isolation: pass/fail
Mlocked after teardown: ____ kB
Secure log panic/BRK: yes/no
Notes:
```
