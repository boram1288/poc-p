# Phase 10 검증 How-to 및 결과

이 문서는 저장소를 처음 실행하는 개발자가 Phase 10의 공개 객체 탐지 fixture 기반
Camera pVM → AI pVM → Host Application 파이프라인을 직접 다시 검증하는 절차다. 실물
camera/GPU는 사용하지 않는다. 준비 Host에서 Open Model Zoo CPU demo를 실행해 fixture를
만들고, E-3 커스텀 QEMU 위에서 protected Camera/AI Linux guest 두 개를 기동한다.

검증은 다음 네 부분으로 구성된다.

1. 고정 revision의 pKVM kernel, QEMU와 kvmtool을 준비한다.
2. 공개 MP4와 model을 받아 30-frame fixture를 두 번 생성하고 동일성을 확인한다.
3. E-3에서 정상 pipeline과 Camera/AI/Host 연결 장애를 실행한다.
4. Phase 09-b의 AF_VSOCK, metadata, DMA-BUF와 revoke 회귀를 실행한다.

Trusted Access 전용 기능, OP-TEE, TA와 Secure Partition은 요구하거나 사용하지 않는다. 별도
설명이 없으면 모든 명령은 저장소 루트에서 실행한다. 명령 앞의 `rtk`는 이 저장소의
`AGENTS.md`가 요구하는 command wrapper다.

- 판정: 완료
- 검증일: 2026-08-19 (Asia/Seoul)
- 실행 환경: E-3 커스텀 QEMU 10.0.0, `virt,iommu=smmuv3`, pKVM protected mode
- 입력/추론 대체: Open Model Zoo 동영상 frame replay와 사전 생성 detection oracle
- Trusted Access: 요구하거나 사용하지 않음
- How-to 순차 재검수: 통과 (2026-08-19)
- 자동 재검증(`work/src/tools/verify/phase10.sh`): 통과 (2026-08-20). 아래 절차와
  완료 조건을 이 저장소 산출물로 다시 실행해 동일하게 확인했다. 새 log는
  `work/build/vision-pipeline/console-vision-pipeline-local.log`,
  `work/build/vision-pipeline/console-vision-fault-local.log`,
  `work/build/pvm-buffer/console-phase10-*.log`,
  `work/build/pvm-framework/console-phase10-phase09b-primitive.log`에 있다. 무거운
  E-3 QEMU 실행 직후 곧바로 `pvm-user-channel`의 `protocol_test`(1000ms 수신
  타임아웃)를 재실행하면 시스템 자원 정리 지연으로 간헐적으로 실패하는 현상을
  발견해, 재실행 전 5초 대기를 추가했다. 자세한 재현 절차는
  [통합 검증 가이드](../VERIFICATION-GUIDE.md)를 참고한다.

## 1. 검증 범위 이해

Phase 10 runtime에서 실제로 이동하는 데이터는 다음과 같다.

```text
Host Application
  └─ AF_VSOCK: CONFIG / CAPTURE / STOP
       ↓
Camera pVM
  ├─ /dev/pvm-dmabuf: 4 KiB BGR24 frame page
  └─ /dev/pvm-msg: BGR3 size/stride/plane descriptor
       ↓
AI pVM
  ├─ imported page SHA-256으로 oracle 조회
  └─ AF_VSOCK: class / Q16 score / Q16 bounding box
       ↓
Host Application
```

Camera와 AI 사이에서 DMA-BUF와 descriptor는 서로 다른 channel을 사용한다. Host에는 raw
frame, frame hash, descriptor, FD, transfer token 또는 주소가 전달되지 않는다. 단, 입력
동영상과 oracle은 공개 fixture이므로 그 내용 자체의 기밀성을 검증하는 시험은 아니다.

## 2. Host 사양과 필수 도구 준비

아래 절차는 Ubuntu 계열 x86-64 Host와 현재 기록된 tool version을 기준으로 한다. QEMU가
TCG로 3 GiB guest를 실행하고 kernel/QEMU/OpenVINO를 빌드하므로 Host RAM 8 GiB 이상과
여러 GiB의 빈 디스크 공간을 권장한다. CPU virtualization extension은 필수가 아니다.

```bash
# OS package index를 갱신한다.
rtk sudo apt-get update

# source, kernel, QEMU, initramfs와 Python fixture 도구를 준비한다.
rtk sudo apt-get install -y \
  git ca-certificates curl build-essential bc bison flex cpio gzip rsync \
  clang-18 lld-18 llvm-18 libssl-dev libelf-dev dwarves \
  ninja-build pkg-config libglib2.0-dev libpixman-1-dev libslirp-dev \
  qemu-system-arm python3 python3-venv python3-pip ffmpeg \
  gcc-9-aarch64-linux-gnu binutils-aarch64-linux-gnu \
  libc6-dev-arm64-cross

# 핵심 실행 파일이 PATH에 있는지 확인한다.
rtk which git
rtk which clang-18
rtk which ld.lld-18
rtk which aarch64-linux-gnu-gcc-9
rtk which qemu-system-aarch64
rtk which ffmpeg
rtk which ffprobe
rtk which python3
```

`which` 명령은 각각 실행 파일 경로를 출력해야 한다. package 이름은 배포판 release에 따라
달라질 수 있다. 특히 `gcc-9-aarch64-linux-gnu`를 제공하지 않는 배포판에서는 같은 GCC 9
cross toolchain을 별도로 설치하고 이후 명령의 `ARM_CC`에 경로를 지정한다.

