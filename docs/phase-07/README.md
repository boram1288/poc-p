# Phase 07: 동적 pVM 수명주기 관리

- 상태: 완료
- 목적: Host 요청으로 pVM을 생성하고 종료하는 제어 흐름을 권한 검사와 이미지 검증까지 포함해 성립시킨다.
- 환경: E-1
- 관련 목표: G-7, 부분적으로 G-5
- 관련 결정: D-4, D-6
- 실행 도구: `work/src/tools/pvm-manager/`
- 실행 산출물: `work/build/pvm-manager/`
- 재수행 설계: [C 기반 userspace VM 관리 프레임워크](userspace-vm-framework-design.md)

## 제어 경로

Host Application은 `CREATE <role> <image>` 또는 `STOP <role> -` 형식의 요청 파일을 만든다.
관리자는 파일의 실제 소유 UID를 확인하고, UID 0 요청만 수락한다. `camera`와 `ai` 역할 및
`/images/*.bin` 경로만 허용하며 역할별 PID와 로그를 `/run/pvm-manager/`에서 관리한다.

이 인터페이스는 QEMU initramfs 안에서 정책, 이미지 검사, KVM selftest 프로세스 수명주기를
한 경로로 검증하기 위한 최소 구현이다. 제품용 IPC나 다중 사용자 인증 프로토콜은 아니다.

## 이미지 검증 결정 (D-6)

현재 커널에는 reserved memory의 pvmfw를 pVM에 적재하는 훅과 firmware IPA 설정 ioctl이
있다. 그러나 E-1에는 pvmfw 바이너리, 검증된 부트 체인 및 키 기반 신뢰 루트가 구성되지
않았다. pvmfw 로딩 훅만으로 Host가 제출한 guest image의 출처와 무결성을 검증할 수
없으므로 Phase 07에서는 Host 관리자 소유의 `SHA256SUMS` 허용 목록을 대체 경로로 확정했다.

기존 관리자는 legacy selftest executable의 SHA-256이 허용 목록과 정확히 일치해야만
프로세스를 생성한다. 재수행 프레임워크에서는 guest code를 build한 guest workload를 먼저
검증한 뒤 guest image에 포함하고, 완성된 guest image도 pVM 생성 전에 별도로 검증한다. 이 방식은
변조 탐지와 실행 전 거부를 검증하지만, 비신뢰 Host에 대한 신뢰 루트는 아니다. 서명 검증,
키 관리, measured boot 및 pvmfw 기반 검증은 제품화 후속 과제다.

## 구현 및 실행

- `pvm-manager.sh`: 요청 소유자·역할·경로 정책 검사, SHA-256 검증, 생성과 종료
- `lifecycle-test.sh`: 거부 경로, 정상 수명주기, 동시 실행과 장애 주입 자동화
- `mkinitramfs.sh`: 정상/변조 이미지와 허용 목록을 포함한 initramfs 생성
- `run.sh`: protected nVHE QEMU 실행과 완료 마커 판정

```bash
work/src/tools/pvm-manager/mkinitramfs.sh
work/src/tools/pvm-manager/run.sh
```

## 검증 절차

1. UID 65534 소유 요청이 pVM 생성 전에 거부되는지 확인한다.
2. 정상 이미지 뒤에 데이터를 추가한 변조본이 해시 검사에서 거부되는지 확인한다.
3. 허용된 요청과 이미지로 Camera pVM을 만들고 KVM FD 3개 이상인 실행 상태를 확인한다.
4. 종료 요청을 보내 프로세스와 KVM 자원을 회수한다.
5. Camera와 AI pVM을 동시에 실행 상태로 만든 뒤 Camera에 `SIGKILL`을 주입한다.
6. AI pVM과 관리자 경로가 생존하고 AI가 selftest 전체를 완료하는지 확인한다.
7. 전체 종료 후 `Mlocked`가 0으로 복귀하는지 확인한다.

## 결과

2026-08-16 QEMU 8.2.2 TCG, `cortex-a57`, 4 vCPU, 3 GiB에서 QEMU rc=0과
`PVM_MANAGER_VALIDATION_OK`를 확인했다.

