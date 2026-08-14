# pKVM 커널 버전 및 패치 소스 조사

- 최초 조사일: 2026-08-06
- 정리일: 2026-08-14
- 목적: upstream Linux 위에서 Android pKVM 패치를 빌드·검증할 기준 버전과 소스 브랜치를 결정한다.
- 범위: 로컬 PoC를 위한 버전·브랜치·패치 집합 조사이며 upstream 투고 계획은 포함하지 않는다.

## 1. 결론

1. 타깃 커널은 Linux v6.18 LTS다.
2. 전체 패치와 의존성의 기준은 `for-android/pkvm-mainline-6.18`이다.
3. 선형 패치 초안은 `for-android/pkvm-master-6.18`에서 가져온다.
4. 경로 기반 pKVM 관련 규모는 최종 재실측 기준 658커밋이다.
5. 실제 빌드 검증 트리는 의존성과 로컬 수정까지 포함해 721커밋이다.

658과 721은 목적이 다른 수치다. 658은 pKVM 관련 변경의 규모를 파악하기 위한 분류 결과이고,
721은 실제로 컴파일과 실행을 통과시킨 작업 트리의 커밋 수다.

## 2. 저장소와 브랜치

| 저장소/브랜치 | 역할 | 베이스 |
|---|---|---|
| kernel.org Linux | upstream 기준 | Linus mainline |
| ACK `kernel/common` | Android 배포 커널 | upstream + Android 패치 |
| `for-android/pkvm-master-6.18` | 선형 pKVM 패치 스택 | Linux v6.18-rc2 |
| `for-android/pkvm-mainline-6.18` | ACK 통합 pKVM 기준 트리 | ACK `android-mainline` |
| `for-android/pkvm-mainline-7.1` | 최신 개발 상태 대조 | 최신 ACK `android-mainline` |
| `for-upstream/pkvm-*` | LKML 투고용 토픽 | 투고 당시 mainline |

브랜치 이름의 `master`와 `mainline`은 pKVM 성숙도를 뜻하지 않는다. 각각 Linus의 `master`와
ACK의 `android-mainline`이라는 베이스 트리를 가리킨다.

## 3. Android와 커널 버전 매핑

조사 당시 브랜치 Makefile과 refs를 직접 확인한 결과다.

| Android | ACK | pKVM 개발 브랜치 | 확인된 베이스 |
|---|---|---|---|
| 14 | `android14-6.1` | `for-android14-6.1/pkvm` | v6.1 |
| 15 | `android15-6.6` | `pkvm-integration-6.6` 계열 | v6.6 |
| 16 | `android16-6.12` | `for-android16/pkvm-integration` | v6.12-rc2 |
| 17 | `android17-6.18` | `for-android/pkvm-master-6.18` | v6.18-rc2 |
| 17 | `android17-6.18` | `for-android/pkvm-mainline-6.18` | ACK v6.18 시점 |

`for-android17/` 네임스페이스는 없다. Android 릴리스 번호 대신 커널 버전을 접미사로 쓰는
`for-android/pkvm-*-6.18` 방식으로 명명 규칙이 바뀌었다.

## 4. v6.18 선택 근거

| 항목 | v6.12 | v6.18 | v7.1 |
|---|---|---|---|
| pKVM 패치 | 있음 | 있음 | 최신 개발 스택 |
| Android 대응 | Android 16 | Android 17 | 개발 최신 |
| 조사 당시 유지보수 | LTS | LTS | 비 LTS stable |
| PoC 적합성 | 가능 | 채택 | 제품 기준선으로 부적합 |

v6.12와 v6.18은 조사 당시 upstream EOL이 모두 2028년 12월로 안내됐다. 같은 유지보수 종료
조건에서 Android 17과 대응하고 코드베이스가 더 새로운 v6.18을 선택했다. 초장기 CIP SLTS가
필수 요건이 되면 v6.12를 별도로 재검토한다.

## 5. 두 v6.18 브랜치 비교

| 항목 | `pkvm-master-6.18` | `pkvm-mainline-6.18` |
|---|---:|---:|
| 베이스 이후 커밋 | 394 | 3533 |
| merge 커밋 | 0 | 1188 |
| ACK 범용 코드 | 없음 | 포함 |
| 마지막 확인 시점 | 2025-11-05 | 2026-04-13 |
| 주 용도 | 선형 초안과 리베이스 | 전체 목록과 통합 검증 |

master의 장점은 v6.18-rc2 위에 merge 없이 선형으로 쌓였다는 점이다. 단점은 이후 추가된
device assignment, pvIOMMU, DMA-BUF 기반 pVM 메모리와 일부 selftest가 빠져 있다는 점이다.

mainline의 장점은 필요한 기능과 후속 의존성을 더 완전하게 포함한다는 점이다. 단점은 GKI,
INCFS, OWNERS 등 pKVM과 무관한 ACK 변경이 섞여 있어 그대로 이식할 수 없다는 점이다.

