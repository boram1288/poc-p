# PoC 수행 계획

- 프로젝트: Linux pKVM 기반 Protected VM 격리 검증
- 계획 기준일: 2026-08-14
- 상위 기준: [README](../README.md)의 프로젝트 목표와 성공 조건
- 실행 원칙: 각 Phase의 선행 조건, 작업, 완료 조건, 증빙을 순서대로 충족한다.
- 경로 원칙: 소스는 `work/src`, 생성물과 로그는 `work/build`, 문서는 `docs/phase-{nn}`에 둔다.

## 1. 목표와 검증 수준

이 계획은 README가 정의한 최종 목표를 Phase 단위로 분해한 것이다. 최종 목표는 비신뢰
Host로부터 카메라 영상과 AI 모델/추론 데이터를 격리한 상태로, Camera pVM과 AI pVM이 각자
할당받은 장치로 영상 추론 파이프라인을 수행하는 것이다. 그 앞 단계로 pKVM의 격리 경계를
기능 수준에서 먼저 확인하고, 이어서 장치와 데이터 경로로 확장한다.

### 1.1 상태 어휘

| 상태 | 의미 |
|---|---|
| 완료 | 완료 조건과 증빙 로그를 모두 확보 |
| 진행 중 | 착수했고 완료 조건 일부만 충족 |
| 미착수 | 환경과 선행 조건은 있으나 아직 시작하지 않음 |
| 방식 미결 | 구현 경로가 결정되지 않아 착수 불가 |
| 환경 미확보 | 필요한 실행 환경이 없어 착수 불가 |

### 1.2 목표

| ID | 목표 | 완료 조건 | 담당 Phase | 현재 상태 |
|---|---|---|---|---|
| G-1 | pKVM 커널 준비 | Linux v6.18 위에 필요한 패치를 적용하고 두 툴체인으로 빌드 | 02 | 완료 |
| G-2 | protected 부팅 | QEMU에서 EL2 진입과 protected nVHE 초기화 로그 확인 | 03 | 완료 |
| G-3 | 단일 pVM 실행 | protected VM/vCPU 생성 후 `KVM_RUN` 완료 | 04 | 완료 |
| G-4 | Host CPU 접근 격리 | Host의 private page 접근이 차단됨을 대조군과 함께 확인 | 04 | 완료 |
| G-5 | 다중 pVM 운용 | 독립된 pVM 2개를 동시에 실행하고 종료/자원 회수 확인 | 05 | 완료 |
| G-6 | OP-TEE 공존 | TF-A/OP-TEE와 pKVM이 같은 시스템에서 정상 초기화/동작하고 암호화/복호화 서비스 호출 성공 | 06 | 완료 |
| G-7 | 동적 pVM 수명주기 | Host 요청의 권한/정책 확인과 이미지 검증을 거쳐 pVM 생성, 모니터링, 장애 격리, 종료, 자원 회수 | 07 | 완료 |
| G-8 | 장치 직접 할당 | 카메라 역할 장치와 추론 역할 장치를 각 pVM에 배타적으로 할당하고 회수 | 08 | 미착수 |
| G-9 | DMA 격리 | S2MPU가 있는 환경에서 장치 DMA 접근 차단 확인 | 08 | 미착수 |
| G-10 | zero-copy 프레임 전달 | 카메라 프레임을 Host에 노출하지 않고 Camera pVM에서 AI pVM으로 복사 없이 이전 | 09 | 방식 미결 |
| G-11 | AI 추론 결과 반환 | AI pVM이 CPU 경로로 추론을 완료하고 허용된 결과만 Host Application에 반환 | 10 | 미착수 |

G-8과 G-11의 완료 조건은 D-9 확정에 따라 QEMU 에뮬레이션 장치 기준으로 판정한다. 실물
USB 카메라와 NVIDIA GPU는 이 PoC의 범위에서 제외했다. 상세는 4절의 D-9와 [Phase 08의
하드웨어 후보 조사](phase-08/hardware-candidates.md)에 있다.