Fixture 준비에는 다음 외부 주소로 HTTPS 접근할 수 있어야 한다.

- `github.com/openvinotoolkit/open_model_zoo`
- `storage.openvinotoolkit.org`
- Python package index
- busybox static package URL

QEMU source를 처음 clone할 때는 GitHub HTTPS 접근이 필요하다. kvmtool fork가 공개되지 않은
환경에서는 `boram1288/kvmtools` repository 권한과 등록된 SSH key가 추가로 필요하다. 접근
권한 오류는 우회하지 말고 repository 관리자에게 권한을 요청한다.

## 3. 저장소와 revision 확인

새 checkout이라면 다음과 같이 source submodule을 모두 초기화한다.

```bash
rtk git clone git@github.com:boram1288/poc-p.git poc-p
```

위 명령 뒤 새로 생긴 `poc-p` 디렉터리로 이동한 다음, 아래 명령부터 저장소 루트에서
실행한다.

```bash
# Phase 10 구현 commit 또는 그 이후 revision인지 확인한다.
rtk git merge-base --is-ancestor \
  f3e17b57a58dd1c5db6c89a17eb6253b1b622206 HEAD

# 대용량 kernel을 포함한 모든 source submodule을 partial clone으로 초기화한다.
rtk git submodule update --init --filter=blob:none
rtk git submodule status

# 고정된 kernel revision인지 확인한다.
rtk git -C work/src/pkvm-linux rev-parse HEAD
```

`merge-base`는 성공하면 출력이 없다. kernel HEAD의 기대값은
`6763e27c1ad00e0f5caf6e6cde5fcb33976e50e0`이다. 값이 다르면 임의 revision으로 계속하지
말고 상위 저장소가 가리키는 submodule commit으로 다시 갱신한다.

## 4. pKVM kernel 준비

이미 올바른 kernel build tree가 있다면 먼저 fast-path 검사를 수행한다.

```bash
rtk proxy test -f work/build/pkvm-full-clang/arch/arm64/boot/Image
rtk proxy test -f work/build/pkvm-full-clang/.config
rtk grep -x 'CONFIG_ARM_SMMU_V3_PKVM_PV=y' \
  work/build/pkvm-full-clang/.config
rtk grep -x 'CONFIG_PKVM_PVIOMMU=y' work/build/pkvm-full-clang/.config
rtk grep -x 'CONFIG_PKVM_PVM_DMA_SHARE=y' work/build/pkvm-full-clang/.config
rtk grep -x 'CONFIG_VIRTIO_VSOCKETS=y' work/build/pkvm-full-clang/.config
```

모두 성공하면 이 절의 나머지 빌드는 건너뛸 수 있다. 파일이 없거나 config가 다르면 다음을
순서대로 실행한다.

```bash
# 별도 output tree에 arm64 기본 config를 만든다.
rtk make -C work/src/pkvm-linux \
  O="$PWD/work/build/pkvm-full-clang" \
  ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 defconfig

# PV IOMMU, edu assignment, DMA share, pKVM guest와 VSOCK 설정을 적용한다.
rtk work/src/tools/qemu/configure-pv-iommu-kernel.sh \
  work/build/pkvm-full-clang

# Host와 protected guest가 공용으로 사용할 Image와 module build metadata를 만든다.
# 메모리가 부족하면 -j16을 더 작은 값으로 낮춘다.
rtk make -C work/src/pkvm-linux \
  O="$PWD/work/build/pkvm-full-clang" \
  ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 -j16
```

빌드 후 다음 파일이 있어야 한다.

```bash
rtk proxy test -f work/build/pkvm-full-clang/arch/arm64/boot/Image
rtk proxy test -f work/build/pkvm-full-clang/vmlinux
rtk proxy test -f work/build/pkvm-full-clang/Module.symvers
```

현재 기준 kernel Image SHA-256은 다음 명령으로 비교한다.

```bash
rtk sha256sum work/build/pkvm-full-clang/arch/arm64/boot/Image
```

기대값은 `a58cf72f405d1c67266532b4a49bbf17ab5ea834962ea1a6cb84094f93efcdf4`다.

## 5. E-3 커스텀 QEMU 준비

배포판의 일반 `qemu-system-aarch64`에는 `pkvm-edu-assignment=on` machine property가 없다.
반드시 Phase 08 QEMU fork commit `5b3965e9c44ce7e8135f2a6ef7680eb563ab8bef`을 사용한다.

이미 빌드한 binary가 있다면 다음 fast-path만 확인한다.

```bash
rtk proxy test -x work/build/qemu-v10-aarch64/qemu-system-aarch64
rtk work/build/qemu-v10-aarch64/qemu-system-aarch64 --version
rtk sha256sum work/build/qemu-v10-aarch64/qemu-system-aarch64
```

기대 version은 `QEMU emulator version 10.0.0`이며 기록된 binary SHA-256은
`913b9b97ab9d47db5764d565faa945de5f14a1a39984fdb5c4cda321c920d384`다. compiler 또는
build path가 다르면 binary digest는 달라질 수 있으므로 source commit과 machine property를
함께 확인한다.

binary가 없으면 상위 저장소가 고정한 QEMU submodule을 초기화하고 빌드한다.