| 경로 | 결과 및 마커 |
|---|---|
| 권한 거부 | `PVM_MANAGER_AUTH_DENIED: uid=65534`, `LIFECYCLE_AUTH_DENIAL_OK` |
| 이미지 검증 실패 | `PVM_MANAGER_IMAGE_REJECTED`, `LIFECYCLE_IMAGE_REJECTION_OK` |
| 정상 생성 | `PVM_MANAGER_IMAGE_VERIFIED`, `LIFECYCLE_RUNNING: ... kvm_fds=3` |
| 정상 종료 | `PVM_MANAGER_STOPPED`, `LIFECYCLE_NORMAL_STOP_OK` |
| 동시 KVM 객체 | `LIFECYCLE_OVERLAP: ... camera_kvm_fds=4 ... ai_kvm_fds=3` |
| 장애 격리 | `AI_SURVIVOR: All ok!`, `LIFECYCLE_FAULT_ISOLATION_OK` |
| 자원 회수 | AI `Host VmLck after teardown: 0`, 전체 `Mlocked: 0 kB` |
| 최종 판정 | `LIFECYCLE_ALL_OK`, `PVM_MANAGER_RUNNER_RC=0`, QEMU rc=0 |

## 산출물

- 제어 경로 소스: `work/src/tools/pvm-manager/`
- initramfs: `work/build/pvm-manager/initramfs-pvm-manager.cpio.gz`
- 콘솔 로그: `work/build/pvm-manager/console-pvm-manager.log`

## 한계

요청 파일 UID 검사는 최소 권한 검증이며 namespace, MAC, 원격 인증을 포함하지 않는다.
SHA-256 허용 목록은 신뢰된 Host 관리자를 전제로 하므로 비신뢰 Host로부터 이미지를 보호하지
않는다. 제품 수준에서는 서명 키와 pvmfw/verified boot 신뢰 체인에 연결해야 한다.

이 Phase는 메모리와 vCPU 회수를 판정한다. 실제 장치 자원의 회수는 Phase 08에서 다룬다.

## C 프레임워크 기반 재수행

기존 완료 결과는 유지하되 Host Application의 직접 KVM ioctl 의존을 없애기 위해 Phase 07을
C 기반 userspace VM 관리 프레임워크 위에서 다시 수행했다. controller daemon과 VM별
VM runner, runner 안에 link되는 private KVM backend를 사용하는 B+W2+R1+I1 설계를
[설계 문서](userspace-vm-framework-design.md)에 확정했다. Application과 public API에는
KVM UAPI가 노출되지 않으며 실제 KVM backend는 VM runner process에서 실행된다.

```text
Application -> libpvm-client -> Unix SOCK_SEQPACKET -> pvmd
                                                       ├─ pvm-runner camera -> private KVM backend -> /dev/kvm
                                                       └─ pvm-runner ai     -> private KVM backend -> /dev/kvm
```

guest code는 독립 arm64 binary인 guest workload로 build된다. packer가 workload SHA-256을
먼저 검증한 뒤 boot metadata와 묶어 guest image를 만들고, controller가 image 전체의
SHA-256을 다시 검증한 후에만 pVM을 생성한다. pVM에서는 image에 포함된 workload binary가
실제로 시작되고 완료된다.

### 소스와 산출물

| 경로 | 역할 |
|---|---|
| `work/src/tools/pvm-framework/include`, `lib` | KVM을 노출하지 않는 public C API와 client library |
| `work/src/tools/pvm-framework/daemon/pvmd.c` | 인증, policy, instance 상태와 VM runner 감시 |
| `work/src/tools/pvm-framework/runner/pvm_runner.c` | VM별 Host VMM process entry |
| `work/src/tools/pvm-framework/backend/` | VM runner에만 link되는 private arm64 KVM backend |
| `work/src/tools/pvm-framework/guest/phase07_guest.S` | 독립 guest workload를 만드는 guest code |
| `work/src/tools/pvm-framework/common/` | versioned protocol, image format와 SHA-256 구현 |
| `work/src/tools/pvm-framework/tests/` | public API lifecycle와 protocol negative C test |
| `work/build/pvm-framework/arm64/` | 정적으로 link된 framework와 test binaries |
| `work/build/pvm-framework/images/` | workload, guest image, 변조본과 `SHA256SUMS` |

`work/src/tools/pvm-framework`는 별도 Git repository가 아니라 이 상위 repository가 관리한다.
이번 재수행에서 `work/src/pkvm-linux`는 읽기 전용 build 입력으로만 사용했으며 submodule
수정은 없다.

### 재현 명령

저장소 루트에서 아래 순서로 실행한다. `BUSYBOX`는 arm64 static BusyBox 경로로 바꿀 수 있다.

