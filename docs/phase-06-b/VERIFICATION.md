# Phase 06-B 수동 검증 How-to

이 문서는 처음 저장소를 실행하는 개발자가 protected Linux pVM의 표준 OP-TEE
client/TA 경로를 직접 검증하는 절차다. Trusted Access 전용 기능과
`pkvm-full-gcc`는 사용하지 않는다. 별도 설명이 없으면 저장소 루트에서 명령을 실행한다.

## 1. 작업 위치와 필수 파일 확인

```bash
# 현재 디렉터리가 저장소 루트인지 확인한다.
pwd
# Clang으로 빌드한 pKVM 커널 이미지가 있는지 확인한다.
test -f work/build/pkvm-full-clang/arch/arm64/boot/Image
# arm64 pKVM selftest 실행 파일이 있는지 확인한다.
test -f work/build/pkvm-pvm/kselftest-build/arm64/pkvm
# OP-TEE QEMU v8 빌드 설정이 있는지 확인한다.
test -f work/src/optee-pkvm/build/qemu_v8.mk
# AArch64 교차 컴파일러가 실행 가능한지 확인한다.
test -x work/src/optee-pkvm/toolchains/aarch64/bin/aarch64-linux-gnu-gcc
```

| 파일 | 용도 |
|---|---|
| `pkvm-full-clang/.../Image` | Host와 pVM에 사용하는 pKVM Linux 커널 이미지 |
| `pkvm-pvm/.../pkvm` | protected VM 생성과 메모리 격리를 검사하는 KVM selftest |
| `optee-pkvm/build/qemu_v8.mk` | QEMU v8용 OP-TEE 전체 빌드 설정 |
| `aarch64-linux-gnu-gcc` | OP-TEE와 AArch64 도구를 빌드하는 교차 컴파일러 |

`pkvm-pvm/kselftest-build/arm64/pkvm`은 단일 실행 파일 형태의 KVM selftest이며
다음 검사를 포함한다.

- protected VM과 vCPU 생성 및 guest payload 실행
- regular page와 THP의 private-page Host 접근 차단
- 메모리 share, unshare, relinquish와 MMIO guard
- FF-A 1.2 협상과 guest endpoint ID 확인
- 잘못된 RX/TX map, memory share, endpoint 요청 거부
- VM 종료 후 locked memory와 pVM 자원 회수

`pwd`는 저장소 루트를 가리켜야 한다. `test` 명령은 성공하면 아무것도 출력하지 않는다.
하나라도 실패하면 이후 단계로 진행하지 말고 해당 커널, selftest 또는 OP-TEE checkout을
먼저 준비한다. Phase 06-B의 커널 기준은 `pkvm-full-clang` 하나다.

## 2. OP-TEE, TF-A, U-Boot와 Buildroot 빌드

