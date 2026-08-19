# Phase 11 최종 결과 및 요구사항 매핑

- 판정일: 2026-08-19 (Asia/Seoul)
- 판정: 완료
- 대상: Phase 00~10, G-1~G-11 및 G-10B, README 성공 조건 6개
- 증거 기준 root commit: `e1629c18725ab833cd8aa3528b94c7ae19193ab1`

## 1. 최종 판정

Phase 00~10이 남긴 구현, 실측 로그와 조사 근거를 종합한 결과는 다음과 같다.

| 판정 대상 | 결과 |
|---|---|
| 목표 G-1~G-11 및 G-10B | 12개 모두 **달성(PoC 범위)** |
| README 성공 조건 | 6개 모두 **달성(PoC 범위)** |
| Phase 00~11 | 모두 완료 |
| 실물 camera/GPU와 실제 inference | 미검증, PoC 범위 밖 |
| 제품 수준 보안 보증 | 미검증, 이 결과로 주장하지 않음 |

여기서 `달성(PoC 범위)`은 각 목표가 문서에 고정된 E-1, E-2 또는 E-3 환경과 대체 판정
기준에서 완료 조건을 통과했다는 뜻이다. QEMU/TCG와 에뮬레이션 장치에서 얻은 기능 결과를
실물 하드웨어의 기밀성, 성능 또는 제품 보안 보증으로 확대하지 않는다.

## 2. 판정 어휘와 환경

| 어휘 | 의미 |
|---|---|
| 달성(PoC 범위) | 정의된 환경에서 구현과 실측 증거가 완료 조건을 충족함 |
| 부분 달성 | 일부 완료 조건만 충족하거나 필요한 환경 하나의 결과가 없음 |
| 미달성 | 완료 조건을 충족하는 구현 또는 실측 증거가 없음 |
| 미검증 | PoC 완료 조건 밖이거나 증거 없이 남은 항목 |

환경별 결과는 서로 대신하지 않는다.

| 환경 | 고정 구성과 용도 | 사용 결과 |
|---|---|---|
| E-1 | x86-64 Host, arm64 QEMU TCG, Linux v6.18+pKVM; protected boot, CPU 격리, 다중 pVM과 수명주기 | Phase 02~05, 07 완료. 초기 기준은 QEMU 4.2.1이고 protected 부팅 재검수에는 QEMU 8.2.2도 사용했다. OP-TEE 결과를 포함하지 않는다. |
| E-2 | QEMU 8.2.2, TF-A v2.13-rc0, OP-TEE 4.7.0, pKVM kernel | Phase 06과 보충 Phase 06-b 완료. 공개 Host/guest interface와 표준 OP-TEE client 경로만 판정했다. |
| E-3 | custom QEMU 10.0.0, `virt,iommu=smmuv3`, PV IOMMU, QEMU edu 역할 장치 2개 | Phase 08~10 완료. 장치/DMA와 fixture 기반 Reference Scenario를 검증한 에뮬레이션 환경이다. |
| fixture 준비 Host | OpenVINO 2024.6, OpenCV 4.10, NumPy 1.26.4, FFmpeg 6.1.1 | 공개 동영상과 CPU demo에서 30-frame canonical fixture/oracle을 두 번 생성해 동일성을 확인했다. E-3 runtime에서는 inference를 수행하지 않는다. |

Trusted Access가 필요한 내부 상태를 요구하거나 우회하지 않았다. Phase 06-b의 목표는 공개된
Host/guest interface와 관찰 가능한 반환값으로 축소했고, 그 범위를 해당 결과 문서에 기록했다.

## 3. Phase별 결과

