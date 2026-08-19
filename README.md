# pKVM Protected VM PoC

이 저장소는 Linux v6.18에 pKVM 패치를 적용하고, QEMU에서 protected VM(pVM) 기반의 신뢰
실행 환경을 단계적으로 검증하는 PoC다. 최종적으로는 비신뢰 Host로부터 카메라 영상과 AI
처리 데이터를 격리하면서 Camera pVM → AI pVM → Host Application 영상 분석 파이프라인을
수행하는 것을 목표로 한다.

장치 할당과 DMA 격리는 D-9 결정에 따라 S2MPU를 에뮬레이션하는 QEMU 환경에서 검증한다.
실물 USB 카메라와 discrete NVIDIA GPU를 사용하는 검증은 이 PoC의 범위에서 제외했다.
Phase 10은 공개 객체 탐지 동영상의 frame과 사전 생성 detection oracle로 두 하드웨어 역할을
재생한다.

## 프로젝트 목표

- **재현 가능한 pKVM 기반선 구축**: Linux kernel v6.18과 pKVM 패치를 통합하고,
  QEMU에서 커널 부팅, EL2 초기화, pVM 생성/실행 및 protected memory 격리를 검증한다.
- **Secure World 공존 검증**: pKVM이 동작하는 Normal World와 OP-TEE Secure OS를 함께
  구성하고, pVM 실행 중에도 OP-TEE의 암호화/복호화 서비스를 사용할 수 있음을 확인한다.
- **장치의 안전한 할당**: 카메라 역할 장치와 추론 역할 장치를 Camera pVM과 AI pVM에
  각각 할당하고, 장치 소유권과 DMA 접근 범위가 Host 및 다른 pVM과 분리되는지 확인한다.
- **격리된 영상 분석 파이프라인 구현**: Camera pVM이 재생한 프레임을 Host runtime이 읽지 않는
  DMA-BUF에 저장하고, EL2-mediated export/import로 AI pVM에 새로운 local FD를 만들어
  버퍼를 복사하지 않고 처리한 뒤 bounded 객체 탐지 결과만 Host Application에 반환한다.
- **동적 pVM 수명주기 검증**: Host 요청의 권한과 정책을 확인한 뒤 pVM 이미지를 검증하고,
  Camera/AI pVM의 생성, 모니터링, 장애 격리, 종료 및 자원 회수를 일관되게 수행한다.

## 목표 구성

| 구성 요소 | 역할 |
|---|---|
| QEMU | pKVM과 OP-TEE 통합 전 단계의 재현 가능한 기능 검증 환경 |
| Linux kernel v6.18 + pKVM | EL2에서 Host와 pVM, pVM 상호 간 메모리 및 실행 경계 제공 |
| OP-TEE | Secure World에서 카메라 영상의 암호화/복호화 등 보안 서비스 제공 |
| 카메라 역할 장치 | Camera pVM에 할당되는 영상 입력 장치 |
| 추론 역할 장치 | AI pVM에 할당되는 추론 담당 장치 |
| Camera pVM / AI pVM | 영상 입력 replay와 객체 탐지 결과 생성을 분리하여 최소 권한으로 실행하는 보호 Workload |

QEMU는 pKVM 부팅과 격리 동작을 확인하는 기능 검증 환경이다. 장치 할당과 DMA 격리는
`virt,iommu=smmuv3`로 S2MPU를 에뮬레이션하는 QEMU 환경에서 판정하며, 두 역할 장치도
에뮬레이션 장치를 사용한다. 실물 하드웨어에서의 기밀성은 이 PoC에서 주장하지 않는다.

## Reference Scenario

비신뢰 Host의 요청으로 Camera pVM과 AI pVM을 동적으로 생성한다. Camera pVM은 USB
카메라로 프레임을 캡처하고, pKVM이 보호하는 DMA-BUF를 AI pVM에 zero-copy 방식으로
export/import한다. AI pVM은 NVIDIA GPU로 추론을 수행하며, 민감한 영상과 모델 중간 데이터 대신
추론 결과만 Host에 전달한다. 암호화/복호화가 필요한 데이터는 OP-TEE의 Crypto Manager를
통해 처리한다.