```bash
rtk git submodule update --init --filter=blob:none -- work/src/qemu-phase08
rtk proxy test "$(rtk git -C work/src/qemu-phase08 rev-parse HEAD)" = \
  5b3965e9c44ce7e8135f2a6ef7680eb563ab8bef
rtk mkdir -p work/build/qemu-v10-aarch64
rtk env -C "$PWD/work/build/qemu-v10-aarch64" \
  "$PWD/work/src/qemu-phase08/configure" \
  --target-list=aarch64-softmmu --enable-slirp --disable-docs \
  --prefix="$PWD/work/build/qemu-v10-aarch64/install"
rtk make -C work/build/qemu-v10-aarch64 -j16
```

빌드 직후 E-3 환경 자체를 먼저 smoke test한다.

```bash
rtk work/src/tools/qemu/mkinitramfs.sh
QEMU="$PWD/work/build/qemu-v10-aarch64/qemu-system-aarch64" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
HYP_IOMMU_PAGES=4096 \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
rtk work/src/tools/qemu/run-e3.sh \
  work/build/pkvm-qemu/console-phase10-prerequisite-e3.log 600
```

아래 두 줄이 log에 있어야 한다.

```bash
rtk grep -E 'kvm-arm-smmu-v3 .*ias .*oas|Found 2 assignable devices' \
  work/build/pkvm-qemu/console-phase10-prerequisite-e3.log
```

`Found 0 assignable devices`, `Failed to init iommu driver` 또는 unknown machine property가
나오면 이후 Phase 10 실행으로 넘어가지 않는다.

## 6. arm64 kvmtool 준비

`lkvm`은 outer QEMU의 arm64 Host userspace 안에서 Camera/AI protected guest를 만드는 VMM이다.
따라서 x86-64 `lkvm`이 아니라 arm64 binary여야 한다.

```bash
rtk proxy test -x work/src/kvmtool/lkvm
rtk file work/src/kvmtool/lkvm
rtk git -C work/src/kvmtool rev-parse HEAD
```

기대 출력은 `ELF 64-bit ... ARM aarch64`이며 source revision은
`6866a248977d16bc293c6f4f6609daa4f465b073`이다. 이미 이 조건을 만족하면 빌드를
건너뛴다.

처음 준비할 때는 권한이 있는 fork submodule을 초기화한다.

```bash
rtk git submodule update --init --filter=blob:none -- work/src/kvmtool
rtk proxy test "$(rtk git -C work/src/kvmtool rev-parse HEAD)" = \
  6866a248977d16bc293c6f4f6609daa4f465b073
```

arm64용 `libfdt.a`가 system sysroot에 없다면 kernel tree의 libfdt source로 로컬 static
library를 만든다. 이 방법은 submodule source를 수정하지 않는다.

```bash
rtk cp -a work/src/pkvm-linux/scripts/dtc/libfdt \
  work/build/libfdt-arm64
rtk env -C "$PWD/work/build/libfdt-arm64" \
  aarch64-linux-gnu-gcc-9 -O2 -fPIC -I. -c \
  fdt.c fdt_ro.c fdt_wip.c fdt_sw.c fdt_rw.c fdt_strerror.c \
  fdt_empty_tree.c fdt_addresses.c fdt_overlay.c
rtk env -C "$PWD/work/build/libfdt-arm64" \
  aarch64-linux-gnu-ar rcs libfdt.a \
  fdt.o fdt_ro.o fdt_wip.o fdt_sw.o fdt_rw.o fdt_strerror.o \
  fdt_empty_tree.o fdt_addresses.o fdt_overlay.o
rtk make -C work/src/kvmtool \
  ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  CC=aarch64-linux-gnu-gcc-9 \
  LIBFDT_DIR="$PWD/work/build/libfdt-arm64" -j16
```

최종 확인은 다음과 같다.

```bash
rtk file work/src/kvmtool/lkvm
rtk sha256sum work/src/kvmtool/lkvm
```

현재 기록된 SHA-256은
`9b718dd8c7fe239f3d73eeedffb4de3a0074696451724477ca9d67ce065707c4`다.

## 7. 공개 fixture 생성과 수동 확인

Fixture 준비 도구는 원본 동영상과 model digest를 먼저 검사하고 CPU demo를 두 번 실행한다.
두 실행에서 선택 frame page와 normalized oracle이 같은지 비교한 뒤 최종 fixture를 만든다.

```bash
rtk work/src/tools/vision-pipeline/prepare-fixture.sh
```

첫 실행은 다음 작업을 자동 수행하므로 네트워크와 시간이 필요하다.

| 단계 | 동작 |
|---|---|
| source 고정 | Open Model Zoo를 commit `7cc29a91472b4cb1289a11e655ba3e188e1d4a31`로 checkout |
| Python 환경 | `work/build/vision-pipeline/venv`에 OpenVINO 2024.6.0과 OpenCV 4.10.0 설치 |
| 입력 검사 | MP4 SHA-256, model XML/BIN SHA-384를 고정값과 비교 |
| oracle 생성 | CPU object detection demo를 두 번 실행 |
| frame 생성 | 647개 원본 frame에서 균등 간격 30개를 골라 32×32 BGR24로 변환 |
| 재현성 검사 | 두 실행의 30 page digest와 normalized detection record 비교 |

성공 시 마지막 부분에 다음 marker가 출력된다.

```text
PVM_VISION_FIXTURE_REPRODUCIBLE_OK
PVM_VISION_FIXTURE_VERIFY_OK: source=768x432 classes=[0, 1, 2]
PVM_VISION_FIXTURE_PREPARE_OK: .../work/build/vision-pipeline/fixtures
```

생성된 파일을 직접 확인한다.

