# D-9 하드웨어 후보 조사

- 조사일: 2026-08-14
- 결정일: 2026-08-15
- 대상 결정: D-9 (E-3 하드웨어 구성 확정)
- 목적: Phase 08의 장치 직접 할당과 DMA 격리를 수행할 실행 환경을 정한다.
- 결정 결과: H-6(QEMU `virt,iommu=smmuv3`) 채택. 실물 하드웨어는 PoC 범위에서 제외.

2절과 3절은 조사 시점의 기록이다. 결정 내용은 4절과 5절에 있다.

이 문서는 표기 규칙에 따라 DMA 격리 하드웨어를 S2MPU로 부른다. `SMMUv3`, `ARM_SMMU_V3`
같은 백틱 표기는 Arm 사양 이름 또는 커널 설정 심볼 이름 그대로다.

## 1. 요구 조건

README의 성공 조건 3과 5에서 다음이 도출된다.

| ID | 조건 | 근거 |
|---|---|---|
| R-1 | arm64이고 EL2에서 pKVM이 동작한다 | pKVM은 arm64 전용 |
| R-2 | S2MPU가 있고 pKVM이 이를 소유한다 | DMA 격리 판정에 필요 |
| R-3 | NVIDIA GPU를 AI pVM에 배타적으로 할당할 수 있다 | 성공 조건 3, 5 |
| R-4 | USB 카메라를 Camera pVM에 배타적으로 할당할 수 있다 | 성공 조건 3 |
| R-5 | Phase 02의 pKVM 커널을 부팅할 수 있다 | 검증 트리 재사용 |
| R-6 | 조달 가능하고 비용이 과도하지 않다 | PoC 제약 |

## 2. 조사에서 확인한 제약

후보 비교 전에, 후보 선택과 무관하게 성립하는 제약을 먼저 정리한다.

### 2.1 pKVM의 DMA 격리는 upstream에 없다

커널 공식 문서는 pKVM의 격리 메커니즘 중 "DMA isolation using an IOMMU"를 미구현으로
표기한다. CPU state isolation과 pvmfw도 같다. pKVM 자체가 실험 기능으로 명시되어 있다.

S2MPU 드라이버는 RFC 상태다. v1(2023-02), v2(2024-12), v4(2025-08)로 이어졌고 아직
머지되지 않았다. `ARM_SMMU_V3_PKVM`은 EL2와 EL1로 나뉘어 동작하는 분리 드라이버이며,
`kvm-arm.mode=protected`일 때 일반 드라이버보다 우선한다.

Phase 02에서 이미 `ARM_SMMU_V3_PKVM`, `ARM_SMMU_V3_PKVM_PV`, `PKVM_PVIOMMU`,
`VFIO_PKVM_IOMMU`를 활성화했다. 이는 android-kvm 트리 기준이며 upstream 상태와 다르다.

### 2.2 pKVM 장치 할당은 platform device 경로다

AVF의 장치 할당은 `vfio-platform` 기반이다. Hypervisor에 MMIO 토큰과 IOMMU 토큰을 요청하는
벤더 하이퍼콜(`VENDOR_HYP_KVM_DEV_REQ_MMIO_FUNC_ID`, `0xc600003f`)로 동작하고, pvmfw가
할당 내용을 실제 하드웨어 능력과 정책에 대조해 검증한다.

`vfio-pci` 기반의 PCIe 장치 할당 경로는 AVF 문서와 pKVM 문서 어디에도 명시되어 있지 않다.
**discrete NVIDIA GPU를 pVM에 직접 할당하는 것은 현재 문서화된 경로가 없다.** 이것이 R-3의
핵심 장애물이며, 하드웨어를 무엇으로 고르든 남는다.

이 제약은 Phase 09의 EL2 벤더 모듈 확장 리스크와 같은 성격이다. 둘 다 EL2 코드 추가를
요구한다.

### 2.3 QEMU가 S2MPU를 에뮬레이션한다

