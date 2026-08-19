# Phase 09 검증 How-to

이 문서는 처음 저장소를 실행하는 개발자가 Phase 09(pVM 간 DMA-BUF export/import)를 직접
검증하는 절차다. 두 단계로 구성된다: (A) flat guest로 EL2 lease/event/revoke primitive를
검증하고, (B) 실제 Linux guest 두 개를 `lkvm --protected`로 기동해 서로 다른 local
DMA-BUF FD가 같은 backing을 관찰하는지 검증한다. Trusted Access 전용 기능(OP-TEE, TA,
Secure Partition, `--protected-ffa`)은 사용하지 않는다. 별도 설명이 없으면 저장소 루트에서
명령을 실행한다.

## 1. 작업 위치와 필수 파일 확인

```bash
# 현재 디렉터리가 저장소 루트인지 확인한다.
pwd
# Clang으로 빌드한 pKVM 커널 이미지가 있는지 확인한다.
# 이 Image는 Host 커널과 lkvm이 기동하는 protected guest 커널로 둘 다 재사용된다.
test -f work/build/pkvm-full-clang/arch/arm64/boot/Image
# protected VM을 기동하는 lkvm 실행 파일이 있는지 확인한다.
test -x work/src/kvmtool/lkvm
# Phase 09 Linux guest driver/workload 소스가 있는지 확인한다.
test -f work/src/tools/pvm-buffer/driver/pvm_dmabuf.c
```

| 파일 | 용도 |
|---|---|
| `pkvm-full-clang/.../Image` | Host 커널이자 `lkvm --protected`가 기동하는 protected guest 커널 |
| `kvmtool/lkvm` | Host userspace에서 protected Linux guest를 만드는 VMM |
| `pvm-buffer/driver/pvm_dmabuf.c` | Camera/AI Linux guest가 공용으로 쓰는 DMA-BUF export/import driver |

`pwd`는 저장소 루트를 가리켜야 한다. `test` 명령은 성공하면 아무것도 출력하지 않는다.
`Image`가 없으면 커널 빌드부터 먼저 끝낸다. Phase 09의 커널 기준은 `pkvm-full-clang`
하나이며 `pkvm-full-gcc`는 저장 공간 확보를 위해 삭제되어 교차 검증하지 않는다.

## 2. 도구 확인

```bash
# camera/ai userspace workload를 정적 ARM64 바이너리로 빌드할 교차 컴파일러를 확인한다.
which aarch64-linux-gnu-gcc-9
# QEMU가 있는지 확인한다. Host를 이 위에서 기동한다.
which qemu-system-aarch64
```

두 명령 모두 실행 파일 경로를 출력해야 한다. `aarch64-linux-gnu-gcc-9`가 없으면
`sudo apt install gcc-9-aarch64-linux-gnu libc6-dev-arm64-cross`로 설치한다.
`work/src/tools/pvm-buffer/build.sh`는 guest용 busybox를 받기 위해 네트워크에
접근한다(`BUSYBOX=<경로>` 환경변수로 로컬 static busybox를 지정하면 건너뛴다).

## 3. EL2 primitive flat guest 회귀 실행

```bash
# pvm-framework 빌드와 initramfs 조립을 수행한다.
# 내부에서 phase09_guest.S(flat guest)와 phase09-app을 빌드하고 image를 서명 포장한다.
work/src/tools/pvm-framework/mkinitramfs.sh

# Phase 09 marker 검사를 활성화해 QEMU에서 flat guest 회귀를 실행한다.
# pvm.phase09=1 kernel 인자로 pvmd가 phase09-app을 추가로 실행하도록 한다.
PHASE09=1 work/src/tools/pvm-framework/run.sh \
  work/build/pvm-framework/console-phase09-primitive.log 900
```

`run.sh`는 Phase 07 protocol/auth/policy/lifecycle/recovery/fault-isolation 검사를 먼저
수행한 뒤 Phase 09 marker를 검사한다. 마지막 줄이 `PVM_FRAMEWORK_RUN_OK`이면 성공이다.
이 단계는 4 KiB page 하나만 다루는 flat guest로 EL2의 export/import/return, wrong
receiver/stale token 거부, owner/receiver teardown과 timeout revoke, Host 비노출을
검증한다. 아직 실제 Linux DMA-BUF나 서로 다른 local FD를 증명하지 않는다.

```bash
# 핵심 marker만 다시 확인한다.
grep -E "PVM_BUFFER_EXPORTED|PVM_BUFFER_IMPORTED|PVM_BUFFER_AI_READ_WRITE_OK|PVM_BUFFER_CAMERA_READ_OK|PVM_BUFFER_OWNER_ACCESS_BLOCKED|PVM_BUFFER_HOST_ACCESS_BLOCKED|Mlocked:" \
  work/build/pvm-framework/console-phase09-primitive.log
```

