# Phase 07 재수행: C 기반 userspace VM 관리 프레임워크 설계

- 문서 상태: 구현 및 E-1 실측 검증 완료
- 대상 환경: E-1(QEMU TCG, arm64, protected nVHE)
- 구현 언어: C
- 목표: Host Application이 KVM ioctl을 직접 사용하지 않고 pVM 수명주기를 관리하게 한다.
- 기존 검증 기준: [Phase 07 README](README.md)

## 1. 재수행 배경

기존 Phase 07의 `pvm-manager.sh`는 요청 파일의 UID, 역할, 이미지 해시를 검사한 뒤
`pkvm.bin` 프로세스를 시작하거나 종료한다. 그러나 `pkvm.bin`은 순수한 guest image가
아니라 다음 요소가 한 ELF에 결합된 Linux KVM selftest다.

| 요소 | 현재 위치와 역할 |
|---|---|
| Host 제어 | `pvm-manager.sh`가 executable의 프로세스 수명주기를 관리 |
| KVM VMM | `pkvm.c`와 KVM selftest library가 `/dev/kvm`, VM/vCPU, memory slot을 직접 관리 |
| guest code | `pkvm.c` 안의 guest source와 protected VM 진입 코드 |
| 검증 코드 | 같은 `pkvm.c` 안에서 heartbeat, 격리, teardown 결과를 판정 |

즉 기존 관리자는 KVM VM 객체의 상태를 알지 못하고 PID와 열린 KVM FD 개수만 관찰한다.
재수행에서는 KVM ioctl을 프레임워크 내부 backend로 한정하고, Application에는 안정된 C API와
관리 명령만 제공한다.

## 2. 용어 규칙

이 문서와 이후 구현에서는 Host 쪽 process, VM에 넣는 파일과 VM 안에서 실행되는 코드를
구분하기 위해 다음 용어를 사용한다.

| 통일 용어 | 의미 | 사용 예 |
|---|---|---|
| controller daemon | client 요청을 인증하고 정책·상태·VM runner를 관리하는 Host process인 `pvmd` | VM runner 생성, 상태 조회, 종료 지시 |
| VM runner | VM 하나의 실행 상태를 담당하는 Host VMM process인 `pvm-runner` | Camera VM runner, AI VM runner |
| KVM backend | VM runner 내부에서 실제 KVM ioctl을 캡슐화하는 private C 모듈 | protected VM 생성, memory 등록, `KVM_RUN` |
| guest code | pVM에서 수행할 기능을 구현한 source code | heartbeat, 완료 마커와 종료 처리 구현 |
| guest workload | guest code를 build하여 만든 executable binary. integrity verification 후 guest image에 포함 | `phase07-guest-workload.bin` |
| guest image | integrity verification을 통과한 guest workload와 boot metadata를 포함하고 pVM에 적재되는 image | Phase 07 test guest image, 향후 Linux `Image`와 rootfs 조합 |
| pVM instance | controller가 ID와 상태를 부여해 관리하는 논리적 VM 한 개 | `camera-1`, `ai-1` |
| legacy selftest executable | VMM, guest code와 검증 코드가 결합된 현재 `pkvm.bin` | 새 guest image와 구분 |

`worker`와 `payload`는 사용하지 않는다. `workload`를 단독으로 쓰지 않고 build가 끝난
executable binary만 **guest workload**라고 부른다. source는 **guest code**, guest workload와
boot metadata를 묶은 image는 **guest image**로 구분한다. 특히 현재 `pkvm.bin`은 guest
image가 아니라 **legacy selftest executable**이다.

### guest artifact 생성과 실행 순서

```text
guest code
    -> build
guest workload
    -> guest workload integrity verification
    -> package with boot metadata
guest image
    -> guest image integrity verification
    -> load and boot pVM
    -> execute embedded guest workload
```

`SHA256SUMS` allowlist에는 guest workload와 guest image의 digest를 각각 기록한다. packaging은
guest workload verification이 성공한 경우에만 수행하며, controller는 pVM 생성 전에 완성된
guest image를 다시 검증한다. guest image digest가 image 전체를 보호하므로 검증 이후 포함된
guest workload가 바뀌면 guest image verification도 실패한다.

## 3. 범위와 성공 기준

이번 재수행은 Phase 07 완료 조건을 대체하지 않고 더 높은 수준의 제어 경로로 다시 검증한다.

