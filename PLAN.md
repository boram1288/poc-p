# PoC 계획: Linux pKVM 기반 Protected VM 격리 검증

본 문서는 `test-p` 과제(로봇용 Secure Vision AI를 위한 Linux pKVM 기반 가상화 보안 Framework)의
핵심 격리 메커니즘을 최소 범위로 검증하는 PoC 계획이다.

---

## 1. PoC 목표

과제의 근본 가설인 **"Host OS가 침해되어도 pVM 메모리는 노출되지 않는다"(R-1)** 를 실물로 증명한다.

| 목표 | 검증 내용 |
|------|-----------|
| G-1 | OP-TEE + QEMU-v8 위에서 pKVM 지원 Linux 커널 부팅 |
| G-2 | pKVM ioctl로 Protected VM 2개 동시 생성/운용 (R-3의 축소판) |
| G-3 | Host OS에서 pVM 내부 메모리 접근 불가 실증 |
| G-4 | (부가) OP-TEE 공존 확인 — TrustZone Secure OS와 pKVM 동시 상주 (R-5 단서) |

### 범위 제외 (PoC 비대상)

- Camera/AI HW IP 실제 가속 (실물 HW 부재 — 모의 Workload로 대체)
- pVM 간 zero-copy DMA-BUF 전달 (`99_pvm_dmabuf_transfer.md`(→ 8절) 결론상 EL2 vendor module 필요, PoC 범위 밖)
- Framework/Middleware 완성형, 동적 확장성(R-4), 암호화 저장 파이프라인
- pKVM EL2 Hypervisor 자체 포팅 (과제 범위상 기 포팅 전제)

---

## 2. 실행 환경 전제

| 항목 | 내용 |
|------|------|
| 개발 호스트 | x86_64 (Intel i9-12900K, 24 core, 62GB RAM) |
| 타겟 아키텍처 | ARM64 (Armv8-A) |
| 에뮬레이션 | QEMU-v8 `-machine virt,virtualization=on -cpu max` — TCG로 **EL2 제공** |
| Secure World | OP-TEE (TF-A 부트 체인) |
| 참조 문서 | `../database/optee-documentation/_sources/building/devices/qemu.rst.txt` (→ 8절) |

> 주의: 호스트가 x86이므로 KVM 가속이 아닌 TCG 에뮬레이션이다. 기능 검증은 가능하나 성능은 낮다.
> QEMU virt 머신이 게스트에 EL2를 제공하므로, 게스트 Linux가 nVHE pKVM Hypervisor로 동작하고
> 그 위에 pVM을 올리는 구조가 성립한다. (실제 nested HW 가속 불필요)

---

## 3. 핵심 의사결정 지점 (사용자 확인 필요)

| ID | 결정 사항 | 후보 / 방향 |
|----|-----------|-------------|
| D-1 | **Linux 커널 버전** | Android AVF가 사용하는 Android Common Kernel(ACK) 계열 — `android14-6.1` 또는 `android15-6.6`. pKVM 성숙도/upstream 근접성 기준으로 Phase 0에서 조사 후 확정 |
| D-2 | **pVM 생성 인터페이스** | KVM ioctl(`KVM_CREATE_VM` + `KVM_CAP_ARM_PROTECTED_VM` / `KVM_VM_TYPE_ARM_PROTECTED`) 직접 사용 vs crosvm/최소 VMM 활용 |
| D-3 | **pvmfw 사용 여부** | `99_pvmfw.md`(→ 8절) 기준 — 비밀 프로비저닝/부트 검증 없이 순수 격리만 볼지, pvmfw까지 포함할지 |
| D-4 | **OP-TEE 통합 깊이** | G-4 공존 확인만 vs GP API(`libteec`) 호출까지 |

> 위 4개는 PoC 착수 전 확정한다. Phase 0(조사)에서 근거를 정리해 사용자 승인을 받는다.

---

## 4. 단계별 실행 계획

### Phase 0. 커널 버전 결정 (D-1)
- AVF pKVM 기능 요구 커널 버전 조사 (ACK 브랜치, pKVM 패치 머지 현황)
- QEMU virt EL2 에뮬레이션 호환성 확인
- 산출물: 커널 버전 결정 근거 문서 → 사용자 승인

### Phase 1. 베이스라인 구축
- OP-TEE + QEMU-v8 표준 빌드/부팅 (`repo init` → `make run`)
- Secure/Normal World 2개 UART 콘솔 확인
- 산출물: 정상 부팅 로그, VirtFS 공유 폴더 설정

### Phase 2. pKVM 커널 패치 반영
- 결정된 커널에 pKVM 패치 적용
- 부팅 파라미터 `kvm-arm.mode=protected` 활성화
- 산출물: pKVM 모드로 부팅된 커널, `dmesg`상 pKVM 초기화 로그

### Phase 3. Protected VM 2개 생성 (G-2, D-2, D-3)
- pKVM ioctl 경로로 protected VM 2개 기동 (Camera pVM / AI pVM 모사)
- 각 pVM에 최소 게스트 이미지(busybox 등) 탑재
- 산출물: pVM 2개 동시 running 상태 로그