| Phase | 환경 | 결과와 대표 근거 |
|---|---|---|
| [00](../phase-00/README.md) | - | 범위, 성공 기준과 E-1~E-3 분리 완료 |
| [01](../phase-01/README.md) | - | Linux v6.18과 pKVM patch source 결정 완료 |
| [02](../phase-02/README.md) | E-1 | clang/gcc kernel build 완료. 저장 정책에 따라 현재는 clang 산출물만 유지 |
| [03](../phase-03/README.md) | E-1 | `Protected nVHE mode initialized successfully`, `PKVM_QEMU_BOOT_OK` |
| [04](../phase-04/README.md) | E-1 | protected VM 실행 `All ok!`; Host private-page 접근은 예상된 `SIGSEGV`; rc=0 |
| [05](../phase-05/README.md) | E-1 | Camera/AI 역할 동시 실행, 단일 pVM 장애 격리, `MULTI_PVM_ALL_OK`, `Mlocked: 0 kB` |
| [06](../phase-06/README.md) | E-2 | pKVM 실행 중 OP-TEE AES와 재호출 성공, `OPTEE_PKVM_COEX_ALL_OK` |
| [06-b](../phase-06-b/README.md) | E-2 | guest Linux 보충 검증, FF-A negative와 두 pVM 격리, `OPTEE_PKVM_VALIDATION_OK` |
| [07](../phase-07/README.md) | E-1 | 권한/정책·image hash 검사, lifecycle/fault/recovery와 `Mlocked: 0 kB` |
| [08](../phase-08/validation-results.md) | E-3 | 역할 장치 배타 할당, DMA 범위 차단, share/revoke, teardown/reassignment 완료 |
| [09](../phase-09/VERIFICATION.md) | E-1, E-3 | 서로 다른 local FD로 같은 backing import/read/write, revoke와 회수 완료 |
| [09-b](../phase-09-b/VERIFICATION.md) | E-1, E-3 | AF_VSOCK command/result와 별도 metadata queue를 한 session으로 결합; negative/fault 완료 |
| [10](../phase-10/VERIFICATION.md) | E-3 | 30 frame의 Camera/AI/Host 결과가 oracle과 일치, fault/회귀와 `PVM_VISION_PIPELINE_OK` 완료 |

## 4. 목표-증거 매핑

| 목표 | 판정 | 핵심 증거 | 판정 범위 |
|---|---|---|---|
| G-1 pKVM kernel 준비 | 달성(PoC 범위) | [Phase 02](../phase-02/README.md)의 Linux v6.18 patch 통합과 clang/gcc build 기록 | gcc 산출물은 저장 정책에 따라 삭제됐고 clang 입력만 유지 |
| G-2 protected boot | 달성(PoC 범위) | `work/build/pkvm-qemu/console-protected-nvhe-rerun.log`: protected nVHE와 userspace 도달 | QEMU TCG 기능 검증 |
| G-3 단일 pVM | 달성(PoC 범위) | `work/build/pkvm-pvm/console-pvm-protected-rerun.log`: `All ok!`, rc=0 | 최소 KVM selftest workload |
| G-4 Host CPU 접근 격리 | 달성(PoC 범위) | 같은 Phase 04 log의 private page 예상 `SIGSEGV`와 regular-memory 대조군 | Host CPU mapping 경로의 기능 검증 |
| G-5 다중 pVM 운용 | 달성(PoC 범위) | `work/build/multi-pvm/console-multi-pvm-rerun.log`: 두 역할 rc=0, fault 격리, 회수 | 최소 Camera/AI 역할 workload |
| G-6 OP-TEE 공존 | 달성(PoC 범위) | `work/build/optee-pkvm/console-optee-pkvm.log`: 실행 중 AES, pVM, 재호출 모두 성공 | E-2 QEMU와 예제 AES TA; 비밀 provisioning 제외 |
| G-7 동적 수명주기 | 달성(PoC 범위) | `work/build/pvm-framework/console-pvm-framework-final.log`: 정책/검증, overlap, fault, recovery | image trust는 관리자 SHA-256 allowlist; pvmfw/attestation 제외 |
| G-8 장치 직접 할당 | 달성(PoC 범위) | `work/build/pvm-framework/console-phase08-share-second.log`: Camera/AI 할당, 회수, 재할당 | QEMU edu 역할 장치와 vfio-platform 경로 |
| G-9 DMA 격리 | 달성(PoC 범위) | 같은 Phase 08 log의 정상 DMA 대조군, 범위 밖/비소유 SID 차단과 revoke | custom QEMU PV SMMUv3; 실물 IOMMU 제외 |
| G-10 cross-pVM DMA-BUF | 달성(PoC 범위) | `work/build/pvm-buffer/console-pvm-buffer-linux.log`: export/import, AI read/write, Camera read-back | EL2-mediated 단일-page backing; runtime Host relay 없음 |
| G-10B 별도 descriptor channel | 달성(PoC 범위) | `work/build/pvm-buffer/console-phase10-user-channel-e2e.log`: metadata join, size/format/plane 검사 | 별도 EL2 message queue와 transfer ID 결합 |
| G-11 객체 탐지 결과 반환 | 달성(PoC 범위) | `work/build/vision-pipeline/console-vision-pipeline-manual.log`: 30-frame 결과 일치와 Host allowlist | 실제 inference가 아닌 공개 demo oracle replay |