- Application 소스는 `<linux/kvm.h>`, `/dev/kvm`, `ioctl()`을 사용하지 않는다.
- C 프레임워크가 정책 검사부터 VM 생성, 실행, 상태 조회, 종료, 회수까지 소유한다.
- Camera와 AI 두 인스턴스를 동시에 관리한다.
- 권한 거부, guest workload 거부, guest image 거부, 정상 생성, 장애 격리와 정상 종료를
  재현한다.
- 종료 후 KVM FD, vCPU, protected memory가 회수되고 `Mlocked: 0 kB`가 된다.
- 각 결과를 구조화된 상태와 서로 다른 로그 마커로 확인할 수 있어야 한다.

OP-TEE와 Trusted Application 호출은 이번 Phase 07 재수행 범위에 포함하지 않는다.
커널은 저장 공간 정책에 따라 `pkvm-full-clang`만 사용하며 삭제된 `pkvm-full-gcc` 산출물을
복구하거나 gcc 교차 검증을 수행하지 않는다.

## 4. 기능 요구사항

아키텍처 선택과 구현 결과를 반영해 아래 요구사항을 모두 확정했다.

| ID | 상태 | 요구사항 | 검증 방법 |
|---|---|---|---|
| FR-01 | 확정 | Application은 KVM ioctl 대신 C client API를 사용한다. | Application의 KVM header/ioctl 참조가 0건인지 검사 |
| FR-02 | 확정 | `camera`, `ai` 역할의 pVM을 생성·시작·조회·정지·삭제한다. | 역할별 정상 lifecycle 시험 |
| FR-03 | 확정 | UID와 역할 정책을 VM 생성 전에 검사한다. | 비인가 UID 요청 거부 |
| FR-04 | 확정 | guest workload를 guest image에 포함하기 전에 SHA-256 allowlist로 무결성을 검사한다. | 변조 guest workload의 packaging 거부 |
| FR-05 | 확정 | pVM 생성 전에 완성된 guest image의 무결성을 SHA-256 allowlist로 검사한다. | 변조 guest image 거부 |
| FR-06 | 확정 | pVM boot 후 guest image에 포함된 guest workload를 실행한다. | guest workload 시작·완료 marker 확인 |
| FR-07 | 확정 | 두 pVM을 동시에 실행하고 독립 상태를 조회한다. | Camera/AI 동시 RUNNING 확인 |
| FR-08 | 확정 | 한 pVM의 강제 종료가 다른 pVM과 관리 경로를 중단시키지 않는다. | Camera 장애 후 AI와 관리자 생존 확인 |
| FR-09 | 확정 | 종료 후 VM/vCPU/memory/FD 자원을 회수한다. | PID·KVM FD 소멸과 `Mlocked` 확인 |
| FR-10 | 확정 | 요청·응답에 protocol version과 request ID를 둔다. | 잘못된 version 및 중복 ID 시험 |
| FR-11 | 확정 | `CREATED`, `RUNNING`, `STOPPING`, `STOPPED`, `FAILED` 상태 전이를 강제한다. | 허용되지 않은 전이 거부 시험 |
| FR-12 | 확정 | 프레임워크가 VM runner의 비정상 종료를 감지하고 `FAILED` 원인을 보존한다. | `SIGKILL` 주입 후 상태·exit reason 확인 |
| FR-13 | 확정 | controller daemon 재시작 시 실행 중 VM runner를 재발견하거나 안전하게 정리한다. | daemon restart recovery 시험 |
| FR-14 | 확정 | 조회 API로 role, instance ID, state, PID, vCPU 수, memory 크기, 종료 원인을 반환한다. | API 응답 필드 검사 |

## 5. 비기능 요구사항

