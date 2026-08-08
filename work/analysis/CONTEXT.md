# 공용 분석 컨텍스트

## 저장소
- 경로: `/home/boram1288/orange/arch/poc-p/work/pkvm-linux`
- 원격: android-kvm.googlesource.com/linux
- 체크아웃 없음(`--no-checkout`), blob 필터(`--filter=blob:none`). 파일 내용은 필요 시 자동으로 받아온다.
- 기준 브랜치: `origin/for-android/pkvm-mainline-6.18` (= `HEAD`), tip `b3b90af8`, 2026-04-09
- 보조 브랜치: `origin/for-android/pkvm-master-6.18`
- 로컬 태그(직접 생성): `v6.18` = `7d0a66e4`, `v6.18-rc2` = `211ddde0`

## 분석 산출물 디렉터리
`/home/boram1288/orange/arch/poc-p/work/analysis`

- `t1.txt` ~ `t5.txt`: 계층별 원시 커밋 SHA (중복 포함)
- `e1.txt` ~ `e5.txt`: 상위 우선 배타 할당 적용 후 (T1 561, T2 63, T3 72, T4 11, T5 151)
- `all_raw.txt`: 배타 할당 합계 858개

## 계층 정의 (경로 기준)
- T1 코어 KVM/hyp: `arch/arm64/kvm`, `arch/arm64/include/asm/kvm*`, `arch/arm64/include/asm/virt.h`, `include/kvm`, `virt/kvm`, `Documentation/virt/kvm`
- T2 IOMMU/SMMU: `drivers/iommu`, `include/linux/iommu.h`, `include/uapi/linux/iommu.h`
- T3 장치·메모리 주변: `drivers/virt`, `drivers/vfio`, `drivers/dma-buf`, `kernel/dma`, `include/linux/swiotlb.h`, `drivers/misc`, `drivers/virtio`
- T4 셀프테스트: `tools/testing/selftests/kvm`, `tools/testing/selftests/hyp-trace`
- T5 arm64 기타: `arch/arm64/kernel`, `arch/arm64/configs`

## 필터
`ANDROID:` / `SQUASH: ANDROID` / `BACKPORT: ANDROID` 계열만 채택.
`ANDROID: GKI` / `ANDROID: INCFS` / `ANDROID: OWNERS`는 제외.
`UPSTREAM:` / `FROMGIT:` / `FROMLIST:`는 제외(이미 상류 반영분).

## ACK 전용 파일 (upstream v6.18에 없음, 머지 불가)
`arch/*/configs/*defconfig`, `BUILD.bazel`, `*.bzl`, `*.fragment`, `build.config`, `OWNERS`,
`TEST_MAPPING`, `tools/testing/selftests/android`, `tools/testing/kunit`, `tools/testing/android`,
`android/`, `gki/`, `kmi/`

## 주의: 기존 문서 수치와의 차이
`research/pkvm-kernel-version.md` 8.1절은 최종 머지 대상을 **673커밋**으로 기록했다.
이번 재현에서 T1(561)과 T2(63)는 일치하나 T3/T4/T5가 다르다.
문서 수치를 그대로 신뢰하지 말고, 본인 작업 범위 안에서는 실측으로 재확인한다.
차이를 발견하면 원인과 함께 보고한다.

## 문체 규칙
한글 UTF-8. 이모지 금지. 문장은 짧게. 추측과 확인 사실을 구분한다.
