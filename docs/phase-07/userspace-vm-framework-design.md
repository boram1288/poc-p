# Phase 07 재수행: C 기반 userspace VM 관리 프레임워크 설계

- 문서 상태: 요구사항 수집 및 아키텍처 결정 대기
- 대상 환경: E-1(QEMU TCG, arm64, protected nVHE)
- 구현 언어: C
- 목표: Host Application이 KVM ioctl을 직접 사용하지 않고 pVM 수명주기를 관리하게 한다.
- 기존 검증 기준: [Phase 07 README](README.md)

## 1. 재수행 배경

기존 Phase 07의 `pvm-manager.sh`는 요청 파일의 UID, 역할, 이미지 해시를 검사한 뒤
`pkvm.bin` 프로세스를 시작하거나 종료한다. 그러나 `pkvm.bin`은 순수한 게스트 이미지가
아니라 다음 요소가 한 ELF에 결합된 Linux KVM selftest다.

| 요소 | 현재 위치와 역할 |
|---|---|
| Host 제어 | `pvm-manager.sh`가 실행 파일의 프로세스 수명주기를 관리 |
| KVM VMM | `pkvm.c`와 KVM selftest library가 `/dev/kvm`, VM/vCPU, memory slot을 직접 관리 |
| Guest payload | `pkvm.c` 안의 guest 코드와 protected VM 진입 코드 |
| 검증 코드 | 같은 `pkvm.c` 안에서 heartbeat, 격리, teardown 결과를 판정 |

즉 기존 관리자는 KVM VM 객체의 상태를 알지 못하고 PID와 열린 KVM FD 개수만 관찰한다.
재수행에서는 KVM ioctl을 프레임워크 내부 backend로 한정하고, Application에는 안정된 C API와
관리 명령만 제공한다.

## 2. 범위와 성공 기준

이번 재수행은 Phase 07 완료 조건을 대체하지 않고 더 높은 수준의 제어 경로로 다시 검증한다.

- Application 소스는 `<linux/kvm.h>`, `/dev/kvm`, `ioctl()`을 사용하지 않는다.
- C 프레임워크가 정책 검사부터 VM 생성, 실행, 상태 조회, 종료, 회수까지 소유한다.
- Camera와 AI 두 인스턴스를 동시에 관리한다.
- 기존 다섯 경로인 권한 거부, 이미지 거부, 정상 생성, 장애 격리, 정상 종료를 재현한다.
- 종료 후 KVM FD, vCPU, protected memory가 회수되고 `Mlocked: 0 kB`가 된다.
- 각 결과를 구조화된 상태와 서로 다른 로그 마커로 확인할 수 있어야 한다.

OP-TEE와 Trusted Application 호출은 이번 Phase 07 재수행 범위에 포함하지 않는다.
커널은 저장 공간 정책에 따라 `pkvm-full-clang`만 사용하며 삭제된 `pkvm-full-gcc` 산출물을
복구하거나 gcc 교차 검증을 수행하지 않는다.

## 3. 기능 요구사항 초안

아래 표에서 **확정**은 기존 Phase 07 목표와 이번 요청으로 이미 정해진 항목이고,
**제안**은 아키텍처 선택 후 확정할 항목이다.

| ID | 상태 | 요구사항 | 검증 방법 |
|---|---|---|---|
| FR-01 | 확정 | Application은 KVM ioctl 대신 C client API를 사용한다. | Application의 KVM header/ioctl 참조가 0건인지 검사 |
| FR-02 | 확정 | `camera`, `ai` 역할의 pVM을 생성·시작·조회·정지·삭제한다. | 역할별 정상 lifecycle 시험 |
| FR-03 | 확정 | UID와 역할 정책을 VM 생성 전에 검사한다. | 비인가 UID 요청 거부 |
| FR-04 | 확정 | 실행 전 workload 무결성을 SHA-256 허용 목록으로 검사한다. | 변조 workload 거부 |
| FR-05 | 확정 | 두 pVM을 동시에 실행하고 독립 상태를 조회한다. | Camera/AI 동시 RUNNING 확인 |
| FR-06 | 확정 | 한 pVM의 강제 종료가 다른 pVM과 관리 경로를 중단시키지 않는다. | Camera 장애 후 AI와 관리자 생존 확인 |
| FR-07 | 확정 | 종료 후 VM/vCPU/memory/FD 자원을 회수한다. | PID·KVM FD 소멸과 `Mlocked` 확인 |
| FR-08 | 제안 | 요청·응답에 protocol version과 request ID를 둔다. | 잘못된 version 및 중복 ID 시험 |
| FR-09 | 제안 | `CREATED`, `RUNNING`, `STOPPING`, `STOPPED`, `FAILED` 상태 전이를 강제한다. | 허용되지 않은 전이 거부 시험 |
| FR-10 | 제안 | 프레임워크가 비정상 worker 종료를 감지하고 `FAILED` 원인을 보존한다. | `SIGKILL` 주입 후 상태·exit reason 확인 |
| FR-11 | 제안 | daemon 재시작 시 실행 중 worker를 재발견하거나 안전하게 정리한다. | daemon restart recovery 시험 |
| FR-12 | 제안 | 조회 API로 role, instance ID, state, PID, vCPU 수, memory 크기, 종료 원인을 반환한다. | API 응답 필드 검사 |

