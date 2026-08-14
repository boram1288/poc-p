# PoC 수행 계획

- 프로젝트: Linux pKVM 기반 Protected VM 격리 검증
- 계획 기준일: 2026-08-14
- 실행 원칙: 각 Phase의 선행 조건, 작업, 완료 조건, 증빙을 순서대로 충족한다.
- 경로 원칙: 소스는 `work/src`, 생성물과 로그는 `work/build`, 문서는 `docs/phase-{nn}`에 둔다.

## 1. 목표와 검증 수준

PoC의 최종 목표는 pKVM이 Host와 pVM 사이에 제공하는 격리 경계를 기능 수준에서 확인하고,
향후 다중 pVM 및 OP-TEE 통합 검증으로 확장할 수 있는 재현 가능한 기반을 만드는 것이다.

| ID | 목표 | 완료 조건 | 현재 상태 |
|---|---|---|---|
| G-1 | pKVM 커널 준비 | Linux v6.18 위에 필요한 패치를 적용하고 두 툴체인으로 빌드 | 완료 |
| G-2 | protected 부팅 | QEMU에서 EL2 진입과 protected nVHE 초기화 로그 확인 | 완료 |
| G-3 | 단일 pVM 실행 | protected VM·vCPU 생성 후 `KVM_RUN` 완료 | 완료 |
| G-4 | Host CPU 접근 격리 | Host의 private page 접근이 차단됨을 대조군과 함께 확인 | 완료 |
| G-5 | 다중 pVM 운용 | 독립된 pVM 2개를 동시에 실행하고 종료·자원 회수 확인 | 미착수 |
| G-6 | OP-TEE 공존 | TF-A/OP-TEE와 pKVM이 같은 시스템에서 정상 초기화·동작 | 미착수 |
| G-7 | DMA 격리 | SMMU/IOMMU가 있는 환경에서 장치 DMA 접근 차단 확인 | 환경 미확보 |

G-4는 Host CPU 매핑 경로에 대한 기능 검증이다. G-7을 완료하기 전에는 “Host가 침해되어도
모든 경로에서 pVM 메모리가 보호된다”는 전체 기밀성 보장을 주장하지 않는다.

## 2. 범위

포함 범위:

- upstream Linux v6.18 기반 pKVM 커널 구성
- clang 및 gcc 빌드 재현
- QEMU TCG의 arm64 EL2 위에서 protected nVHE 초기화
- KVM ioctl 기반 pVM 생성·실행
- Host CPU의 pVM private page 접근 차단
- pVM 2개 동시 운용과 OP-TEE 공존으로의 단계적 확장

현재 제외 범위:

- Camera/AI 하드웨어 가속과 성능 평가
- pVM 간 zero-copy DMA-BUF 데이터 전달
- 제품 수준 Framework/Middleware
- 암호화 저장 파이프라인과 비밀 프로비저닝
- pKVM 코드의 upstream 투고

## 3. 실행 환경 프로필

서로 다른 환경을 하나의 결과로 섞지 않는다.

| 프로필 | 목적 | 구성 | 상태 |
|---|---|---|---|
| E-1 기능 검증 | 커널·pVM 기능 경로 확인 | x86_64, QEMU 4.2.1 TCG, `virt,virtualization=on`, OP-TEE 없음 | 사용 중 |
| E-2 통합 검증 | Secure World 공존 확인 | QEMU v8, TF-A, OP-TEE, pKVM 커널 | Phase 06에서 구성 |
| E-3 보안 검증 | DMA 격리와 기밀성 확인 | SMMUv3 및 assignable device를 제공하는 ARM 환경 | 미확보 |

E-1 결과는 E-2 또는 E-3의 결과를 대신하지 않는다.

## 4. 결정 사항

| ID | 결정 | 상태 | 근거 |
|---|---|---|---|
| D-1 | 타깃 커널은 Linux v6.18 LTS | 확정 | Phase 01 조사 |
| D-2 | 패치 목록 기준은 `pkvm-mainline-6.18`, 선형 초안은 `pkvm-master-6.18` 사용 | 확정 | 두 브랜치의 완전성과 적용 편의 분리 |
| D-3 | 첫 pVM 검증은 커널 KVM selftest와 직접 ioctl 프로브 사용 | 확정 | VMM 의존성을 최소화한 기능 검증 |
| D-4 | 다중 pVM VMM은 Phase 05에서 최소 구현과 crosvm을 비교 후 결정 | 미결 | 동시 운용 요구에 맞춰 별도 평가 필요 |
| D-5 | OP-TEE 검증은 E-1과 분리된 E-2 환경에서 수행 | 확정 | 현재 QEMU-only 결과와 통합 결과 혼동 방지 |