### Phase 4. 메모리 격리 실증 (G-3)
- pVM 내부에 알려진 마커 데이터 배치
- Host에서 pVM 물리 메모리 접근 시도 (`/proc`, VMM 메모리 맵, 디버거)
- 접근 차단 확인 (Stage-2 unmap으로 마커 미검출)
- 산출물: 격리 성공 증빙 (접근 실패 로그 + 대조군 비교)

### Phase 5. OP-TEE 공존 확인 (G-4, D-4)
- pKVM 상주 상태에서 OP-TEE TA 실행 (`xtest` 등)
- Secure World와 pVM 동시 정상 동작 확인
- 산출물: 공존 검증 로그

### Phase 6. 정리/보고
- PoC 결과 종합, 과제 요구사항(R-1/R-3/R-5) 검증 매핑
- 한계/후속 과제 정리 (특히 pVM 간 전달, HW IP 공유)

---

## 5. Orca-IDE 멀티툴 워크플로우

각 Phase는 아래 도구 역할 분담으로 진행한다.

| 역할 | 도구 / 모델 | 담당 작업 |
|------|-------------|-----------|
| 설계/계획 | Claude Opus (xhigh) | 아키텍처 결정, Phase 계획, 리스크 판단, D-1~D-4 근거 정리 |
| 구현/실행/테스트 | opencode (DeepSeek-V4-Flash-Thinking-Max, Ultra) | 빌드 스크립트, 커널 패치 적용, ioctl 코드, QEMU 실행/테스트 |
| 디버깅 | Claude Sonnet (high) | 빌드/부팅 실패, 격리 검증 실패 원인 분석 |

### 협업 규칙
- 중요 의사결정(D-1~D-4)은 Opus가 정리 → 사용자 승인 → opencode 실행.
- 각 Phase 종료 시 결과 검증 후 보고, git commit.
- 실패 시 Sonnet 디버깅 결과를 Opus가 계획에 반영.

---

## 6. 산출물 구조 (예정)

```
poc-p/
  PLAN.md              # 본 문서
  poc/
    00_kernel_decision/# Phase 0 커널 결정 근거
    01_baseline/       # Phase 1 빌드/부팅
    02_pkvm_patch/     # Phase 2 패치
    03_pvm_create/     # Phase 3 pVM 생성 코드/스크립트
    04_isolation/      # Phase 4 격리 검증
    05_optee_coexist/  # Phase 5 공존 검증
  docs/
    RESULT.md          # Phase 6 종합 보고
```

---

## 7. 리스크

| 리스크 | 영향 | 대응 |
|--------|------|------|
| x86 TCG 에뮬레이션 성능 | 빌드/부팅/테스트 지연 | 기능 검증에 한정, 성능 수치는 비대상 명시 |
| pKVM 패치와 OP-TEE 커널 버전 충돌 | Phase 2 실패 | Phase 0에서 호환 커널 우선 선정 |
| QEMU virt EL2 + pKVM 조합 미검증 사례 | Phase 3 난항 | AVF 문서/upstream 사례 조사 선행 |
| pVM 2개 동시 기동 자원 부족 | Phase 3 | 게스트 메모리 최소화 |

---

## 8. 참조

본 계획 수립에 참조한 외부 문서 경로.

### 과제 문서 (`architect/test-p`)

| 문서 | 경로 | 참조 내용 |
|------|------|-----------|
| 과제 개요 | `../test-p/docs/00_overview.md` | 과제 배경/목적, 시스템 요구사항 R-1~R-5, 과제 범위(포함/제외) |
| 레퍼런스 시나리오 | `../test-p/docs/02_reference_scenario.md` | Secure Vision AI 파이프라인, Camera/AI pVM 구성, 데이터 보호 경계 |
| 시나리오 실행 흐름 | `../test-p/research/99_reference_scenario_flow.md` | pVM 생성/Workload 탑재/격리 실행 순서 |
| pVM 간 DMA-BUF 전달 조사 | `../test-p/research/99_pvm_dmabuf_transfer.md` | pVM 간 zero-copy 전달 제약(EL2 vendor module 필요) — PoC 범위 제외 근거 |
| pvmfw 정리 | `../test-p/research/99_pvmfw.md` | pVM 부트 신뢰 루트, 비밀 프로비저닝, pKVM hypercall 목록 — D-3 근거 |

### OP-TEE / QEMU 문서 (`architect/database/optee-documentation`)

| 문서 | 경로 | 참조 내용 |
|------|------|-----------|
| QEMU v8 빌드 가이드 | `../database/optee-documentation/_sources/building/devices/qemu.rst.txt` | OP-TEE + QEMU-v8 빌드/부팅 절차, Secure/Normal UART, VirtFS 공유 |
| 빌드 문서 색인 | `../database/optee-documentation/building/gits/build.html` | `repo`/`make` 빌드 플로우 |

> 경로는 `poc-p/` 기준 상대 경로다.