## 4. 비기능 요구사항 초안

| ID | 상태 | 요구사항 |
|---|---|---|
| NFR-01 | 확정 | 구현은 C로 작성하고 arm64 initramfs에서 정적으로 실행 가능해야 한다. |
| NFR-02 | 확정 | Application과 public header는 Linux KVM UAPI에 의존하지 않는다. |
| NFR-03 | 제안 | control path는 shell script에 의존하지 않고 C binary로 동작한다. shell은 패키징과 검증 구동에만 사용한다. |
| NFR-04 | 제안 | protocol은 고정 폭 타입, 명시적 길이, 상한 검사로 malformed request를 거부한다. |
| NFR-05 | 제안 | 최대 VM 수, vCPU 수, guest memory, 요청 크기에 정적 상한을 둔다. |
| NFR-06 | 제안 | 로그는 timestamp, instance ID, state, result code를 포함하는 한 줄 형식으로 출력한다. |
| NFR-07 | 제안 | VM 하나의 crash가 manager process와 다른 VM의 주소 공간에 직접 전파되지 않아야 한다. |
| NFR-08 | 제안 | public API와 wire protocol에 version을 두어 backend 변경을 Application에서 격리한다. |
| NFR-09 | 제안 | 단위 시험은 Host에서, 실제 KVM lifecycle 시험은 E-1 QEMU에서 분리 실행한다. |

성능 정량 평가, 원격 관리, 네트워크 API, 영구 데이터베이스, 라이브 마이그레이션,
제품 수준 서명·키 관리 및 고가용성은 이번 재수행의 비기능 범위에서 제외한다.

## 5. 확인된 제약사항

| ID | 제약 | 설계 영향 |
|---|---|---|
| C-01 | KVM ioctl 자체는 없어지는 것이 아니라 신뢰된 VMM/backend 내부로 이동해야 한다. | ioctl 사용 파일을 private backend로 한정 |
| C-02 | 현재 `pkvm.bin`은 VMM, guest payload, 검증이 결합된 selftest ELF다. | 순수 guest image loader로 바로 사용할 수 없음 |
| C-03 | protected VM은 일반 KVM VM 생성 외에 `KVM_CAP_ARM_PROTECTED_VM` 설정과 전용 부팅 순서가 필요하다. | backend가 순서와 오류 rollback을 캡슐화 |
| C-04 | E-1 initramfs는 BusyBox 중심의 최소 환경이다. | 외부 runtime과 동적 library 의존을 피함 |
| C-05 | QEMU TCG 결과는 기능 검증이며 실장치 성능·보안 보증이 아니다. | 실측 결과의 주장 범위를 E-1로 제한 |
| C-06 | E-1에는 pvmfw 신뢰 체인이 없다. | 기존 SHA-256 allowlist를 유지하고 한계를 명시 |
| C-07 | gcc 커널 build tree는 삭제되었고 이후 교차 검증을 하지 않는다. | clang kernel 한 개만 검증 입력으로 사용 |
| C-08 | OP-TEE/TA가 없어도 완료 가능한 목적 범위다. | Secure World 연동 API는 이번 설계에서 제외 |
| C-09 | kernel selftest library는 제품용 안정 ABI가 아니다. | 초기 backend adapter로 격리하고 public API에 노출하지 않음 |