QEMU `virt` 머신은 `iommu=smmuv3` 옵션으로 머신 전역 S2MPU를 만든다. 더 중요한 것은
pKVM S2MPU 드라이버 RFC v4가 **QEMU와 Morello board에서 테스트됐다**는 점이다. QEMU
테스트는 S1 only, S2 only, nested 세 가지와 4K/16K/64K 페이지 크기를 포함한다.

즉 G-9(DMA 격리)의 상당 부분은 실물 하드웨어 없이 QEMU에서 먼저 검증할 수 있다. 현재
Phase 03의 `Found 0 assignable devices`는 QEMU 4.2.1에 S2MPU 옵션을 주지 않아서 나온
결과이지, QEMU가 원리적으로 불가해서가 아니다.

## 3. 후보 비교

| ID | 후보 | R-1 pKVM | R-2 S2MPU | R-3 GPU | R-4 USB | R-5 커널 | R-6 조달 |
|---|---|---|---|---|---|---|---|
| H-1 | Ampere Altra Developer Platform | 미검증 | 표준 `SMMUv3` | discrete PCIe | 가능 | upstream | $3,999~ |
| H-2 | NVIDIA Jetson AGX Thor Developer Kit | 미검증 | Tegra `SMMUv3` | SoC 통합 | 가능 | L4T 다운스트림 | $3,499 |
| H-3 | NVIDIA Jetson AGX Orin Developer Kit | KVM 동작 사례 | Tegra SMMU | SoC 통합 | 가능 | L4T 다운스트림 | 저가 |
| H-4 | Arm Morello board | RFC 테스트 플랫폼 | 표준 `SMMUv3` | 없음 | 제한적 | 연구용 | 입수 곤란 |
| H-5 | NVIDIA DGX Spark (GB10) | 미검증 | Grace `SMMUv3` | SoC 통합 | 가능 | 폐쇄적 | 소비자 유통 |
| H-6 | QEMU `virt,iommu=smmuv3` | 검증됨 | 에뮬레이션 | 없음 | 에뮬레이션 | upstream | 비용 없음 |

### H-1 Ampere Altra Developer Platform

ADLINK COM-HPC 기반 arm64 워크스테이션이다. Neoverse N1 32/64/80코어, PCIe Gen4 64레인,
x16 슬롯 3개와 x4 슬롯 2개를 제공한다. 제품 브리프에 IO Virtualization 항목으로
`SMMUv3`와 SR-IOV가 명시되어 있다. Arm SystemReady SR 인증과 EDK II UEFI를 지원해 일반
aarch64 배포판이 그대로 부팅된다. 기본 구성 $3,999부터다.

NVIDIA aarch64 드라이버가 지원하는 프로세서 목록에 Ampere 계열이 포함되며, Ampere가
직접 NVIDIA GPU 가속 데스크톱 구성 문서를 공개하고 있다. GeForce RTX 3070 Ti, RTX 3060 Ti
등 실제 동작 사례가 커뮤니티에 보고되어 있다.

장점은 R-2와 R-5를 표준 방식으로 만족한다는 것이다. 표준 `SMMUv3`이므로 upstream
`ARM_SMMU_V3_PKVM` RFC가 겨냥하는 대상과 같고, upstream 커널이 부팅되므로 Phase 02의
검증 트리를 그대로 쓸 수 있다. discrete PCIe GPU라서 "장치를 pVM에 할당한다"는 README의
문언과 의미가 정확히 맞는다.

단점은 이 플랫폼에서 pKVM을 protected 모드로 부팅한 공개 사례를 찾지 못했다는 것이다.
2.2절의 `vfio-pci` 경로 부재도 그대로 적용된다.

### H-2 NVIDIA Jetson AGX Thor Developer Kit

Neoverse-V3AE 14코어와 Blackwell GPU 2560코어를 한 SoC에 담았다. 128GB LPDDR5X 통합
메모리, PCIe Gen5, USB 3.2/USB-C, 카메라 20대 이상 지원. $3,499다.