![Reference Scenario 개념도](docs/concepts/reference-scenario-concept.png)

![Reference Scenario 시퀀스](docs/concepts/reference-scenario-sequence-diagram.png)

세부 설계는 [pVM 수명주기 관리](docs/concepts/vm-management.png),
[장치 직접 할당과 소유권 전환](docs/concepts/hw-sharing-by-arbiter.png),
[프레임 버퍼 zero-copy 소유권 이전](docs/concepts/zero-copy-buffer-sharing.png)을 기준으로 한다.

### 성공 조건

1. Linux v6.18 + pKVM 커널과 OP-TEE가 동일 시스템에서 초기화되고 각각 정상 동작한다.
2. Camera pVM과 AI pVM을 동시에 생성/실행하며 Host와 각 pVM의 메모리 접근을 격리한다.
3. 카메라 역할 장치와 추론 역할 장치의 직접 할당, 회수 및 배타적 소유권 전환을 검증한다.
4. 카메라 역할 frame을 E-3 runtime Host에 relay하지 않고 Camera pVM에서 AI pVM으로
   zero-copy 전달한다.
5. Camera pVM이 공개 동영상 frame을 재생하고 AI pVM이 frame과 결합된 허용 목록의 객체 탐지
   결과만 Host Application에 반환한다.
6. pVM 종료 후 장치, 메모리 및 vCPU 자원이 안전하게 회수된다.

### 판정 기준

성공 조건 3의 두 역할 장치는 QEMU 에뮬레이션 장치다. Reference Scenario의 USB 카메라가
카메라 역할 장치에, NVIDIA GPU가 추론 역할 장치에 대응한다. 판정 대상은 장치 할당 경로,
배타적 소유권 전환, DMA 격리, 회수와 재할당이 성립하는지다.

성공 조건 5는 Reference Scenario의 카메라/GPU 처리를 Open Model Zoo 동영상 frame과 사전 생성
detection oracle replay로 대체한 것이다. 판정 대상은 입력 frame과 결과의 상관관계, 데이터
보호 경계와 결과 반환 경로가 성립하는지다. 실제 model inference와 model/tensor 기밀성은
판정하지 않는다.

실제 USB 카메라의 캡처 동작, NVIDIA GPU 가속 추론과 AI pVM 내부 실제 model inference는 이
PoC에서 검증하지 않는다.

이 대체 판정은 D-9와 D-11 결정에 따른 것이다. 근거는 [하드웨어 후보
조사](docs/phase-08/hardware-candidates.md)와 [Phase 10 계획](docs/phase-10/README.md)에 있다.
실장치와 실제 inference 검증은 후속 과제로 분리했다.

## 최종 상태

Phase 00~11을 완료했다. G-1~G-11과 G-10B의 12개 목표 및 위 성공 조건 6개는 모두
**달성(PoC 범위)**으로 판정했다. 이 판정은 E-1/E-2 QEMU 기능·통합 환경, E-3 에뮬레이션
역할 장치와 공개 fixture/oracle replay에 한정된다. 실물 USB camera/NVIDIA GPU, 실제 model
inference와 제품 수준 보안 보증은 포함하지 않는다.

목표별 증거, 환경, revision/digest, 알려진 warning과 후속 검증은
[Phase 11 최종 결과](docs/phase-11/RESULT.md)에 정리했다.

## 문서 구조

- [전체 수행 계획](docs/PLAN.md): 목표, Phase 순서, 완료 조건, 현재 상태와 남은 작업
- `docs/phase-00` ~ `docs/phase-11`: Phase별 절차, 완료 조건, 결과와 한계
- [Phase 07 C VM 관리 프레임워크](docs/phase-07/userspace-vm-framework-design.md): public API,
  controller, VM runner와 private KVM backend 설계 및 완료 조건
- [Phase 08 장치 할당·DMA 격리 결과](docs/phase-08/README.md): PV IOMMU, QEMU edu 두 장치,
  Host/non-owner 차단, pVM 간 DMA share/revoke 및 teardown/reassignment 실측
- [Phase 08 validation evidence](docs/phase-08/validation-results.md): 재현 명령, 필수 marker,
  소스 모듈 변경과 검증 범위/한계
