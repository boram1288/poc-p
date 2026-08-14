# pKVM Protected VM PoC

이 저장소는 Android pKVM 패치를 upstream Linux v6.18에 적용하고, x86_64 호스트의
QEMU TCG 환경에서 protected VM(pVM)의 생성·실행과 메모리 격리를 검증하는 PoC다.

현재 결과는 기능 검증이다. Host CPU가 pVM private page에 접근하지 못하는 것은 확인했지만,
SMMU/IOMMU 기반 DMA 격리와 실제 ARM 하드웨어에서의 기밀성은 아직 검증하지 않았다.

## 현재 상태

Linux v6.18 기반 커널 빌드, QEMU protected 부팅, 단일 pVM 실행과 Host CPU 접근 차단까지
완료했다. 다중 pVM, OP-TEE 공존과 SMMU/IOMMU 기반 DMA 격리는 후속 단계다.

Phase별 상태, 완료 조건과 검증 수준은 [전체 수행 계획](docs/PLAN.md)을 기준으로 관리한다.

## 문서 구조

- [전체 수행 계획](docs/PLAN.md): 목표, Phase 순서, 완료 조건, 현재 상태와 남은 작업
- `docs/phase-{nn}/`: 각 Phase에서 작성한 조사, 절차와 결과
- [커널 버전 및 패치 소스 조사](docs/phase-01/pkvm-kernel-version.md): Linux v6.18 결정 근거
- [work 디렉터리 안내](work/README.md): 소스와 빌드 산출물 관리 규칙

## 작업 디렉터리

```text
work/
├── src/
│   ├── pkvm-linux/       Linux v6.18 + pKVM 패치 소스 트리
│   └── tools/            분석 및 QEMU 실행 도구
└── build/
    ├── analysis/         커밋 집계·분류 결과
    ├── pkvm-full-clang/  clang 커널 빌드 산출물
    ├── pkvm-full-gcc/    gcc 커널 빌드 산출물
    ├── pkvm-qemu/        부팅용 initramfs와 콘솔 로그
    └── pkvm-pvm/         pVM selftest 산출물과 콘솔 로그
```

`work/src/tools`의 프로젝트 도구는 Git으로 관리한다. 외부 커널 소스와 빌드 산출물은
용량이 크거나 재생성 가능하므로 Git에서 제외한다. 모든 명령은 별도 언급이 없으면 저장소
루트에서 실행한다.

## 검증 경계

현재 결과는 QEMU TCG에서 확인한 기능 검증이다. SMMU/IOMMU 기반 DMA 격리, OP-TEE 통합과
실제 ARM 하드웨어의 기밀성은 아직 검증하지 않았으며 상세 구분은 전체 수행 계획을 따른다.
