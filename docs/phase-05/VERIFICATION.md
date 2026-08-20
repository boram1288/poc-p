# Phase 05 검증 결과

- 판정: 완료
- 검증일: 2026-08-20 (Asia/Seoul)
- 환경: E-1 QEMU(TCG), Phase 02 kernel Image / Phase 04 selftest 바이너리 재사용
- 검증 스크립트: `work/src/tools/verify/phase05.sh`

## 재현 명령

```bash
work/src/tools/multi-pvm/mkinitramfs.sh
work/src/tools/multi-pvm/run.sh
```

Camera/AI 두 역할의 pVM을 한 QEMU 인스턴스 안에서 동시에 기동하고, 정상 동시 실행과
한쪽 pVM 강제 종료(fault injection) 두 시나리오를 순서대로 수행한다.

## 완료 조건 결과 (docs/phase-05/README.md 기준)

| 조건 | 결과 |
|---|---|
| 두 pVM의 `KVM_RUN`이 시간상 겹침 | 통과 — `MULTI_KVM_OVERLAP: camera_pid=76 camera_kvm_fds=3 ai_pid=97 ai_kvm_fds=3` |
| 각 pVM heartbeat/종료 상태 독립 기록 | 통과 — `CAMERA:`/`AI:` heartbeat가 각자 로그에 교차 기록 |
| private memory/자원 회수가 VM별 독립 | 통과 — `MULTI_NORMAL_RESULT: camera_rc=0 ai_rc=0`, 최종 `Mlocked: 0 kB` |
| 장애 주입이 다른 pVM에 전파되지 않음 | 통과 — `MULTI_FAULT_RESULT: camera_rc=137 ai_rc=0`(Camera만 SIGKILL, AI는 `AI_SURVIVOR: All ok!`) |
| panic/Oops/BUG 없음 | 통과 |

## 핵심 marker

```text
kvm [1]: Protected nVHE mode initialized successfully
MULTI_KVM_OVERLAP: camera_pid=76 camera_kvm_fds=3 ai_pid=97 ai_kvm_fds=3
MULTI_NORMAL_RESULT: camera_rc=0 ai_rc=0
AI_SURVIVOR: All ok!
MULTI_FAULT_RESULT: camera_rc=137 ai_rc=0
MULTI_PVM_ALL_OK
Mlocked:               0 kB
```

## Revision과 digest

Phase 02/04와 동일한 `pkvm-linux` revision(`7034ea6fc1e0`)의 kernel Image와 selftest
바이너리를 재사용했다.

최종 로그: `work/build/multi-pvm/console-multi-pvm.log`

Phase 07의 C VM 관리 프레임워크는 이 Phase가 확립한 동시 실행/장애 격리 판정
패턴(overlap, per-VM 독립 회수, fault isolation)을 그대로 확장해서 쓴다.