- [Phase 09 EL2 DMA-BUF channel 설계](docs/phase-09/el2-dmabuf-channel-design.md): Host runtime
  relay 없는 FD-passing abstraction, C application API/예제와 전체 sequence
- [Phase 09 검증 How-to](docs/phase-09/VERIFICATION.md): flat guest EL2 primitive 회귀부터
  Linux guest 통합까지 처음 실행하는 개발자를 위한 명령 단위 재현 절차
- [Phase 09-b 사용자 공간 통신 계획](docs/phase-09-b/README.md): Host↔Camera command,
  Camera↔AI protected DMA-BUF와 별도 size/format metadata channel, AI↔Host allowlist result를
  하나의 end-to-end session으로 묶는 구현·검증 계획
- [Phase 10 Reference Scenario](docs/phase-10/README.md): 공개 객체 탐지 동영상 frame과
  detection oracle로 camera/GPU 역할을 재생한 end-to-end 구현·검증 결과
- [Phase 11 최종 결과](docs/phase-11/RESULT.md): 목표 12개와 README 성공 조건 6개의 최종
  판정, 환경별 증거, 검증 한계와 후속 과제
- [work 디렉터리 안내](work/README.md): 소스와 빌드 산출물 관리 규칙

위 성공 조건 6개는 수행 계획의 목표 ID 및 Phase에 매핑되어 있다. 매핑표는
[전체 수행 계획](docs/PLAN.md)의 1.3절에 있다.

## 작업 디렉터리

```text
work/
├── src/
│   ├── pkvm-linux/       Linux v6.18 + pKVM 패치 소스 트리 (submodule)
│   └── tools/
│       ├── analysis/     패치 집합 분석 도구
│       ├── qemu/         protected 부팅 실행 도구
│       ├── pvm/          pVM selftest 실행 도구
│       └── pvm-framework/ Phase 07 C 기반 VM 관리 프레임워크
└── build/
    ├── analysis/         커밋 집계/분류 결과
    ├── pkvm-full-clang/  clang 커널 빌드 산출물
    ├── pkvm-qemu/        부팅용 initramfs와 콘솔 로그
    ├── pkvm-pvm/         pVM selftest 산출물과 콘솔 로그
    └── pvm-framework/    C framework binaries, guest image와 E-1 검증 로그
```

Phase 05 이후의 도구와 산출물은 각 Phase 문서에 명시한 경로에 추가한다.

`work/src/tools`의 프로젝트 도구는 Git으로 관리한다. 커널 소스 트리는 submodule로 두어
커밋 SHA만 기록한다. 빌드 산출물은 재생성 가능하므로 Git에서 제외한다. 모든 명령은 별도
언급이 없으면 저장소 루트에서 실행한다.

저장 공간 정책에 따라 커널 검증 입력은 `pkvm-full-clang`만 유지하며 삭제한
`pkvm-full-gcc`를 복구하거나 gcc kernel 교차 검증을 수행하지 않는다.

저장소를 처음 받을 때는 submodule을 partial clone으로 초기화한다. 커널 트리가 5.6GB를
넘는다.

```bash
git clone git@github.com:boram1288/poc-p.git
cd poc-p
git submodule update --init --filter=blob:none work/src/pkvm-linux
```

## 다른 개발자 PC에서 재현하기

이 절은 새 x86-64 Linux PC에서 저장소를 받고, Git에 포함되지 않은 산출물을 다시 생성해
최종 PoC까지 검증하는 진입 가이드다. 검증 기준과 고정 revision/digest는
[Phase 11 최종 결과](docs/phase-11/RESULT.md)를 따른다.

### 1. 권장 Host 환경

- Ubuntu 24.04 LTS 계열 x86-64 Host
- RAM 8 GiB 이상
- 빈 디스크 50 GiB 이상 권장
- HTTPS로 GitHub, Open Model Zoo, Python package index와 Ubuntu package 저장소에 접근 가능
- CPU virtualization extension은 필수가 아니다. arm64 guest는 QEMU TCG로 실행한다.

