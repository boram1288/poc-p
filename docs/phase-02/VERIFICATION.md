# Phase 02 검증 결과

- 판정: 완료
- 검증일: 2026-08-20 (Asia/Seoul)
- 환경: clang-18/ld.lld-18 크로스 빌드, `poc-reproduce` 저장소 안의 `work/src/pkvm-linux`
  submodule만 사용 (`../poc-p` 참조 없음)
- 검증 스크립트: `work/src/tools/verify/phase02.sh`

## 재현 명령

```bash
make -C work/src/pkvm-linux O=work/build/pkvm-full-clang ARCH=arm64 LLVM=1 \
  CC=clang-18 LD=ld.lld-18 defconfig
work/src/pkvm-linux/scripts/config --file work/build/pkvm-full-clang/.config \
  -e KVM -e PKVM_DEBUG -e PKVM_DISABLE_STAGE2_ON_PANIC -e PKVM_STACKTRACE \
  -d ARM_SMMU_V3 -d ARM_SMMU_V3_PKVM -e ARM_SMMU_V3_PKVM_PV \
  -e PKVM_PVIOMMU -e VFIO_PKVM_IOMMU
work/src/pkvm-linux/scripts/config --file work/build/pkvm-full-clang/.config \
  -m PKVM_SMC_FILTER -m PKVM_IOMMU_TEMPLATE
make -C work/src/pkvm-linux O=work/build/pkvm-full-clang ARCH=arm64 LLVM=1 \
  CC=clang-18 LD=ld.lld-18 olddefconfig
make -C work/src/pkvm-linux O=work/build/pkvm-full-clang ARCH=arm64 LLVM=1 \
  CC=clang-18 LD=ld.lld-18 -j"$(nproc)"
```

위 절차는 `work/src/tools/verify/phase02.sh`가 그대로 자동 실행하며, 빌드 로그에
`error:`/`warning:` 문자열이 있으면 즉시 실패로 판정한다.

## 완료 조건 결과 (docs/phase-02/README.md 기준)

| 조건 | 결과 |
|---|---|
| `arch/arm64/boot/Image` 생성 | 통과 |
| `vmlinux` 생성 | 통과 |
| `arch/arm64/kvm/hyp/nvhe/kvm_nvhe.o` 생성 | 통과 |
| `drivers/misc/pkvm-smc/pkvm_smc.ko` 생성 | 통과 |
| `drivers/misc/pkvm-iommu-temp/pkvm_iommu_temp.ko` 생성 | 통과 |
| 빌드 error/warning 없음 | 통과 |

## Revision과 digest

| 항목 | 값 |
|---|---|
| `pkvm-linux` submodule revision | `7034ea6fc1e0b031127130666a7d1d8990dc84d1` (build-success-394-334) |
| kernel Image SHA-256 | `f20572a5c6113ca85da66c58298a406f98e5bdd68c4a4b1ef29bce08e7578495` |

빌드 로그: `work/build/pkvm-full-clang/build.log`
defconfig/olddefconfig 로그: `work/build/verify/phase-02/defconfig.log`,
`work/build/verify/phase-02/olddefconfig.log`

이후 Phase 03~07은 이 Phase의 `work/build/pkvm-full-clang` kernel Image/vmlinux를
그대로 재사용한다(다시 빌드하지 않음).