목표 12개에는 `부분 달성` 또는 `미달성` 판정이 없다. 각 행의 제한은 성공 판정을 낮추는 누락이
아니라 처음부터 완료 조건에서 제외하고 별도 후속 검증으로 둔 범위다.

## 5. README 성공 조건 판정

| 성공 조건 | 판정 | 대응 목표/증거 | 범위 한정 |
|---|---|---|---|
| 1. pKVM kernel과 OP-TEE의 동일 시스템 초기화/동작 | 달성(PoC 범위) | G-1, G-2, G-6; E-2의 pKVM/OP-TEE 동시 부팅, 실행 중 AES와 pVM 완료 | QEMU 8.2.2 E-2; 실제 SoC Secure World 제외 |
| 2. Camera/AI pVM 동시 실행과 memory 격리 | 달성(PoC 범위) | G-3~G-5; 두 역할 동시 rc=0, Host private page 차단, 단일 역할 fault 격리 | 최소 workload와 CPU mapping 경로 |
| 3. 역할 장치 직접 할당·회수·배타 소유권 | 달성(PoC 범위) | G-8, G-9; 할당, owner/non-owner DMA 대조, revoke, reassignment | QEMU edu 역할 장치; 실물 USB/GPU 제외 |
| 4. E-3 runtime Host relay 없는 frame zero-copy와 descriptor 검사 | 달성(PoC 범위) | G-10, G-10B; EL2 DMA-BUF backing import와 별도 descriptor queue | 단일 4 KiB frame page; runtime Host에 frame copy/relay 없음 |
| 5. 공개 video frame과 결합된 허용 결과만 Host에 반환 | 달성(PoC 범위) | G-11; 30 frame의 oracle byte 일치, negative와 Host result allowlist | 사전 생성 oracle replay; 실제 model inference 제외 |
| 6. pVM 종료 후 장치·memory·vCPU 회수 | 달성(PoC 범위) | G-5, G-7, G-8; 정상/fault teardown, 재할당, `Mlocked: 0 kB` | 관찰 가능한 kernel/userspace 자원과 QEMU 역할 장치 |

## 6. 검증된 경계와 검증하지 않은 보증

### 검증한 기능 경계

- Host CPU의 protected private page 접근 거부와 regular-memory 대조군
- E-3 PV SMMUv3에서 owner DMA 허용, 범위 밖·비소유 DMA 거부, revoke 후 접근 차단
- Camera→AI frame backing을 E-3 runtime Host가 relay/copy하지 않는 EL2-mediated 경로
- DMA-BUF와 별도 size/FOURCC/dimension/plane descriptor의 transfer-ID 결합 및 bounds 검사
- Host-facing command/result allowlist와 raw frame/hash/descriptor/FD/token/address 비노출
- 두 pVM의 동시 실행, 한 역할의 장애 격리, 정상·fault teardown과 재할당
- E-2에서 pVM 실행 중 표준 OP-TEE client/TA AES 호출 및 세션 재개방

### 미검증 또는 범위 밖