```bash
rtk ls -l work/build/vision-pipeline/fixtures
rtk sha256sum \
  work/build/vision-pipeline/fixtures/frames.bin \
  work/build/vision-pipeline/fixtures/oracle.bin
rtk make -C work/src/tools/vision-pipeline verify
rtk json work/build/vision-pipeline/fixtures/manifest.json
```

기대값은 다음과 같다.

| 파일 | 크기 | SHA-256 |
|---|---:|---|
| `frames.bin` | 122,880 bytes | `655cd5aa44c2585ee435466015bdb38f6abbdb8623877d92847bd02aad415030` |
| `oracle.bin` | 13,032 bytes | `37905752542e5c43551cc18e911ed4c0394333f25882b7c9ef4890ff5ace177f` |

`frames.bin`은 4,096-byte page 30개다. 각 page 앞 3,072 bytes만 BGR24 pixel이고 나머지
1,024 bytes는 zero padding이다. `verify`는 page padding, page hash, oracle record 크기,
class/Q16/bbox 범위와 사용하지 않는 detection slot의 zero 여부까지 다시 검사한다.

이미 fixture가 있고 네트워크 없이 무결성만 재검사하려면 `prepare-fixture.sh` 대신 위의
`make ... verify`만 실행한다. 이는 demo 재실행과 두 번 생성의 재현성까지 다시 증명하지는
않는다.

## 8. userspace protocol과 runtime 빌드

```bash
# native protocol/SHA-256 unit test와 pvm_vision을 빌드한다.
rtk make -C work/src/tools/pvm-user-channel clean all test

# arm64 workload, 두 guest module과 Host/guest initramfs를 조립한다.
rtk work/src/tools/pvm-buffer/build.sh
```

첫 명령은 compiler warning도 오류로 처리한다. 두 번째 명령의 마지막 줄은
`PVM_BUFFER_BUILD_OK: .../work/build/pvm-buffer`여야 한다.

```bash
rtk proxy test -x work/build/pvm-buffer/pvm_vision
rtk proxy test -f work/src/tools/pvm-buffer/driver/pvm_dmabuf.ko
rtk proxy test -f work/src/tools/pvm-user-channel/driver/pvm_message.ko
rtk proxy test -f work/build/pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz
rtk proxy test -f work/build/pvm-buffer/initramfs-pvm-buffer-host.cpio.gz
```

`build.sh`는 fixture의 `frames.bin`과 `oracle.bin`을 protected guest rootfs에 넣고 Host
rootfs에는 결과 검증용 `oracle.bin`만 넣는다. MP4/model/OpenVINO runtime은 E-3 image에
포함하지 않는다.

## 9. E-3 정상 pipeline 실행

아래 명령은 fixture를 다시 준비하고 build한 뒤 outer QEMU를 부팅한다. outer Host는 AI
CID 4101을 먼저, Camera CID 4102를 다음에 `lkvm --protected`로 기동한다. 약식 환경인 E-1이
아니라 반드시 `VISION_E3=1`과 아래 machine/device 인자를 모두 사용한다.

```bash
VISION_E3=1 \
QEMU="$PWD/work/build/qemu-v10-aarch64/qemu-system-aarch64" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
CPU=max HYP_IOMMU_PAGES=4096 \
CMDLINE_EXTRA='vfio_platform.reset_required=0' \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
rtk work/src/tools/pvm-buffer/run-vision-pipeline.sh \
  work/build/vision-pipeline/console-vision-pipeline-manual.log 360
```

성공하면 wrapper의 마지막 두 줄은 다음과 같다.

```text
PVM_VISION_E3_ENVIRONMENT_OK
PVM_VISION_PIPELINE_OK
```

실행 log에서 환경과 세 역할의 완료를 직접 확인한다.

```bash
rtk grep -E 'kvm-arm-smmu-v3 .*ias .*oas|Found 2 assignable devices' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log
rtk grep -E 'PVM_VISION_(CAMERA_REPLAY|ORACLE_LOOKUP|RESULTS_MATCH|EOS|RC|PIPELINE_VALIDATION)' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log
rtk grep -c 'PVM_VISION_CAMERA_FRAME_OK' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log
rtk grep -c 'PVM_VISION_AI_FRAME_OK' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log
rtk grep -c 'PVM_VISION_HOST_FRAME_OK' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log
```

세 `grep -c` 결과는 모두 정확히 `30`이어야 한다. 다음 명령으로 Host가 받은 detection을
사람이 직접 볼 수 있다.

```bash
rtk grep 'PVM_VISION_DETECTION:' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log
```

출력의 `class=0`, `class=1`, `class=2`는 각각 vehicle, person, bike다. `score_q16`과
`bbox_q16=xmin,ymin,xmax,ymax`는 0~65,536 범위의 정규화된 정수다. 일부 frame의
`detections=0`은 정상이며, 전체 30 frame에서 세 class가 모두 한 번 이상 나와야 한다.

## 10. Negative와 Host allowlist 수동 판정

정상 pipeline 실행 앞부분은 malformed layout, one-byte mutation, hash miss, transfer ID
mismatch와 duplicate/replay를 의도적으로 주입한다.

```bash
rtk grep -E 'PVM_VISION_(LAYOUT|MUTATION|HASH|MISMATCH|DUPLICATE_REPLAY)_REJECT_OK' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log
rtk grep 'PVM_VISION_HOST_ALLOWLIST_OK' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log
```

아래 여섯 marker가 모두 있어야 한다.

