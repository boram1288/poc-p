# Phase 02: 소스 통합과 커널 빌드

- 상태: 완료
- 목적: Linux v6.18 위에 pKVM 검증 트리를 구성하고 두 툴체인에서 빌드한다.
- 환경: E-1
- 관련 목표: G-1
- 관련 결정: D-1, D-2, D-7
- 소스: `work/src/pkvm-linux/`
- 빌드 산출물: `work/build/pkvm-full-clang/`, `work/build/pkvm-full-gcc/`
- 분석 결과: `work/build/analysis/`

## 선행 조건

- Phase 01의 커널 버전과 패치 소스 결정
- clang 18과 aarch64 gcc 크로스 툴체인

## 목표

Linux v6.18 위에 pKVM 코어, S2MPU 관련 드라이버(`ARM_SMMU_V3`, `PKVM_PVIOMMU`) 및 EL2
벤더 모듈을 포함한 검증 트리를 구성하고 clang과 gcc 양쪽에서 빌드한다. S2MPU 드라이버는
Phase 08의 DMA 격리 검증을 위한 사전 준비다.

## 소스 준비

```bash
git clone --filter=blob:none --single-branch \
    -b for-android/pkvm-mainline-6.18 \
    https://android-kvm.googlesource.com/linux \
    work/src/pkvm-linux

cd work/src/pkvm-linux
git tag v6.18 7d0a66e4bb9081d75c82ec4957c50034cb0ea449
git tag v6.18-rc2 211ddde0823f1442e4ad052a2f30f050145ccada
```

검증한 `pkvm-6.18-full` 브랜치는 다음 순서로 구성했다.

1. v6.18에서 작업 브랜치를 만든다.
2. `pkvm-master-6.18`의 394커밋을 v6.18-rc2에서 v6.18로 리베이스한다.
3. `pkvm-mainline-6.18`의 후속 커밋과 v6.18에 없는 의존성을 시간순으로 적용한다.
4. 불필요한 ACK 벤더 훅을 제외하고 로컬 빌드 수정 5건을 적용한다.

후속 커밋 후보는 [pick-candidates.txt](pick-candidates.txt)에 보존한다. 이 파일은 빌드 중
중복/빈 커밋과 대체 커밋을 정리하기 전 목록이므로 그대로 `cherry-pick`하지 않는다. 경로 기반
658커밋 목록은 [Phase 01의 target-commits.tsv](../phase-01/target-commits.tsv)에 있으며,
실제 검증 트리는 `pkvm-6.18-full` 브랜치의 이력을 기준으로 삼는다.

## 빌드 설정

먼저 소스트리의 in-tree 빌드 흔적을 제거한다.

```bash
cd work/src/pkvm-linux
make ARCH=arm64 mrproper
```

pKVM 및 S2MPU 기능을 위해 다음 설정을 활성화한다. 설정 심볼 이름은 커널 소스의 표기를
그대로 쓴다.

```bash
./scripts/config --file "$O/.config" \
    -e KVM -e PKVM_DEBUG -e PKVM_DISABLE_STAGE2_ON_PANIC -e PKVM_STACKTRACE \
    -e ARM_SMMU_V3 -e ARM_SMMU_V3_PKVM -e ARM_SMMU_V3_PKVM_PV \
    -e PKVM_PVIOMMU -e VFIO_PKVM_IOMMU
./scripts/config --file "$O/.config" -m PKVM_SMC_FILTER -m PKVM_IOMMU_TEMPLATE
```

EL2 벤더 모듈은 Kconfig 제약으로 `m`으로 설정해야 한다.

## clang 빌드

```bash
cd work/src/pkvm-linux
O="$PWD/../../build/pkvm-full-clang"
make O="$O" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 defconfig
# 위 scripts/config 명령 실행
make O="$O" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 olddefconfig
make O="$O" ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 -j"$(nproc)"
```

## gcc 빌드

```bash
cd work/src/pkvm-linux
O="$PWD/../../build/pkvm-full-gcc"
make O="$O" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    CC=aarch64-linux-gnu-gcc-9 defconfig
# 위 scripts/config 명령 실행
make O="$O" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    CC=aarch64-linux-gnu-gcc-9 olddefconfig
make O="$O" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    CC=aarch64-linux-gnu-gcc-9 -j"$(nproc)"
```

## 완료 조건

다음 파일이 생성되고 빌드가 오류/경고 없이 끝나야 한다.

- `arch/arm64/boot/Image`
- `vmlinux`
- `arch/arm64/kvm/hyp/nvhe/kvm_nvhe.o`
- `drivers/misc/pkvm-smc/pkvm_smc.ko`
- `drivers/misc/pkvm-iommu-temp/pkvm_iommu_temp.ko`

## 확인된 결과

| 항목 | clang 18.1.8 | gcc 9.4.0 |
|---|---:|---:|
| 종료 코드 | 0 | 0 |
| 오류/경고 | 0/0 | 0/0 |
| Image | 40.5M | 49.4M |
| vmlinux | 443.6M | 228.8M |
| kvm_nvhe.o | 9.3M | 5.4M |
| `__kvm_nvhe_` 심볼 | 6,724 | 1,723 |

## 빌드 수정과 주의점

검증 트리에는 ACK 헤더 보충, 무관한 S2MPU 벤더 훅 제거, DMA-BUF 링키지 수정과
master/mainline의 EL2 모듈 API 차이 보정 등 로컬 수정 5건이 포함됐다.

- 동일 소스트리에서 in-tree와 out-of-tree 빌드를 섞지 않는다.
- 중단된 병렬 빌드에서 `fixdep`의 `.o.d` 오류가 나면 동일 빌드를 다시 실행해 상태를 복구한다.
- 충돌 해결 시 v6.18-rc2 이후 추가된 PFN 및 overflow 검사를 유지한다.
- 같은 제목의 master/mainline 커밋도 변경 파일 집합을 비교한다.

## 한계

빌드 성공은 실행 검증이 아니다. 부팅과 pVM 동작은 Phase 03, 04에서 판정한다.

S2MPU 관련 드라이버는 빌드에 포함됐을 뿐 동작을 확인하지 않았다. E-1에는 대상 하드웨어가
없다. 실제 동작은 Phase 08에서 확인한다.