## 4. Linux guest 통합 빌드

```bash
# camera/ai workload, pvm_dmabuf.ko, guest/host rootfs를 모두 조립한다.
work/src/tools/pvm-buffer/build.sh
```

이 스크립트가 내부에서 수행하는 단계는 다음과 같다.

| 단계 | 내용 |
|---|---|
| userspace 빌드 | `camera.c`, `ai.c`를 `aarch64-linux-gnu-gcc-9 -static`으로 컴파일 |
| kernel module 빌드 | `pkvm-full-clang` 빌드 tree(`KDIR`)를 기준으로 `pvm_dmabuf.ko`를 out-of-tree로 빌드 |
| guest rootfs 조립 | busybox + `pvm_dmabuf.ko` + `camera`/`ai` 바이너리 + `/init`을 `rootfs-pvm-buffer-guest.cpio.gz`로 패키징. `/init`은 kernel 인자의 `pvmrole=`로 camera/ai 중 하나를 실행 |
| Host rootfs 조립 | busybox + `lkvm` + 같은 `Image`(guest 커널로 재사용) + 위 guest rootfs를 `initramfs-pvm-buffer-host.cpio.gz`로 패키징. `/init`이 AI를 먼저, 3초 뒤 Camera를 `lkvm --protected`로 각각 기동 |

마지막 줄이 `PVM_BUFFER_BUILD_OK: <경로>`이면 성공이다. 산출물은
`work/build/pvm-buffer/`에 생긴다.

```bash
# 산출물이 만들어졌는지 확인한다.
test -x work/build/pvm-buffer/camera
test -x work/build/pvm-buffer/ai
test -f work/src/tools/pvm-buffer/driver/pvm_dmabuf.ko
test -f work/build/pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz
test -f work/build/pvm-buffer/initramfs-pvm-buffer-host.cpio.gz
```

AI는 endpoint 1, Camera는 endpoint 2를 받아야 `camera.c`/`ai.c`의 자체 검사를 통과한다.
endpoint 번호는 pKVM EL2가 pVM 생성 순서로 부여하므로(먼저 생성된 pVM이 endpoint 1),
Host `/init`은 반드시 AI를 먼저 기동한다. 이 순서를 바꾸면 두 guest 모두
`PVM_LINUX_*_FAILED`로 실패한다.

## 5. Linux guest 통합 실행

```bash
# build.sh를 다시 호출한 뒤 QEMU로 Host를 부팅하고,
# Host /init이 AI와 Camera pVM을 순서대로 기동해 완료를 기다린다.
work/src/tools/pvm-buffer/run.sh \
  work/build/pvm-buffer/console-pvm-buffer-manual.log 300
```

마지막 줄이 `PVM_BUFFER_LINUX_RUN_OK`이면 성공이다. 실행 로그는
`work/build/pvm-buffer/console-pvm-buffer-manual.log`에 남는다.

```bash
# 핵심 marker를 다시 확인한다.
grep -E "PVM_LINUX_AI_ID_GET|PVM_LINUX_AI_IMPORTED|PVM_LINUX_AI_READ_WRITE_OK|PVM_LINUX_AI_COMPLETED|PVM_LINUX_CAMERA_ID_GET|PVM_LINUX_CAMERA_EXPORTED|PVM_LINUX_CAMERA_READ_OK|PVM_LINUX_CAMERA_COMPLETED|PVM_BUFFER_HOST_RC|Mlocked:" \
  work/build/pvm-buffer/console-pvm-buffer-manual.log
```

`PVM_LINUX_CAMERA_EXPORTED`의 `fd=`와 `PVM_LINUX_AI_IMPORTED`의 `fd=`는 서로 다른 Linux
kernel(별도 `lkvm --protected` instance, 별도 FD table)에서 나온 값이다. 값이 같은 숫자로
보여도 무방하다. 판정 기준은 두 값이 서로 독립된 FD table의 local FD라는 점과, 둘이 같은
`token=`(같은 backing)을 가리키며 `PVM_LINUX_AI_READ_WRITE_OK`와 `PVM_LINUX_CAMERA_READ_OK`가
같은 marker(`0x41495f5245533039`, `AI_WRITE_OK`)를 관찰한다는 점이다.

## 6. (선택) Host를 대화형으로 부팅해 수동 관찰

첫 실행에서 내부 동작을 직접 보고 싶다면 Host를 자동 `/init` 대신 shell로 부팅한다.