| ID | 상태 | 요구사항 |
|---|---|---|
| NFR-01 | 확정 | 구현은 C로 작성하고 arm64 initramfs에서 정적으로 실행 가능해야 한다. |
| NFR-02 | 확정 | Application과 public header는 Linux KVM UAPI에 의존하지 않는다. |
| NFR-03 | 확정 | control path는 shell script에 의존하지 않고 C binary로 동작한다. shell은 패키징과 검증 구동에만 사용한다. |
| NFR-04 | 확정 | protocol은 고정 폭 타입, 명시적 길이, 상한 검사로 malformed request를 거부한다. |
| NFR-05 | 확정 | 최대 VM 수, vCPU 수, guest memory, 요청 크기에 정적 상한을 둔다. |
| NFR-06 | 확정 | controller 운영 로그는 monotonic timestamp와 role을 한 줄에 기록하고, lifecycle event에는 해당 instance ID, state 또는 result를 함께 기록한다. |
| NFR-07 | 확정 | VM 하나의 crash가 manager process와 다른 VM의 주소 공간에 직접 전파되지 않아야 한다. |
| NFR-08 | 확정 | public API와 wire protocol에 version을 두어 backend 변경을 Application에서 격리한다. |
| NFR-09 | 확정 | 단위 시험은 Host에서, 실제 KVM lifecycle 시험은 E-1 QEMU에서 분리 실행한다. |

성능 정량 평가, 원격 관리, 네트워크 API, 영구 데이터베이스, 라이브 마이그레이션,
제품 수준 서명·키 관리 및 고가용성은 이번 재수행의 비기능 범위에서 제외한다.

## 6. 확인된 제약사항

| ID | 제약 | 설계 영향 |
|---|---|---|
| C-01 | KVM ioctl 자체는 없어지는 것이 아니라 신뢰된 VMM/backend 내부로 이동해야 한다. | ioctl 사용 파일을 private backend로 한정 |
| C-02 | 현재 `pkvm.bin`은 VMM, guest code와 검증이 결합된 legacy selftest ELF다. | guest code를 guest workload로 별도 build하고 guest image에 package해야 함 |
| C-03 | protected VM은 일반 KVM VM 생성 외에 `KVM_CAP_ARM_PROTECTED_VM` 설정과 전용 부팅 순서가 필요하다. | backend가 순서와 오류 rollback을 캡슐화 |
| C-04 | E-1 initramfs는 BusyBox 중심의 최소 환경이다. | 외부 runtime과 동적 library 의존을 피함 |
| C-05 | QEMU TCG 결과는 기능 검증이며 실장치 성능·보안 보증이 아니다. | 실측 결과의 주장 범위를 E-1로 제한 |
| C-06 | E-1에는 pvmfw 신뢰 체인이 없다. | 기존 SHA-256 allowlist를 유지하고 한계를 명시 |
| C-07 | gcc 커널 build tree는 삭제되었고 이후 교차 검증을 하지 않는다. | clang kernel 한 개만 검증 입력으로 사용 |
| C-08 | OP-TEE/TA가 없어도 완료 가능한 목적 범위다. | Secure World 연동 API는 이번 설계에서 제외 |
| C-09 | kernel selftest library는 제품용 안정 ABI가 아니다. | 초기 KVM backend adapter로 격리하고 public API에 노출하지 않음 |
| C-10 | guest workload와 guest image는 서로 다른 artifact다. | allowlist에 두 digest를 별도로 기록하고 workload 검증을 먼저 수행 |

## 7. 관리 방식 후보

Application 안에 KVM backend를 포함하는 embedded library 방식은 후보에서 제외한다.
Application crash와 VM lifecycle이 결합되고 중앙 정책을 보장하기 어려워, 이번 재수행의
관리 경로 분리와 장애 격리 목적에 맞지 않기 때문이다. 비교 대상은 daemon 기반의 다음 두
가지 방식으로 좁힌다.

### 안 A. 단일 daemon이 모든 VM을 직접 소유

```text
Application -> libpvm-client -> Unix socket -> pvmd
                                           ├─ VM camera (thread)
                                           └─ VM ai (thread)
```

Application은 C client API만 사용하고 `pvmd`가 인증, 정책, 이미지 검증과 모든 KVM 객체를
소유한다. VM별 vCPU는 daemon 안의 thread로 실행한다.

- 장점: 정책, 상태와 KVM 객체가 한 process에 있어 동기화와 rollback이 단순하다.
- 장점: 별도 VM runner process와 내부 IPC가 없어 구현량, memory 사용량과 context switch가 적다.
- 단점: 잘못된 pointer 접근, assertion, signal 같은 process-wide fault가 모든 VM과 관리
  API를 동시에 중단시킬 수 있다.
- 단점: 모든 VM thread가 daemon의 주소 공간과 `/dev/kvm` 권한을 공유하므로 VM별 최소 권한
  및 resource limit 적용이 어렵다.
