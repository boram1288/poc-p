# Phase 05: 다중 pVM 운용

- 상태: 완료
- 목적: Camera와 AI 역할을 모사하는 protected VM 2개를 동시에 운용한다.
- 환경: E-1
- 관련 목표: G-5
- 관련 결정: D-4
- 실행 도구: `work/src/tools/multi-pvm/`
- 실행 산출물: `work/build/multi-pvm/`

## 선행 조건

- Phase 04의 단일 pVM 생성/실행과 자원 회수 성공
- 다중 VM을 제어할 VMM 경로 결정 (D-4)
- 각 pVM에 넣을 최소 독립 Workload와 식별 마커 정의

## VMM 경로 결정

직접 KVM ioctl을 사용하는 Phase 04의 arm64 pKVM selftest를 두 프로세스로 조정하는 최소
오케스트레이터를 선택했다. crosvm은 범용 장치 모델과 Rust 빌드 계층을 추가하지만 이 Phase는
사전 정의된 단일 vCPU pVM 두 개의 동시 운용만 요구한다. 검증된 selftest를 재사용하면 각
프로세스가 별도의 KVM VM, vCPU, private memory를 소유하면서 VMM 의존성을 최소화할 수 있다.

이에 따라 D-4를 최소 오케스트레이터 사용으로 확정했다.

## 구현 및 실행

- `run-two-pvms.sh`: Camera/AI 역할 selftest 실행, 시작 장벽, 로그 prefix, 실패 주입
- `mkinitramfs.sh`: 정적 pKVM selftest와 오케스트레이터를 포함한 initramfs 생성
- `run.sh`: QEMU protected nVHE 실행과 핵심 마커 출력

각 역할 프로세스는 KVM 관련 FD를 3개 이상 확보하면 일시 정지된다. 두 역할이 모두 준비된
뒤 동시에 재개하므로, 서로 다른 KVM VM/vCPU 객체가 공존하는 상태를 실행 전에 고정해
기록한다.

```bash
work/src/tools/multi-pvm/mkinitramfs.sh
work/src/tools/multi-pvm/run.sh
```

기본 로그는 `work/build/multi-pvm/console-multi-pvm.log`에 생성된다. 2026-08-16 재실행
로그는 `work/build/multi-pvm/console-multi-pvm-rerun.log`에 보존했다.

## 검증 절차

1. Camera와 AI 프로세스를 각각 KVM VM/vCPU 준비 상태에서 정지한다.
2. 두 프로세스의 KVM FD와 서로 다른 private memory 매핑을 기록한다.
3. 두 프로세스를 동시에 재개하고 역할별 heartbeat와 완료 상태를 수집한다.
4. 별도 장애 시나리오에서 Camera 프로세스에 `SIGKILL`을 주입한다.
5. AI 프로세스가 영향 없이 전체 selftest를 완료하는지 확인한다.
6. 모든 프로세스 종료 후 `Mlocked`가 0으로 복귀하는지 확인한다.

## 완료 조건

- 두 pVM의 `KVM_RUN`이 시간상 겹쳐야 한다.
- 각 pVM의 heartbeat와 종료 상태가 독립적으로 기록되어야 한다.
- private memory와 자원 회수가 VM별로 독립적이어야 한다.
- 실패 주입 결과가 다른 pVM에 전파되지 않아야 한다.

## 결과

QEMU 8.2.2 TCG, `cortex-a57`, 4 vCPU, 3 GiB 메모리에서 다음 결과를 확인했다.

| 검사 | 결과 및 마커 |
|---|---|
| protected nVHE | `Protected nVHE mode initialized successfully` |
| 동시 KVM 객체 | `MULTI_KVM_OVERLAP: ... camera_kvm_fds=4 ... ai_kvm_fds=3` |
| 역할별 heartbeat | `CAMERA: Guest heartbeat.`, `AI: Guest heartbeat.` |
| 독립 private memory | Camera `0xffffa2c22000`, AI `0xffff9afeb000` 등 서로 다른 매핑 |
| 정상 종료 | `MULTI_NORMAL_RESULT: camera_rc=0 ai_rc=0` |
| 장애 격리 | `MULTI_FAULT_RESULT: camera_rc=137 ai_rc=0` |
| 생존 pVM 완주 | `AI_SURVIVOR: All ok!` |
| VM별 회수 | 각 역할의 `Host VmLck after teardown: 0` |
| 전체 회수 | `Mlocked: 0 kB` |
| 최종 판정 | `MULTI_PVM_ALL_OK`, `MULTI_PVM_RUNNER_RC=0`, QEMU rc=0 |

정상 시나리오의 두 역할은 regular page와 THP 경로에서 각각 private page Host 접근 차단,
guest 완료, poison 및 teardown을 독립적으로 통과했다. 장애 시나리오에서는 Camera VMM만
강제 종료됐고 AI pVM은 두 메모리 경로와 자원 회수까지 완료했다.

## 한계

이 Phase의 pVM은 Camera와 AI 역할을 모사할 뿐 장치를 할당받지 않는다. 카메라 역할 장치와
추론 역할 장치의 할당은 Phase 08에서 다룬다.

두 pVM 사이의 데이터 전달도 다루지 않는다. Phase 09의 대상이다.

동시성 증빙은 서로 다른 프로세스가 KVM VM/vCPU FD를 동시에 보유한 상태와 장벽 해제 뒤
양쪽 heartbeat/완료 로그를 결합한 기능 증빙이다. QEMU TCG 내부의 명령 단위 실행 시간을
계측하거나 성능상 병렬성을 주장하지 않는다.

Host 요청에 따른 동적 생성과 이미지 검증은 Phase 07에서 다룬다. 이 Phase는 미리 정의된
pVM 2개를 띄우는 것까지만 확인한다.
