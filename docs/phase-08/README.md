# Phase 08: 실제 장치 직접 할당과 DMA 격리

- 상태: 환경 미확보
- 목적: USB 카메라와 NVIDIA GPU를 각 pVM에 배타적으로 할당하고, 장치 DMA가 소유 pVM 밖으로 나가지 못하게 한다.
- 환경: E-3a(QEMU S2MPU), E-3b(실장치)
- 관련 목표: G-8, G-9
- 관련 결정: D-7, D-9

## 선행 조건

- E-3 하드웨어 확정 (D-9)
- USB 카메라 1대와 NVIDIA GPU 1대
- Phase 02의 pKVM 커널이 해당 하드웨어에서 부팅
- Phase 05의 다중 pVM 운용 성공

## D-9 하드웨어 후보 조사 결과

상세 근거와 참고 자료는 [하드웨어 후보 조사](hardware-candidates.md)에 있다. 요약은
다음과 같다.

### 후보와 판정

| ID | 후보 | 판정 |
|---|---|---|
| H-1 | Ampere Altra Developer Platform | 실물 1순위 |
| H-2 | NVIDIA Jetson AGX Thor Developer Kit | 실물 2순위 |
| H-3 | NVIDIA Jetson AGX Orin Developer Kit | 제외 |
| H-4 | Arm Morello board | 제외 |
| H-5 | NVIDIA DGX Spark (GB10) | 제외 |
| H-6 | QEMU `virt,iommu=smmuv3` | 선행 환경으로 채택 |

H-1은 표준 `SMMUv3`, upstream 커널 부팅, discrete PCIe NVIDIA GPU 세 가지가 동시에
성립하는 유일한 후보다. Arm SystemReady SR 인증으로 Phase 02의 검증 트리를 그대로 쓸 수
있고, PCIe Gen4 x16 슬롯을 제공하며, Ampere가 NVIDIA GPU 구성 문서를 공개하고 있다.

H-2는 카메라 지원이 뛰어나지만 GPU가 SoC 통합이고 L4T 다운스트림 커널을 쓴다. Phase 02를
다시 해야 하므로 2순위다. H-3과 H-5는 같은 문제를 공유하며 세대 또는 개방성에서 밀린다.
H-4는 pKVM S2MPU 드라이버의 실제 테스트 플랫폼이지만 NVIDIA GPU를 붙일 수 없고 조달이
어렵다.

### 환경 분할

조사 결과 이 Phase를 두 환경으로 나눈다.

| 프로필 | 구성 | 대상 | 시점 |
|---|---|---|---|
| E-3a | QEMU v9 이상 + `virt,iommu=smmuv3` + pKVM 커널 + 가상 장치 | G-9의 DMA 격리 로직 | 즉시 착수 가능 |
| E-3b | H-1 + NVIDIA GPU + USB 카메라 | G-8과 실장치 DMA 격리 | 하드웨어 확보 후 |

pKVM S2MPU 드라이버 RFC 자체가 QEMU와 Morello board에서 테스트됐다. QEMU `virt` 머신은
`iommu=smmuv3`로 머신 전역 S2MPU를 제공한다. 따라서 DMA 격리 로직은 하드웨어 확보를
기다리지 않고 먼저 검증할 수 있다.

Phase 03의 `Found 0 assignable devices`는 QEMU 4.2.1에 S2MPU 옵션을 주지 않아서 나온
결과다. QEMU가 원리적으로 불가한 것이 아니다.

### 후보와 무관하게 남는 제약

1. 커널 공식 문서는 pKVM의 "DMA isolation using an IOMMU"를 미구현으로 표기한다. S2MPU
   드라이버는 2023년부터 RFC 상태이며 아직 머지되지 않았다. Phase 02가 활성화한 설정은
   android-kvm 트리 기준이고 upstream 상태와 다르다.
2. AVF의 장치 할당은 `vfio-platform` 경로다. `vfio-pci` 기반 PCIe 장치 할당은 pKVM과 AVF
   문서 어디에도 명시되어 있지 않다. **discrete NVIDIA GPU를 pVM에 직접 할당하는 문서화된
   경로가 현재 없다.** 하드웨어를 무엇으로 고르든 남는 제약이며, Phase 09의 EL2 벤더 모듈
   확장과 같은 성격의 리스크다.

### 확정 전 해소 항목

