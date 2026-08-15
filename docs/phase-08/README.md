# Phase 08: 장치 직접 할당과 DMA 격리

- 상태: 미착수
- 목적: 카메라 역할 장치와 추론 역할 장치를 각 pVM에 배타적으로 할당하고, 장치 DMA가 소유 pVM 밖으로 나가지 못하게 한다.
- 환경: E-3
- 관련 목표: G-8, G-9
- 관련 결정: D-7, D-9

## 선행 조건

- QEMU v9 이상과 `virt,iommu=smmuv3` 구성
- Phase 02의 pKVM 커널이 해당 QEMU 머신에서 부팅
- Phase 05의 다중 pVM 운용 성공

## D-9 결정

D-9는 H-6(QEMU `virt,iommu=smmuv3`)으로 확정했다. E-3는 QEMU 단일 환경이며 실물
하드웨어는 PoC 범위에서 제외한다. 후보 비교와 근거는 [하드웨어 후보
조사](hardware-candidates.md)에 있다.

### 후보와 판정

| ID | 후보 | 판정 |
|---|---|---|
| H-1 | Ampere Altra Developer Platform | 미채택 |
| H-2 | NVIDIA Jetson AGX Thor Developer Kit | 미채택 |
| H-3 | NVIDIA Jetson AGX Orin Developer Kit | 미채택 |
| H-4 | Arm Morello board | 미채택 |
| H-5 | NVIDIA DGX Spark (GB10) | 미채택 |
| H-6 | QEMU `virt,iommu=smmuv3` | 채택 |

H-6를 채택한 근거는 세 가지다.

1. pKVM S2MPU 드라이버 RFC v4가 QEMU에서 테스트됐다. S1 only, S2 only, nested 세 조합과
   4K/16K/64K 페이지 크기를 포함한다. 검증된 실행 환경이다.
2. 실물 후보는 모두 `kvm-arm.mode=protected` 부팅 사례가 확인되지 않는다. 조달 후에도
   성립 여부를 알 수 없는 리스크가 남는다.
3. `vfio-pci` 기반 discrete GPU 할당 경로가 문서화되어 있지 않다. 이 제약은 하드웨어를
   무엇으로 고르든 남으므로 하드웨어 조달로 해소되지 않는다.

Phase 03의 `Found 0 assignable devices`는 QEMU 4.2.1에 S2MPU 옵션을 주지 않아서 나온
결과다. QEMU가 원리적으로 불가한 것이 아니다.

### 판정 대상의 변경

실물 장치가 없으므로 G-8의 판정 대상을 다음과 같이 대체한다.

| 원래 대상 | 대체 대상 |
|---|---|
| USB 카메라 | Camera pVM에 할당하는 에뮬레이션 카메라 역할 장치 |
| NVIDIA GPU | AI pVM에 할당하는 에뮬레이션 추론 역할 장치 |

판정하는 것은 장치 할당 경로, 배타적 소유권, DMA 격리, 회수와 재할당이 성립하는지다.
실제 카메라 캡처 성능이나 GPU 가속은 판정 대상이 아니다.

### 확정 후에도 남는 제약

1. 커널 공식 문서는 pKVM의 "DMA isolation using an IOMMU"를 미구현으로 표기한다. S2MPU
   드라이버는 2023년부터 RFC 상태이며 아직 머지되지 않았다. Phase 02가 활성화한 설정은
   android-kvm 트리 기준이고 upstream 상태와 다르다.
2. AVF의 장치 할당은 `vfio-platform` 경로다. `vfio-pci` 기반 PCIe 장치 할당은 pKVM과 AVF
   문서 어디에도 명시되어 있지 않다. 에뮬레이션 PCIe 장치에도 같은 제약이 적용된다.
   Q-2의 조사 결과에 따라 `vfio-platform` 경로의 에뮬레이션 장치로 전환할 수 있다.
3. QEMU의 S2MPU는 에뮬레이션이다. 실물 `SMMUv3`의 동작과 다를 수 있다.

### 남은 확인 항목

| 항목 | 내용 | 해소 방법 |
|---|---|---|
| Q-2 | pVM에 장치를 할당하는 경로 | Phase 08 착수 시 선행 조사, D-7에 반영 |

D-9 조사 당시의 Q-1, Q-3, Q-4는 실물 하드웨어 채택을 전제한 항목이었다. H-6 확정으로
해소 대상에서 제외한다.

## 계획

1. QEMU v9 이상을 준비하고 `virt,iommu=smmuv3`로 pKVM 커널을 protected 모드로 부팅한다.
2. `Found N assignable devices`가 0이 아닌 값이 되는지 확인한다.
3. pVM에 장치를 할당하는 경로를 조사해 확정하고 결과를 D-7에 반영한다.
4. 카메라 역할 장치를 Camera pVM에, 추론 역할 장치를 AI pVM에 배타적으로 할당한다.
5. Host와 다른 pVM에서 해당 장치에 접근할 수 없음을 확인한다.
6. 장치 DMA가 소유 pVM의 메모리 범위를 벗어나지 못하는지 확인한다.
7. 범위를 벗어나는 DMA를 의도적으로 유발해 S2MPU 차단 결과를 얻는다.
8. 할당한 장치의 최소 드라이버가 pVM 안에서 기동하는지 확인한다.
9. pVM 종료 후 장치 소유권이 회수되고 재할당 가능한지 확인한다.

## 완료 조건

| 검사 | 판정 |
|---|---|
| 할당 가능 장치 인식 | `Found N assignable devices`에서 N이 0이 아니다 |
| 장치 배타 할당 | 두 장치가 각각 다른 pVM에 할당된다 |
| Host 접근 차단 | 할당 중 Host와 비소유 pVM의 접근이 차단된다 |
| DMA 범위 위반 차단 | 소유 범위 밖 DMA가 S2MPU에서 차단된다 |
| pVM 내부 드라이버 기동 | 할당된 장치의 최소 드라이버가 pVM 안에서 기동한다 |
| 회수와 재할당 | pVM 종료 후 장치가 회수되고 다시 할당된다 |

차단 결과에는 반드시 대조군(차단되지 않는 정상 접근)이 함께 있어야 한다. 모든 결과에
QEMU 버전과 머신 옵션을 함께 기록한다.

## 예정 산출물

- 하드웨어 후보 조사: [hardware-candidates.md](hardware-candidates.md)
- E-3 환경 구성과 부팅 절차: 이 디렉터리에 추가
- 할당 도구: `work/src/tools/device-assign/`
- 부팅 및 실행 로그: `work/build/device-assign/`
- 결과 문서: 이 디렉터리에 추가

## 한계

이 Phase가 완료되기 전까지 "Host가 침해되어도 모든 경로에서 pVM 메모리가 보호된다"는
주장을 하지 않는다. Phase 04의 결과는 CPU 매핑 경로에 한정된다.

E-3는 에뮬레이션 환경이다. E-3에서 DMA 격리가 성립해도 실제 하드웨어의 기밀성을 주장하지
않는다. 실물 USB 카메라와 discrete NVIDIA GPU에 대한 할당과 DMA 격리는 이 PoC에서
검증하지 않으며 후속 과제로 남긴다.

장치 할당 성공은 실제 카메라 캡처나 GPU 가속이 성립한다는 뜻이 아니다.

pKVM의 DMA 격리는 upstream 미머지 RFC에 의존한다. 이 Phase의 결과는 특정 시점의 개발
브랜치에 대한 것이며, upstream 병합 결과와 다를 수 있다. 사용한 커밋 SHA를 결과 문서에
반드시 기록한다.