```text
PVM_VISION_LAYOUT_REJECT_OK
PVM_VISION_MUTATION_REJECT_OK
PVM_VISION_HASH_REJECT_OK
PVM_VISION_MISMATCH_REJECT_OK
PVM_VISION_DUPLICATE_REPLAY_REJECT_OK
PVM_VISION_HOST_ALLOWLIST_OK
```

Host-facing result ABI를 source에서도 확인하려면 다음 파일을 본다.

```bash
rtk grep -n -A20 'struct pvm_user_detection_result' \
  work/src/tools/pvm-user-channel/include/pvm_user_channel.h
rtk grep -n 'PVM_USER_MSG_DETECTION_RESULT' \
  work/src/tools/pvm-user-channel/pvm_vision.c
```

허용 필드는 frame sequence, status, detection count/truncated와 최대 16개의 class/Q16
score/Q16 bbox다. raw frame/hash/descriptor/FD/token/address를 result payload에 추가한
구현은 이 검증을 통과한 것으로 판정하지 않는다.

## 11. E-3 장애 주입과 자원 회수 실행

다음 실행은 Phase 10 message protocol에서 Camera 연결, AI 연결과 Host 연결 종료를 각각
주입하고 양쪽 guest가 false success 없이 종료하는지 검사한다.

```bash
VISION_E3=1 \
QEMU="$PWD/work/build/qemu-v10-aarch64/qemu-system-aarch64" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
CPU=max HYP_IOMMU_PAGES=4096 \
CMDLINE_EXTRA='vfio_platform.reset_required=0' \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
rtk work/src/tools/pvm-buffer/run-vision-fault.sh \
  work/build/vision-pipeline/console-vision-fault-manual.log 300
```

마지막 줄이 `PVM_VISION_FAULT_OK`여야 한다. 다음 marker도 직접 확인한다.

```bash
rtk grep -E 'PVM_VISION_(CAMERA_FAILURE|AI_FAILURE|HOST_FAILURE|.*HOST_FAILURE_RECOVERY|FAULT_RC|FAULT_VALIDATION)' \
  work/build/vision-pipeline/console-vision-fault-manual.log
rtk grep '^Mlocked:' work/build/vision-pipeline/console-vision-fault-manual.log
```

기대 RC는 `PVM_VISION_FAULT_RC: host=0 ai=0 camera=0`, 회수 결과는
`Mlocked: 0 kB`다.

## 12. Phase 09-b 전체 회귀 실행

Phase 10이 기존 AF_VSOCK, 별도 metadata channel과 DMA-BUF primitive를 깨지 않았는지 다음
명령을 모두 실행한다.

```bash
rtk make -C work/src/tools/pvm-user-channel test
rtk work/src/tools/pvm-buffer/run-vsock-smoke.sh \
  work/build/pvm-buffer/console-phase10-vsock-regression.log 240
rtk work/src/tools/pvm-buffer/run-user-channel-e2e.sh \
  work/build/pvm-buffer/console-phase10-user-channel-e2e.log 300
rtk work/src/tools/pvm-buffer/run-user-channel-fault.sh \
  work/build/pvm-buffer/console-phase10-user-channel-fault.log 240
PHASE09=1 PHASE09_ONLY=1 rtk work/src/tools/pvm-framework/run.sh \
  work/build/pvm-framework/console-phase10-phase09b-primitive.log 900
```

각 명령의 마지막 성공 marker는 다음과 같다.

| 실행 | 성공 marker |
|---|---|
| protocol/SHA unit | `make` exit code 0 |
| AF_VSOCK smoke | `PVM_USER_VSOCK_SMOKE_OK` |
| 기존 10-frame E2E | `PVM_USER_CHANNEL_E2E_OK` |
| 기존 channel fault | `PVM_USER_CHANNEL_FAULT_OK` |
| EL2 DMA-BUF primitive | `PVM_FRAMEWORK_RUN_OK` |

primitive log에서는 normal return뿐 아니라 owner/receiver teardown과 timeout revoke 후 회수도
확인한다.

```bash
rtk grep -E 'PVM_BUFFER_(OWNER_FAULT_RECOVERY|RECEIVER_TEARDOWN_RECOVERY|TIMEOUT_RECOVERY|RESOURCE_RECOVERY)_OK|PVM_BUFFER_TEST_RC|Mlocked:' \
  work/build/pvm-framework/console-phase10-phase09b-primitive.log
```

## 13. 최종 수동 판정

정상·fault·회귀 log 전체에서 치명적 kernel 오류가 없는지 확인한다. 아래 명령은 아무것도
출력하지 않아야 정상이다.

```bash
rtk grep -E 'Kernel panic|Oops|BUG:' \
  work/build/vision-pipeline/console-vision-pipeline-manual.log \
  work/build/vision-pipeline/console-vision-fault-manual.log \
  work/build/pvm-buffer/console-phase10-vsock-regression.log \
  work/build/pvm-buffer/console-phase10-user-channel-e2e.log \
  work/build/pvm-buffer/console-phase10-user-channel-fault.log \
  work/build/pvm-framework/console-phase10-phase09b-primitive.log || true
```

다음 조건을 모두 만족해야 수동 재검증 성공이다.

