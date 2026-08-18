# E-3 스모크 테스트 실측 기록

- 실측일: 2026-08-15
- 목적: D-9에서 채택한 H-6(QEMU `virt,iommu=smmuv3`)이 실제로 성립하는지 확인한다.
- 판정 대상: Phase 08 계획 1번과 2번. protected 부팅과 `Found N assignable devices`의 N.
- 실행 도구: `work/src/tools/qemu/run-e3.sh`
- 로그: `work/build/pkvm-qemu/console-e3-smmuv3*.log`

2026-08-18에 QEMU v10.0.0 소스 빌드로 동일 테스트를 재실행했다. nested driver 경로는
Stage-2 미노출로 실패했지만, Phase 08 설계를 PV single-stage로 전환한 뒤 PV IOMMU
초기화에 성공했다. 따라서 Q-5는 PV 설계의 선행 조건에서 제외한다.

## 실행 환경

| 항목 | 값 |
|---|---|
| QEMU | 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18) |
| 머신 | `virt,virtualization=on,gic-version=3,iommu=smmuv3` |
| CPU / SMP / MEM | `max` / 2 / 2G |
| 커널 | Phase 02 clang 재현 빌드, submodule `281fa709853a` |
| 커널 설정 | `ARM_SMMU_V3`, `ARM_SMMU_V3_PKVM`, `PKVM_PVIOMMU`, `VFIO_PKVM_IOMMU` 모두 `y` |
| initramfs | 정적 arm64 BusyBox 1.36.1 |

Phase 02의 산출물이 작업 트리에 없어 clang 빌드를 다시 수행했다. initramfs 생성 절차가
문서에 없어 `work/src/tools/qemu/mkinitramfs.sh`를 새로 만들었다.

## 실행 결과

| 회차 | `kvm-arm.hyp_iommu_pages` | IOMMU 풀 경고 | iommu 드라이버 init | assignable devices |
|---|---|---|---|---|
| 1 | 미지정 | 2회 | `-19` ENODEV | 0 |
| 2 | `0x609` | 2회 | `-19` ENODEV | 0 |
| 3 | `2048` | 1회 | `-19` ENODEV | 0 |
| 4 | `4096` | 없음 | `-6` ENXIO | 0 |

네 회차 모두 protected 부팅과 user space 진입에 성공했다.

## 확인된 사실

### 1. QEMU 8.2.2도 SMMUv3를 노출한다

`virt` 머신의 `iommu=smmuv3` 옵션은 8.2.2에 이미 있다. 커널이 장치를 프로브하고 PCI
장치를 iommu group에 편입한다.

```text
arm_smmu_v3.arm-smmu-v3-emu protected_kvm.smmu_v3_emu.0: Probing from 9050000.smmuv3
smmuv3-nesting 9050000.smmuv3: ias 44-bit, oas 44-bit (features 0x01008305)
pci 0000:00:00.0: Adding to iommu group 0
pci 0000:00:01.0: Adding to iommu group 1
```

Phase 03의 QEMU 4.2.1에는 SMMUv3 자체가 없었다. 그 차이는 확인됐다.

### 2. EL2 IOMMU 풀 메모리를 커맨드라인으로 지정해야 한다

지정하지 않으면 부팅 초기에 다음 경고가 나오고 EL2 iommu 드라이버 초기화가 실패한다.

```text
kvm [1]: Missing memory for the IOMMU pool, need 0x609 pages, check kvm-arm.hyp_iommu_pages
```

두 가지 함정이 있다.

첫째, 경고는 필요량을 16진수로 출력하지만 파서는 10진수만 받는다.
`arch/arm64/kvm/iommu.c:118`의 `early_hyp_iommu_pages()`가 `kstrtoul(arg, 10, ...)`를
쓴다. `0x609`를 그대로 넘기면 파싱에 실패하고 파라미터가 조용히 무시된다. 회차 2가 회차
1과 결과가 같은 이유다.

둘째, 판정이 누적식이다. `iommu.c:54`의 조건은 다음과 같다.

```c
if (pool_pages + requested_pool_pages > kvm_nvhe_sym(hyp_kvm_iommu_pages)) {
```

드라이버가 각 1545 페이지로 두 번 등록하므로 총 3090 페이지 이상이 필요하다. 2048은 첫
등록만 통과시킨다. 회차 3에서 경고가 한 번으로 줄어든 것이 이를 보여준다. 4096에서 경고가
사라졌다.

### 3. QEMU 8.2.2의 SMMUv3는 stage-2를 지원하지 않는다

