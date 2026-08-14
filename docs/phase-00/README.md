# Phase 00: 범위와 환경 확정

- 상태: 완료
- 목적: 검증 목표, 환경 프로필, 디렉터리 규칙과 성공 판정을 작업 전에 고정한다.
- 환경: 해당 없음
- 관련 목표: G-1 ~ G-11

## 선행 조건

- [README](../../README.md)의 프로젝트 목표와 성공 조건 6개
- 레퍼런스 시나리오의 데이터 보호 경계 정의

## 결정된 범위

PoC는 README의 최종 목표를 다음 순서로 분해해 검증한다.

1. 커널과 EL2 Hypervisor 빌드
2. protected 모드 부팅
3. 단일 pVM 생성/실행
4. Host CPU의 pVM private page 접근 차단
5. pVM 2개 동시 운용
6. OP-TEE 공존과 암호화/복호화 서비스 호출
7. Host 요청 기반 pVM 동적 수명주기 관리
8. USB 카메라와 NVIDIA GPU의 직접 할당과 S2MPU 기반 DMA 격리
9. Camera pVM에서 AI pVM으로의 zero-copy 프레임 전달
10. AI pVM의 GPU 추론과 결과만 반환

1~4는 현재 환경에서 완료했다. 5~7은 QEMU 환경에서, 8~10은 실제 하드웨어에서 수행한다.
Phase 대응은 [전체 수행 계획](../PLAN.md)의 5절을 따른다.

## 환경 분리

| 프로필 | 환경 | 용도 | 보안 주장 범위 |
|---|---|---|---|
| E-1 | x86_64 + QEMU TCG + pKVM | 빠른 기능 검증 | CPU 실행 및 메모리 매핑 경로 |
| E-2 | QEMU v8 + TF-A + OP-TEE | Secure World 공존 | OP-TEE와 pKVM의 통합 동작 |
| E-3 | arm64 + S2MPU + USB 카메라 + NVIDIA GPU | 장치 할당, DMA 격리, 실제 추론 | 장치 DMA를 포함한 기밀성 |

QEMU TCG 결과만으로 실제 arm64 하드웨어의 기밀성을 주장하지 않는다. E-3는 아직 확보하지
않았다.

E-3는 이후 D-9 조사에 따라 E-3a(QEMU S2MPU 에뮬레이션)와 E-3b(실장치)로 분리했다.
현재 정의는 [전체 수행 계획](../PLAN.md)의 3절을 따른다.

## 경로 규칙

- 문서: `docs/phase-{nn}/`
- 소스: `work/src/`
- 빌드 및 실행 결과: `work/build/`
- 전체 계획: `docs/PLAN.md`
- 프로젝트 안내: `README.md`

## 완료 조건과 근거

- 목표별 완료 조건이 [전체 수행 계획](../PLAN.md)에 정의되어 있다.
- README 성공 조건 6개가 목표 ID와 Phase에 각각 매핑되어 있다.
- 현재 환경과 목표 통합 환경이 분리되어 있다.
- Git 추적 대상과 재생성 가능한 대용량 산출물의 경계가 `.gitignore`에 반영되어 있다.

## 한계

이 Phase는 범위와 판정 기준만 고정한다. 어떤 기술적 검증도 수행하지 않는다.

범위는 고정이 아니다. Phase 07의 이미지 검증 방식, Phase 08의 하드웨어 구성, Phase 09의
전달 방식은 각각 D-6, D-9, D-8에서 확정된 뒤 이 문서에 반영한다.