| 검사 | 판정 기준 |
|---|---|
| 고정 환경 | kernel/QEMU/kvmtool revision 확인 |
| E-3 | PV SMMUv3 초기화 및 `Found 2 assignable devices` |
| fixture | 두 번 생성 동일, 30 frame, class `0,1,2`, 고정 digest |
| 정상 pipeline | Camera/AI/Host marker 각각 30개 |
| 결과 상관 | `PVM_VISION_RESULTS_MATCH_OK: frames=30` |
| Negative | layout/mutation/hash/mismatch/replay 거부 marker 전부 존재 |
| Host allowlist | `PVM_VISION_HOST_ALLOWLIST_OK` |
| 정상 종료 | EOS/STOP, 세 role RC 0 |
| 장애 종료 | Camera/AI/Host failure marker와 fault RC 0 |
| 자원 회수 | 정상/fault/primitive 모두 `Mlocked: 0 kB` |
| Phase 09-b 회귀 | VSOCK/E2E/fault/primitive 최종 marker 전부 존재 |
| kernel 안정성 | panic/Oops/BUG 0건 |

## 14. 자주 발생하는 실패와 조치

| 증상 | 가능한 원인 | 확인 및 조치 |
|---|---|---|
| `unknown property 'pkvm-edu-assignment'` | 배포판 QEMU 사용 | `QEMU=`가 5절의 custom binary인지 확인 |
| `Found 0 assignable devices` | machine/device 인자 누락 또는 잘못된 QEMU | `MACHINE`, 두 `-device edu`, QEMU commit 확인 |
| `Failed to init iommu driver` | kernel config 또는 EL2 pool 누락 | PV-only config와 `HYP_IOMMU_PAGES=4096` 확인 |
| video/model checksum mismatch | 불완전 download 또는 외부 파일 변경 | 잘못된 cache 파일을 별도 `.bad` 이름으로 이동한 뒤 fixture 준비를 재실행 |
| `aarch64-linux-gnu-gcc-9: not found` | GCC 9 cross toolchain 없음 | package 설치 또는 `ARM_CC=<절대경로>` 지정 |
| `No libfdt found` | kvmtool용 arm64 libfdt 없음 | 6절의 local `libfdt.a` 생성 후 `LIBFDT_DIR` 지정 |
| `PVM_VISION_PIPELINE_FAILED: e3-environment` | E-1 옵션으로 실행 | 9절 명령을 줄 생략 없이 다시 실행 |
| frame count가 30이 아님 | guest 중도 종료 또는 stale build | 정상 log의 첫 실패 marker 확인 후 `build.sh`와 pipeline 재실행 |
| wrapper timeout | Host가 느리거나 guest가 응답하지 않음 | log 끝부분을 먼저 확인하고 마지막 timeout 인자를 늘림 |
| MMIO guard `WARNING:` | 알려진 VSOCK guest 부팅 warning | panic/Oops가 없고 RC 0, `Mlocked: 0 kB`이면 known issue |

checksum mismatch cache는 삭제 대신 다음처럼 명시적인 이름으로 이동하면 원본을 보존할 수
있다. 실제 mismatch가 난 파일만 선택한다.

```bash
rtk mv work/build/vision-pipeline/source/person-bicycle-car-detection.mp4 \
  work/build/vision-pipeline/source/person-bicycle-car-detection.mp4.bad
rtk work/src/tools/vision-pipeline/prepare-fixture.sh
```

model mismatch라면 `work/build/vision-pipeline/model/` 아래 해당 `.xml` 또는 `.bin` 파일에
동일하게 `.bad` suffix를 붙인다.

## 15. 수동 검증 결과 기록 양식

```text
Date / verifier:
Root commit:
Kernel commit / Image SHA-256:
QEMU commit / binary SHA-256:
kvmtool commit / binary SHA-256:
Video SHA-256:
frames.bin SHA-256:
oracle.bin SHA-256:
Fixture reproducible: yes/no
E-3 assignable devices: ____
Camera / AI / Host frame count: ____ / ____ / ____
Observed classes:
Negative markers complete: yes/no
Normal RC host/ai/camera:
Fault RC host/ai/camera:
Mlocked normal / fault / primitive:
Phase 09-b regression: pass/fail
Kernel panic/Oops/BUG: yes/no
Known MMIO warning seen: yes/no
Normal log:
Fault log:
Notes:
```

아래부터는 2026-08-19에 수행한 완료 실측 기록이다. 신규 검증자는 위 양식과 새 log를
별도로 남기고, 기존 log를 새 실행의 증거로 대신 사용하지 않는다.

## 16. 완료 조건 결과