회차 4에서 에러가 `-19`에서 `-6`(ENXIO)으로 바뀌었다. 발생 지점은
`drivers/iommu/arm/arm-smmu-v3/pkvm/nested/arm-smmu-v3.c:248`이다.

```c
if (!(smmu->features & ARM_SMMU_FEAT_TRANS_S1) ||
    !(smmu->features & ARM_SMMU_FEAT_TRANS_S2))
	return -ENXIO;
```

pKVM nested 드라이버는 stage-1과 stage-2를 모두 요구한다. 로그의 `features 0x01008305`를
`arm-smmu-v3.h`의 비트 정의로 판정한 결과는 다음과 같다.

| 비트 | 심볼 | 값 |
|---|---|---|
| 9 | `ARM_SMMU_FEAT_TRANS_S1` | 있음 |
| 10 | `ARM_SMMU_FEAT_TRANS_S2` | 없음 |

QEMU 8.2.2는 stage-1만 제공한다. 이것이 상위 버전이 필요한 실제 이유다.

### 4. `Found 0 assignable devices`는 SMMUv3와 별개 문제다

`arch/arm64/kvm/pkvm.c:693`의 `pkvm_init_devices()`는 device tree에서
`pkvm,device-assignment` compatible 노드를 찾아 `devices` phandle 개수를 센다.

```c
for_each_compatible_node (np, NULL, PKVM_DEVICE_ASSIGN_COMPAT) {
	while (!of_parse_phandle_with_fixed_args(np, "devices", 1, cnt, &args))
		cnt++;
	dev_cnt += cnt;
}
kvm_info("Found %d assignable devices", dev_cnt);
```

QEMU가 생성하는 기본 device tree에는 이 노드가 없다. SMMUv3 stage-2 문제가 해소되어도 N은
0으로 남는다. 할당 대상 장치를 기술한 device tree를 따로 만들어 넣어야 한다.

### 5. 부팅 모드가 hVHE다

`Protected hVHE mode initialized successfully`가 나온다. Phase 03의 완료 마커는
`Protected nVHE mode initialized successfully`다. `-cpu max`가 VHE를 제공해 커널이 hVHE
경로를 택했다. 마커 문자열이 다르므로 Phase 03의 판정 스크립트를 그대로 쓰면 실패로
읽힌다.

## D-9에 대한 판정

### QEMU v10.0.0 재검증 (2026-08-18)

| 항목 | 결과 |
|---|---|
| QEMU | v10.0.0 (소스 빌드) |
| protected 부팅 | 성공 (`PKVM_QEMU_BOOT_OK`) |
| SMMUv3 features | `0x01008305` (TRANS_S1만 존재, TRANS_S2 없음) |
| EL2 IOMMU init | 실패 `-19` (`ENODEV`) |
| assignable devices | `0` |

v10 소스의 `hw/arm/virt.c`에는 nested SMMUv3 구현이 있으나 런타임 stage-2 비트가
노출되지 않았다. `virt_machine_10_0_options()`에서 `no_nested_smmu=false`를 명시한
후에도 결과가 같았다. 이 변경은 원인 규명용 로컬 패치이며 완료 조건을 충족하지 못해
커밋하지 않는다.

### 웹 조사에 따른 원인