카메라 입력이 강점이고 R-4를 여유 있게 만족한다. 하지만 GPU가 SoC 통합이라 "GPU 1대를
AI pVM에 할당"의 의미가 H-1과 다르다. 통합 GPU를 pVM에 넘기려면 Tegra 고유 경로가
필요하고, 이는 벤더 코드 의존을 늘린다. L4T 다운스트림 커널을 쓰므로 R-5도 어긋난다.
Phase 02의 v6.18 검증 트리를 그대로 올릴 수 없다.

### H-3 NVIDIA Jetson AGX Orin Developer Kit

Tegra234 기반이다. KVM을 켜서 VHE 모드로 VM을 띄운 사례가 공개되어 있어 가상화 자체는
동작한다. IOMMU도 device tree의 stream ID로 구성 가능하다.

다만 확인된 사례는 전부 일반 KVM이고 protected 모드가 아니다. GPU passthrough 문의에
대한 NVIDIA 포럼 답변도 정식 지원을 확인해주지 않는다. H-2와 같은 통합 GPU 및 다운스트림
커널 문제를 공유하되 세대가 낮다. 저가라는 점만 이점이다.

### H-4 Arm Morello board

pKVM S2MPU 드라이버 RFC가 실제로 성능 측정까지 수행한 플랫폼이다. 4코어 구성이 언급된다.
R-1과 R-2를 가장 확실하게 만족하는 유일한 실물이다.

그러나 NVIDIA GPU를 붙일 수 없고 연구용 배포 프로그램 기반이라 조달이 현실적이지 않다.
R-3과 R-6에서 탈락한다. 참고 기준으로만 의미가 있다.

### H-5 NVIDIA DGX Spark (GB10)

Grace Blackwell 슈퍼칩이다. Cortex-X925 10코어와 Cortex-A725 10코어, 128GB 통합 메모리.
Grace SoC의 `SMMUv3`는 NVIDIA 고유 CMDQ-Virtualization(CMDQV) 확장을 포함한다.

통합 GPU라는 점은 H-2와 같고, 펌웨어와 소프트웨어 스택이 더 닫혀 있다. 커스텀 커널로
protected 모드 부팅을 시도하기에 적합하지 않다.

### H-6 QEMU `virt,iommu=smmuv3`

실물이 아니지만 pKVM S2MPU 드라이버의 공식 테스트 환경 중 하나다. 비용이 없고 즉시 착수
가능하며, S1/S2/nested 조합을 모두 시험할 수 있다.

실제 NVIDIA GPU와 USB 카메라가 없으므로 R-3, R-4를 만족하지 못한다. 대신 R-2에 해당하는
DMA 격리 로직을 가상 장치로 먼저 검증할 수 있다.

## 4. 결정

E-3는 H-6(QEMU `virt,iommu=smmuv3`) 단일 환경으로 확정한다. 실물 하드웨어 후보 H-1~H-5는
채택하지 않으며, 실장치 검증은 이 PoC의 범위에서 제외한다.

| 프로필 | 구성 | 대상 |
|---|---|---|
| E-3 | QEMU (SMMUv3 stage-2 지원) + `virt,iommu=smmuv3` + pKVM 커널 + 에뮬레이션 장치 | G-8, G-9, G-11 |

근거는 다음과 같다.

1. H-6는 pKVM S2MPU 드라이버 RFC의 공식 테스트 환경이다. R-1과 R-2에서 유일하게 검증된
   후보이며, 비용과 대기 없이 즉시 착수할 수 있다.
2. 실물 후보는 어느 것도 `kvm-arm.mode=protected` 부팅 사례가 확인되지 않는다. 조달 후에도
   R-1이 성립하는지 알 수 없다. H-1의 $3,999 이상을 지출하고도 Phase 08에 착수하지 못할
   수 있다.
3. 2.2절의 `vfio-pci` 경로 부재는 하드웨어 선택으로 해소되지 않는다. R-3의 핵심 장애물이
   조달로 사라지지 않으므로, 하드웨어 구매가 R-3 달성을 보장하지 않는다.