| ID | 결과 | 실측 증거 |
|---|---|---|
| CC-10-01 | 통과 | OMZ commit, URL, Apache-2.0 license, 도구 버전과 아래 입력/fixture digest를 고정했다. 동영상은 재배포 조건을 확인하지 못해 Git에 넣지 않았다. |
| CC-10-02 | 통과 | 두 CPU demo 실행에서 `PVM_VISION_FIXTURE_REPRODUCIBLE_OK`; 30 page와 oracle digest가 같고 class `0,1,2`를 포함한다. |
| CC-10-03 | 통과 | Camera pVM의 `PVM_VISION_CAMERA_FRAME_OK`가 정확히 30개다. 각 4 KiB DMA-BUF와 별도 BGR3 descriptor를 전달했다. |
| CC-10-04 | 통과 | AI pVM이 kernel `actual_size`, BGR3 stride/plane/padding을 검사하고 page SHA-256으로 oracle을 찾았다. `PVM_VISION_ORACLE_LOOKUP_OK: frames=30`. |
| CC-10-05 | 통과 | layout, one-byte mutation/hash miss, transfer mismatch, duplicate/replay를 모두 result 생성 전에 거부했다. |
| CC-10-06 | 통과 | Host/AI/Camera frame marker가 각각 30개고 `PVM_VISION_RESULTS_MATCH_OK`; vehicle/person/bike 결과가 class/score/bbox까지 oracle과 byte 단위로 일치했다. |
| CC-10-07 | 통과 | Host result ABI는 session/request/frame/status, count/truncated와 최대 16개 class/Q16 score/Q16 bbox만 가진다. `PVM_VISION_HOST_ALLOWLIST_OK`; raw frame/hash/descriptor/FD/token/address/oracle path를 보내는 Host-facing encoder는 없다. |
| CC-10-08 | 통과 | 정상 EOS/STOP 및 Phase 10 전용 Camera/AI/Host 연결 상실 주입이 모두 성공했다. 정상·fault 실행 모두 RC `0/0/0`, `Mlocked: 0 kB`다. Phase 09 primitive teardown/timeout revoke도 통과했다. |
| CC-10-09 | 통과 | AF_VSOCK smoke, 기존 10-frame metadata/DMA-BUF E2E, channel fault, Phase 09 buffer primitive 회귀가 모두 통과했다. |
| CC-10-10 | 통과 | 여섯 최종 로그에서 panic/Oops/BUG 0건, unexpected timeout 0건이며 `PVM_VISION_PIPELINE_OK`를 출력했다. |
| CC-10-11 | 통과 | 아래 제한에 실제 camera/GPU/inference/model 보호를 검증하지 않았음을 명시했다. |

## 17. 핵심 실측 marker

```text
kvm [1]: Found 2 assignable devices
kvm-arm-smmu-v3 9050000.smmuv3: ias 44-bit, oas 44-bit
PVM_VISION_FIXTURE_REPRODUCIBLE_OK
PVM_VISION_FIXTURE_VERIFY_OK: source=768x432 classes=[0, 1, 2]
PVM_VISION_CAMERA_REPLAY_OK: frames=30
PVM_VISION_ORACLE_LOOKUP_OK: frames=30
PVM_VISION_RESULTS_MATCH_OK: frames=30
PVM_VISION_HOST_ALLOWLIST_OK
PVM_VISION_EOS_OK
PVM_VISION_RC: host=0 ai=0 camera=0
PVM_VISION_PIPELINE_VALIDATION_OK
PVM_VISION_E3_ENVIRONMENT_OK
PVM_VISION_PIPELINE_OK
PVM_VISION_CAMERA_FAILURE_RECOVERY_OK
PVM_VISION_AI_FAILURE_RECOVERY_OK
PVM_VISION_HOST_FAILURE_INJECTED_OK
PVM_VISION_FAULT_RC: host=0 ai=0 camera=0
PVM_VISION_FAULT_E3_ENVIRONMENT_OK
PVM_VISION_FAULT_OK
Mlocked: 0 kB
```

Negative marker는 `PVM_VISION_LAYOUT_REJECT_OK`, `PVM_VISION_MUTATION_REJECT_OK`,
`PVM_VISION_HASH_REJECT_OK`, `PVM_VISION_MISMATCH_REJECT_OK`와
`PVM_VISION_DUPLICATE_REPLAY_REJECT_OK`다.

## 18. Revision, 도구와 digest

| 항목 | 값 |
|---|---|
| root 기준 commit | `ceaffb5da598348d8caca169662ff4b7dbb2ce3e` (Phase 10 완료 commit 전 기준) |
| pKVM Linux | `6763e27c1ad00e0f5caf6e6cde5fcb33976e50e0` |
| kvmtool | `6866a248977d16bc293c6f4f6609daa4f465b073` |
| E-3 QEMU source | `5b3965e` (`boram1288/qemu`, Phase 08 고정 revision) |
| Open Model Zoo | `7cc29a91472b4cb1289a11e655ba3e188e1d4a31` |
| OpenVINO / OpenCV / NumPy | `2024.6.0-17404-4c0f47d2335-releases/2024/6` / `4.10.0` / `1.26.4` |
| FFmpeg | `6.1.1-3ubuntu5` |
| source video SHA-256 | `452b11b7e0efbd019f1d9570d0c790e90416ad4ad29eec6003872d08443140ef` |
| model XML SHA-384 | `8c4f1a14c1e00709391c2bded1157d4497cf56be6a1d919b09747cecef183380dbae659a5c555dedbc81b9e4da579096` |
| model BIN SHA-384 | `2217e4a07f0fe94a2e13bb80c359c4d6125454956e08e806eacc81176a888060f573a7f7352c5a4f4fa0288f2c53bb78` |
| `frames.bin` SHA-256 / size | `655cd5aa44c2585ee435466015bdb38f6abbdb8623877d92847bd02aad415030` / 122,880 bytes |
| `oracle.bin` SHA-256 / size | `37905752542e5c43551cc18e911ed4c0394333f25882b7c9ef4890ff5ace177f` / 13,032 bytes |
| kernel Image / config SHA-256 | `a58cf72f405d1c67266532b4a49bbf17ab5ea834962ea1a6cb84094f93efcdf4` / `7ef1e6b3d688f516ac9e98730ff65429d42d748bd2a835d59fe639c5898ac77e` |
| QEMU / lkvm SHA-256 | `913b9b97ab9d47db5764d565faa945de5f14a1a39984fdb5c4cda321c920d384` / `9b718dd8c7fe239f3d73eeedffb4de3a0074696451724477ca9d67ce065707c4` |
| `pvm_vision` SHA-256 | `1cd5284f616fdd0bc53aada833e593e52c5e9bdd29c574dc385fce64bccb9a43` |
| `pvm_message.ko` / `pvm_dmabuf.ko` SHA-256 | `3eafe10bb5c7fc5f8d2d73786bc32717a8c660d3ae997db4fb641e04a93af693` / `dff6ad1da851f448a0360fc12eb3db9a47478e14041da082dd33484e2900db2e` |
| Host / guest initramfs SHA-256 | `a3a119ec4096649befd7c9b1b4447383d7d97121a10c503d7c60a3ba4cac693c` / `c094357b0e133626cacd67599fe20d922e8a921bb9801dd7e992f0434fb88361` |