### 1.3 README 성공 조건과의 매핑

| README 성공 조건 | 대응 목표 | 대응 Phase |
|---|---|---|
| 1. pKVM 커널과 OP-TEE가 동일 시스템에서 초기화/동작 | G-1, G-2, G-6 | 02, 03, 06 |
| 2. Camera/AI pVM 동시 실행과 메모리 격리 | G-3, G-4, G-5 | 04, 05 |
| 3. 카메라/추론 역할 장치 직접 할당, 회수, 배타적 소유권 전환 | G-8, G-9 | 08 |
| 4. 카메라 프레임의 Host 비노출 zero-copy 전달 | G-10 | 09 |
| 5. CPU 경로 추론 완료와 허용된 결과만 반환 | G-11 | 10 |
| 6. pVM 종료 후 장치/메모리/vCPU 자원 회수 | G-5, G-7, G-8 | 05, 07, 08 |

G-4는 Host CPU 매핑 경로에 대한 기능 검증이다. G-9를 완료하기 전에는 "Host가 침해되어도
모든 경로에서 pVM 메모리가 보호된다"는 전체 기밀성 보장을 주장하지 않는다.

성공 조건 3의 카메라 역할 장치와 추론 역할 장치는 QEMU 에뮬레이션 장치다. Reference
Scenario의 USB 카메라와 NVIDIA GPU가 각각 여기에 대응한다. 성공 조건 5는 Reference
Scenario의 GPU 추론을 AI pVM 안의 CPU 추론으로 대체한 것이다.

두 조건 모두 장치 할당 경로, 소유권 전환, DMA 격리 로직, 결과 반환 경로가 성립하는지를
판정한다. 실제 USB 카메라와 NVIDIA GPU에 대한 동작과 기밀성은 이 PoC에서 주장하지 않는다.

## 2. 범위

포함 범위:

- upstream Linux v6.18 기반 pKVM 커널 구성
- clang 및 gcc 빌드 재현
- QEMU TCG의 arm64 EL2 위에서 protected nVHE 초기화
- KVM ioctl 기반 pVM 생성/실행과 Host CPU의 pVM private page 접근 차단
- pVM 2개 동시 운용
- OP-TEE 공존과 pVM 실행 중 암호화/복호화 서비스 호출
- Host 요청 기반 pVM 동적 생성, 이미지 검증, 종료, 자원 회수
- QEMU 에뮬레이션 장치의 pVM 직접 할당과 S2MPU 기반 DMA 격리
- Camera pVM에서 AI pVM으로의 프레임 버퍼 소유권 이전
- AI pVM의 추론 수행과 결과만 반환하는 경로

제외 범위:

- 성능 정량 평가와 최적화
- 제품 수준 Framework/Middleware
- 암호화 저장 파이프라인과 비밀 프로비저닝 구현
- 다중 카메라, 다중 GPU 또는 다중 파이프라인 확장
- pKVM 코드의 upstream 투고
- 실물 arm64 하드웨어 조달과 실장치 검증
- 실제 USB 카메라와 discrete NVIDIA GPU의 pVM 할당
- GPU 가속 추론과 pVM 내부 GPU 드라이버 기동

제외 범위는 기능 성립을 확인한 뒤의 과제로 본다. 특히 성능은 zero-copy 경로가 성립하는지만
확인하고 처리량과 지연은 측정 대상에서 뺀다.

## 3. 실행 환경 프로필

서로 다른 환경을 하나의 결과로 섞지 않는다.

| 프로필 | 목적 | 구성 | 담당 Phase | 상태 |
|---|---|---|---|---|
| E-1 기능 검증 | 커널/pVM 기능 경로 확인 | x86_64, QEMU 4.2.1 TCG, `virt,virtualization=on`, OP-TEE 없음 | 02~05, 07 | 사용 중 |
| E-2 통합 검증 | Secure World 공존 확인 | QEMU 8.2.2, TF-A v2.13-rc0, OP-TEE 4.7.0, pKVM 커널 | 06 | 사용 완료 |
| E-3 장치 할당 및 DMA 격리 검증 | 장치 할당, DMA 격리, 추론 파이프라인 확인 | QEMU (SMMUv3 stage-2 지원), `virt,iommu=smmuv3`, pKVM 커널, 에뮬레이션 장치 | 08~10 | 구성 가능 |