QEMU 공식 v10.0.3 문서는 `iommu=smmuv3`를 “machine-wide SMMUv3” 생성 옵션으로
설명하지만, nested translation은 별도의 `arm-smmuv3,accel=on` 경로로 설명한다.
이 경로는 host SMMUv3 하드웨어, iommufd, ACPI 부팅을 요구하며 device-tree 기반
에뮬레이션에는 적용되지 않는다. [QEMU virt 문서](https://qemu.readthedocs.io/en/v10.0.3/system/arm/virt.html#accelerated-smmuv3-nested-translation)

QEMU의 SMMUv3 nested *에뮬레이션*은 2024년에 RFC/패치 시리즈로 제안되었고, 당시
“QEMU는 stage-1 또는 stage-2 중 하나만 에뮬레이트한다”는 전제가 명시되어 있다.
[nested translation 패치 시리즈](https://mail.gnu.org/archive/html/qemu-devel/2024-07/msg03294.html)
따라서 v10.0.0의 버전 문자열만으로 pKVM이 요구하는 virtual SMMU Stage-2가
제공된다고 판단할 수 없다. 로컬 소스에 `stage="nested"` 관련 코드가 있더라도
현재 `virt,iommu=smmuv3` 실행에서 IDR0의 S2 비트가 0으로 관측된 것이 최종
판정 근거다.

즉 실패 원인은 다음의 조합이다.

1. pKVM nested 드라이버는 IDR0에서 `TRANS_S1`과 `TRANS_S2`를 모두 요구한다.
2. QEMU의 기본 machine-wide SMMUv3는 현재 실행 모드에서 Stage-1만 광고한다.
3. `accel=on`은 실제 host SMMU/iommufd/ACPI 경로라 현재 TCG+DT E-3 구성의 대체가 아니다.
4. Stage-2가 초기화되지 않아 장치 할당 검색도 `Found 0 assignable devices`에서 중단된다.

### PV single-stage 전환 결과 (2026-08-18)

계측 결과 DT의 SMMU 수는 1개였지만, 일반 `ARM_SMMU_V3` driver가 먼저 platform
device에 bind하여 PV driver probe가 `-19`를 반환했다. 일반 driver와 nested driver를
끄고 PV driver만 활성화하자 다음과 같이 초기화가 성공했다.

```text
kvm-arm-smmu-v3 9050000.smmuv3: ias 44-bit, oas 44-bit (features 0x01088705)
kvm-arm-smmu-v3 9050000.smmuv3: allocated 65536 entries for cmdq
kvm-arm-smmu-v3 9050000.smmuv3: allocated 32768 entries for evtq
```

`Failed to init iommu driver`는 더 이상 출력되지 않는다. 따라서 Q-5(Stage-2 QEMU)는
PV 전용 설계에서 제거하며, 다음 blocker는 `pkvm,device-assignment` DT 노드와 실제
IOMMU endpoint를 가진 할당 대상 device 작성이다.

### QEMU edu assignable device (2026-08-18)

QEMU `virt`에 `pkvm-edu-assignment=on` 옵션을 추가해 PCI `edu` 장치의 고정 BAR0와
Requester ID를 `pkvm,device-assignment` DT descriptor로 전달했다. descriptor node는
Linux platform device로 생성되지 않도록 `status="disabled"`로 두어 실제 PCI endpoint와
Stream ID가 중복 등록되지 않게 했다.

```bash
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
QEMU_EXTRA_ARGS='-device edu,addr=2' \
HYP_IOMMU_PAGES=4096 \
work/src/tools/qemu/run-e3.sh \
    work/build/pkvm-qemu/console-e3-pv-edu-assignment3.log 600
```

실측 결과 PV IOMMU 초기화, PCI endpoint의 IOMMU group 편입, assignable device 등록이
모두 성공했다.

```text
pci 0000:00:02.0: Adding to iommu group 2
kvm [1]: Found 1 assignable devices
```

QEMU 소스 커밋은 [`2ebc078`](https://github.com/boram1288/qemu/commit/2ebc078)이며
branch는 `boram1288/phase08-pkvm-edu`다. 다음 단계는 EL2 reset callback과 Phase 07
runner의 device MMIO mapping을 연결하는 것이다.

H-6 채택은 유지한다. QEMU가 SMMUv3를 제공하고 pKVM이 protected로 부팅하는 것까지는
확인됐다. 다만 조사 단계에서 기록하지 못한 두 개의 선행 작업이 드러났다.

| 항목 | 내용 |
|---|---|
| Q-5 | SMMUv3 stage-2를 지원하는 QEMU 버전 확보 |
| Q-6 | `pkvm,device-assignment` 노드를 포함한 device tree 작성 |

Q-5는 QEMU 버전 문제다. stage-2 지원이 어느 릴리스에 들어갔는지 확인하고 해당 버전
이상을 준비한다. QEMU SMMUv3의 stage-2 지원 패치는 2023년 5월, nested 지원 패치는 2024년에
투고됐다. 8.2.2에 stage-2가 없는 것은 실측으로 확인했다.

Q-6은 QEMU 버전과 무관하다. 상위 버전을 확보해도 별도로 해결해야 한다.

## 다음 작업

1. stage-2를 지원하는 QEMU 버전을 특정하고 확보한다. 확보 후 `features` 값의 비트 10을
   다시 확인한다.
2. `pkvm,device-assignment` 노드의 스키마를 커널 소스에서 확인하고 device tree를 작성한다.
3. 두 항목이 해소된 뒤 `Found N assignable devices`를 다시 측정한다.

## 재현 방법

```bash
# initramfs 생성 (최초 1회)
work/src/tools/qemu/mkinitramfs.sh

# 실행. HYP_IOMMU_PAGES 기본값은 2048이며 4096을 권장한다.
HYP_IOMMU_PAGES=4096 work/src/tools/qemu/run-e3.sh
```

커널 빌드는 `docs/phase-02/README.md`의 clang 절차를 따른다.