```bash
# 이후 명령에서 사용할 저장소와 빌드 경로를 정의한다.
PROJECT_ROOT=$PWD
SOURCE_DIR=$PROJECT_ROOT/work/src/optee-pkvm
HOST_TOOLS=$PROJECT_ROOT/work/build/host-tools
JOBS=8

# pyelftools가 없으면 지정 버전을 로컬 빌드 디렉터리에 받는다.
test -d "$HOST_TOOLS/pyelftools/elftools" || \
  git clone --depth 1 --branch v0.32 \
  https://github.com/eliben/pyelftools.git "$HOST_TOOLS/pyelftools"

# OP-TEE 빌드가 로컬 pyelftools와 U-Boot dtc를 찾도록 환경을 설정한다.
export PYTHONPATH="$HOST_TOOLS/pyelftools${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$SOURCE_DIR/u-boot/scripts/dtc:$PATH"

# OP-TEE에서 사용하는 AArch64 toolchain을 준비한다.
make -C "$SOURCE_DIR/build" aarch64-toolchain
# S-EL1 SPMC와 세 개의 NS virtualization context로 OP-TEE를 빌드한다.
make -C "$SOURCE_DIR/build" -j"$JOBS" \
  RUST_ENABLE=n MEASURED_BOOT_FTPM=n SPMC_AT_EL=1 \
  CFG_NS_VIRTUALIZATION=y CFG_VIRT_GUEST_COUNT=3 optee-os

# U-Boot 소스 디렉터리로 이동한다.
cd "$SOURCE_DIR/u-boot"
# QEMU 기본 설정에 pKVM 전용 U-Boot 설정을 병합한다.
scripts/kconfig/merge_config.sh configs/qemu_arm64_defconfig \
  "$SOURCE_DIR/build/kconfigs/u-boot_qemu_v8.conf" \
  "$PROJECT_ROOT/work/src/tools/optee-pkvm/u-boot-pkvm.conf"
# 병합된 설정의 누락된 기본값을 채운다.
make olddefconfig \
  CROSS_COMPILE="$SOURCE_DIR/toolchains/aarch64/bin/aarch64-linux-gnu-"
# 저장소 루트로 돌아온다.
cd "$PROJECT_ROOT"

# U-Boot, Buildroot, TF-A와 U-Boot용 rootfs를 빌드한다.
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
# kvmtool, dtc와 교차 컴파일러 경로를 정의한다.
PROJECT_ROOT=$PWD
KVMTOOL_DIR=$PROJECT_ROOT/work/src/kvmtool
DTC_DIR=$PROJECT_ROOT/work/src/dtc
TOOLCHAIN=$PROJECT_ROOT/work/src/optee-pkvm/toolchains/aarch64/bin/aarch64-linux-gnu-

# 상위 저장소가 검증한 dtc와 kvmtool revision을 초기화한다.
git submodule update --init --filter=blob:none -- \
  work/src/dtc work/src/kvmtool
test "$(git -C "$DTC_DIR" rev-parse HEAD)" = \
  89c99ce78ac8e5ff10e829e21e6cffa12a6e1416
test "$(git -C "$KVMTOOL_DIR" rev-parse HEAD)" = \
  6866a248977d16bc293c6f4f6609daa4f465b073

# protected-FFA 지원이 없을 때만 저장소의 패치를 적용한다.
grep -q protected_ffa "$KVMTOOL_DIR/arm64/include/kvm/kvm-config-arch.h" || \
  git -C "$KVMTOOL_DIR" apply \
  "$PROJECT_ROOT/work/src/tools/optee-pkvm-guest/kvmtool-protected-ffa.patch"

# kvmtool이 링크할 libfdt를 먼저 빌드한다.
make -C "$DTC_DIR" -j8 libfdt
# OP-TEE와 같은 toolchain으로 arm64 lkvm을 빌드한다.
make -C "$KVMTOOL_DIR" -j8 ARCH=arm64 \
  CROSS_COMPILE="$TOOLCHAIN" CC="${TOOLCHAIN}gcc" \
  LIBFDT_DIR="$DTC_DIR/libfdt"
# 최종 lkvm 바이너리가 실행 가능한지 확인한다.
test -x "$KVMTOOL_DIR/lkvm"
```

`lkvm`은 `--protected-ffa` 옵션으로 protected VM에 virtual FF-A instance를 연결한다.
Host rootfs와 libc ABI를 맞추기 위해 OP-TEE 빌드와 동일한 AArch64 toolchain을 사용한다.

## 4. guest rootfs를 수동으로 조립

```bash
# guest rootfs 원본과 출력 경로를 정의한다.
PROJECT_ROOT=$PWD
SOURCE_ROOT=$PROJECT_ROOT/work/src/optee-pkvm/out-br/target
GUEST_OUT=$PROJECT_ROOT/work/build/optee-pkvm-guest
GUEST_ROOT=$GUEST_OUT/initramfs-root

# guest 출력 디렉터리를 만들고 이전 staging rootfs를 비운다.
mkdir -p "$GUEST_OUT"
rm -rf "$GUEST_ROOT"
mkdir -p "$GUEST_ROOT"
# Buildroot target 전체를 guest staging rootfs로 복사한다.
cp -a "$SOURCE_ROOT/." "$GUEST_ROOT/"
# guest 전용 init을 PID 1로 설치한다.
install -m 755 work/src/tools/optee-pkvm-guest/init.sh "$GUEST_ROOT/init"
# Host 자동 검증 서비스가 guest에서 실행되지 않도록 제거한다.
rm -f "$GUEST_ROOT/etc/init.d/S99optee-pkvm"

# staging rootfs를 gzip 압축된 newc initramfs로 패키징한다.
(cd "$GUEST_ROOT" && find . | cpio -o -H newc --quiet | gzip -9) \
  >"$GUEST_OUT/rootfs-optee-pkvm-guest.cpio.gz"
# 생성된 guest initramfs를 확인한다.
test -f "$GUEST_OUT/rootfs-optee-pkvm-guest.cpio.gz"
```

Buildroot target을 복사한 뒤 guest 전용 `/init`을 넣는다. rootfs에는 `libteec`,
`tee-supplicant`, `optee_example_aes`와 AES TA가 포함된다. Host 자동 검증 서비스는
guest에서 제거한다.

## 5. Host rootfs를 수동으로 조립