E-1 결과는 E-2 또는 E-3의 결과를 대신하지 않는다.

E-3는 D-9에서 H-6(QEMU `virt,iommu=smmuv3`)으로 확정했다. pKVM S2MPU 드라이버 RFC 자체가
QEMU에서 테스트되므로 DMA 격리 로직을 하드웨어 없이 검증할 수 있다. 근거는 [Phase 08의
하드웨어 후보 조사](phase-08/hardware-candidates.md)에 있다.

E-3는 에뮬레이션 환경이다. E-3 결과는 실물 하드웨어의 기밀성을 대신하지 않는다. 모든
E-3 결과에는 에뮬레이션 환경임을 함께 표기한다.

## 4. 결정 사항

| ID | 결정 | 상태 | 근거 |
|---|---|---|---|
| D-1 | 타깃 커널은 Linux v6.18 LTS | 확정 | Phase 01 조사 |
| D-2 | 패치 목록 기준은 `pkvm-mainline-6.18`, 선형 초안은 `pkvm-master-6.18` 사용 | 확정 | 두 브랜치의 완전성과 적용 편의 분리 |
| D-3 | 첫 pVM 검증은 커널 KVM selftest와 직접 ioctl 프로브 사용 | 확정 | VMM 의존성을 최소화한 기능 검증 |
| D-4 | 다중 pVM VMM은 직접 KVM selftest를 조정하는 최소 오케스트레이터 사용 | 확정 | Phase 04 경로를 재사용해 두 KVM VM/vCPU의 동시 운용과 장애 격리를 최소 의존성으로 검증 |
| D-5 | OP-TEE 검증은 E-1과 분리된 E-2 환경에서 수행 | 확정 | 현재 QEMU-only 결과와 통합 결과 혼동 방지 |
| D-6 | E-1 이미지 검증은 Host 관리자 소유 SHA-256 허용 목록 사용. pvmfw 신뢰 체인은 후속 과제 | 확정 | 커널에 pvmfw 적재 훅은 있으나 E-1에 firmware와 검증된 부트 체인이 없어 Phase 07 PoC는 실행 전 해시 검증으로 대체 |
| D-7 | 장치 직접 할당 경로는 VFIO와 pKVM pvIOMMU 조합으로 검토 | 미결 | AVF는 `vfio-platform` 경로만 문서화. PCIe 할당 경로 확인 필요 |
| D-8 | pVM 간 프레임 전달은 EL2 벤더 모듈 확장을 1안, Host 릴레이를 대조군으로 둔다 | 미결 | upstream pKVM에 guest-to-guest 메모리 프리미티브가 없음 |
| D-9 | E-3는 H-6(QEMU `virt,iommu=smmuv3`) 단일 환경. 실물 하드웨어는 PoC 범위에서 제외 | 확정 | Phase 08 조사. 실물 후보는 모두 미검증 리스크가 남고 조달 비용이 큼 |

D-9 확정으로 실물 하드웨어 후보 H-1~H-5는 채택하지 않는다. Phase 08과 Phase 10은 QEMU
에뮬레이션 장치로 수행한다. 실장치 검증은 이 PoC 이후의 후속 과제로 분리하며, 조사 결과는
[하드웨어 후보 조사](phase-08/hardware-candidates.md)에 남긴다.

D-8의 근거는 [pVM 전달 조사](../../test-p/docs/99_pvm_dmabuf_transfer.md)다. 조사 결론은
표준 스택만으로는 pVM 간 zero-copy 전달이 불가하고, EL2 벤더 모듈로 guest-to-guest
share/lend 하이퍼콜을 구현하는 것이 사실상 유일한 경로라는 것이다.