4. 이 PoC의 판정 대상은 격리 경계의 성립 여부다. 장치 할당 경로, 배타적 소유권, DMA 격리,
   회수와 재할당은 에뮬레이션 장치로도 판정할 수 있다.

이 결정으로 R-3과 R-4는 에뮬레이션 장치 기준으로 대체한다. R-6은 비용 없이 만족한다.

## 5. 결정에 따른 후속 처리

### 5.1 조사 시점 해소 항목의 처리

| 항목 | 내용 | 처리 |
|---|---|---|
| Q-1 | H-1에서 `kvm-arm.mode=protected` 부팅이 되는가 | 무효. 실물 미채택 |
| Q-2 | pVM에 장치를 할당하는 경로를 어떻게 만드는가 | 유효. Phase 08 착수 시 선행 조사 |
| Q-3 | README의 "NVIDIA GPU 1대"가 통합 GPU를 포함하는가 | 무효. 실물 미채택 |
| Q-4 | android-kvm 트리를 H-1에서 부팅할 수 있는가 | 무효. 실물 미채택 |

Q-2만 남는다. Phase 08의 1번 확인 항목이며 결과는 D-7에 반영한다.

### 5.2 후속 과제로 넘기는 항목

다음은 이 PoC에서 검증하지 않는다. 실물 환경으로 확장할 때의 검증 항목으로 남긴다.

1. 실제 USB 카메라의 Camera pVM 할당과 캡처 동작
2. discrete NVIDIA GPU의 AI pVM 할당과 GPU 가속 추론
3. 실물 `SMMUv3`에서의 DMA 격리 재현
4. 실물 플랫폼에서의 `kvm-arm.mode=protected` 부팅

확장 시점에 후보를 재평가할 경우 H-1이 출발점이다. 표준 `SMMUv3`, upstream 커널,
discrete PCIe GPU 세 가지가 동시에 성립하는 유일한 후보이기 때문이다. H-2는 카메라
지원이 강점이나 L4T 다운스트림 커널이 R-5를 깨뜨린다.

## 6. 참고 자료

- [Protected KVM (pKVM) — The Linux Kernel documentation](https://www.kernel.org/doc/html/next/virt/kvm/arm/pkvm.html)
- [KVM: arm64: SMMUv3 driver for pKVM (trap and emulate), RFC v4 — LWN](https://lwn.net/Articles/1034478/)
- [RFC PATCH v2 00/58 KVM: Arm SMMUv3 driver for pKVM](https://lists.infradead.org/pipermail/linux-arm-kernel/2024-December/985908.html)
- [AVF architecture — Android Open Source Project](https://source.android.com/docs/core/virtualization/architecture)
- [Implement a pKVM vendor module — Android Open Source Project](https://source.android.com/docs/core/virtualization/pkvm-modules)
- [QEMU virt machine documentation](https://www.qemu.org/docs/master/system/arm/virt.html)
- [Ampere Altra Family Product Brief](https://amperecomputing.com/en/briefs/ampere-altra-family-product-brief)
- [ADLINK Launches Ampere Altra Developer Platform — Phoronix](https://www.phoronix.com/news/ADLINK-Ampere-Altra-Developer)
- [NVIDIA GPU Accelerated Linux Desktop on Ampere](https://github.com/AmpereComputing/NVIDIA-GPU-Accelerated-Linux-Desktop-on-Ampere)
- [NVIDIA aarch64 driver minimum requirements](https://download.nvidia.com/XFree86/Linux-aarch64/575.51.02/README/minimumrequirements.html)
- [Jetson AGX Thor — NVIDIA](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-thor/)
- [Boot a VM on an NVIDIA Jetson AGX Orin — Cloudkernels](https://blog.cloudkernels.net/posts/orin-vm/)
- [DGX Spark Hardware Overview — NVIDIA](https://docs.nvidia.com/dgx/dgx-spark/hardware.html)