## 5. Phase 계획

| Phase | 목적 | 상태 | 문서 |
|---|---|---|---|
| 00 | 범위, 요구사항, 환경 프로필 확정 | 완료 | [phase-00](phase-00/README.md) |
| 01 | 커널 버전과 pKVM 패치 소스 결정 | 완료 | [phase-01](phase-01/README.md) |
| 02 | 커널 소스 통합 및 빌드 | 완료 | [phase-02](phase-02/README.md) |
| 03 | QEMU protected 부팅 및 EL2 초기화 | 완료 | [phase-03](phase-03/README.md) |
| 04 | 단일 pVM 실행 및 Host CPU 접근 격리 | 완료 | [phase-04](phase-04/README.md) |
| 05 | pVM 2개 동시 생성·운용 | 미착수 | [phase-05](phase-05/README.md) |
| 06 | OP-TEE와 pKVM 공존 | 미착수 | [phase-06](phase-06/README.md) |
| 07 | 결과 종합 및 요구사항 매핑 | 진행 예정 | [phase-07](phase-07/README.md) |

### Phase 00. 범위와 환경 확정

1. 검증 목표를 CPU 접근 격리, DMA 격리, 다중 pVM, OP-TEE 공존으로 분해한다.
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
3. protected VM·vCPU 생성 후 게스트 코드를 실행한다.
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

완료 조건: OP-TEE 호출과 pVM 실행이 같은 부팅 세션에서 모두 성공해야 한다.

### Phase 07. 결과 종합

1. G-1부터 G-7까지 결과와 증빙을 연결한다.
2. 기능 검증과 보안 보증의 경계를 명시한다.
3. 재현 명령, 커밋, 툴체인과 로그 위치를 고정한다.
4. 실제 ARM/SMMU 환경에서 필요한 후속 검증을 정리한다.

완료 조건: 모든 주장에 실행 환경과 근거 로그가 연결되고 미검증 항목이 분리되어야 한다.

## 6. 산출물 규칙

- Phase 설명과 판단 근거: `docs/phase-{nn}/`
- Linux와 프로젝트 소스: `work/src/`
- 커널·initramfs·selftest·로그: `work/build/`
- 외부에서 다시 받을 수 있는 대용량 소스와 모든 빌드 결과: Git 비추적
- 프로젝트가 관리하는 실행·분석 도구: `work/src/tools/`, Git 추적

각 Phase 문서는 최소한 목적, 선행 조건, 절차, 완료 조건, 현재 결과, 한계를 포함한다.

## 7. 주요 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| 경로 기반 패치 필터 오판 | 필수 의존성 누락 또는 무관 패치 포함 | 실제 빌드와 파일 단위 검토로 교차 검증 |
| master/mainline 구현 차이 | 같은 제목의 커밋도 변경 파일이 달라 빌드 실패 | 제목뿐 아니라 변경 파일 집합 비교 |
| TCG와 실제 하드웨어 차이 | 기능 성공을 제품 보안 보증으로 오해 | 환경 프로필과 검증 수준을 결과마다 표시 |
| SMMU 부재 | DMA 기밀성 검증 불가 | E-3 환경 확보 전 미검증으로 유지 |
| OP-TEE 커널 통합 충돌 | Phase 06 지연 | E-2 베이스라인을 먼저 고정하고 pKVM을 단계적으로 적용 |
| 재생성 불가능한 work 산출물 | 결과 추적 불가 | 커밋 SHA, 명령, 로그 마커를 Phase 문서에 기록 |

## 8. 참조 문서

- 과제 개요: `../../test-p/docs/00_overview.md`
- 레퍼런스 시나리오: `../../test-p/docs/02_reference_scenario.md`
- pVM 전달 조사: `../../test-p/research/99_pvm_dmabuf_transfer.md`
- pvmfw 조사: `../../test-p/research/99_pvmfw.md`
- OP-TEE QEMU 문서: `../../database/optee-documentation/_sources/building/devices/qemu.rst.txt`