- Phase 07 적합성: lifecycle 기능은 검증할 수 있지만 한 VM backend 장애가 다른 VM과
  manager에 전파되지 않는다는 조건을 process boundary로 입증할 수 없다.

### 안 B. controller daemon과 VM별 VM runner process 분리 — 권고

```text
Application
    -> libpvm-client
        -> Unix SOCK_SEQPACKET
            -> pvmd (인증·정책·상태·감시)
                ├─ pvm-runner camera -> private KVM backend -> /dev/kvm
                └─ pvm-runner ai     -> private KVM backend -> /dev/kvm
```

`pvmd`는 control plane을 소유하고 `pidfd` 또는 `SIGCHLD`로 VM runner 종료를 감지한다.
각 VM runner는 자신의 KVM backend, VM/vCPU FD, memory와 실행 상태를 소유한다.

- 장점: Application에서 KVM을 완전히 분리하고 VM별 process fault domain을 제공한다.
- 장점: Phase 07의 Camera 강제 종료 후 AI와 manager 생존을 구조적으로 검증할 수 있다.
- 장점: VM runner별 UID, capability, `rlimit` 및 향후 cgroup을 적용할 수 있어 최소 권한과 자원
  상한을 VM 단위로 확장할 수 있다.
- 단점: controller-VM runner IPC, 상태 동기화, timeout과 비정상 종료 rollback을 별도로
  구현해야 한다.
- 단점: VM runner process별 page table, stack, FD와 context switch 비용이 추가된다.
- Phase 07 적합성: 기존 완료 조건과 이후 장치 backend 확장에 가장 잘 맞는다.

### 두 안의 장점·단점과 trade-off

| 비교 기준 | 안 A: 단일 daemon | 안 B: daemon + VM runner | 선택에 따른 trade-off |
|---|---|---|---|
| 장애 격리 | daemon fault가 모든 VM에 전파 | VM runner fault를 해당 VM에 한정 | B는 격리를 얻는 대신 감시·복구 로직이 증가 |
| 상태 일관성 | 상태와 KVM 객체가 같은 주소 공간에 있어 즉시 일관 | controller 상태와 VM runner 실제 상태가 잠시 다를 수 있음 | A는 단순성, B는 timeout·sequence 기반 동기화 필요 |
| 구현·시험 난이도 | thread 동기화와 KVM backend에 집중 | 내부 protocol, spawn, reap, reconnect 오류까지 시험 | B의 초기 구현·negative test 범위가 더 큼 |
| 자원 효율 | process 하나로 memory와 FD overhead가 작음 | VM마다 process 기본 비용이 추가 | 소수 pVM에서는 B의 비용이 작지만 VM 수 증가 시 누적 |
| 제어 지연 | 내부 함수 호출로 가장 짧음 | lifecycle 명령마다 내부 IPC 한 번 이상 추가 | data path가 아닌 control path라 Phase 07에서는 영향이 작음 |
| 권한 분리 | daemon 하나가 전체 KVM 권한 보유 | controller와 VM runner 권한을 역할별로 축소 가능 | B가 least privilege 설계에 유리하지만 설정이 복잡 |
| 자원 회수 | daemon 종료 시 모든 VM FD가 한꺼번에 닫힘 | VM runner 종료 시 해당 VM FD만 독립적으로 닫힘 | B가 VM별 회수와 장애 주입 증명에 유리 |
| 운영 관찰성 | thread와 VM 로그가 한 process에 섞임 | VM runner PID, exit status와 VM별 로그가 분리 | B가 원인 추적에 유리하나 로그 correlation ID 필요 |
| 확장성 | backend 추가가 daemon 안정성에 직접 영향 | backend 또는 VM 유형을 VM runner 단위로 격리 가능 | 이후 장치 backend까지 고려하면 B가 변경 영향 축소 |
| Phase 07 증거력 | 기능 성공은 확인 가능 | Camera VM runner kill 뒤 AI와 controller 생존을 직접 확인 | B가 장애 격리 완료 조건에 더 강한 증거 제공 |