## 6. 관리 방식 후보

### 안 A. Application 내 embedded library

```text
Application -> libpvm -> private KVM backend -> /dev/kvm
```

Application이 `libpvm`을 링크하고 같은 프로세스에서 VM을 생성한다. KVM 코드는 library 뒤로
숨지만 VM FD와 vCPU thread는 Application 프로세스가 소유한다.

- 장점: 구현과 배포가 가장 단순하고 IPC가 없다.
- 단점: Application crash가 VM 전체를 종료하며 중앙 정책과 다중 client 조정이 어렵다.
- Phase 07 적합성: 최소 API 검증에는 충분하지만 관리 경로 장애 격리 요구에는 약하다.

### 안 B. 단일 daemon이 모든 VM을 직접 소유

```text
Application -> libpvm-client -> Unix socket -> pvmd
                                           ├─ VM camera (thread)
                                           └─ VM ai (thread)
```

Application은 C client API만 사용하고 `pvmd`가 인증, 정책, 이미지 검증과 모든 KVM 객체를
소유한다. VM별 vCPU는 daemon 안의 thread로 실행한다.

- 장점: 정책과 상태가 한곳에 있고 A보다 Application 격리가 명확하다.
- 단점: backend 오류나 process-wide fault가 모든 VM과 관리 경로에 영향을 줄 수 있다.
- Phase 07 적합성: 중앙 관리 기능은 좋지만 VM 간 장애 격리 증명은 제한적이다.

### 안 C. controller daemon과 VM별 worker process 분리 — 권고

```text
Application
    -> libpvm-client
        -> Unix SOCK_SEQPACKET
            -> pvmd (인증·정책·상태·감시)
                ├─ pvm-worker camera -> private KVM backend -> /dev/kvm
                └─ pvm-worker ai     -> private KVM backend -> /dev/kvm
```

`pvmd`는 control plane만 소유하고 각 VM의 KVM FD, memory, vCPU는 별도 `pvm-worker`
process가 소유한다. `pidfd` 또는 `SIGCHLD`로 worker 종료를 감지한다.

- 장점: Application에서 KVM을 완전히 분리하고 VM별 process fault domain을 제공한다.
- 장점: Phase 07의 Camera 강제 종료 후 AI와 manager 생존을 구조적으로 검증할 수 있다.
- 단점: IPC, worker protocol, 상태 동기화와 종료 순서 구현량이 가장 많다.
- Phase 07 적합성: 기존 완료 조건과 이후 장치 backend 확장에 가장 잘 맞는다.

## 7. workload/backend 이관 후보

관리 방식과 별도로 현재 selftest 결합을 어느 수준까지 해소할지 결정해야 한다.

| 안 | 내용 | 장점 | 한계 |
|---|---|---|---|
| W1 | worker가 기존 `pkvm.bin`을 그대로 exec하는 adapter | 가장 빠르게 기존 결과 재사용 | 프레임워크가 VM 객체를 소유하지 않아 핵심 목적을 부분 충족 |
| W2 | 최소 protected VM runner를 C backend로 분리하고 test payload를 로드 | ioctl 캡슐화와 실제 VM 상태 관리가 성립 | selftest helper 의존을 private 영역에 격리해야 함 |
| W3 | Linux-capable VMM(kvmtool 계열)을 backend로 연결 | 이후 일반 guest workload에 유리 | Phase 07 범위를 크게 넘고 장치/boot protocol 구현 부담이 큼 |

**권고는 W2**다. Phase 07에서는 작은 test payload로 lifecycle을 검증하고, public API는
backend 중립적으로 설계하여 W3를 후속 backend로 추가할 수 있게 한다. W1은 전환 중 대조군
용도로만 유지한다.

## 8. 권고 기준 설계 초안

안 C와 W2를 선택할 경우 모듈 경계는 다음과 같다.