완료 검증 환경은 12 vCPU, RAM 16 GiB인 Ubuntu 24.04 LTS Host였다. 커널 source만 5.6 GiB를
넘고 전체 검증 작업 디렉터리는 약 28 GiB까지 사용했다. 빌드 병렬도는 Host 사양에 맞게
`-j"$(nproc)"` 또는 더 작은 값으로 조정한다.

Ubuntu 계열에서 Phase 10까지 필요한 기본 package는 다음과 같다. 배포판 release에 따라
package 이름이 다를 수 있다.

```bash
sudo apt-get update
sudo apt-get install -y \
  git ca-certificates curl build-essential bc bison flex cpio gzip rsync \
  clang-18 lld-18 llvm-18 libssl-dev libelf-dev dwarves \
  ninja-build pkg-config libglib2.0-dev libpixman-1-dev libslirp-dev \
  qemu-system-arm python3 python3-venv python3-pip ffmpeg \
  gcc-9-aarch64-linux-gnu binutils-aarch64-linux-gnu \
  libc6-dev-arm64-cross
```

`gcc-9-aarch64-linux-gnu`를 제공하지 않는 배포판에서는 GCC 9 arm64 cross toolchain을 별도로
설치하고 각 검증 문서의 `ARM_CC` 또는 `CROSS_COMPILE`에 절대 경로를 지정한다.

### 2. 코드 받기

SSH key와 저장소 권한이 있으면 다음 명령을 사용한다.

```bash
git clone git@github.com:boram1288/poc-p.git
cd poc-p
git submodule update --init --filter=blob:none work/src/pkvm-linux
```

공개 HTTPS 또는 credential helper를 사용할 수 있는 환경에서는 첫 명령을 다음과 같이 바꾼다.

```bash
git clone https://github.com/boram1288/poc-p.git
cd poc-p
git submodule update --init --filter=blob:none work/src/pkvm-linux
```

특정 결과를 정확히 재현할 때는 전달받은 root commit을 먼저 checkout한 다음 submodule을
초기화한다. branch 최신 상태만 사용하는 것보다 root와 submodule revision을 함께 고정하는
방법이 안전하다.

```bash
git checkout --detach <ROOT_COMMIT>
git submodule update --init --filter=blob:none work/src/pkvm-linux
git rev-parse HEAD
git -C work/src/pkvm-linux rev-parse HEAD
```

Phase 11 완료 증거가 포함된 root 기준 commit은
`e1629c18725ab833cd8aa3528b94c7ae19193ab1`이다. 이 commit 이후의 문서 commit을 사용해도
다음 명령이 성공하면 해당 완료 증거를 포함한다.

```bash
git merge-base --is-ancestor e1629c18725ab833cd8aa3528b94c7ae19193ab1 HEAD
git submodule status work/src/pkvm-linux
```

고정된 pKVM Linux submodule revision은
`6763e27c1ad00e0f5caf6e6cde5fcb33976e50e0`이다. `git submodule status`의 첫 글자가 `-`, `+`
또는 `U`이면 초기화 누락, revision 불일치 또는 충돌 상태이므로 빌드를 시작하지 않는다.

### 3. Clone에 포함되는 것과 다시 생성할 것

| 구분 | 경로 | 새 PC에서의 처리 |
|---|---|---|
| 프로젝트 source/문서 | `README.md`, `docs/`, `work/src/tools/` | root repository clone에 포함 |
| pKVM Linux source | `work/src/pkvm-linux/` | submodule로 별도 초기화 |
| OP-TEE/TF-A/U-Boot/Buildroot source | `work/src/optee-pkvm/` | Phase 06 bootstrap으로 다시 받음 |
| E-3 custom QEMU source | `work/src/qemu-phase08/` | Phase 10 검증 문서의 고정 commit으로 다시 받음 |
| arm64 kvmtool source | `work/src/kvmtool/` | Phase 10 검증 문서의 고정 commit으로 다시 받음 |
| 공개 video/model/fixture | `work/build/vision-pipeline/` | Phase 10 fixture 준비 도구로 다시 받거나 생성 |
| kernel/QEMU/initramfs/binary/log | `work/build/` | Git 비추적 영역이며 새 PC에서 모두 다시 생성 |