| 항목 | 내용 | 해소 방법 |
|---|---|---|
| Q-1 | H-1에서 `kvm-arm.mode=protected` 부팅 가능 여부 | 구매 전 판단 곤란, 벤더 문의 |
| Q-2 | pVM에 PCIe 장치를 할당하는 경로 | E-3a 단계에서 선행 조사 |
| Q-3 | README의 "NVIDIA GPU 1대"가 통합 GPU를 포함하는가 | 사용자 확인 필요 |
| Q-4 | android-kvm 트리를 H-1에서 부팅 가능한가 | E-3a 이후 판단 |

Q-3의 답에 따라 H-2가 1순위로 바뀔 수 있다. 통합 GPU를 허용하면 카메라와 GPU를 한
보드에서 해결할 수 있으나, Phase 02를 다시 수행해야 한다.

## 계획

### 1단계: E-3a에서 DMA 격리 로직 검증

1. QEMU v9 이상을 준비하고 `virt,iommu=smmuv3`로 pKVM 커널을 protected 모드로 부팅한다.
2. `Found N assignable devices`가 0이 아닌 값이 되는지 확인한다.
3. 가상 장치를 pVM에 할당하고 Host 접근 차단을 확인한다.
4. 소유 pVM 범위를 벗어나는 DMA를 유발해 S2MPU 차단 결과를 얻는다.
5. Q-2의 PCIe 장치 할당 경로를 조사하고 결과를 D-7에 반영한다.

### 2단계: E-3b에서 실장치 검증

6. E-3b 하드웨어에서 pKVM 커널을 protected 모드로 부팅한다.
7. USB 카메라를 Camera pVM에, NVIDIA GPU를 AI pVM에 배타적으로 할당한다.
8. Host와 다른 pVM에서 해당 장치에 접근할 수 없음을 확인한다.
9. 장치 DMA가 소유 pVM의 메모리 범위를 벗어나지 못하는지 확인한다.
10. 범위를 벗어나는 DMA를 의도적으로 유발해 차단 결과를 대조군으로 남긴다.
11. pVM 종료 후 장치 소유권이 회수되고 재할당 가능한지 확인한다.

## 완료 조건

| 검사 | 환경 | 판정 |
|---|---|---|
| 할당 가능 장치 인식 | E-3a | `Found N assignable devices`에서 N이 0이 아니다 |
| DMA 범위 위반 차단 | E-3a | 소유 범위 밖 DMA가 S2MPU에서 차단된다 |
| 장치 배타 할당 | E-3b | 두 장치가 각각 다른 pVM에 할당된다 |
| Host 접근 차단 | E-3b | 할당 중 Host와 비소유 pVM의 접근이 차단된다 |
| 실장치 DMA 격리 | E-3b | 실제 장치의 DMA가 소유 pVM 범위를 벗어나지 못한다 |
| 회수와 재할당 | E-3b | pVM 종료 후 장치가 회수되고 다시 할당된다 |

차단 결과에는 반드시 대조군(차단되지 않는 정상 접근)이 함께 있어야 한다. E-3a 결과를
E-3b 결과로 표기하지 않는다.

## 예정 산출물

- 하드웨어 후보 조사: [hardware-candidates.md](hardware-candidates.md)
- 하드웨어 구성과 부팅 절차: 이 디렉터리에 추가
- 할당 도구: `work/src/tools/device-assign/`
- 부팅 및 실행 로그: `work/build/device-assign/`
- 결과 문서: 이 디렉터리에 추가

## 한계

이 Phase가 완료되기 전까지 "Host가 침해되어도 모든 경로에서 pVM 메모리가 보호된다"는
주장을 하지 않는다. Phase 04의 결과는 CPU 매핑 경로에 한정된다.

E-3a는 에뮬레이션 환경이다. E-3a에서 DMA 격리가 성립해도 실제 하드웨어의 기밀성을
주장하지 않는다. G-9의 최종 판정은 E-3b에서 한다.

장치 할당 성공은 pVM 내부에서 해당 장치 드라이버가 정상 동작한다는 뜻이 아니다. GPU
드라이버 기동은 Phase 10의 선행 확인 항목으로 별도로 다룬다.

pKVM의 DMA 격리는 upstream 미머지 RFC에 의존한다. 이 Phase의 결과는 특정 시점의 개발
브랜치에 대한 것이며, upstream 병합 결과와 다를 수 있다. 사용한 커밋 SHA를 결과 문서에
반드시 기록한다.
