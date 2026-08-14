# defconfig pKVM 옵션 수집

## 0. 범위와 방법

기준 트리: `HEAD` (`origin/for-android/pkvm-mainline-6.18`, tip `b3b90af8`).
비교 기준: 로컬 태그 `v6.18` (`7d0a66e4`).

대상 파일이다.
- `arch/arm64/configs/gki_defconfig` (`git show HEAD:...`, 797줄)
- `arch/arm64/configs/microdroid_defconfig` (`git show HEAD:...`, 180줄)

추출 키워드다. `KVM`, `PKVM`, `PVIOMMU`, `NVHE`, `PROTECTED`, `VFIO`, `PTDUMP`, `ARM_SMMU`, `IOMMU`, `VIRTIO`, `DMA_BUF`, `CMDLINE`, `HYP`.
`ARM_SMMU`, `NVHE`, `HYP`, `PROTECTED`(CMDLINE 문자열 제외)는 두 defconfig 어디에도 없었다. 키워드에 정확히 일치하진 않지만 같은 계열인 `UDMABUF`, `DMABUF_HEAPS`, `DMABUF_SYSFS_STATS`(`DMA_BUF`가 아니라 `DMABUF`로 붙어 있음)도 함께 수집했다.

upstream 존재 확인은 `git show v6.18:<Kconfig 경로>`로 심볼 정의를 직접 읽었다. 확인한 파일이다.
`arch/arm64/kvm/Kconfig`, `virt/kvm/Kconfig`, `drivers/iommu/Kconfig`, `drivers/iommu/arm/Kconfig`, `drivers/vfio/Kconfig`, `drivers/vfio/platform/Kconfig`, `arch/arm64/Kconfig`, `drivers/virt/Kconfig`, `drivers/virt/coco/pkvm-guest/Kconfig`, `drivers/virtio/Kconfig`, `drivers/dma-buf/Kconfig`, `drivers/dma-buf/heaps/Kconfig`, `drivers/ptp/Kconfig`, `drivers/block/Kconfig`, `drivers/char/Kconfig`, `net/vmw_vsock/Kconfig`, `fs/fuse/Kconfig`.

도입 패치 탐색은 `git log -S'<문자열>' -- <파일>`을 파일 단위로 좁혀서 실행했다. 저장소가 `--filter=blob:none` 부분 클론이라 전체 트리 대상 `git grep`/`git log -S`는 네트워크 blob 페치 비용 때문에 반복적으로 타임아웃(90~150초)이 났다. 특정 파일로 좁힌 검색은 대부분 성공했다.

## 1. 옵션 표