안 A는 구현 기간과 구성 요소 수를 최소화하는 데 유리하다. 관리 대상이 하나이고 backend를
신뢰할 수 있으며 process 전체 재시작을 허용한다면 합리적이다. 안 B는 구현 복잡도와 소량의
자원 비용을 감수하고 VM별 fault domain, 독립 회수와 향후 backend 확장성을 얻는다. 이번
Phase 07은 두 pVM 동시 운용과 한 pVM 장애 후 생존을 완료 조건으로 삼으므로 **안 B를
권고**한다.

## 8. guest artifact와 KVM backend 이관 후보

관리 방식과 별도로 현재 selftest 결합을 어느 수준까지 해소할지 결정해야 한다.

| 안 | 내용 | 장점 | 한계 |
|---|---|---|---|
| W1 | controller가 기존 `pkvm.bin`을 legacy VM runner로 그대로 시작 | 가장 빠르게 기존 결과 재사용 | guest workload와 guest image가 분리되지 않아 새 artifact model을 충족하지 못함 |
| W2 | guest code를 test guest workload로 build·verify·package하고 최소 protected VM 경로에서 guest image를 실행 | artifact와 ioctl 책임 분리가 성립 | selftest helper 의존을 private 영역에 격리해야 함 |
| W3 | Linux-capable VMM(kvmtool 계열)로 Linux guest image를 실행하고 내부에서 guest workload를 시작 | 이후 일반 Linux guest에 유리 | Phase 07 범위를 크게 넘고 장치·boot protocol 구현 부담이 큼 |

**권고는 W2**다. Phase 07에서는 작은 test guest workload와 guest image로 lifecycle을
검증하고, public API는 backend 중립적으로 설계하여 W3를 후속 경로로 추가할 수 있게 한다.
W1은 전환 중 대조군 용도로만 유지한다.

## 9. 최종 설계와 구현 모듈

선택한 안 B와 W2의 최종 모듈 경계는 다음과 같다.

| 모듈 | 공개 여부 | 책임 |
|---|---|---|
| `include/pvm/pvm.h` | 공개 | Application용 create/start/status/stop/list API와 오류 코드 |
| `lib/pvm_client.c` | 공개 library | 요청 직렬화, socket 연결, 응답 검증 |
| `daemon/pvmd.c` | 비공개 | peer credential 인증, policy, instance registry, 상태 전이 |
| `runner/pvm_runner.c` | 비공개 | VM별 runner process entry, guest image 실행 상태와 종료 결과 보고 |
| `backend/pvm_kvm_arm64.c` | 비공개 | VM runner에만 link되는 `/dev/kvm`, protected VM/vCPU/memory/ioctl 순서와 rollback |
| `common/runner_protocol.h` | 내부 공유 | controller와 VM runner의 readiness/resource report |
| `common/sha256.[ch]` | 비공개 | 외부 crypto library 없이 artifact SHA-256 계산 |
| `common/pvm_image.[ch]` | 비공개 | guest image header 검사와 embedded workload 검증 |
| `guest/phase07_guest.S` | 비공개 | 독립적으로 build되는 arm64 test guest code source |
| `tools/pvm_image_pack.c` | 비공개 도구 | verified guest workload와 metadata를 guest image로 packaging |
| `common/protocol.h` | 내부 공유 | versioned fixed-size IPC message와 크기 상한 |
| `cli/pvmctl.c` | 공개 도구 | 수동 검증과 운영 진단용 CLI; client library만 사용 |
| `tests/phase07_app.c` | 검증용 | KVM을 모르는 Host Application 역할 |
| `tests/protocol_negative.c` | 검증용 | 잘못된 protocol version과 중복 request ID 거부 시험 |
| `build.sh` | build 전용 | framework와 guest artifact를 arm64 static binary로 build |
| `mkinitramfs.sh` | packaging 전용 | BusyBox, framework와 image를 E-1 initramfs에 배치 |
| `run.sh` | 실행 전용 | QEMU 실행과 최종 marker 판정 |
| `verify-static.sh` | 정적 검증 | KVM 경계, link map, static binary와 artifact layout 검사 |

Build 산출물인 `phase07-guest-workload.bin`, `phase07-guest.img`와 `SHA256SUMS`는
`work/build/pvm-framework/` 아래에 생성한다. source tree에는 생성물을 커밋하지 않는다.

초기 IPC는 로컬 `AF_UNIX`의 `SOCK_SEQPACKET`을 사용하고 `SO_PEERCRED`에서 얻은 실제 UID로
인증하는 방식을 권고한다. 요청 파일의 `chown`을 인증 근거로 삼던 기존 방식보다 요청 주체와
연결을 직접 묶을 수 있고 message boundary도 보존된다.