- 실물 arm64 SoC/SMMUv3/S2MPU, USB camera와 discrete NVIDIA GPU의 할당·DMA 기밀성
- camera sensor capture/driver/timing과 GPU driver/가속 추론
- AI pVM 내부 실제 inference, model weight와 intermediate tensor의 기밀성
- 민감 영상 자체의 제품 수준 end-to-end 기밀성; fixture는 공개 데이터다.
- signed pvmfw, verified boot, remote attestation과 실제 secret provisioning
- OP-TEE AES temporary memref를 겨냥한 침해 Host의 직접 read 시험
- 성능, FPS, latency, cache coherency, fence, backpressure, multi-buffer/multi-stream
- speculative execution, timing/cache 등 side channel과 전체 공격면 보안 시험
- 표준 FF-A 기반 VM-to-VM transport; 현재 cross-pVM channel은 PoC 전용 EL2 interface다.

## 7. 고정 revision, 도구와 주요 digest

| 항목 | 고정 값 |
|---|---|
| Phase 11 증거 기준 root | `e1629c18725ab833cd8aa3528b94c7ae19193ab1` |
| pKVM Linux submodule | `6763e27c1ad00e0f5caf6e6cde5fcb33976e50e0` |
| kvmtool | `6866a248977d16bc293c6f4f6609daa4f465b073` |
| E-3 QEMU source | `5b3965e9c44ce7e8135f2a6ef7680eb563ab8bef` |
| Open Model Zoo | `7cc29a91472b4cb1289a11e655ba3e188e1d4a31` |
| E-2 OP-TEE manifest/build | 4.7.0 / `dcff191dafb2` |
| E-2 TF-A / OP-TEE OS | `842ce6391fec` / `86846f4fdf14` |
| E-2 OP-TEE client/test/examples | `23c112a6f05c` / `a15be9eca1b7` / `14321a0607db` |
| E-2 U-Boot | `b249e08ec9b7` |
| kernel Image / config SHA-256 | `a58cf72f405d1c67266532b4a49bbf17ab5ea834962ea1a6cb84094f93efcdf4` / `7ef1e6b3d688f516ac9e98730ff65429d42d748bd2a835d59fe639c5898ac77e` |
| E-3 QEMU / lkvm SHA-256 | `913b9b97ab9d47db5764d565faa945de5f14a1a39984fdb5c4cda321c920d384` / `9b718dd8c7fe239f3d73eeedffb4de3a0074696451724477ca9d67ce065707c4` |
| OpenVINO / OpenCV / FFmpeg | 2024.6 / 4.10 / 6.1.1 |
| source video SHA-256 | `452b11b7e0efbd019f1d9570d0c790e90416ad4ad29eec6003872d08443140ef` |
| `frames.bin` / `oracle.bin` SHA-256 | `655cd5aa44c2585ee435466015bdb38f6abbdb8623877d92847bd02aad415030` / `37905752542e5c43551cc18e911ed4c0394333f25882b7c9ef4890ff5ace177f` |

Phase별 더 세부적인 build input과 digest는 각 Phase 문서를 기준으로 한다. root commit 값은
Phase 11 문서를 작성하기 직전까지 모든 기능 검증과 Phase 10 수동 재검수 기록을 포함한 증거
snapshot이다. Phase 11 완료 commit은 이 문서 자체를 포함하므로 저장소 이력으로 고정한다.

## 8. 핵심 실측 로그 색인

| 범위 | 로그 |
|---|---|
| protected boot | `work/build/pkvm-qemu/console-protected-nvhe-rerun.log` |
| single pVM/CPU isolation | `work/build/pkvm-pvm/console-pvm-protected-rerun.log` |
| multi-pVM | `work/build/multi-pvm/console-multi-pvm-rerun.log` |
| OP-TEE coexistence | `work/build/optee-pkvm/console-optee-pkvm.log`, `work/build/optee-pkvm/secure-optee.log` |
| OP-TEE guest supplement | `work/build/optee-pkvm/console-phase-06-b-guest-linux-12.log` |
| lifecycle | `work/build/pvm-framework/console-pvm-framework-final.log` |
| assignment/DMA | `work/build/pvm-framework/console-phase08-share-second.log` |
| DMA-BUF Linux guests | `work/build/pvm-buffer/console-pvm-buffer-linux.log` |
| userspace channel | `work/build/pvm-buffer/console-phase10-user-channel-e2e.log` |
| Phase 10 normal/fault | `work/build/vision-pipeline/console-vision-pipeline-manual.log`, `work/build/vision-pipeline/console-vision-fault-manual.log` |
| Phase 09-b regression | `work/build/pvm-buffer/console-phase10-vsock-regression.log`, `work/build/pvm-buffer/console-phase10-user-channel-fault.log`, `work/build/pvm-framework/console-phase10-phase09b-primitive.log` |

