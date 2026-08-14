# Phase 05: 다중 pVM 운용

- 상태: 미착수
- 목적: Camera와 AI 역할을 모사하는 protected VM 2개를 동시에 운용한다.

## 선행 조건

- Phase 04의 단일 pVM 생성·실행과 자원 회수 성공
- 다중 VM을 제어할 VMM 경로 결정
- 각 pVM에 넣을 최소 독립 workload와 식별 마커 정의

## 계획

1. 직접 KVM ioctl을 사용하는 최소 VMM과 crosvm의 구현 비용을 비교한다.
2. pVM A와 pVM B에 독립적인 guest memory와 vCPU를 할당한다.
3. 두 pVM을 동시에 실행하고 각 heartbeat를 수집한다.
4. 서로 다른 private memory marker가 반대 pVM 또는 Host에서 노출되지 않는지 확인한다.
5. 한 pVM의 비정상 종료가 다른 pVM의 실행에 영향을 주지 않는지 확인한다.
6. 두 VM teardown 후 pinned/locked memory가 원상 복귀하는지 확인한다.

## 완료 조건

- 두 pVM의 `KVM_RUN`이 시간상 겹쳐야 한다.
- 각 pVM의 heartbeat와 종료 상태가 독립적으로 기록되어야 한다.
- private memory와 자원 회수가 VM별로 독립적이어야 한다.
- 실패 주입 결과가 다른 pVM에 전파되지 않아야 한다.

## 예정 산출물

- VMM 소스: `work/src/tools/multi-pvm/`
- 빌드 및 로그: `work/build/multi-pvm/`
- 결과 문서: 이 디렉터리에 추가
