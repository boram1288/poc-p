# Phase 00: 범위와 환경 확정

- 상태: 완료
- 목적: 검증 목표, 환경 프로필, 디렉터리 규칙과 성공 판정을 작업 전에 고정한다.

## 결정된 범위

현재 PoC는 pKVM의 기능 경로를 단계적으로 검증한다.

1. 커널과 EL2 하이퍼바이저 빌드
2. protected 모드 부팅
3. 단일 pVM 생성·실행
4. Host CPU의 pVM private page 접근 차단
5. pVM 2개 동시 운용
6. OP-TEE 공존
7. SMMU/IOMMU 기반 DMA 격리

1~4는 현재 환경에서 완료했다. 5~7은 별도 Phase로 남긴다.

## 환경 분리

| 환경 | 용도 | 보안 주장 범위 |
|---|---|---|
| x86_64 + QEMU TCG + pKVM | 빠른 기능 검증 | CPU 실행 및 메모리 매핑 경로 |
| QEMU v8 + TF-A + OP-TEE | Secure World 공존 | OP-TEE와 pKVM의 통합 동작 |
| ARM + SMMUv3 | DMA 보안 검증 | 장치 DMA를 포함한 기밀성 |

QEMU TCG 결과만으로 실제 ARM 하드웨어의 기밀성을 주장하지 않는다.

## 경로 규칙

- 문서: `docs/phase-{nn}/`
- 소스: `work/src/`
- 빌드 및 실행 결과: `work/build/`
- 전체 계획: `docs/PLAN.md`
- 프로젝트 안내: `README.md`

## 완료 근거

- 목표별 완료 조건이 [전체 수행 계획](../PLAN.md)에 정의되어 있다.
- 현재 환경과 목표 통합 환경이 분리되어 있다.
- Git 추적 대상과 재생성 가능한 대용량 산출물의 경계가 `.gitignore`에 반영되어 있다.