| 심볼 | gki 값 | microdroid 값 | upstream v6.18 존재 | 도입 패치(ACK 전용인 경우) | 용도 |
|---|---|---|---|---|---|
| `KVM` | `y` | (없음) | 존재. `arch/arm64/kvm/Kconfig` menuconfig | - | 호스트 KVM 지원. microdroid는 게스트 커널이라 미설정 |
| `PTDUMP_STAGE2_DEBUGFS` | `y` | (없음) | 존재. `arch/arm64/kvm/Kconfig`, `depends on KVM && DEBUG_KERNEL && DEBUG_FS && ARCH_HAS_PTDUMP` | - | stage-2 페이지테이블 debugfs 노출 |
| `VFIO` | `y` | (없음) | 존재. `drivers/vfio/Kconfig` menuconfig | - | VFIO 프레임워크 |
| `VFIO_PLATFORM` | `y` | (없음) | 존재. `drivers/vfio/platform/Kconfig` | - | 플랫폼 장치 VFIO 지원 |
| `VFIO_PKVM_IOMMU` | `y` | (없음) | **없음. ACK 전용** | `6b83b3c7cdc6b090d99ef54ca5351b5773c77227` "ANDROID: drivers/vfio: Add VFIO_PKVM_IOMMU" (2023-11-13) | pKVM 보호 게스트에 장치 할당 시 필요. `depends on ARM64` |
| `IOMMU_IO_PGTABLE_ARMV7S` | `y` | (없음) | 존재. `drivers/iommu/Kconfig` | - | ARMv7s 포맷 IOMMU 페이지테이블 |
| `PKVM_PVIOMMU` | `y` | (없음) | **없음. ACK 전용** | `acf2e802e7d1103e62a30de1050cf9fb2f1cec56` "ANDROID: drivers: iommu: pviommu: Add basic driver structure" (2023-04-18) | pKVM 반가상 IOMMU(pvIOMMU) 드라이버. `tristate, depends on ARM64, select IOMMU_API` |
| `ARM_PKVM_GUEST` | `y` | `y` | 존재. `drivers/virt/coco/pkvm-guest/Kconfig` | (HEAD에서 `select ARCH_HAS_VIRTIO_BALLOON_HYP_OPS` 추가됨. 이 select 대상 심볼 자체는 v6.18에 없어 별도 확인 필요 — 확인 불가) | pKVM 보호 게스트용 하이퍼콜 드라이버. 두 defconfig 값 동일 |
| `VIRTIO_VSOCKETS` | `m` | `y` | 존재. `net/vmw_vsock/Kconfig` | - | virtio vsock 전송. 값 다름(모듈 vs 내장) |
| `VIRTIO_BLK` | `m` | `y` | 존재. `drivers/block/Kconfig` | - | virtio 블록 드라이버. 값 다름 |
| `VIRTIO_CONSOLE` | `m` | `y` | 존재. `drivers/char/Kconfig` | - | virtio 콘솔. 값 다름 |
| `VIRTIO_PCI` | `m` | `y` | 존재. `drivers/virtio/Kconfig` | - | virtio-PCI 트랜스포트. 값 다름 |
| `VIRTIO_BALLOON` | `m` | `y` | 존재. `drivers/virtio/Kconfig` | - | 메모리 밸룬. 값 다름 |
| `VIRTIO_FS` | `y` | (없음) | 존재. `fs/fuse/Kconfig`, `depends on FUSE_FS` | - | virtio-fs. gki만 설정 |
| `PTP_1588_CLOCK_KVM` | `# is not set` | (없음) | 존재. `drivers/ptp/Kconfig` | - | gki defconfig에 명시적으로 끈 상태로 기록됨 |
| `UDMABUF` | `y` | (없음) | 존재. `drivers/dma-buf/Kconfig` | - | 사용자공간 dma-buf 드라이버(QEMU 게스트 프레임버퍼용) |
| `DMABUF_HEAPS` | `y` | `y` | 존재. `drivers/dma-buf/Kconfig` menuconfig | - | dma-buf heap 캐릭터 디바이스. 두 defconfig 동일 |
| `DMABUF_SYSFS_STATS` | (없음) | `y` | 존재(단, upstream 헬프 텍스트에 "(DEPRECATED)"로 표기됨) | - | dma-buf sysfs 통계. microdroid만 설정 |
| `CMDLINE` | `"console=ttynull stack_depot_disable=on cgroup_disable=pressure kasan.stacktrace=off kvm-arm.mode=protected bootconfig"` | `"stack_depot_disable=on kasan.stacktrace=off cgroup_disable=pressure ioremap_guard panic=-1 bootconfig arm64.nompam"` | 존재. `arch/arm64/Kconfig`, `string` 타입 | - | 4절 참조 |
| `CMDLINE_EXTEND` | `y` | `y` | **없음. Kconfig 구조 자체가 다름** | `cae118b6acc309539b33339e846cbb19187c164c` "arm64: Drop support for CMDLINE_EXTEND" (Will Deacon, 2021-03-03, Linux 5.12 머지). team-lead 확인, 우리 트리에도 존재(`git log --all --grep='Drop support for CMDLINE_EXTEND'`) | 5절 참조 |

집계: 수집한 고유 심볼 20개(`CMDLINE`, `CMDLINE_EXTEND` 포함). 이 중 upstream v6.18에 해당 심볼이 없거나 구조가 다른 항목은 3개(`VFIO_PKVM_IOMMU`, `PKVM_PVIOMMU`, `CMDLINE_EXTEND`).

## 2. gki와 microdroid의 값 차이

값이 다르게 설정된 항목이다(둘 다 설정된 경우만).
- `VIRTIO_VSOCKETS`, `VIRTIO_BLK`, `VIRTIO_CONSOLE`, `VIRTIO_PCI`, `VIRTIO_BALLOON`: gki는 전부 `m`(모듈), microdroid는 전부 `y`(내장). microdroid는 부트 시점부터 필요한 최소 게스트라 내장으로 판단된다.
- `CMDLINE`: 완전히 다른 문자열(4절 참조).

값이 같은 항목: `ARM_PKVM_GUEST=y`, `DMABUF_HEAPS=y`, `CMDLINE_EXTEND=y`.

gki에만 있고 microdroid에는 아예 없는 항목(호스트 전용): `KVM`, `PTDUMP_STAGE2_DEBUGFS`, `VFIO`, `VFIO_PLATFORM`, `VFIO_PKVM_IOMMU`, `IOMMU_IO_PGTABLE_ARMV7S`, `PKVM_PVIOMMU`, `VIRTIO_FS`, `PTP_1588_CLOCK_KVM`, `UDMABUF`.

microdroid에만 있는 항목: `DMABUF_SYSFS_STATS`.