`work/build`의 기존 log는 clone에 포함되지 않는다. 새 개발자는 자신의 실행에서 새 log를
생성해야 하며, 다른 PC에서 복사한 log를 재현 증거로 사용하지 않는다. 외부 source 접근에
권한이 필요하면 저장소 관리자에게 권한을 요청한다. 권한 우회 또는 Trusted Access는 재현
절차에 포함하지 않는다.

### 4. 권장 재현 순서

최종 Reference Scenario를 가장 짧게 재현하려면
[Phase 10 검증 How-to](docs/phase-10/VERIFICATION.md)의 2~13절을 순서대로 수행한다. 이 문서에는
Host package, kernel, custom QEMU, arm64 kvmtool, 공개 fixture, 정상/fault pipeline과 회귀
검사가 명령 단위로 정리되어 있다.

핵심 흐름은 다음과 같다.

1. pKVM submodule을 고정 revision으로 초기화한다.
2. `work/build/pkvm-full-clang`에 clang 18 pKVM kernel을 빌드한다.
3. QEMU fork `5b3965e9c44ce7e8135f2a6ef7680eb563ab8bef`을 빌드한다.
4. arm64 kvmtool `6866a248977d16bc293c6f4f6609daa4f465b073`을 빌드한다.
5. 공개 video/model에서 30 frame fixture/oracle을 두 번 생성하고 digest를 비교한다.
6. userspace protocol, guest module, Host/guest initramfs를 빌드한다.
7. E-3 정상 pipeline, 장애 주입, Phase 09-b 회귀를 실행한다.
8. 모든 완료 marker, 자원 회수와 panic/Oops/BUG 부재를 확인한다.

최종 E-3 정상 pipeline 실행 형식은 다음과 같다. 선행 산출물이 없는 상태에서 이 명령만 먼저
실행하지 말고 Phase 10 검증 How-to의 2~8절을 먼저 완료한다.

```bash
VISION_E3=1 \
QEMU="$PWD/work/build/qemu-v10-aarch64/qemu-system-aarch64" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
CPU=max HYP_IOMMU_PAGES=4096 \
CMDLINE_EXTRA='vfio_platform.reset_required=0' \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
work/src/tools/pvm-buffer/run-vision-pipeline.sh \
  work/build/vision-pipeline/console-vision-pipeline-local.log 360
```

정상 완료 시 wrapper의 마지막에 다음 두 marker가 출력되어야 한다.

```text
PVM_VISION_E3_ENVIRONMENT_OK
PVM_VISION_PIPELINE_OK
```

전체 Phase를 처음부터 감사하려면 아래 문서 순서를 따른다.

| 순서 | 범위 | 재현 문서 |
|---:|---|---|
| 1 | 범위/환경/기준선 | [전체 수행 계획](docs/PLAN.md), [Phase 00](docs/phase-00/README.md), [Phase 01](docs/phase-01/README.md) |
| 2 | kernel build/protected boot | [Phase 02](docs/phase-02/README.md), [Phase 03](docs/phase-03/README.md) |
| 3 | 단일/다중 pVM과 CPU 격리 | [Phase 04](docs/phase-04/README.md), [Phase 05](docs/phase-05/README.md) |
| 4 | OP-TEE 공존 | [Phase 06](docs/phase-06/README.md), [Phase 06-b 검증](docs/phase-06-b/VERIFICATION.md) |
| 5 | 수명주기/장치/DMA | [Phase 07](docs/phase-07/README.md), [Phase 08 검증](docs/phase-08/validation-results.md) |
| 6 | DMA-BUF/사용자 공간 channel | [Phase 09 검증](docs/phase-09/VERIFICATION.md), [Phase 09-b 검증](docs/phase-09-b/VERIFICATION.md) |
| 7 | 최종 pipeline/결과 감사 | [Phase 10 검증](docs/phase-10/VERIFICATION.md), [Phase 11 결과](docs/phase-11/RESULT.md) |

Phase 06의 E-2 환경은 다음 순서로 외부 source와 산출물을 다시 만든다.