```bash
# Host rootfs에 넣을 입력 파일과 출력 경로를 정의한다.
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

# 이전 Host staging rootfs를 비우고 Buildroot target을 복사한다.
rm -rf "$HOST_ROOT"
mkdir -p "$HOST_ROOT"
cp -a "$SOURCE_ROOT/." "$HOST_ROOT/"
# devtmpfs를 mount하고 Buildroot init으로 넘어가는 init을 설치한다.
install -m 755 work/src/tools/optee-pkvm/init.sh "$HOST_ROOT/init"
# pKVM selftest와 protected-FFA VMM을 Host rootfs에 설치한다.
install -m 755 "$PKVM" "$HOST_ROOT/usr/bin/pkvm"
install -m 755 "$LKVM" "$HOST_ROOT/usr/bin/lkvm"
# pVM이 사용할 커널과 guest rootfs를 /opt/pvm에 설치한다.
mkdir -p "$HOST_ROOT/opt/pvm"
install -m 644 "$KERNEL" "$HOST_ROOT/opt/pvm/Image"
install -m 644 "$GUEST_ROOTFS" "$HOST_ROOT/opt/pvm/rootfs.cpio.gz"

# 수동 검증이므로 S99optee-pkvm 자동 실행 파일은 만들지 않는다.
rm -f "$HOST_ROOT/etc/init.d/S99optee-pkvm"

# Host staging rootfs를 수동 검증용 initramfs로 패키징한다.
(cd "$HOST_ROOT" && find . | cpio -o -H newc --quiet | gzip -9) \
  >"$HOST_OUT/rootfs-optee-pkvm-manual.cpio.gz"

# Linux Image를 U-Boot가 읽는 legacy kernel image로 감싼다.
"$MKIMAGE" -A arm64 -O linux -T kernel -C none \
  -a 0x42200000 -e 0x42200000 -n 'Linux pKVM kernel' \
  -d "$KERNEL" "$HOST_OUT/uImage"
# 수동 검증용 initramfs를 U-Boot ramdisk image로 감싼다.
"$MKIMAGE" -A arm64 -T ramdisk -C gzip \
  -a 0x45000000 -e 0x45000000 -n 'OP-TEE pKVM manual rootfs' \
  -d "$HOST_OUT/rootfs-optee-pkvm-manual.cpio.gz" \
  "$HOST_OUT/rootfs-manual.cpio.uboot"
```

자동 하네스가 실행되지 않는 별도 Host rootfs를 만든다. 기존 자동 검증 rootfs를
덮어쓰지 않으므로 자동 시험과 수동 시험을 서로 독립적으로 유지할 수 있다.

## 6. QEMU를 직접 실행

```bash
# QEMU 입력 이미지와 OP-TEE checkout 경로를 정의한다.
PROJECT_ROOT=$PWD
SOURCE_DIR=$PROJECT_ROOT/work/src/optee-pkvm
HOST_OUT=$PROJECT_ROOT/work/build/optee-pkvm

# TF-A/U-Boot가 찾는 고정 파일명에 수동 검증 이미지를 연결한다.
ln -sf "$HOST_OUT/uImage" "$SOURCE_DIR/out/bin/uImage"
ln -sf "$HOST_OUT/rootfs-manual.cpio.uboot" \
  "$SOURCE_DIR/out/bin/rootfs.cpio.uboot"

# TF-A의 bl1.bin이 있는 실행 디렉터리로 이동한다.
cd "$SOURCE_DIR/out/bin"
# secure/virtualization 지원 QEMU를 시작하고 두 번째 UART를 secure log에 저장한다.
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
# Host OP-TEE device 권한을 제한하고 tee-supplicant를 시작한다.
chmod 0600 /dev/tee0 /dev/teepriv0
/usr/sbin/tee-supplicant -d /dev/teepriv0

# pKVM selftest를 background로 시작하고 PID를 저장한다.
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
# 관찰된 KVM 관련 fd 개수를 출력한다. 3개 이상이어야 한다.
echo "KVM fd count: $kvm_fds"

# pVM이 멈춘 동안 Host AES 호출을 시작한다.
/usr/bin/optee_example_aes >/tmp/aes-during-pvm.log 2>&1 &
aes_pid=$!
# pVM과 Host AES가 겹쳐 실행되도록 pVM을 재개한다.
kill -CONT "$pkvm_pid"
# Host AES 종료와 원본 일치 문구를 확인한다.
wait "$aes_pid"
grep 'Clear text and decoded text match' /tmp/aes-during-pvm.log

# pVM 종료를 기다린 뒤 FF-A, 접근 차단과 전체 성공 marker를 확인한다.
wait $pkvm_pid
grep -E 'PVM_FFA_MINIMAL_OK|PVM_FFA_NEGATIVE_OK|Caught expected segfault|All ok!' \
  /tmp/pkvm-manual.log

# pVM teardown 후 Host AES 세션을 다시 열 수 있는지 확인한다.
/usr/bin/optee_example_aes >/tmp/aes-after-pvm.log 2>&1
grep 'Clear text and decoded text match' /tmp/aes-after-pvm.log
# 회수되지 않은 locked page가 없는지 확인한다. 기대값은 0 kB다.
grep '^Mlocked:' /proc/meminfo
```