## 3. upstream에 없는 심볼(ACK 전용)

### VFIO_PKVM_IOMMU
`drivers/vfio/Kconfig`에 정의됨(v6.18에는 없음, HEAD에만 있음).
```
config VFIO_PKVM_IOMMU
	bool "VFIO pKVM IOMMU"
	depends on ARM64
```
도입 패치: `6b83b3c7` "ANDROID: drivers/vfio: Add VFIO_PKVM_IOMMU" (2023-11-13).

### PKVM_PVIOMMU
`drivers/iommu/Kconfig`에 정의됨(v6.18에는 없음, HEAD에만 있음).
```
config PKVM_PVIOMMU
	tristate "pKVM pvIOMMU driver"
	depends on ARM64
	select IOMMU_API
```
도입 패치: `acf2e802` "ANDROID: drivers: iommu: pviommu: Add basic driver structure" (2023-04-18). 관련 후속 패치로 `09c523c5` "ANDROID: drivers: iommu: pviommu: Add selftest" (2023-11-24)가 `PKVM_PVIOMMU_SELFTEST`를 추가했다.

### CMDLINE_EXTEND
이 항목은 "새 심볼 추가"가 아니라 **upstream이 다른 메커니즘으로 바뀐 경우**다. v6.18의 `arch/arm64/Kconfig`를 직접 읽은 결과다.
```
config CMDLINE
	string "Default kernel command string"
	default ""

choice
	prompt "Kernel command line type"
	depends on CMDLINE != ""
	default CMDLINE_FROM_BOOTLOADER

config CMDLINE_FROM_BOOTLOADER
	bool "Use bootloader kernel arguments if available"

config CMDLINE_FORCE
	bool "Always use the default kernel command string"
endchoice
```
`CONFIG_CMDLINE_EXTEND`라는 심볼 자체가 이 파일에 없다. `CMDLINE_FROM_BOOTLOADER`/`CMDLINE_FORCE` 중 하나를 고르는 `choice` 구조로 대체되어 있다. 두 defconfig가 쓰는 `CMDLINE_EXTEND=y`는 이 구조에서 무효한 심볼이라 `olddefconfig`/`scripts/config` 적용 시 경고 없이 무시되거나 `WARNING: unknown symbol` 형태로 잡힐 수 있다(실제 빌드 실행으로는 확인하지 않았고 파일 비교로만 판단했다 — 실행 검증은 확인 불가).
제거 경위: `cae118b6acc309539b33339e846cbb19187c164c` "arm64: Drop support for CMDLINE_EXTEND"(Will Deacon, 2021-03-03 작성, Linux 5.12에서 머지)가 `CMDLINE_EXTEND` 심볼을 제거했다. `choice` 구조 자체는 그 이전부터 있었고, 이 커밋으로 `CMDLINE_EXTEND` 선택지만 빠진 것이다. team-lead가 확인했고 우리 트리에도 이 커밋이 존재한다(`git log --all --grep='Drop support for CMDLINE_EXTEND'`). 대안은 `CONFIG_CMDLINE`에 필요한 인자를 넣고 `CONFIG_CMDLINE_FORCE=y`를 켜는 것이다(5절 참조).

## 4. CONFIG_CMDLINE 값

**gki_defconfig**:
```
CONFIG_CMDLINE="console=ttynull stack_depot_disable=on cgroup_disable=pressure kasan.stacktrace=off kvm-arm.mode=protected bootconfig"
```
`kvm-arm.mode=protected`가 포함되어 있다. 즉 gki 커널은 부트 인자로 pKVM 보호 모드를 켠다.

**microdroid_defconfig**:
```
CONFIG_CMDLINE="stack_depot_disable=on kasan.stacktrace=off cgroup_disable=pressure ioremap_guard panic=-1 bootconfig arm64.nompam"
```
`kvm-arm.mode=protected` 없음. microdroid는 게스트 커널이므로 호스트 쪽 pKVM 모드 인자가 필요 없다.

## 5. 최소 Kconfig 집합 권고

기존 문서(8.2절 6단계)의 스크립트다.
```
./scripts/config -e KVM -e NVHE_EL2_DEBUG -e PROTECTED_NVHE_STACKTRACE
```

**이 스크립트는 pKVM 패치를 모두 올린 검증 트리에서는 그대로 동작하지 않는다.** `arch/arm64/kvm/Kconfig` 파일 히스토리를 직접 읽은 결과, 다음 ANDROID 커밋들이 해당 심볼을 이름 변경했다(모두 T1 core KVM/hyp 경로, ANDROID: 접두, 필터 통과 대상).