`work/build`는 Git 비추적 재생성 영역이다. 저장소를 새로 clone하면 로그가 자동으로 포함되지
않으며 각 Phase의 verification 문서에 따라 다시 생성해야 한다.

### Phase 11 증거 감사

2026-08-19에 위 15개 로그의 존재와 대표 완료 marker를 다시 확인했다. protected boot,
single/multi-pVM, OP-TEE, lifecycle, device/DMA, DMA-BUF, userspace channel, Phase 10 normal/fault 및
회귀 marker가 모두 존재했다. pKVM Linux, kvmtool, E-3 QEMU와 Open Model Zoo revision을 현재
checkout에서 대조했고 kernel/QEMU/lkvm/video/frame/oracle digest도 7절의 값과 일치했다.

이 감사는 기존 증거의 완전성과 문서 전사 오류를 확인한 것이다. Phase 11에서 QEMU workload나
fixture demo를 새로 실행하지 않았으며 기능 재검증은 각 Phase의 마지막 실측 기록을 인용한다.

## 9. 알려진 warning

- Phase 09에서 파생된 DMA-BUF 실행 일부에서 `__pkvm_pgtable_stage2_unmap` warning이 알려져
  있다. 해당 실행은 panic/Oops 없이 종료하고 page/lease 회수와 `Mlocked: 0 kB`를 확인했지만,
  제품화 전에 reference-count와 unmap 순서를 수정해야 한다.
- 일부 VSOCK guest 부팅에서 MMIO guard `WARN_ON_ONCE`가 관찰된다. queue 왕복, guest 종료와
  자원 회수에는 영향을 주지 않았고 Phase 10 최종 로그의 panic/Oops/BUG는 0건이다.

warning이 허용됐다는 사실은 원인이 해소됐거나 제품 안정성이 증명됐다는 뜻이 아니다.

## 10. 후속 검증 우선순위

1. 실제 arm64/SMMUv3 플랫폼에서 USB camera와 GPU를 할당하고 Phase 08~10 전체를 재실행한다.
2. AI pVM 안에서 실제 inference runtime을 실행하고 model/tensor 보호 경계를 검증한다.
3. signed pvmfw, verified boot, attestation과 secret provisioning을 신뢰 체인에 연결한다.
4. 알려진 EL2 unmap/MMIO warning을 제거하고 page/lease reference를 stress test한다.
5. OP-TEE temporary memref의 침해 Host 접근을 공개 interface 범위에서 별도 검증한다.
6. multi-buffer, fence/cache coherency, backpressure와 FPS/latency를 측정한다.
7. cross-pVM transport를 표준화하고 protocol parser/driver를 fuzzing 및 보안 시험한다.

## 11. 결론

이 프로젝트는 정의한 세 환경에서 pKVM boot와 CPU 격리, OP-TEE 공존, 다중 pVM lifecycle,
에뮬레이션 역할 장치의 DMA 격리, Host runtime relay 없는 Camera→AI buffer/metadata 전달 및
bounded 결과 반환을 하나의 재현 가능한 PoC로 완성했다. 따라서 목표 12개와 README 성공 조건
6개는 모두 `달성(PoC 범위)`으로 판정한다.

최종 결과는 Reference Scenario의 interface와 격리 로직이 기능적으로 성립한다는 증거다. 실물
camera/GPU, 실제 model inference와 제품 수준 기밀성·무결성 보증은 위 후속 검증을 완료하기
전까지 주장하지 않는다.