```bash
# C binaries, guest workload와 guest image를 build하고 KVM 경계·link·artifact layout을 검사한다.
work/src/tools/pvm-framework/verify-static.sh

# framework, image와 C test application을 포함한 E-1 initramfs를 만든다.
BUSYBOX="$PWD/work/build/pvm-manager/initramfs-root/bin/busybox" \
  work/src/tools/pvm-framework/mkinitramfs.sh

# pkvm-full-clang kernel로 QEMU를 실행하고 최종 marker를 판정한다.
work/src/tools/pvm-framework/run.sh \
  work/build/pvm-framework/console-pvm-framework-final.log 900
```

정적 검증에서는 다음 marker가 모두 출력되어야 한다.

```text
PVM_FRAMEWORK_BUILD_OK
PVM_FRAMEWORK_KVM_BOUNDARY_OK
PVM_FRAMEWORK_STATIC_BUILD_OK
PVM_FRAMEWORK_ARTIFACT_LAYOUT_OK
```

### E-1 실측 결과

2026-08-18 QEMU 8.2.2 TCG에서 clang으로 build한 Linux 6.18
`3b5e0f83d34d` submodule source와 `work/build/pkvm-full-clang` kernel을 사용했다. QEMU rc=0,
Protected KVM 초기화, 아래 검증 marker와 kernel panic 없음이 확인되었다. 삭제한
`pkvm-full-gcc`를 복구하거나 gcc kernel 교차 검증은 하지 않았다. OP-TEE와 Trusted
Application도 이 재수행의 완료 조건에 포함하지 않았다.

| 완료 조건 | 실측 결과 |
|---|---|
| CC-01~CC-04 설계·build·KVM 경계 | arm64 static binaries 생성, KVM 참조는 runner private backend link map에만 존재 |
| CC-05~CC-08 artifact·무결성·실행 | workload 선검증/변조 거부, image 검증/변조 거부, guest 시작·완료 확인 |
| CC-09~CC-10 API·인증·policy | 정상 lifecycle과 잘못된 전이, UID 65534와 invalid role 거부 확인 |
| CC-11 다중 pVM | Camera/AI가 동시에 RUNNING, 각 1 vCPU·16 KiB memory·KVM resource 6개 확인 |
| CC-12 장애 격리 | Camera runner `SIGKILL` 후 FAILED, AI workload와 controller 생존 확인 |
| CC-13 회수 | VM runner/KVM resource 회수와 `Mlocked: 0 kB` 확인 |
| CC-14 E-1 runtime | `PVM_FRAMEWORK_VALIDATION_OK`, test rc=0, QEMU rc=0 |
| CC-15 재현성 | 명령, version, digest와 log 경로를 이 문서에 기록 |

주요 runtime 증빙은 다음과 같다.

```text
PVM_FRAMEWORK_WORKLOAD_VERIFIED
PVM_FRAMEWORK_WORKLOAD_REJECTED
PVM_FRAMEWORK_PROTOCOL_NEGATIVE_OK
PVM_FRAMEWORK_AUTH_TEST_OK
PVM_FRAMEWORK_POLICY_TEST_OK
PVM_FRAMEWORK_IMAGE_REJECTION_OK: kvm_fds=0
PVM_FRAMEWORK_NORMAL_LIFECYCLE_OK
PVM_FRAMEWORK_DAEMON_RECOVERY_OK
PVM_FRAMEWORK_OVERLAP: camera_resources=6 ai_resources=6
GUEST_WORKLOAD_STARTED
GUEST_WORKLOAD_COMPLETED
PVM_FRAMEWORK_FAULT_ISOLATION_OK
PVM_FRAMEWORK_RESOURCE_RECOVERY_OK
PVM_FRAMEWORK_VALIDATION_OK
```

| Artifact | SHA-256 |
|---|---|
| `phase07-guest-workload.bin` | `ab42ea25732c85d141de953016f771446f9a024cb316610f4c7f32bc2de13cfe` |
| `phase07-guest.img` | `ac9b0104cb5539f531a8753b2760c5a2045125aeffaedc9b2befb2e4b000a22b` |

- initramfs: `work/build/pvm-framework/initramfs-pvm-framework.cpio.gz`
- 최종 console log: `work/build/pvm-framework/console-pvm-framework-final.log`
- 최종 판정: 설계 문서의 CC-01~CC-15 모두 통과, C 프레임워크 기반 재수행 완료

### 재수행 한계

192-byte test guest image와 SHA-256 allowlist는 artifact 경계와 실행 전 거부를 검증하는 PoC
형식이다. Linux guest boot image, signature key, measured boot 또는 pvmfw trust chain은 아니다.
private backend는 현재 kernel selftest helper를 내부 adapter로 재사용하며 public ABI로
노출하지 않는다. QEMU TCG 결과는 기능 증빙이고 실물 hardware의 성능·보안 보증은 아니다.