```bash
work/src/tools/optee-pkvm/bootstrap.sh
work/src/tools/optee-pkvm/build.sh
work/src/tools/optee-pkvm/mkrootfs.sh
work/src/tools/optee-pkvm/run.sh
```

`bootstrap.sh`는 OP-TEE manifest 4.7.0, TF-A, U-Boot와 Buildroot source를 네트워크에서 받는다.
Phase 06-b까지 다시 검증할 때는 [Phase 06-b 검증](docs/phase-06-b/VERIFICATION.md)의 고정
revision과 arm64 kvmtool 절차를 추가로 적용한다.

### 5. 최종 검증 기준

최종 pipeline log에서 아래 항목을 확인한다.

```bash
grep -E 'Found 2 assignable devices|PVM_VISION_(CAMERA_REPLAY|ORACLE_LOOKUP|RESULTS_MATCH|HOST_ALLOWLIST|EOS|RC|PIPELINE_VALIDATION|E3_ENVIRONMENT|PIPELINE_OK)' \
  work/build/vision-pipeline/console-vision-pipeline-local.log

grep -c 'PVM_VISION_CAMERA_FRAME_OK' \
  work/build/vision-pipeline/console-vision-pipeline-local.log
grep -c 'PVM_VISION_AI_FRAME_OK' \
  work/build/vision-pipeline/console-vision-pipeline-local.log
grep -c 'PVM_VISION_HOST_FRAME_OK' \
  work/build/vision-pipeline/console-vision-pipeline-local.log

grep -E 'Kernel panic|Oops|BUG:' \
  work/build/vision-pipeline/console-vision-pipeline-local.log || true
```

Camera/AI/Host frame count는 각각 정확히 `30`이어야 한다. 마지막 오류 검색은 아무것도 출력하지
않아야 한다. 정상/fault/회귀 전체 판정은 Phase 10 검증 How-to의 13절을 기준으로 한다.

주요 고정값은 다음과 같다.

| 항목 | 기대값 |
|---|---|
| pKVM Linux | `6763e27c1ad00e0f5caf6e6cde5fcb33976e50e0` |
| E-3 QEMU source | `5b3965e9c44ce7e8135f2a6ef7680eb563ab8bef` |
| kvmtool source | `6866a248977d16bc293c6f4f6609daa4f465b073` |
| kernel Image SHA-256 | `a58cf72f405d1c67266532b4a49bbf17ab5ea834962ea1a6cb84094f93efcdf4` |
| `frames.bin` SHA-256 | `655cd5aa44c2585ee435466015bdb38f6abbdb8623877d92847bd02aad415030` |
| `oracle.bin` SHA-256 | `37905752542e5c43551cc18e911ed4c0394333f25882b7c9ef4890ff5ace177f` |

compiler version과 build path가 다르면 QEMU/lkvm binary digest는 달라질 수 있다. 이 경우 source
commit, build option, 실행 환경 marker와 기능 결과를 함께 기록한다. 전체 revision/digest와
알려진 warning은 [Phase 11 최종 결과](docs/phase-11/RESULT.md)의 7~9절을 기준으로 한다.

### 6. 명령 표기와 문제 해결

이 절의 명령은 일반 개발자 shell에서 실행할 수 있는 표준 명령이다. Codex 같은 자동화 Agent가
이 저장소에서 명령을 실행할 때는 [AGENTS.md](AGENTS.md)에 따라 각 shell 명령 앞에 `rtk`를
붙인다.

주요 실패 원인은 다음 문서에서 확인한다.

- E-3 QEMU, toolchain, fixture, timeout 문제: [Phase 10 검증 How-to의 문제 해결](docs/phase-10/VERIFICATION.md#14-자주-발생하는-실패와-조치)
- DMA-BUF endpoint, local FD와 known warning: [Phase 09 검증](docs/phase-09/VERIFICATION.md)
- 최종 검증 범위와 미검증 항목: [Phase 11 최종 결과](docs/phase-11/RESULT.md)

재현 과정에서 Trusted Access가 필요하다는 메시지가 나오면 권한을 요구하거나 우회하지 않는다.
공개된 Host/guest interface와 관찰 가능한 반환값으로 검증 범위를 축소하고 제외 항목을 새 검증
기록에 남긴다.
