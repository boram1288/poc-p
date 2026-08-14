# Phase 06: OP-TEE 공존

- 상태: 미착수
- 목적: Secure World의 OP-TEE와 Normal World의 pKVM이 같은 시스템에서 함께 동작하는지 확인한다.

## 환경

현재 QEMU 4.2.1 TCG 검증 환경과 분리해 QEMU v8, TF-A, OP-TEE 부트 체인을 구성한다.
Phase 03과 04의 결과를 이 환경에서 다시 확인한다.

## 계획

1. OP-TEE 공식 QEMU v8 기준 빌드와 부팅을 재현한다.
2. Secure World와 Normal World UART 로그를 각각 확보한다.
3. Normal World 커널을 Phase 02의 pKVM 커널로 교체한다.
4. protected nVHE 초기화와 OP-TEE 초기화를 같은 부팅에서 확인한다.
5. pVM selftest 실행 중 `xtest` 또는 최소 TA 호출을 수행한다.
6. 종료 및 재실행 시 양쪽 상태가 정상적으로 회수되는지 확인한다.

## 완료 조건

- TF-A, OP-TEE, Linux와 pKVM 초기화 로그가 한 실행에서 확인되어야 한다.
- OP-TEE TA 호출과 pVM 게스트 실행이 모두 성공해야 한다.
- 한쪽 작업이 다른 실행 환경을 중단시키지 않아야 한다.

## 예정 산출물

- 통합 소스 및 도구: `work/src/optee-pkvm/`
- 빌드 및 로그: `work/build/optee-pkvm/`
- 결과 문서: 이 디렉터리에 추가
