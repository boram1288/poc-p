# Phase 06: OP-TEE 공존

- 상태: 미착수
- 목적: Secure World의 OP-TEE와 Normal World의 pKVM이 같은 시스템에서 함께 동작하는지 확인한다.
- 환경: E-2
- 관련 목표: G-6
- 관련 결정: D-5

## 선행 조건

- Phase 02의 pKVM 커널 구성
- Phase 03, 04의 E-1 결과
- QEMU v8, TF-A, OP-TEE 빌드 환경

현재 QEMU 4.2.1 TCG 검증 환경과 분리해 QEMU v8, TF-A, OP-TEE 부트 체인을 구성한다.
E-1과 E-2의 결과를 하나로 섞지 않는다.

## 계획

1. OP-TEE 공식 QEMU v8 기준 빌드와 부팅을 재현한다.
2. Secure World와 Normal World UART 로그를 각각 확보한다.
3. Normal World 커널을 Phase 02의 pKVM 커널로 교체한다.
4. protected nVHE 초기화와 OP-TEE 초기화를 같은 부팅에서 확인한다.
5. pVM selftest 실행 중 `xtest` 또는 최소 TA 호출을 수행한다.
6. 카메라 영상에 해당하는 데이터의 암호화/복호화를 TA로 처리한다.
7. 종료 및 재실행 시 양쪽 상태가 정상적으로 회수되는지 확인한다.

## 완료 조건

- TF-A, OP-TEE, Linux와 pKVM 초기화 로그가 한 실행에서 확인되어야 한다.
- OP-TEE TA 호출과 pVM 게스트 실행이 모두 성공해야 한다.
- 암호화한 데이터를 같은 세션에서 복호화해 원본과 일치함을 확인해야 한다.
- 한쪽 작업이 다른 실행 환경을 중단시키지 않아야 한다.

## 예정 산출물

- 통합 소스 및 도구: `work/src/optee-pkvm/`
- 빌드 및 로그: `work/build/optee-pkvm/`
- 결과 문서: 이 디렉터리에 추가

## 한계

이 Phase는 공존과 서비스 호출 성립만 확인한다. 키 관리, 비밀 프로비저닝, 암호화 저장
파이프라인은 범위 밖이다.

QEMU v8 기반 결과이므로 실제 하드웨어의 Secure World 동작을 대신하지 않는다.

pVM 내부에서 OP-TEE를 직접 호출하는 경로는 다루지 않는다. pVM 실행 중 Host 측 OP-TEE
호출이 성립하는지까지만 확인한다.