## 5. Phase 계획

| Phase | 목적 | 환경 | 상태 | 문서 |
|---|---|---|---|---|
| 00 | 범위, 요구사항, 환경 프로필 확정 | - | 완료 | [phase-00](phase-00/README.md) |
| 01 | 커널 버전과 pKVM 패치 소스 결정 | - | 완료 | [phase-01](phase-01/README.md) |
| 02 | 커널 소스 통합 및 빌드 | E-1 | 완료 | [phase-02](phase-02/README.md) |
| 03 | QEMU protected 부팅 및 EL2 초기화 | E-1 | 완료 | [phase-03](phase-03/README.md) |
| 04 | 단일 pVM 실행 및 Host CPU 접근 격리 | E-1 | 완료 | [phase-04](phase-04/README.md) |
| 05 | pVM 2개 동시 생성/운용 | E-1 | 완료 | [phase-05](phase-05/README.md) |
| 06 | OP-TEE와 pKVM 공존 | E-2 | 완료 | [phase-06](phase-06/README.md) |
| 07 | 동적 pVM 수명주기 관리 | E-1 | 완료 | [phase-07](phase-07/README.md) |
| 08 | 장치 직접 할당과 DMA 격리 | E-3 | 완료 | [phase-08](phase-08/README.md) |
| 09 | 프레임 버퍼 zero-copy 소유권 이전 | E-1, E-3 | 방식 미결 | [phase-09](phase-09/README.md) |
| 10 | AI 추론 파이프라인 통합 | E-3 | 미착수 | [phase-10](phase-10/README.md) |
| 11 | 결과 종합 및 요구사항 매핑 | - | 진행 중 | [phase-11](phase-11/README.md) |

Phase 05, 06, 07은 E-1과 E-2에서 병행할 수 있다. D-9 확정으로 Phase 08과 Phase 10도
하드웨어 대기 없이 착수할 수 있다. Phase 08은 E-3 환경 구성만 끝나면 Phase 05, 06, 07과
병행 가능하다.

### Phase 00. 범위와 환경 확정

1. 검증 목표를 CPU 접근 격리, DMA 격리, 다중 pVM, OP-TEE 공존, 동적 수명주기, 장치 할당,
   zero-copy 전달, AI 추론으로 분해한다.
2. E-1, E-2, E-3 환경을 구분한다.
3. 생성물 경로와 문서화 규칙을 확정한다.

완료 조건: 목표별 성공 판정과 현재 환경의 한계가 문서화되어야 한다.

### Phase 01. 커널과 패치 소스 결정

1. ACK와 android-kvm 브랜치 관계를 조사한다.
2. 6.12, 6.18 및 최신 개발 브랜치를 비교한다.
3. 패치 추출 기준과 빌드 기준을 구분한다.
4. 경로 기반 집합과 실제 빌드 집합을 별도로 기록한다.

완료 조건: v6.18 선택과 두 pKVM 브랜치의 역할이 근거와 함께 확정되어야 한다.

### Phase 02. 소스 통합과 빌드

1. `work/src/pkvm-linux`에 커널 소스를 준비한다.
2. `pkvm-master-6.18`의 394커밋을 v6.18 위에 리베이스한다.
3. `pkvm-mainline-6.18`에서 필요한 후속 커밋과 의존성을 시간순으로 적용한다.
4. 빌드 수정 5건과 충돌 해결 내용을 기록한다.
5. clang과 gcc 산출물을 각각 `work/build` 아래에 생성한다.

완료 조건: 두 툴체인에서 Image, vmlinux, nVHE 오브젝트와 EL2 모듈이 생성되어야 한다.

### Phase 03. protected 부팅

1. 최소 arm64 initramfs를 생성한다.
2. QEMU TCG에서 EL2를 노출하고 `kvm-arm.mode=protected`로 부팅한다.
3. EL2 진입, Protected KVM 감지, protected nVHE 초기화, user space 도달을 확인한다.