따라서 브랜치 하나를 정답으로 삼지 않고 역할을 분리한다.

## 6. 커밋 집합 분석

### 6.1 673 집계가 폐기된 이유

초기 경로 필터와 수동 검토에서는 673커밋을 얻었다. 재실측 결과 `drivers/dma-buf`와
`kernel/dma`에서 Android 범용 유지보수 커밋 18건이 오탐으로 포함됐고, 원시 집합에서 3건이
누락된 것으로 확인됐다. 동일 필터의 재실측 660건에서 pKVM과 무관한 역방향 2건을 제외해
658건으로 정리했다.

앞선 673 기반 `356/317` 커버리지 수치는 폐기한다. 658 기준 커버리지는 다음과 같다.

| 구분 | 커밋 수 |
|---|---:|
| master에 있음 | 368 |
| mainline에서 추가 추출 | 290 |
| 합계 | 658 |

### 6.2 경로 필터의 한계

빌드 검증에서 서로 반대인 판정 오류가 확인됐다.

| 커밋 | 경로 기반 판정 | 실제 역할 |
|---|---|---|
| `b163851117b3` `Expose is_dma_buf_file()` | pKVM 무관으로 배제 | DMA-BUF 기반 pVM 메모리의 필수 전제 |
| `6484ce851c96` vendor IOMMU fault handler | pKVM 관련으로 채택 | ACK 벤더 훅이며 pKVM과 무관 |

건수는 서로 상쇄되지만 구성원이 달라진다. 따라서 658은 규모 기준으로 사용하고, 실제 적용
목록은 빌드 성공으로 교차 검증해야 한다.

### 6.3 빌드 집합 721

실제 검증 트리는 다음으로 구성된다.

| 구성 | 커밋 수 |
|---|---:|
| `pkvm-master-6.18` 리베이스 | 394 |
| mainline 후속 및 v6.18 미포함 의존성 | 322 |
| 로컬 빌드 수정 | 5 |
| 합계 | 721 |

경로 분석에서는 제외한 `FROMLIST`와 `FROMGIT` 중 일부가 v6.18에 아직 없고 IOMMU 기반 파일을
제공하므로 빌드에는 필수였다. 반대로 `UPSTREAM` 커밋은 v6.18에 이미 존재하므로 제외했다.

721 트리의 구성과 빌드 결과는 [Phase 02](../phase-02/README.md)에 기록한다.

## 7. 패치 적용 원칙

1. 전체 기능과 의존성 목록은 mainline 브랜치에서 확정한다.
2. master에 있는 커밋은 v6.18-rc2 위의 선형 순서를 이용한다.
3. master에 없는 커밋은 mainline에서 시간순으로 적용한다.
4. 동일 제목의 master/mainline 커밋도 변경 파일을 비교한다.
5. 충돌 시 v6.18-rc2 이후 upstream에 추가된 overflow 및 PFN 검사를 유지한다.
6. 경로 필터 결과는 실제 빌드로 교차 검증한다.

특히 master판에는 당시 존재하지 않던 `pkvm-smc` 파일 수정이 빠질 수 있다. 제목 정규화만으로
동일 커밋이라고 판단하지 않고 `git show --name-only` 결과를 비교해야 한다.

## 8. Upstream 상태와 PoC 해석

Host stage-2 격리를 포함한 pKVM 기반은 이미 upstream에 들어갔지만, protected guest 전체 기능,
vendor module, SMMUv3/pvIOMMU, device assignment 등은 조사 당시 개발 또는 out-of-tree 상태였다.

따라서 이 PoC는 Android 개발 트리의 기능을 v6.18에 이식해 검증한 결과다. upstream v6.18이
동일한 pVM 기능을 기본 제공한다는 의미가 아니다.

## 9. 결정과 후속 작업

- 커널 버전 결정은 완료했다.
- 소스 통합과 빌드는 Phase 02에서 완료했다.
- QEMU protected 부팅은 Phase 03에서 완료했다.
- 단일 pVM과 CPU 접근 격리는 Phase 04에서 완료했다.
- S2MPU 기반 DMA 격리는 적합한 하드웨어 또는 에뮬레이션 환경이 없어 미검증이다.

## 10. 참고 자료

- [android-kvm/linux refs](https://android-kvm.googlesource.com/linux/+refs)
- [ACK kernel/common refs](https://android.googlesource.com/kernel/common/+refs)
- [Linux pKVM documentation](https://www.kernel.org/doc/html/next/virt/kvm/arm/pkvm.html)
- [AOSP AVF architecture](https://source.android.com/docs/core/virtualization/architecture)
- [AOSP pKVM vendor modules](https://source.android.com/docs/core/virtualization/pkvm-modules)
- [kernel.org releases](https://www.kernel.org/category/releases.html)
