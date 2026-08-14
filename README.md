# pKVM Protected VM PoC

이 저장소는 Android pKVM 패치를 upstream Linux v6.18에 적용하고, x86_64 호스트의
QEMU TCG 환경에서 protected VM(pVM)의 생성·실행과 메모리 격리를 검증하는 PoC다.

현재 결과는 기능 검증이다. Host CPU가 pVM private page에 접근하지 못하는 것은 확인했지만,
SMMU/IOMMU 기반 DMA 격리와 실제 ARM 하드웨어에서의 기밀성은 아직 검증하지 않았다.

## 현재 상태

| 항목 | 상태 | 근거 |
|---|---|---|
| 타깃 커널과 패치 소스 결정 | 완료 | Linux v6.18, `pkvm-master-6.18` + `pkvm-mainline-6.18` |
| pKVM 커널 빌드 | 완료 | 721커밋 검증 트리, clang 18.1.8 및 gcc 9.4.0 |
| QEMU protected 부팅 | 완료 | `Protected nVHE mode initialized successfully` 관측 |
| 단일 pVM 생성·실행 | 완료 | pKVM selftest `PASS` |
| Host CPU의 pVM private page 접근 차단 | 완료 | `Caught expected segfault` 관측 |
| pVM 2개 동시 운용 | 미착수 | Phase 05 |
| OP-TEE와 pKVM 공존 | 미착수 | Phase 06 |
| IOMMU 기반 DMA 격리 | 미검증 | 현재 QEMU가 SMMU와 할당 장치를 제공하지 않음 |

## 문서 구조

- [전체 수행 계획](docs/PLAN.md): Phase 순서, 완료 조건, 현재 상태와 남은 작업
- [Phase 00: 범위와 환경](docs/phase-00/README.md)
- [Phase 01: 커널 및 패치 결정](docs/phase-01/README.md)
- [Phase 02: 소스 통합과 커널 빌드](docs/phase-02/README.md)
- [Phase 03: QEMU protected 부팅](docs/phase-03/README.md)
- [Phase 04: 단일 pVM과 메모리 격리](docs/phase-04/README.md)
- [Phase 05: 다중 pVM](docs/phase-05/README.md)
- [Phase 06: OP-TEE 공존](docs/phase-06/README.md)
- [Phase 07: 종합 결과](docs/phase-07/README.md)

조사 근거는 [커널 버전 및 패치 소스 조사](docs/phase-01/pkvm-kernel-version.md)에 있다.

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
용량이 크거나 재생성 가능하므로 Git에서 제외한다. 자세한 규칙은
[work 디렉터리 안내](work/README.md)를 따른다.

## 재현 순서

1. [전체 수행 계획](docs/PLAN.md)에서 Phase의 선행 조건과 완료 조건을 확인한다.
2. Phase 01 문서에 따라 커널 버전과 패치 집합을 확인한다.
3. Phase 02에서 커널 트리를 구성하고 clang 또는 gcc로 빌드한다.
4. Phase 03에서 protected 모드 부팅과 EL2 초기화를 확인한다.
5. Phase 04에서 pVM selftest와 private page 접근 차단을 확인한다.
6. Phase 05와 06에서 다중 pVM 및 OP-TEE 통합 검증을 확장한다.

모든 명령은 별도 언급이 없으면 저장소 루트에서 실행한다.

## 검증 경계

- QEMU TCG가 arm64 EL2를 에뮬레이션하므로 pKVM 기능 경로는 검증할 수 있다.
- 현재 환경의 `KVM_CAP_ARM_EL2=0`은 nested virtualization 미지원 상태이며 pVM과는 별개다.
- QEMU가 SMMU와 assignable device를 제공하지 않아 DMA 격리는 검증되지 않았다.
- OP-TEE, TF-A 및 Secure World가 포함된 통합 환경은 Phase 06의 별도 목표다.