| 원래 심볼(v6.18) | 변경 후 심볼(HEAD) | 커밋 |
|---|---|---|
| `NVHE_EL2_DEBUG` | `PKVM_DEBUG`(menuconfig) | `62c0dcbb` "ANDROID: KVM: arm64: NVHE_EL2_DEBUG to PKVM_DEBUG menuconfig" (2025-02-21) |
| `PROTECTED_NVHE_STACKTRACE` | `PKVM_STACKTRACE` | `8d88e567` "ANDROID: KVM: arm64: PROTECTED_NVHE_STACKTRACE to PKVM_STACKTRACE" (2025-02-21) |

HEAD의 `arch/arm64/kvm/Kconfig`를 직접 읽어 확인한 새 정의다.
```
menuconfig PKVM_DEBUG
	bool "Debug mode for Protected KVM hypervisor"

if PKVM_DEBUG
config PKVM_STRICT_CHECKS
	default y
config PKVM_SELFTESTS
	default y
config PKVM_DUMP_TRACE_ON_PANIC
	default y
config PKVM_FTRACE
	depends on FTRACE
	default y
config PKVM_STACKTRACE
	bool "Protected KVM hypervisor stacktraces"
	depends on PKVM_DISABLE_STAGE2_ON_PANIC
	default y
config PKVM_DISABLE_STAGE2_ON_PANIC
	bool "Disable the host stage-2 on panic"
	default n
endif
```

중요한 점은 `PKVM_STACKTRACE`가 `PKVM_DISABLE_STAGE2_ON_PANIC`에 의존한다는 것이다. 이 의존관계는 원래의 `PROTECTED_NVHE_STACKTRACE`(단순히 `depends on NVHE_EL2_DEBUG`)에는 없던 새 제약이다. `PKVM_DISABLE_STAGE2_ON_PANIC`은 기본값 `n`이라, 명시적으로 켜지 않으면 `PKVM_STACKTRACE=y`를 요청해도 자동으로 꺼진다.

**패치 적용 후 트리에서 원래 의도(KVM + 디버그 모드 + 스택트레이스)를 재현하려면 다음이 필요하다.**
```
./scripts/config -e KVM -e PKVM_DEBUG -e PKVM_DISABLE_STAGE2_ON_PANIC -e PKVM_STACKTRACE
```
`PKVM_DEBUG=y`를 켜면 `PKVM_STRICT_CHECKS`, `PKVM_SELFTESTS`, `PKVM_DUMP_TRACE_ON_PANIC`, (`FTRACE`가 켜져 있다면)`PKVM_FTRACE`는 기본값 `y`로 자동 반영된다. 이 4개를 굳이 `-e`로 명시할 필요는 없다.

**Kconfig 외에 추가로 필요한 것: 부트 커맨드라인.** `CONFIG_KVM=y`만으로는 pKVM 보호 모드가 켜지지 않는다. 4절에서 확인했듯 gki_defconfig는 `kvm-arm.mode=protected`를 `CONFIG_CMDLINE`에 박아 넣는 방식으로 이를 해결한다. 검증 스크립트가 Kconfig만 조정하고 부트 인자를 그대로 둔다면, 커널은 일반(비보호) nVHE/VHE KVM 모드로 뜬다. 부트로더나 QEMU 커맨드라인에 `kvm-arm.mode=protected`를 직접 추가하거나, `CONFIG_CMDLINE`에 포함시키고 `CONFIG_CMDLINE_FORCE=y`(v6.18의 새 choice 구조, 3절 참조)를 켜서 강제해야 한다.

**T2/T3 범위(장치 패스스루·pvIOMMU) 검증까지 하려면 추가로 필요하다.** 기본 KVM 부트 검증(6단계 범위)에는 필수가 아니다.
```
./scripts/config -e VFIO -e VFIO_PLATFORM -e VFIO_PKVM_IOMMU -e PKVM_PVIOMMU
```

## 6. 확인 불가 항목

- `ARM_PKVM_GUEST`가 HEAD에서 추가로 `select`하는 `ARCH_HAS_VIRTIO_BALLOON_HYP_OPS`가 v6.18에 존재하는지: 확인하지 못함. defconfig grep 결과에는 나타나지 않는 내부 select 대상이라 우선순위를 낮췄다.
- `PKVM_STACKTRACE=y` + `PKVM_DISABLE_STAGE2_ON_PANIC=y` 조합으로 실제 빌드가 성공하는지: 파일 읽기로만 판단했고 실제 `make olddefconfig`나 빌드는 실행하지 않았다. 실행 검증은 별도로 필요하다.

`CMDLINE_EXTEND` 제거 커밋은 team-lead가 확인해 3절에 반영했다(더 이상 확인 불가 항목 아님).