| 모듈 | 공개 여부 | 책임 |
|---|---|---|
| `include/pvm/pvm.h` | 공개 | Application용 create/start/status/stop/list API와 오류 코드 |
| `lib/pvm_client.c` | 공개 library | 요청 직렬화, socket 연결, 응답 검증 |
| `daemon/pvmd.c` | 비공개 | peer credential 인증, policy, instance registry, 상태 전이 |
| `worker/pvm_worker.c` | 비공개 | VM별 process entry, backend 호출, 상태/종료 결과 보고 |
| `backend/pvm_kvm_arm64.c` | 비공개 | `/dev/kvm`, protected VM/vCPU/memory/ioctl 순서와 rollback |
| `common/protocol.h` | 내부 공유 | versioned fixed-size IPC message와 크기 상한 |
| `cli/pvmctl.c` | 공개 도구 | 수동 검증과 운영 진단용 CLI; client library만 사용 |
| `tests/phase07_app.c` | 검증용 | KVM을 모르는 Host Application 역할 |

초기 IPC는 로컬 `AF_UNIX`의 `SOCK_SEQPACKET`을 사용하고 `SO_PEERCRED`에서 얻은 실제 UID로
인증하는 방식을 권고한다. 요청 파일의 `chown`을 인증 근거로 삼던 기존 방식보다 요청 주체와
연결을 직접 묶을 수 있고 message boundary도 보존된다.

초기 상태는 아래 단방향 전이를 기본으로 한다.

```text
NEW -> VERIFIED -> CREATED -> RUNNING -> STOPPING -> STOPPED
  \       \          \          \           \
   +-------+----------+----------+------------> FAILED
```

## 9. Phase 07 재검증 매핑

| 기존 검증 | 새 프레임워크 검증 |
|---|---|
| 요청 파일 UID 65534 거부 | 비인가 client의 socket 연결/CREATE 거부 |
| 변조 `pkvm.bin` 거부 | 변조 workload manifest 검증 실패 |
| PID와 KVM FD 3개 이상 | API state=RUNNING 및 worker의 VM/vCPU FD 보유 확인 |
| STOP 요청 | client API STOP 후 STOPPED와 FD/worker 회수 확인 |
| Camera `SIGKILL` | Camera worker kill 후 FAILED, AI RUNNING, pvmd 응답 확인 |
| AI selftest 완료 | AI worker의 guest completion/result event 확인 |
| `Mlocked: 0 kB` | 전체 destroy 뒤 기존 기준을 동일하게 확인 |

shell script는 cross-build, initramfs 생성, QEMU 시작과 최종 마커 수집에만 남긴다. Phase 07의
실제 요청, 인증, 정책, VM 상태 전이와 lifecycle 검증 로직은 C API와 C test application으로
이관한다.

## 10. 사용자 결정이 필요한 항목

### D07-F1. process 구조

- A: embedded library
- B: 단일 daemon + VM thread
- C: controller daemon + VM별 worker process (**권고**)

### D07-F2. 초기 backend 범위

- W1: 기존 selftest exec adapter
- W2: 최소 protected VM C runner로 분리 (**권고**)
- W3: 처음부터 Linux-capable VMM backend

### D07-F3. daemon 재시작 복구 수준

- R1: 이번 PoC에서는 daemon 생존 중 lifecycle만 보장하고 재시작 시 남은 worker를 정리
  (**권고**)
- R2: daemon 재시작 후 기존 worker에 재연결하여 관리 지속

### D07-F4. 초기 public interface

- I1: C library와 `pvmctl` CLI를 함께 제공 (**권고**)
- I2: C library만 제공
- I3: CLI만 제공

권고 조합은 **C + W2 + R1 + I1**이다. 이 조합은 Application의 KVM 의존을 제거하면서
Phase 07 장애 격리를 실제 process boundary로 재검증하고, 영구 복구나 full Linux VMM 때문에
초기 범위가 과도하게 커지는 것을 피한다.

## 11. 결정 후 작업 순서

1. 선택 결과로 기능·비기능 요구사항의 **제안** 항목을 확정하거나 제외한다.
2. public C API, IPC protocol, 상태 머신, 오류·rollback 상세 설계를 작성한다.
3. Host 단위 시험이 가능한 protocol/policy/state 모듈을 먼저 구현한다.
4. arm64 protected KVM backend와 worker를 구현한다.
5. 기존 shell lifecycle test를 C test application으로 대체한다.
6. clang kernel 기반 E-1 QEMU에서 Phase 07 완료 조건 전체를 다시 실측한다.
7. 성공 로그와 한계를 Phase 07 README에 반영하고 완료 조건 충족 시 커밋·push한다.