완료 조건: 네 개 성공 마커와 정상 종료 로그가 남아야 한다.

### Phase 04. 단일 pVM과 메모리 격리

1. 최신 UAPI 헤더로 pKVM selftest를 정적 크로스 빌드한다.
2. `/dev/kvm`과 `KVM_CAP_ARM_PROTECTED_VM`을 확인한다.
3. protected VM/vCPU 생성 후 게스트 코드를 실행한다.
4. private page 접근 차단과 teardown 후 메모리 회수를 확인한다.

완료 조건: `All ok!`, selftest rc=0, 예상된 segfault, 자원 회수 로그가 모두 있어야 한다.

### Phase 05. 다중 pVM

1. 최소 VMM과 crosvm 중 구현 경로를 결정한다.
2. Camera 역할과 AI 역할의 pVM을 각각 생성한다.
3. 두 pVM을 동시에 `KVM_RUN` 상태로 유지한다.
4. 주소 공간과 private memory가 상호 독립임을 확인한다.
5. 한 pVM의 실패가 다른 pVM에 전파되지 않는지 확인한다.

완료 조건: 두 pVM의 동시 heartbeat, 독립된 메모리 마커, 정상 종료 및 자원 회수 로그가 필요하다.

### Phase 06. OP-TEE 공존

1. QEMU v8 + TF-A + OP-TEE 기준 부팅을 재현한다.
2. 동일한 Normal World 커널에 Phase 02의 pKVM 구성을 적용한다.
3. Secure/Normal World 콘솔과 pKVM 초기화를 동시에 확인한다.
4. pVM 실행 중 `xtest` 또는 최소 TA 호출을 수행한다.
5. 카메라 영상에 해당하는 데이터의 암호화/복호화를 TA로 처리한다.

완료 조건: OP-TEE 호출과 pVM 실행이 같은 부팅 세션에서 모두 성공해야 한다.

### Phase 07. 동적 pVM 수명주기 관리

1. Host Application의 pVM 생성 요청을 받는 제어 경로를 정의한다.
2. 요청자의 권한과 정책을 확인하는 최소 검사를 구현한다.
3. pVM 이미지의 무결성 검증 방식을 결정한다. pvmfw 기준을 먼저 평가한다.
4. 생성, 실행 상태 모니터링, 종료를 하나의 제어 흐름으로 묶는다.
5. 한 pVM의 장애가 다른 pVM과 Host 제어 경로로 전파되지 않게 격리한다.
6. 종료 후 메모리와 vCPU 자원 회수를 확인한다.

완료 조건: 권한 거부, 이미지 검증 실패, 정상 생성, 장애 격리, 정상 종료의 다섯 경로가
각각 재현되고 로그로 구분되어야 한다.

### Phase 08. 장치 직접 할당과 DMA 격리

E-3에서 수행한다. 실물 하드웨어는 사용하지 않는다.

1. SMMUv3 stage-2를 지원하는 QEMU를 `virt,iommu=smmuv3`로 구성해 pKVM 커널을 protected 모드로 부팅한다.
2. `Found N assignable devices`에서 N이 0이 아님을 확인한다.
3. pVM에 장치를 할당하는 경로를 확정하고 D-7에 반영한다.
4. 카메라 역할 장치를 Camera pVM에, 추론 역할 장치를 AI pVM에 배타적으로 할당한다.
5. Host와 다른 pVM에서 해당 장치에 접근할 수 없음을 확인한다.
6. 장치 DMA가 소유 pVM의 메모리 범위를 벗어나지 못하는지 확인한다.
7. 범위를 벗어나는 DMA를 의도적으로 유발해 S2MPU 차단 결과를 대조군과 함께 남긴다.
8. pVM 종료 후 장치 소유권이 회수되고 재할당 가능한지 확인한다.

9. EL2 shared-buffer manager로 Camera가 승인한 4 KiB page를 AI pVIOMMU domain에 read-only로
   매핑하고, 승인되지 않은 receiver SID를 거부한다.