```bash
# Host를 자동 init 대신 대화형 /bin/sh로 부팅한다.
qemu-system-aarch64 \
  -machine virt,virtualization=on,gic-version=3 -cpu cortex-a57 -smp 4 -m 3G \
  -nographic -nic none -no-reboot \
  -kernel work/build/pkvm-full-clang/arch/arm64/boot/Image \
  -initrd work/build/pvm-buffer/initramfs-pvm-buffer-host.cpio.gz \
  -append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/bin/sh"
```

Host shell이 나타나면 안에서 다음을 실행한다.

```sh
# proc/sysfs/devtmpfs를 mount한다.
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# AI pVM을 먼저 기동해 endpoint 1을 받도록 한다. 로그는 파일로 분리한다.
/bin/lkvm run --name pvm-buffer-ai --protected --cpus 1 --mem 256 \
  --network mode=none --console serial \
  --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
  --params "earlycon rdinit=/init pvmrole=ai" >/tmp/ai.log 2>&1 &
ai_pid=$!

# AI의 pKVM VM 생성이 끝나도록 잠시 기다린 뒤 Camera를 기동해 endpoint 2를 받게 한다.
sleep 3
/bin/lkvm run --name pvm-buffer-camera --protected --cpus 1 --mem 256 \
  --network mode=none --console serial \
  --kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
  --params "earlycon rdinit=/init pvmrole=camera" >/tmp/camera.log 2>&1 &
camera_pid=$!

# 두 pVM 종료를 각각 기다리고 종료 코드를 확인한다. 둘 다 0이어야 한다.
wait "$ai_pid"; ai_rc=$?
wait "$camera_pid"; camera_rc=$?
echo "ai_rc=$ai_rc camera_rc=$camera_rc"

# 두 guest 로그에서 marker를 직접 확인한다.
grep PVM_LINUX_ /tmp/ai.log
grep PVM_LINUX_ /tmp/camera.log

# 회수되지 않은 locked page가 없는지 확인한다. 기대값은 0 kB다.
grep '^Mlocked:' /proc/meminfo

# Host를 종료한다.
poweroff -f
```

이 절차는 `work/src/tools/pvm-buffer/build.sh`가 만드는 Host `/init`과 동일한 순서를
손으로 재현한다. AI를 먼저 기동해야 하는 이유(endpoint 할당은 pVM 생성 순서로 결정)를
직접 확인할 수 있다. `sleep 3`을 지우거나 Camera를 먼저 기동하면 두 guest 모두
`PVM_LINUX_*_FAILED`가 나야 정상이다.

## 7. 최종 판정

```bash
# panic/Oops/BUG가 없는지 확인한다. 아무것도 출력되지 않아야 정상이다.
grep -E "Kernel panic|Oops|BUG:" work/build/pvm-buffer/console-pvm-buffer-manual.log || true
```

다음 조건을 모두 만족하면 Phase 09 검증 성공이다.

| 검사 | 판정 기준 |
|---|---|
| flat guest EL2 primitive | 3절 `PVM_FRAMEWORK_RUN_OK` |
| Linux guest 빌드 | 4절 `PVM_BUFFER_BUILD_OK` |
| endpoint 할당 | `PVM_LINUX_AI_ID_GET: endpoint=1`, `PVM_LINUX_CAMERA_ID_GET: endpoint=2` |
| Camera export | `PVM_LINUX_CAMERA_EXPORTED` |
| AI import/read/write | `PVM_LINUX_AI_IMPORTED`, `PVM_LINUX_AI_READ_WRITE_OK` |
| Camera 반환 확인 | `PVM_LINUX_CAMERA_READ_OK` |
| 두 pVM 종료 코드 | `PVM_BUFFER_HOST_RC: ai_rc=0 camera_rc=0` |
| 자원 회수 | `Mlocked: 0 kB` |
| panic/Oops 부재 | 위 grep 결과 없음 |
| 최종 marker | 5절 `PVM_BUFFER_LINUX_RUN_OK` |

AI pVM teardown 시 Host 콘솔에 `__pkvm_pgtable_stage2_unmap`에서 발생하는 `WARNING:`과
call trace가 매번 나타날 수 있다. `Kernel panic`이나 `Oops`가 아니고 `Mlocked: 0 kB`가
그대로 성립하면 known issue이며 판정에 영향을 주지 않는다. 자세한 내용은
[phase-09 README](README.md)를 참고한다.

## 8. 결과 기록 양식

```text
Date:
Kernel Image:
Phase 09 primitive (3절): PVM_FRAMEWORK_RUN_OK yes/no
Linux guest build (4절): PVM_BUFFER_BUILD_OK yes/no
AI endpoint: ____
Camera endpoint: ____
AI fd / Camera fd:
AI rc / Camera rc:
Mlocked after teardown: ____ kB
stage2_unmap WARNING seen: yes/no
Kernel panic/Oops: yes/no
Notes:
```