KVM fd가 보여야 protected VM과 vCPU가 생성된 것이다. 두 AES 호출은 각각 pVM 실행 중
Host OP-TEE 호출과 teardown 후 재호출을 검증한다. selftest 로그에는 정상 FF-A,
잘못된 RX/TX map/share/endpoint 거부, Host private-page 접근 차단과 `All ok!`이 있어야
한다. 마지막 `Mlocked` 값은 `0 kB`여야 한다.

## 8. Linux pVM의 OP-TEE TA를 수동 검증

Host Linux shell에서 guest를 `/bin/sh`로 부팅한다.

```sh
# protected-FFA Linux pVM을 자동 init 대신 대화형 /bin/sh로 부팅한다.
/usr/bin/lkvm run --name optee-pvm-manual --protected --protected-ffa \
  --cpus 1 --mem 512 --network mode=none --console serial \
  --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
  --params 'earlycon rdinit=/bin/sh'
```

guest shell이 나타나면 다음 명령을 guest 안에서 실행한다.

```sh
# guest의 proc, sysfs와 동적 device filesystem을 mount한다.
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
# guest OP-TEE private device가 생성됐는지 확인한다.
test -e /dev/teepriv0
# device 권한을 제한하고 guest tee-supplicant를 시작한다.
chmod 0600 /dev/tee0 /dev/teepriv0
/usr/sbin/tee-supplicant -d /dev/teepriv0
# 일반 OP-TEE client로 4096-byte AES 암복호화를 실행한다.
/usr/bin/optee_example_aes
# guest를 종료해 session, 공유 page와 vCPU 회수를 유도한다.
poweroff -f
```

kernel log에 `ARM FF-A: Firmware version 1.2 found`와 `optee: initialized driver`가
있어야 한다. AES client는 encode/decode 뒤 `Clear text and decoded text match`를
출력해야 한다. 이 client의 `AES_TEST_BUFFER_SIZE`는 4096이므로 정확히 4 KiB를
검증한다.

## 9. 두 pVM endpoint/session 분리 검증

Host Linux shell에서 두 VMM을 동시에 시작한다.

```sh
# 첫 번째 protected-FFA pVM을 background로 시작한다.
/usr/bin/lkvm run --name optee-pvm-a --protected --protected-ffa \
  --cpus 1 --mem 384 --network mode=none --console serial \
  --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
  --params 'earlycon rdinit=/init' >/tmp/optee-pvm-a.log 2>&1 &
a_pid=$!

# 두 번째 protected-FFA pVM을 동시에 시작한다.
/usr/bin/lkvm run --name optee-pvm-b --protected --protected-ffa \
  --cpus 1 --mem 384 --network mode=none --console serial \
  --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
  --params 'earlycon rdinit=/init' >/tmp/optee-pvm-b.log 2>&1 &
b_pid=$!

# 두 pVM 종료 코드를 각각 저장한다.
wait $a_pid; a_rc=$?
wait $b_pid; b_rc=$?
# 두 로그가 모두 4 KiB TA 성공 marker를 포함하는지 확인한다.
grep 'PVM_TA_AES_4K_OK' /tmp/optee-pvm-a.log
grep 'PVM_TA_AES_4K_OK' /tmp/optee-pvm-b.log
# 두 VMM의 종료 코드를 출력한다. 둘 다 0이어야 한다.
echo "pVM-A rc=$a_rc, pVM-B rc=$b_rc"
```

두 로그 모두 4 KiB 성공 marker를 포함하고 반환값이 0이어야 한다. secure log에는 서로
다른 guest 생성과 제거가 쌍으로 나타난다.

## 10. 최종 결과 판정

QEMU 종료 후 개발 Host에서 확인한다.

```bash
# secure log에서 OP-TEE 시작과 각 guest 생성/제거를 확인한다.
grep -E 'Added guest|Removing guest|OP-TEE version' \
  work/build/optee-pkvm/secure-manual.log
# panic, EL2 BRK 또는 처리되지 않은 fault가 없는지 검색한다.
# 아무것도 출력되지 않는 것이 정상이다.
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