초기 상태는 아래 단방향 전이를 기본으로 한다.

```text
NEW -> VERIFIED -> CREATED -> RUNNING -> STOPPING -> STOPPED
  \       \          \          \           \
   +-------+----------+----------+------------> FAILED
```

## 10. Phase 07 재검증 매핑

| 기존 검증 | 새 프레임워크 검증 |
|---|---|
| 요청 파일 UID 65534 거부 | 비인가 client의 socket 연결/CREATE 거부 |
| 변조 `pkvm.bin` 거부 | 변조 guest workload의 packaging 거부와 변조 guest image의 create 거부를 각각 확인 |
| PID와 KVM FD 3개 이상 | API state=RUNNING 및 framework가 관리하는 VM/vCPU FD 확인 |
| STOP 요청 | client API STOP 후 STOPPED와 FD/VM runner 회수 확인 |
| Camera `SIGKILL` | Camera VM runner kill 후 FAILED, AI RUNNING, `pvmd` 응답 확인 |
| AI selftest 완료 | AI pVM의 guest workload 완료 event 확인 |
| `Mlocked: 0 kB` | 전체 destroy 뒤 기존 기준을 동일하게 확인 |

shell script는 cross-build, initramfs 생성, QEMU 시작과 최종 마커 수집에만 남긴다. Phase 07의
실제 요청, 인증, 정책, VM 상태 전이와 lifecycle 검증 로직은 C API와 C test application으로
이관한다.

## 11. 확정한 설계 결정

| ID | 확정안 | 상태 |
|---|---|---|
| D07-F1 | B: controller daemon + VM별 VM runner process | 확정 |
| D07-F2 | W2: guest workload와 guest image를 분리하고 최소 protected VM 실행 경로로 검증 | 확정 |
| D07-F3 | R1: daemon 생존 중 lifecycle을 보장하고 재시작 시 남은 VM runner 정리 | 확정 |
| D07-F4 | I1: C library와 `pvmctl` CLI를 함께 제공 | 확정 |
| D07-F5 | KVM backend를 VM runner 내부 private module로 link | 확정 |

확정 조합은 **B + W2 + R1 + I1**이다. 이 조합은 Application의 KVM 의존을 제거하면서
Phase 07 장애 격리를 실제 process boundary로 재검증하고, 영구 복구나 full Linux VMM 때문에
초기 범위가 과도하게 커지는 것을 피한다.

## 12. 구현 완료 조건

아래 조건은 모두 필수다. Host unit test나 build 성공만으로는 완료로 판정하지 않고,
`pkvm-full-clang` kernel을 사용한 E-1 QEMU session에서 runtime 조건까지 통과해야 한다.

