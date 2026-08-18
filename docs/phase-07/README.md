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
않았다. pvmfw 로딩 훅만으로 Host가 제출한 workload 이미지의 출처와 무결성을 검증할 수
없으므로 Phase 07에서는 Host 관리자 소유의 `SHA256SUMS` 허용 목록을 대체 경로로 확정했다.

관리자는 실행 파일의 SHA-256이 허용 목록과 정확히 일치해야만 프로세스를 생성한다. 이 방식은
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
C 기반 userspace VM 관리 프레임워크 위에서 다시 수행한다. 현재는 기능·비기능 요구사항과
관리 방식 후보를 [설계 문서](userspace-vm-framework-design.md)에 정리했으며, 사용자
아키텍처 결정 후 상세 설계, 구현 및 E-1 실측 검증을 진행한다.