10. Camera teardown 뒤 AI의 기존 shared IOVA DMA가 차단되고 mapping/page reference가
    receiver context에서 회수되는지 확인한다.

완료 조건: 장치 할당 성공 로그, Host 접근 차단 결과, DMA 범위 위반 차단, 승인된 pVM 간
DMA read, 승인되지 않은 receiver 차단, owner teardown revoke, 회수 후 재할당 성공이
모두 있어야 한다. 모든 결과에 에뮬레이션 환경임을 함께 기록한다.

하드웨어 후보 비교와 제약은 [하드웨어 후보 조사](phase-08/hardware-candidates.md)에 있다.

### Phase 09. 프레임 버퍼 zero-copy 소유권 이전

1. Host 릴레이 경로로 대조군을 먼저 구성한다. 이 경로는 복사가 발생하고 Host에 노출된다.
2. EL2 벤더 모듈로 guest-to-guest share/lend 하이퍼콜을 설계한다.
3. Camera pVM이 캡처 버퍼의 소유권을 AI pVM으로 이전하는 경로를 구현한다.
4. 이전 전후로 Host stage-2에 해당 페이지가 매핑되지 않음을 확인한다.
5. 버퍼 핸들과 링 인덱스를 주고받는 제어 채널을 별도로 둔다.
6. 대조군과 zero-copy 경로의 복사 횟수를 비교해 기록한다.

완료 조건: AI pVM이 Camera pVM의 프레임 마커를 읽고, 같은 구간에 대한 Host 접근이 차단되며,
전달 과정에 데이터 복사가 없음이 확인되어야 한다.

### Phase 10. AI 추론 파이프라인 통합

1. AI pVM 안에서 추론 런타임을 기동한다. GPU 가속 없이 CPU 경로로 수행한다.
2. Phase 09로 전달받은 프레임에 대해 추론을 수행한다.
3. 모델 가중치와 중간 데이터가 AI pVM 밖으로 나가지 않음을 확인한다.
4. 추론 결과만 Host Application으로 반환하는 경로를 구현한다.
5. 캡처, 전달, 추론, 결과 반환을 반복 실행하고 종료 명령으로 정지한다.
6. 파이프라인 종료 후 두 pVM의 장치와 메모리 자원을 회수한다.

완료 조건: 반복 실행에서 추론 결과가 Host에 도달하고, 영상 원본과 모델 데이터에 대한 Host
접근이 모두 차단되어야 한다. GPU 가속 성립 여부는 판정 대상이 아니다.

### Phase 11. 결과 종합

1. G-1부터 G-11까지 결과와 증빙을 연결한다.
2. README 성공 조건 6개에 대한 달성 여부를 판정한다.
3. 기능 검증과 보안 보증의 경계를 명시한다.
4. 재현 명령, 커밋, 툴체인과 로그 위치를 고정한다.
5. 미검증 항목과 후속 검증을 분리해 정리한다.

완료 조건: 모든 주장에 실행 환경과 근거 로그가 연결되고 미검증 항목이 분리되어야 한다.

## 6. 산출물 규칙

- Phase 설명과 판단 근거: `docs/phase-{nn}/`
- Linux와 프로젝트 소스: `work/src/`
- 커널, initramfs, selftest, 로그: `work/build/`
- 커널 작업 트리: `work/src/pkvm-linux`, Git submodule로 커밋 SHA만 상위에 기록
- 모든 빌드 결과: Git 비추적
- 프로젝트가 관리하는 실행/분석 도구: `work/src/tools/`, Git 추적

커널 트리를 submodule로 둔 이유는 재현성이다. 상위 저장소의 각 커밋이 어떤 커널 커밋으로
검증됐는지 SHA로 고정된다. 갱신할 때는 submodule 저장소에 먼저 push한 뒤 상위에서 새 SHA를
커밋한다. 순서를 바꾸면 상위 저장소가 원격에 없는 커밋을 가리킨다.