| ID | 영역 | 완료 조건 | 필수 증빙 |
|---|---|---|---|
| CC-01 | 설계 결정 | D07-F1~F5와 최종 module/process view를 문서에서 확정한다. | 결정표와 최종 module/process view |
| CC-02 | C build | framework, client library, `pvmctl`, `pvm-runner`와 C test application이 arm64 static binary로 build된다. | build rc=0, artifact별 `file` 결과 |
| CC-03 | KVM 경계 | Application과 public header에 KVM UAPI, `/dev/kvm`, `ioctl()` 참조가 없고 KVM 호출은 VM runner의 private KVM backend에만 존재한다. | source scan 결과와 target별 link map |
| CC-04 | control path | 인증, policy, 상태 전이와 lifecycle 요청은 C API를 통해 수행되며 shell script는 build, packaging, QEMU start와 marker 수집에만 사용된다. | C test application 실행 경로와 source scan |
| CC-05 | guest artifact | guest code, guest workload와 guest image가 서로 다른 artifact로 생성되고 guest workload가 guest image 안에 포함된다. | 세 artifact 경로와 image content listing |
| CC-06 | guest workload integrity | guest workload verification 성공 후에만 packaging이 진행되고 변조 binary는 packaging 전에 거부된다. | `PVM_FRAMEWORK_WORKLOAD_VERIFIED`, `PVM_FRAMEWORK_WORKLOAD_REJECTED` |
| CC-07 | guest image integrity | 완성된 guest image가 pVM 생성 전에 검증되고 변조 image는 VM/KVM resource 생성 전에 거부된다. | `PVM_FRAMEWORK_IMAGE_VERIFIED`, `PVM_FRAMEWORK_IMAGE_REJECTED`, 거부 전후 KVM FD=0 |
| CC-08 | guest execution | pVM boot 후 guest image에 포함된 guest workload binary가 실제로 시작되고 정상 완료된다. | `GUEST_WORKLOAD_STARTED`, `GUEST_WORKLOAD_COMPLETED` |
| CC-09 | API lifecycle | create, start, status, stop, delete가 public C API에서 성공하고 허용되지 않은 상태 전이는 거부된다. | 상태 전이 log와 negative API result |
| CC-10 | 인증·policy | 비인가 UID와 허용되지 않은 role 요청이 VM 생성 전에 거부된다. | `PVM_FRAMEWORK_AUTH_DENIED`, `PVM_FRAMEWORK_POLICY_DENIED` |
| CC-11 | 다중 pVM | Camera와 AI pVM이 동시에 `RUNNING`이고 instance ID, state와 resource가 분리된다. | 역할별 `PVM_FRAMEWORK_RUNNING`과 overlap log |
| CC-12 | 장애 격리 | Camera VM runner에 `SIGKILL`을 주입하면 Camera는 `FAILED`가 되지만 AI pVM과 controller API는 계속 동작한다. | `PVM_FRAMEWORK_FAULT_ISOLATION_OK` |
| CC-13 | 정상 종료·회수 | stop/delete 후 해당 VM/vCPU FD와 VM runner가 사라지고 전체 종료 후 `Mlocked: 0 kB`가 된다. | `PVM_FRAMEWORK_STOPPED`, `PVM_FRAMEWORK_RESOURCE_RECOVERY_OK` |
| CC-14 | E-1 실측 | 동일 QEMU session에서 protected nVHE 초기화와 CC-06~CC-13이 모두 통과하며 timeout, kernel panic과 unexpected error가 없다. | QEMU rc=0, `PVM_FRAMEWORK_VALIDATION_OK`, 전체 console log |
| CC-15 | 문서·재현성 | build, packaging, 실행 명령, kernel/QEMU version, artifact digest와 log 경로가 Phase 07 문서에 기록된다. | README 결과표와 재현 명령 |

### 최종 판정 규칙

- CC-01~CC-15 중 하나라도 실패하거나 증빙이 없으면 상태는 **진행 중**이다.
- `PVM_FRAMEWORK_VALIDATION_OK` marker는 개별 검증을 모두 확인한 최종 C test application만
  출력한다.
- gcc kernel cross-validation, OP-TEE와 TA 호출은 완료 조건이 아니다.
- QEMU TCG 실측은 기능 검증이며 실물 hardware의 성능 또는 security assurance를 의미하지
  않는다.
- 모든 조건을 실측한 뒤에만 Phase 07 C framework 재수행 결과를 완료로 기록하고 관련 source,
  문서와 증빙 metadata를 completion commit으로 push한다.

## 13. 구현 및 검증 결과

| 작업 | 상태 | 결과 |
|---|---|---|
| 기능·비기능 요구사항 확정 | 완료 | FR-01~FR-14, NFR-01~NFR-09 확정 |
| public API, IPC와 상태 머신 | 완료 | C API와 versioned `SOCK_SEQPACKET` protocol 구현 |
| controller와 VM runner | 완료 | `pvmd`와 role별 `pvm-runner` process 구현 |
| guest artifact pipeline | 완료 | 독립 workload build, 선검증, image packaging과 재검증 구현 |
| protected KVM backend | 완료 | VM runner에만 link되는 private arm64 backend 구현 |
| C lifecycle test | 완료 | 정상·negative·restart·fault isolation 경로 구현 |
| 정적·artifact 검증 | 완료 | `PVM_FRAMEWORK_STATIC_BUILD_OK`, `PVM_FRAMEWORK_ARTIFACT_LAYOUT_OK` |
| E-1 QEMU 실측 | 완료 | QEMU rc=0, `PVM_FRAMEWORK_VALIDATION_OK`, kernel panic 없음 |

CC-01~CC-15의 상세 증빙, 재현 명령, artifact digest와 console log 경로는
[Phase 07 README](README.md#c-프레임워크-기반-재수행)에 기록한다.