최종 로그는 다음과 같다.

- `work/build/vision-pipeline/console-vision-pipeline-e3-final.log`
- `work/build/vision-pipeline/console-vision-fault-e3.log`
- `work/build/pvm-buffer/console-phase10-vsock-regression.log`
- `work/build/pvm-buffer/console-phase10-user-channel-e2e.log`
- `work/build/pvm-buffer/console-phase10-user-channel-fault.log`
- `work/build/pvm-framework/console-phase10-phase09b-primitive.log`

## 19. 판정 범위와 제한

- 실물 USB camera, sensor capture/driver/timing은 사용하거나 검증하지 않았다.
- 실제 NVIDIA GPU assignment/driver/inference와 model weight/intermediate tensor 기밀성은
  검증하지 않았다. AI pVM은 실제 inference 대신 공개 demo의 사전 생성 oracle을 page hash로
  조회한다.
- 공개 동영상과 파생 fixture 자체의 비밀성은 주장하지 않는다. Host 비노출 판정은 E-3 runtime
  Camera↔AI DMA-BUF를 Host가 relay/copy하지 않고 Host-facing result allowlist에 frame 또는 내부
  handle을 포함하지 않는다는 경로 특성에 한정한다.
- QEMU edu/SMMUv3는 에뮬레이션이므로 실물 IOMMU·camera·GPU의 성능과 기밀성을 보증하지 않는다.
- 객체 탐지 정확도, FPS, latency, backpressure와 production reconnect는 판정하지 않았다.
- VSOCK guest 부팅 중 알려진 pKVM MMIO guard `WARN_ON_ONCE`가 관찰되지만 queue 초기화, 왕복,
  guest 종료와 회수에 영향은 없었다. 완료 조건이 금지한 panic/Oops/BUG는 없었다.

## 20. How-to 순차 재검수 기록

2026-08-19에 root commit `2807351379c6b2fdd3b5fc29adcf951455ca68cb`에서 이 문서의
2~13절을 순서대로 다시 수행했다. 이미 고정 digest를 만족한 kernel/QEMU/kvmtool은 각 절의
fast-path를 사용했다. package 재설치, repository 재-clone과 동일 source의 full rebuild는
수행하지 않았다. fixture는 CPU demo 두 번을 실제로 다시 실행했고, runtime/initramfs는
source에서 다시 빌드했다.

| 절 | 재검수 결과 |
|---|---|
| 2~3 Host/source | 필수 명령 8개 확인, root ancestor 검사 통과, pKVM `6763e27c1ad0` 일치 |
| 4 kernel | PV IOMMU/PVIOMMU/DMA share/VSOCK config와 Image digest 일치 |
| 5 QEMU | version/digest 일치, 새 smoke에서 PV SMMUv3와 assignable device 2개 확인 |
| 6 kvmtool | arm64 ELF, commit `6866a248977d`, binary digest 일치 |
| 7 fixture | demo 2회 동일, class `0,1,2`, frame/oracle digest 일치, offline verifier 통과 |
| 8 build | native unit test, ARM workload, 두 module과 Host/guest initramfs 재빌드 통과 |
| 9 정상 E-3 | Camera/AI/Host 각각 30 frame, 결과 oracle 일치, RC `0/0/0` |
| 10 negative | layout/mutation/hash/mismatch/duplicate-replay 거부와 Host allowlist 통과 |
| 11 fault | Camera/AI/Host 연결 상실 처리, RC `0/0/0`, `Mlocked: 0 kB` |
| 12 회귀 | unit, VSOCK smoke, 10-frame E2E, channel fault, EL2 primitive 모두 통과 |
| 13 최종 판정 | 여섯 log의 panic/Oops/BUG 0건, teardown/timeout 뒤 `Mlocked: 0 kB` |

재검수에서 사용한 신규 log와 SHA-256은 다음과 같다.

| log | SHA-256 |
|---|---|
| `work/build/pkvm-qemu/console-phase10-prerequisite-e3-review.log` | `9b481292a6e7cb0880dc6451f88c965f89050204f250209c250cf6b834edec02` |
| `work/build/vision-pipeline/console-vision-pipeline-manual.log` | `e509b07843d2b1fba7c95b3111c79ab864e93ced887c17d016cda140807b9194` |
| `work/build/vision-pipeline/console-vision-fault-manual.log` | `85dd117f5ae378fc4554b0b17d3e3fa018f39363824a0d7d5b956c17c86d0c53` |

Phase 09-b 회귀 log는 18절에 기록된 경로를 새 실행으로 덮어썼다. wrapper terminal marker와
log 내부 완료 marker를 모두 확인했다. 문서 명령의 수정이 필요한 실패는 발견되지 않았다.