각 Phase 문서는 다음 섹션을 포함한다.

| 섹션 | 내용 |
|---|---|
| 머리말 | 상태, 목적, 환경 프로필, 관련 목표 ID, 주요 경로 |
| 선행 조건 | 착수 전에 충족해야 할 항목 |
| 절차 또는 계획 | 실행한 순서 또는 예정 순서 |
| 완료 조건 | 판정 기준과 성공 마커 |
| 결과 또는 예정 산출물 | 확인된 결과 또는 만들 산출물 |
| 한계 | 이 Phase가 주장하지 않는 범위 |

## 7. 주요 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| 경로 기반 패치 필터 오판 | 필수 의존성 누락 또는 무관 패치 포함 | 실제 빌드와 파일 단위 검토로 교차 검증 |
| master/mainline 구현 차이 | 같은 제목의 커밋도 변경 파일이 달라 빌드 실패 | 제목뿐 아니라 변경 파일 집합 비교 |
| TCG와 실제 하드웨어 차이 | 기능 성공을 제품 보안 보증으로 오해 | 환경 프로필과 검증 수준을 결과마다 표시 |
| 실물 S2MPU 부재 | 실장치 DMA 기밀성 검증 불가 | D-9에서 범위 제외로 확정. 모든 DMA 격리 결과에 에뮬레이션 표기를 붙이고 실장치 판정은 후속 과제로 분리 |
| QEMU S2MPU 에뮬레이션과 실물 `SMMUv3`의 차이 | E-3 결과가 실물에서 재현되지 않을 수 있음 | QEMU 버전과 머신 옵션을 결과 문서에 고정 기록. 실물 확장 시 재검증 항목으로 명시 |
| pKVM에 PCIe 장치 할당 경로 부재 | 에뮬레이션 PCIe 장치도 pVM에 할당 불가 | Q-2를 Phase 08 착수 시 선행 조사. 없으면 `vfio-platform` 경로의 에뮬레이션 장치로 전환 |
| pKVM DMA 격리가 upstream 미머지 | 개발 브랜치 갱신 시 결과 재현 불가 | 사용한 커밋 SHA를 결과 문서에 고정 기록 |
| pVM 간 zero-copy 프리미티브 부재 | Phase 09에서 EL2 확장 개발 필요, 일정과 난이도 급증 | Host 릴레이 대조군을 먼저 확보해 파이프라인을 성립시킨 뒤 zero-copy로 대체 |
| 에뮬레이션 장치의 pVM 내부 드라이버 동작 불확실 | Phase 10 지연 | Phase 08에서 장치 할당 직후 최소 드라이버 기동을 먼저 확인 |
| E-1에 pvmfw 신뢰 체인 미구성 | 비신뢰 Host에 대한 이미지 신뢰 근거 부족 | Phase 07은 SHA-256 허용 목록으로 변조 거부만 검증. pvmfw/verified boot와 서명 키 연결은 후속 과제로 명시 |
| OP-TEE 커널 통합 충돌 | Phase 06 지연 | E-2 베이스라인을 먼저 고정하고 pKVM을 단계적으로 적용 |
| 재생성 불가능한 work 산출물 | 결과 추적 불가 | 커밋 SHA, 명령, 로그 마커를 Phase 문서에 기록 |

## 8. 참조 문서

- 과제 개요: `../../test-p/docs/00_overview.md`
- 레퍼런스 시나리오: `../../test-p/docs/02_reference_scenario.md`
- pVM 전달 조사: `../../test-p/docs/99_pvm_dmabuf_transfer.md`
- pvmfw 조사: `../../test-p/docs/99_pvmfw.md`
- OP-TEE QEMU 문서: `../../database/optee-documentation/_sources/building/devices/qemu.rst.txt`

경로는 이 문서(`docs/PLAN.md`) 기준의 상대 경로다. 저장소 루트 기준으로는 `../test-p/`와
`../database/` 아래에 있다.
