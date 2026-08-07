# Android Common Kernel pKVM 패치의 베이스 커널 버전 조사

- 조사일: 2026-08-06
- 목적: Android AVF가 사용하는 Android Common Kernel(ACK)의 pKVM 패치를 upstream Linux kernel에 머지하기 위해, 해당 패치들이 어떤 Linux 버전을 베이스로 하고 있는지 확인
- 조사 방법: `android.googlesource.com/kernel/common` 및 `android-kvm.googlesource.com/linux` 저장소의 브랜치/태그 목록과 각 브랜치의 `Makefile` 버전 변수 직접 확인

---

## 1. 결론 요약

ACK의 pKVM 패치는 **ACK 브랜치별 LTS 버전**을 베이스로 한다. 그러나 upstream 머지 작업의 소스로 사용해야 할 것은 ACK가 아니라, **`android-kvm.googlesource.com/linux`의 mainline 리베이스 브랜치**다.

- 현재 최신 통합 브랜치: `for-android/pkvm-mainline-7.1` (Makefile v7.1.0)
- ACK(`kernel/common`)는 pKVM 개발의 원본 트리가 아니라 **하류(downstream) 배포처**다.
- **주의**: `pkvm-mainline-<VER>`는 순수 mainline 위 리베이스가 아니라 ACK `android-mainline` 스냅샷이다. 이름이 헷갈리기 쉽다.
- 6.18 소스는 **`pkvm-mainline-6.18`을 기준으로 삼는다.** 머지 대상은 경로 기반 실측과 수동 검토로 **673커밋 · 38,844라인**이었고, 2026-08-07 재실측과 전수 대조로 **658커밋**으로 확정했다. 차이 15건은 T2·T3에 국한되며 개별 SHA까지 특정했다. 8.1절 참조. 라인 수 38,844는 673 기준이다.
- **`pkvm-master-6.18`은 뼈대로 쓸 수 없다.** 순서가 mainline과 사실상 같고(Spearman 0.9997) IOMMU 트랙이 통째로 빠져 있다. 투고 순서의 기준은 `pkvm-7.1-*` 태그 스택이다. 8.2절 4단계 참조.
- 투고 단위는 **32시리즈**(코어 24 · IOMMU 7 · 검증 1)로 짰다. 8.3절 참조.
- **v6.18 빌드 검증을 마쳤다.** IOMMU 스택과 EL2 벤더 모듈까지 포함한 **721커밋** 트리를 clang과 gcc 양쪽에서 빌드하는 데 성공했다. 동작 검증은 하지 않았다. 9장 참조.
- **투고용 집합과 빌드용 집합은 다르다.** 8장의 658커밋은 투고 기준이라 `FROMLIST:`를 제외하는데, 이들은 v6.18에 없으므로 빌드에는 필수다. IOMMU 스택의 기반 파일이 여기 해당한다. 9.2절 참조.
- **타깃 커널 버전은 6.18로 결정했다.** 근거는 5장 참조.

---

## 2. pKVM 개발 트리 구조

### 2-1. 저장소와 브랜치의 관계

```mermaid
flowchart LR
    subgraph KORG["kernel.org - upstream"]
        LINUS["Linus master<br/>mainline"]
        RC2["v6.18-rc2"]
        REL["v6.18 릴리스"]
    end

    subgraph AKVM["android-kvm.googlesource.com/linux<br/>pKVM 원본 개발 트리"]
        MASTER["for-android/pkvm-master-6.18<br/>베이스: upstream v6.18-rc2<br/>pKVM 394커밋 · merge 0"]
        MAINLINE["for-android/pkvm-mainline-6.18<br/>베이스: ACK android-mainline<br/>pKVM + Android 전체"]
        ML71["for-android/pkvm-mainline-7.1<br/>최신 개발 tip"]
        UPST["for-upstream/pkvm-*<br/>LKML 투고용 토픽 시리즈"]
    end

    subgraph ACKR["android.googlesource.com/kernel/common - ACK"]
        AMAIN["android-mainline<br/>롤링 통합 브랜치"]
        A17["android17-6.18<br/>Android 17 릴리스 브랜치"]
    end

    LINUS --> RC2
    LINUS --> REL
    LINUS -->|"v6.x-rc 상시 병합"| AMAIN
    RC2 -->|"베이스"| MASTER
    AMAIN -->|"베이스"| MAINLINE
    AMAIN -->|"베이스"| ML71
    AMAIN -->|"6.18 시점 fork"| A17
    MASTER -->|"378/394 커밋 반영"| A17
    MASTER -.->|"진부분집합<br/>대상 673 중 356만 보유"| MAINLINE
    MASTER -.->|"토픽 분할 투고"| UPST
    UPST -.->|"LKML 리뷰 후 머지"| LINUS
```

읽는 법이다.

- **왼쪽이 상류, 오른쪽이 하류다.** upstream에서 출발해 pKVM 개발 트리를 거쳐 ACK 릴리스 브랜치로 흘러간다.
- **`master`와 `mainline`은 베이스 트리 이름이다.** `pkvm-master-*`는 Linus의 `master`를, `pkvm-mainline-*`는 ACK의 `android-mainline`을 베이스로 한다. 헷갈리기 쉬운 지점이다.
- **실선은 실측으로 확인한 관계다.** 커밋 수치는 2-4절 조사 결과다.
- **점선은 포함 관계 또는 투고 경로다.** `for-upstream/pkvm-*`에서 LKML을 거쳐 mainline에 반영되는 흐름은 AOSP·LKML 공개 절차 기준이며 커밋 단위로 대조하지는 않았다.
- 폐기된 `for-android16/*` 네임스페이스는 생략했다. 2-3절 참조.

### 2-2. 브랜치 계열

pKVM의 원본 개발은 `android-kvm.googlesource.com/linux`에서 이루어지며, 세 갈래로 관리된다.

| 브랜치 계열 | 용도 | 베이스 |
|---|---|---|
| `for-upstream/pkvm-*` | LKML 투고용 토픽 시리즈 (core, modules, smmu-v3, tracing, pviommu, dev-assign, sme, kcov 등 약 25개) | 투고 당시 mainline |
| `for-android/pkvm-master-<VER>` | **순수 pKVM 패치 스택**. Android 범용 코드 없음 | upstream(Linus) `master`, v`<VER>`-rc2 |
| `for-android/pkvm-mainline-<VER>` | ACK `android-mainline` 스냅샷 **위에** 얹은 pKVM 스택 | ACK `android-mainline` (Makefile v`<VER>`) |
| `for-android<NN>/pkvm-*` | 특정 ACK 릴리스를 타깃으로 한 백포트 (**구 방식, 폐기**) | 해당 ACK 포크 지점 |

브랜치 이름의 `master`와 `mainline`은 **베이스 트리를 가리키는 말**이다. `master`는 Linus의 `master`(upstream), `mainline`은 ACK의 `android-mainline`이다. 이름이 헷갈리기 쉬우니 주의한다. 상세 비교는 2-4절 참조.

`for-android<NN>/` 네임스페이스는 더 이상 쓰이지 않는다. 2-3절 참조.

LKML은 **L**inux **K**ernel **M**ailing **L**ist의 약자다. 커널 개발의 주 메일링 리스트이며, 모든 패치가 여기에 게시되어 리뷰를 거친다. 주소는 `linux-kernel@vger.kernel.org`다. pKVM처럼 arm64 KVM 영역은 `kvmarm@lists.linux.dev`와 `linux-arm-kernel@lists.infradead.org`에도 함께 보낸다.

### 2-3. `for-android17/pkvm-*` 브랜치가 없는 이유

조사일 2026-08-07. `git ls-remote --heads`로 두 저장소를 전수 확인했다.

`for-android17/` 네임스페이스는 **존재하지 않는다**. 오타나 권한 문제가 아니다. `for-android15/`도 마찬가지로 없다. 이 네임스페이스가 있는 것은 `for-android14-6.1/`(1개)과 `for-android16/`(27개, 2024-10-15 이후 동결)뿐이다.

ACK(`kernel/common`)에는 `android17-6.18`과 그 파생 브랜치가 정상 존재한다. **Android 17의 브랜치 컷은 완료되었고, pKVM 개발 저장소의 명명 규칙만 바뀐 것**이다.

원인은 두 가지다.

1. **버전 키가 Android 릴리스 번호에서 커널 버전 번호로 바뀌었다.** `for-android16/<토픽>` 방식이 `for-android/pkvm-<종류>-<커널버전>` 방식으로 대체되었다. Android 17에 해당하는 브랜치는 `-6.18` 접미사가 붙은 것들이다.
2. **토픽 분할이 브랜치에서 태그로 옮겨갔다.** `for-android16/`의 27개 토픽 브랜치가 하던 역할을 `pkvm-<VER>-<토픽>` 태그(7.1 기준 약 40개)가 대신한다. 새 네임스페이스를 팔 이유가 사라졌다.

따라서 Android 17 = 커널 6.18에 해당하는 브랜치는 다음 둘이다. 차이는 2-4절에서 다룬다.

- `for-android/pkvm-master-6.18` — `for-android16/pkvm-integration`의 후계
- `for-android/pkvm-mainline-6.18` — `for-android/pkvm-mainline-6.12`의 후계

`for-android/pkvm-master-6.18-protected`(protected guest), `-smmu`(SMMUv3) 파생 브랜치도 있다.

### 2-4. `pkvm-master-6.18`과 `pkvm-mainline-6.18`의 차이

- 조사일: 2026-08-07
- 조사 방법: `git fetch --filter=tree:0 --depth=3000`으로 세 브랜치를 실제로 받아 커밋 그래프 직접 분석

#### 실측 비교표

| 항목 | `for-android/pkvm-master-6.18` | `for-android/pkvm-mainline-6.18` |
|---|---|---|
| 베이스 트리 | **upstream Linus `master`** | **ACK `android-mainline`** |
| 베이스 커밋 | `211ddde0823` = **Linux 6.18-rc2** | android-mainline (6.19 머지윈도 시점) |
| Makefile 버전 | `6.18.0-rc2` | `6.18.0` |
| 베이스 이후 커밋 수 | **394** | **3533** |
| merge 커밋 | **0** | 1188 |
| `into android-mainline` 병합 | **0** | **1141** |
| ACK 전용 코드 (`GKI`/`INCFS`/`OWNERS`/`ashmem` 등) | **없음** | 158개 커밋 |
| 최종 커밋 | 2025-11-05 | 2026-04-13 |

#### `pkvm-master-6.18` = 순수 pKVM 패치 스택

394개 커밋의 접두사 분포다. 전부 pKVM 또는 그 주변 기능이다.

| 접두사 | 수 |
|---|---|
| `ANDROID: KVM:` | 343 |
| `ANDROID:` (비 KVM) | 17 |
| `KVM:` | 13 |
| `FROMLIST:` 계열 | 13 |
| `ANDROID: BACKPORT: KVM:` | 4 |
| 기타 (`SQUASH:`, `BACKPORT:` 등) | 4 |

비 KVM `ANDROID:` 17개도 모두 pKVM 종속 기능이다. virtio-balloon(메모리 릴린퀴시), ring-buffer(hyp tracing), kallsyms/modpost(EL2 모듈 심볼), MMIO guard, pKVM용 pl011 예제 드라이버 등이다. GKI·ashmem·incfs 같은 Android 범용 코드는 **한 건도 없다**.

merge 커밋이 0이라는 점도 중요하다. v6.18-rc2 위에 선형으로 쌓인 패치 시리즈이므로 `git format-patch`로 그대로 뽑아낼 수 있다.

#### `pkvm-mainline-6.18` = android-mainline 스냅샷

`android-mainline`은 ACK가 upstream mainline을 상시 추종하며 Android 패치를 얹는 롤링 브랜치다. `pkvm-mainline-6.18`은 그 위에 pKVM 스택을 올린 것이다.

- `Merge tag 'v6.17-rc5' into android-mainline` 형태의 병합이 1141개 있다.
- `Merge tag 'vfs-6.19-rc1.*'` 등 6.19 머지윈도 내용까지 포함한다. Makefile이 아직 `6.18.0`인 이유는 Linus가 `-rc1` 태그를 찍을 때 버전을 올리기 때문이다. 즉 이 브랜치는 **v6.18 릴리스보다 뒤**에 있다.
- `ANDROID: GKI:` 147개, `ANDROID: INCFS:`, `ANDROID: OWNERS:`, ashmem 관련 등 pKVM과 무관한 ACK 코드가 섞여 있다.

#### 포함 관계

`pkvm-master-6.18`의 394개 커밋 중 **391개(99%)가 `pkvm-mainline-6.18`에도 존재한다** (접두사 정규화 후 비교). 즉 master는 mainline에서 pKVM 부분만 떼어낸 부분집합에 가깝다.

ACK 반영도 확인했다. `kernel/common`의 `android17-6.18`을 받아 대조한 결과 **394개 중 378개(96%)가 ACK에 그대로 들어가 있다.** `pkvm-master-6.18`이 Android 17로 흘러가는 실제 경로임이 확인된다.

참고로 `pkvm-mainline-7.1`과의 정규화 일치는 238개(60%)다. 나머지는 upstream 반영 과정에서 제목이 바뀌었거나 재작성된 것으로 보인다.

#### master는 mainline의 진부분집합이다 (중요)

8.1절의 경로 기반 대상 집합 673개를 기준으로 양방향 비교했다.

| 구분 | 개수 |
|---|---|
| 머지 대상 (경로 기반 + 수동 검토 확정) | 673 |
| 그중 `pkvm-master-6.18`에 있는 것 | **356** |
| **`pkvm-mainline-6.18`에만 있는 것** | **317** |
| `pkvm-master-6.18`에만 있는 것 | **0** |

**master에만 있는 커밋은 하나도 없다.** 즉 `pkvm-master-6.18`은 깨끗하지만 **불완전하다**. 대상의 53%만 갖고 있다. 2025-11-05에 갱신이 멈춘 스냅샷이라 이후 작업이 통째로 빠져 있다.

master에 없는 317개는 특정 기능 영역에 몰려 있다.

- device assignment (`Add arch function for device assignment`, `Add HVC to donate/reclaim assignable MMIO`)
- pvIOMMU (`Add documentation for pvIOMMU UAPI`, `Add extra IOMMU idmap callbacks`)
- DMA-BUF 기반 pVM 메모리 (`Accept DMA-BUF mappings to back pVMs`)
- guest share/unshare 하이퍼콜의 range 확장
- pKVM selftest (`tools/testing/selftests/kvm/arm64/pkvm.c`) 및 hyp tracefs 테스트

따라서 **머지 대상 목록을 master만 보고 확정하면 안 된다.**

#### 용도 구분

| 목적 | 사용할 브랜치 | 근거 |
|---|---|---|
| 머지 대상 **전체 목록 확정** | `pkvm-mainline-6.18` | 대상 673개 전량 보유. master는 317개 누락 |
| 패치 시리즈 **초안 추출** | `pkvm-master-6.18` | v6.18-rc2 위 선형 394커밋, merge 0. `git format-patch` 직행 가능 |
| ACK/GKI 통합 환경 빌드·검증 | `pkvm-mainline-6.18` | ACK `android17-6.18`과 사실상 동일 구성 |
| 최신 pKVM 개발 현황 추적 | `pkvm-mainline-7.1` | 2026-07-31 tip. 가장 활발 |

권장 순서는 이렇다. `pkvm-mainline-6.18`에서 머지 대상 673개를 확정하고, 그중 `pkvm-master-6.18`에 있는 356개는 선형 시리즈로 그대로 뽑는다. 나머지 317개는 `pkvm-mainline-6.18`에서 개별 cherry-pick 한다. 상세는 8장이다.

`pkvm-master-<VER>` 계열은 6.17과 6.18에만 존재하고 7.1용은 없다. 이 계열이 계속 유지될지는 확인되지 않았으므로 의존도를 낮춰 두는 편이 안전하다.

### 2-5. 커밋 태그로 본 출처 구분

ACK에 반영된 pKVM 커밋은 다음 접두사로 출처가 구분된다.

- `UPSTREAM:` / `BACKPORT:` — 이미 mainline에 있는 커밋
- `FROMGIT:` / `FROMLIST:` — maintainer tree 또는 메일링 리스트 게시분
- `ANDROID:` — **순수 out-of-tree 패치** (실제 머지 대상)

`for-android/pkvm-mainline-7.1`의 최근 100 커밋 기준으로 `ANDROID:` 접두사 커밋은 약 45~50%를 차지한다.

---

## 3. 버전 매핑표

각 브랜치의 `Makefile` VERSION/PATCHLEVEL/SUBLEVEL 값을 직접 확인한 결과다.

| Android | ACK 브랜치 | ACK 커널 버전 | 대응 pKVM 개발 브랜치 | 확인된 베이스 |
|---|---|---|---|---|
| 14 | `android14-6.1` | 6.1.x | `for-android14-6.1/pkvm` | v6.1 |
| 15 | `android15-6.6` | 6.6.x | `pkvm-integration-6.6`, `dmitriyf/pkvm-android15-6.6` | v6.6 |
| 16 | `android16-6.12` | **6.12.90** | `for-android16/pkvm-integration` 외 16개 토픽 | **v6.12.0-rc2** |
| 17 | `android17-6.18` | **6.18.32** | `for-android/pkvm-master-6.18` | **v6.18.0-rc2** (upstream `master`) |
| 17 | `android17-6.18` | **6.18.32** | `for-android/pkvm-mainline-6.18` | **v6.18.0** (ACK `android-mainline`) |
| (개발 최신) | — | — | **`for-android/pkvm-mainline-7.1`** | **v7.1.0** (ACK `android-mainline`, tip: 2026-07-31) |

`확인된 베이스`는 `Makefile` 값이다. 같은 `6.18`이라도 `pkvm-master-6.18`은 upstream 트리, `pkvm-mainline-6.18`은 ACK `android-mainline` 트리 위에 있다. 2-4절 참조.

### 참고: kernel.org 현황 (2026-08-06 기준)

| 구분 | 버전 | 릴리스일 |
|---|---|---|
| mainline | 7.2-rc6 | 2026-08-02 |
| stable | 7.1.6 | 2026-08-03 |
| longterm | 6.18.42 | 2026-08-03 |
| longterm | 6.12.101 | 2026-08-03 |
| longterm | 6.6.148 | 2026-08-03 |
| longterm | 6.1.180 | 2026-07-30 |

---

## 4. 대상 커널 버전의 유지보수 기간

- 조사일: 2026-08-07
- 출처: kernel.org Releases 페이지, Greg Kroah-Hartman의 2026-02-25 LTS 연장 발표

### 4.1 요약표

| 버전 | 구분 | 릴리스일 | 유지보수 종료(EOL) | 총 유지보수 기간 | 잔여 기간 |
|---|---|---|---|---|---|
| **6.12** | longterm (LTS) | 2024-11-17 | **2028년 12월** | 약 4년 | 약 2년 4개월 |
| **6.18** | longterm (LTS) | 2025-11-30 | **2028년 12월** | 약 3년 | 약 2년 4개월 |
| **7.1** | stable (비 LTS) | 2026-06-14 | **7.2 릴리스 직후 (2026년 8월 예상)** | 약 2~3개월 | 수 주 |

### 4.2 버전별 상세

#### 6.12 (LTS)

- 25번째 LTS 릴리스. 최신 릴리스는 6.12.101 (2026-08-03).
- 당초 EOL은 2026년 12월이었으나 2026-02-25 발표로 **2년 연장**되어 2028년 12월이 되었다.
- 연장 근거: PREEMPT_RT 정식 반영, Debian 13(Trixie)과 RHEL 10의 베이스, Raspberry Pi 5 지원.
- CIP(Civil Infrastructure Platform)의 SLTS 대상이다. `6.12-cip`는 **2035년 중반까지** 유지된다.
- Android 16의 ACK(`android16-6.12`) 베이스이기도 하다.

#### 6.18 (LTS)

- 26번째 LTS 릴리스. 최신 릴리스는 6.18.43 (2026-08-06).
- 2026-02-25 발표에서 "최소 3년" 유지로 확정되어 EOL은 2028년 12월이다.
- Android 17의 ACK(`android17-6.18`) 베이스다.
- 아직 CIP SLTS 대상으로 지정되지 않았다.

#### 7.1 (stable, 비 LTS)

- 정규 stable 릴리스이며 **LTS가 아니다**. 최신 릴리스는 7.1.7 (2026-08-06).
- 정규 stable은 다음 메이저 버전이 나오면 곧바로 EOL 처리된다.
- 직전 사례: 7.0은 2026-04-12 릴리스 후 2026-06-27 EOL. 유지 기간 약 2.5개월.
- 현재 7.2-rc6(2026-08-02)까지 진행되었다. 7.2 정식 릴리스 후 7.1도 수 주 내 EOL 예상.

#### 참고: CIP SLTS란

CIP(Civil Infrastructure Platform)는 Linux Foundation 산하 프로젝트다. 발전소, 철도, 산업 제어 등 수명이 수십 년인 인프라 설비를 대상으로 한다. 이런 설비는 커널 LTS 주기(3~6년)보다 훨씬 오래 가동된다.

SLTS(Super Long Term Support)는 CIP가 선정한 커널을 **최소 10년** 유지하는 프로그램이다. kernel.org의 upstream 지원이 끝난 뒤에도 CIP가 자체적으로 보안 패치와 버그 수정을 이어받는다.

- 현재 SLTS 대상: 4.19, 5.10, 6.1, 6.12 (5개 계열)
- `6.12-cip`는 2035년 중반까지 유지 예정
- upstream LTS와 별개의 브랜치다. 신규 기능은 받지 않고 수정만 반영한다
- 모든 LTS가 SLTS가 되지는 않는다. CIP가 선별한다

정리하면 6.12는 **2028년 12월까지 upstream 커뮤니티(Greg KH) 지원 → 이후 2035년까지 CIP 지원** 구조다.

### 4.3 2026-02-25 LTS 연장 발표 전문 요약

Greg Kroah-Hartman이 여러 기업 및 stable 메인테이너와의 논의를 거쳐 유지보수 기간을 갱신했다.

| 버전 | 확정 유지 기간 | EOL |
|---|---|---|
| 5.10 | 6년 | 2026년 12월 |
| 5.15 | 5년 | 2026년 12월 |
| 6.1 | — | 2027년 12월 |
| 6.6 | 4년 | 2027년 12월 |
| 6.12 | 4년 | 2028년 12월 |
| 6.18 | 최소 3년 | 2028년 12월 |

EOL 날짜는 확정된 것이 아니다. 산업계 수요와 메인테이너 여력에 따라 추가 연장될 수 있다.

### 4.4 pKVM 머지 관점의 시사점

1. **7.1은 제품 타깃으로 부적합하다.** 유지보수 기간이 사실상 남아 있지 않다. `for-android/pkvm-mainline-7.1`은 개발/리베이스 기준선으로만 활용하고, 실제 머지 타깃은 mainline(7.2 이후) 또는 LTS로 잡아야 한다.
2. **장기 제품 타깃은 6.12 또는 6.18이다.** 두 버전의 EOL이 2028년 12월로 동일하다. 따라서 신규 진입이라면 코드베이스가 1년 더 새로운 **6.18을 권장한다**.
3. **초장기 유지가 필요하면 6.12다.** CIP SLTS로 2035년까지 커버되는 유일한 후보다. 다만 upstream 커뮤니티 지원은 2028년 12월에 끝나고 이후는 CIP 범위다.
4. **upstream 머지 자체는 mainline을 타깃해야 한다.** LTS 브랜치는 신규 기능을 받지 않는다. mainline 반영 후 필요 시 백포트하는 순서가 맞다.

---

## 5. 결정: 타깃 커널 버전은 6.18

- 결정일: 2026-08-07
- **결정: 6.18을 타깃 커널 버전으로 채택한다.**

### 5.1 후보 비교

| 항목 | 6.12 | 6.18 |
|---|---|---|
| pKVM 패치 존재 | 있음 (`for-android16/pkvm-integration`) | 있음 (`for-android/pkvm-mainline-6.18`) |
| 유지보수 종료 | 2028년 12월 | 2028년 12월 |
| 대응 Android | Android 16 (`android16-6.12`) | Android 17 (`android17-6.18`) |
| 릴리스일 | 2024-11-17 | 2025-11-30 |

### 5.2 결정 근거

1. **양쪽 모두 pKVM 패치가 존재한다.** 6.12와 6.18 각각에 대응하는 pKVM 개발 브랜치가 갖춰져 있다. 패치 가용성 측면에서는 두 후보가 동등하다.
2. **유지보수 기간이 동일하다.** 두 버전 모두 upstream EOL이 2028년 12월이다. 6.12를 선택해도 지원 기간상 이득이 없다.
3. **Android 17이 6.18을 사용한다.** 최신 Android 릴리스와 커널 버전을 맞추는 편이 ACK 대응과 향후 추적에 유리하다.

따라서 유지보수 기간이 같은 조건에서 더 새로운 코드베이스이자 최신 Android가 채택한 **6.18**을 선택한다.

### 5.3 결정에 따른 후속 사항

- 소스 브랜치는 **용도별로 나눠 쓴다**. 머지 대상 목록 확정과 검증은 `for-android/pkvm-mainline-6.18`, 패치 시리즈 초안 추출은 `for-android/pkvm-master-6.18`이다. 6.1절 참조.
- 6.12는 대상에서 제외한다. CIP SLTS(2035년)가 필요한 요건이 새로 생기면 재검토한다.
- 7.1은 유지보수 기간이 사실상 없어 제품 타깃에서 제외한다. 개발/리베이스 기준선으로만 참고한다.

---

## 6. 머지 전략 권고

### 6.1 타깃 커널 버전별 소스 선택

타깃은 5장 결정에 따라 **LTS 6.18**이다. 6.18 소스는 단일 브랜치가 아니라 **역할별로 두 개를 나눠 쓴다.**

| 역할 | 사용할 브랜치 | 근거 |
|---|---|---|
| **① 머지 대상 목록 확정 (기준 트리)** | **`for-android/pkvm-mainline-6.18`** | 머지 대상 673커밋 전량 보유. 2026-04-13까지 갱신 |
| **② 패치 시리즈 초안 추출** | **`for-android/pkvm-master-6.18`** | v6.18-rc2 위 선형 394커밋, merge 0. `git format-patch` 직행 |
| ③ ACK/GKI 환경 빌드·검증 | `for-android/pkvm-mainline-6.18` | ACK `android17-6.18`과 사실상 동일 구성 |
| ④ 최신 개발 현황 대조 | `for-android/pkvm-mainline-7.1` | 2026-07-31 tip |

#### 두 브랜치를 나눠 쓰는 이유

**mainline이 기준인 이유**는 완전성이다. `pkvm-master-6.18`은 2025-11-05에 멈춘 스냅샷이라 머지 대상 673개 중 356개만 갖고 있다. **317개가 누락**되어 있으며 device assignment, pvIOMMU, DMA-BUF 기반 pVM 메모리 등 통째로 빠진 기능 영역이 있다. 반대로 master에만 있는 커밋은 0개다. 목록 확정을 master로 하면 기능이 누락된다. 상세는 2-4절이다.

**master를 함께 쓰는 이유**는 추출 편의다. `pkvm-mainline-6.18`은 ACK `android-mainline` 스냅샷이라 GKI·ashmem·incfs 등 pKVM과 무관한 커밋이 대량으로 섞여 있다(v6.18 이후 3533커밋, merge 1188개). 여기서 pKVM만 골라내는 작업이 만만치 않다. `pkvm-master-6.18`은 그 선별을 이미 끝내 둔 결과물이라 356개를 그대로 뽑을 수 있다.

#### 권장 절차

1. `pkvm-mainline-6.18`에서 머지 대상을 확정한다. 경로 기반 실측과 수동 검토로 **673개**다.
2. 그중 `pkvm-master-6.18`에 있는 356개는 선형 시리즈로 일괄 추출한다.
3. 나머지 317개는 `pkvm-mainline-6.18`에서 개별 cherry-pick 한다.
4. 베이스 차이에 주의한다. master는 **v6.18-rc2** 기준이므로 v6.18 정식 위에 올릴 때 재정렬이 필요할 수 있다.

**master의 쓰임은 커밋 집합이지 순서가 아니다.** master는 pKVM 선별을 끝내 둔 결과물이라 추출 편의가 있다. 그러나 그 선형 순서는 mainline과 사실상 동일한 시간순이며 토픽별 재배열이 아니다. 투고 순서의 기준은 `pkvm-7.1-*` 태그 스택이다. 근거는 8.2절 4단계다.

단계별 명령과 리스크는 **8장 실행 계획**에 정리했다.

#### 그 외 커널 버전 (참고)

| 머지 타깃 | 사용할 브랜치 | 근거 |
|---|---|---|
| 최신 mainline (7.1 / 7.2) | `for-android/pkvm-mainline-7.1` | 2026-07-31 tip. `pkvm-master-7.1`은 없음 |
| LTS 6.12 | `for-android16/pkvm-integration` | v6.12.0-rc2 베이스 |
| LTS 6.6 | `pkvm-integration-6.6` | v6.6 베이스 |

**ACK 브랜치(`kernel/common`)에서 직접 패치를 추출하는 것은 권장하지 않는다.** ACK에는 pKVM 외의 대량의 Android 전용 패치가 뒤섞여 있어 pKVM 패치만 분리하기 어렵고, LTS 백포트가 누적되어 mainline과의 diff가 불필요하게 커진다.

---

## 7. Upstream 반영 현황

### 7.1 이미 mainline에 있는 부분

pKVM 호스트 측 기반(nVHE protected mode, host stage-2 격리)은 **v5.13 ~ v5.16 시기에 mainline 진입 완료**. `Documentation/virt/kvm/arm/pkvm.rst`가 mainline에 존재한다.

### 7.2 아직 out-of-tree인 부분

Protected guest(pVM) 지원은 **여전히 진행 중**이다.

- 2026-01 투고 시리즈 "KVM: arm64: Add support for protected guest memory with pKVM" 기준 베이스는 v6.19-rc4
- guest_memfd 작업 대기로 upstream 진행이 지연되어 왔고, 익명 메모리 기반의 점진적 접근으로 방향 전환
- 현재도 protected VM 생성에 **개발자용 Kconfig 옵션 + kernel taint**를 요구하는 단계
- 미구현: CPU 레지스터 상태 격리, DMA 접근 격리, 호스트로부터의 완전 격리

그 외 다음 영역이 대부분 out-of-tree로 남아 있다.

- pKVM vendor module 프레임워크 (EL2 module loading, symbol/permission 관리)
- SMMUv3 / pvIOMMU (`for-upstream/pkvm-smmu-v3`, `pkvm-smmu-v3-part-2`)
- hyp tracing / hyp_printk
- FF-A (Firmware Framework for Armv8-A) 프록시 처리
- pvmfw loader, PSCI mem-protect, MMIO guard

---

## 8. 6.18 머지 실행 계획

upstream **v6.18** 위에 pKVM 패치를 올리는 실제 작업 절차다. 5장 결정과 6장 소스 선택을 전제로 한다.

### 8.1 대상 규모 (경로 기반 확정)

- 측정일: 2026-08-07
- 방법: `git clone --filter=blob:none --depth=3000`으로 트리까지 받아 `v6.18..for-android/pkvm-mainline-6.18` 구간을 **파일 경로 기준**으로 집계
- 필터: `ANDROID:` 계열만 채택. `UPSTREAM:`/`FROMGIT:`/`FROMLIST:`와 `ANDROID: GKI/INCFS/OWNERS`는 제외

**머지 대상은 673 커밋이다.** T4·T5 전수 수동 검토와 파일 단위 재검증을 마쳤다.

| 계층 | 경로 | 원시 | 채택 |
|---|---|---|---|
| T1 코어 KVM/hyp | `arch/arm64/kvm`, `arch/arm64/include/asm/kvm*`, `include/kvm`, `virt/kvm`, `Documentation/virt/kvm` | 561 | **561** |
| T2 IOMMU/SMMU | `drivers/iommu`, iommu 헤더 | 63 | **62** |
| T3 장치·메모리 주변 | `drivers/virt`, `drivers/vfio`, `drivers/dma-buf`, `kernel/dma`, `drivers/misc`, `drivers/virtio` | 67 | **36** |
| T4 셀프테스트 | `tools/testing/selftests/kvm`, `hyp-trace` | 185 | **11** |
| T5 arm64 기타 | `arch/arm64/kernel`, `arch/arm64/configs` | 101 | **3** |
| | **합계** | 977 | **673** |

계층은 상위 우선 배타 할당이다. 중복 계산은 없다. 코드 본체는 T1~T3의 659커밋이다.

#### T4·T5 수동 검토 결과

원시 286개를 파일 경로와 커밋 본문까지 확인해 분류했다. **채택은 14개뿐이다.**

**1차 배제 — upstream에 존재하지 않는 파일만 건드리는 커밋**

`arch/*/configs/*defconfig`, `BUILD.bazel`, `*.bzl`, `*.fragment`, `build.config`, `OWNERS`는 ACK 전용이다. upstream 트리에 대응 파일이 없으므로 머지 자체가 성립하지 않는다.

| 계층 | 원시 | ACK 전용 | 코드 포함 |
|---|---|---|---|
| T4 | 185 | 142 | 43 |
| T5 | 101 | 87 | 14 |

여기서 `ANDROID: ARM64: gki_defconfig: Enable PKVM guest driver`, `ANDROID: gki: Enable pkvm pviommu driver` 같이 **제목에 pKVM이 들어가지만 defconfig만 바꾸는 커밋**이 걸러진다. 직전 키워드 휴리스틱이 이들을 잘못 채택했다.

**2차 선별 — 코드 커밋 57개 중 pKVM 관련만**

T4 채택 11건이다.

- `tools/testing/selftests/kvm/arm64/pkvm.c` — pkvm selftest 신설, PIE/POE 테스트, 성공 출력 (3건)
- `tools/testing/selftests/hyp-trace/` — hyp tracefs ftrace 테스트 (1건)
- `kvm_util.h` / `kvm_util.c` — protected VM 타입 추가, vcpu iterator 수정, VM fd 종료 후 메모리 정리, guest global memory 읽기 매크로, 주석 (5건)
- `ucall_common.h` / `ucall_common.c` — guest mmio 영역 주소 조회, ucall 풀 메모리 정보 조회 (2건)

나머지 32건은 `selftests/android/*.xml`, `tools/testing/kunit/`, `tools/testing/android/bin/` 등 Android 테스트 패키징이다. pKVM과 무관하다.

T5 채택 3건이다.

- `arch/arm64/kernel/module.c` — pKVM 모듈 심볼 import 수정
- `arch/arm64/kernel/module-plts.c` — `CONFIG_KVM` 가드 추가
- `arch/arm64/include/asm/hyp_image.h` + `arch/arm64/kernel/alternative.c` — `alt_cb_patch_nops`의 `kvm_nvhe` 별칭 export

**판정 보류였다가 배제한 3건**

| 커밋 | 배제 근거 |
|---|---|
| `ANDROID: arm64: Forcefully disable SME at runtime` | 본문상 KMI freeze 전 `CONFIG_ARM64_SME` 비활성화 목적. pKVM SME 작업과 무관 |
| `ANDROID: arm64: stacktrace: Export arch_stack_walk symbol` | 본문상 vendor module의 스택 덤프 커스터마이즈용 |
| `ANDROID: Reintroduce support for CONFIG_CMDLINE_EXTEND` | crosvm 부팅과 관련은 있으나, upstream이 `arm64: Drop support for CMDLINE_EXTEND`로 의도적으로 제거한 기능. 재투고는 결정된 사안을 되돌리는 일 |

세 번째 항목은 AVF 게스트 부팅 요건이므로 머지 대상에서는 빼되 별도로 기록해 둔다.

#### 교차 검증

접두사 기반 집계와 대조했다.

| 방식 | 결과 | 판정 |
|---|---|---|
| 경로 기반 + 수동 검토 (확정) | **673** | 기준 |
| 접두사 확장 필터 (pKVM 키워드) | 710 | 오차 37. 대체로 일치하나 오탐 포함 |
| 접두사 좁은 필터 (`ANDROID: KVM/ARM64`) | 566 | **107 누락** |
| `ANDROID:` 계열 전체 | 1587 | 과다. 비대상 다수 포함 |

좁은 필터가 놓치는 107개는 IOMMU/SMMU(62), 장치·메모리 주변(36), 셀프테스트·arm64 기타(9)에 몰려 있다. `iommu/arm-smmu-v3-kvm-pv`, `pviommu`, `dma-buf`, `virtio_balloon`, `swiotlb` 계열이 대표적이다. **접두사 필터만으로 대상을 확정하면 IOMMU 스택이 통째로 빠진다.**

#### 3차 정제 — 파일 단위 재검증

diff 규모를 재면서 `drivers/misc/uid_sys_stats.c`와 `TEST_MAPPING`이 상위에 잡혔다. 둘 다 pKVM과 무관하다. 경로 필터 `drivers/misc`·`drivers/virtio`가 끌어온 오탐이었다.

- `TEST_MAPPING`은 upstream v6.18에 존재하지 않는다(`git ls-tree` 확인). ACK 전용 파일 목록에 추가했다.
- `tools/testing/{selftests/android,kunit,android}`, `android/`, `gki/`, `kmi/`도 같은 이유로 배제했다.
- 이 규칙으로 28건이 빠졌다. Cts/Vts presubmit 등록, `uid_sys_stats` 개선 등이다.
- 남은 의심 6건을 본문까지 확인해 4건을 더 뺐다. `ZONE_DMA32` 옵션, dma ops vendor hook, `CONFIG_CFI_CLANG` 개명, `UID_SYS_STATS_DEBUG` 정리다.
- 반대로 `arm64: Disable MTE at EL1/EL0`과 `head.S: Do not trap access to MPAMSM_EL1`은 각각 `kvm/arm.c`, `hyp/switch.h`를 건드리므로 유지했다.

**최종 머지 대상은 673 커밋이다.**

#### 파일별 diff 규모

673커밋의 `--numstat`을 합산했다. ACK 전용 파일은 제외했다.

**총 38,844 라인 (추가 32,201 / 삭제 6,643), 고유 파일 231개.**

| 영역 | 추가 | 삭제 | 합계 | 파일 |
|---|---|---|---|---|
| `arch/arm64/kvm/hyp` (EL2 코드) | 14961 | 3022 | **17983** | 68 |
| `drivers/iommu` (SMMUv3·pvIOMMU) | 5353 | 1736 | **7089** | 26 |
| `arch/arm64/kvm` (호스트측) | 5540 | 1253 | **6793** | 23 |
| `arch/arm64` (헤더·부팅) | 2276 | 398 | **2674** | 33 |
| `Documentation` | 1119 | 24 | **1143** | 11 |
| `tools` (셀프테스트) | 1045 | 23 | **1068** | 9 |
| `include` | 472 | 53 | **525** | 17 |
| `drivers/misc/pkvm-*` | 434 | 14 | **448** | 10 |
| `drivers/virt` | 290 | 66 | **356** | 5 |
| `virt/kvm` (공통) | 288 | 6 | **294** | 3 |
| `drivers/vfio` | 216 | 5 | **221** | 9 |
| `drivers/virtio` (balloon) | 92 | 11 | **103** | 5 |
| `dma-buf` / `kernel/dma` | 66 | 16 | **82** | 6 |
| 기타 | 49 | 16 | **65** | 6 |

**EL2 코드가 전체의 46%를 차지한다.** IOMMU 스택(18%)과 호스트측 KVM(17%)이 뒤를 잇는다. 이 셋이 82%다.

변경량 상위 파일이다.

| 파일 | 변경 라인 | 커밋 |
|---|---|---|
| `arch/arm64/kvm/hyp/nvhe/mem_protect.c` | 3569 | 109 |
| `arch/arm64/kvm/pkvm.c` | 2493 | 104 |
| `arch/arm64/kvm/hyp/nvhe/pkvm.c` | 2140 | 78 |
| `arch/arm64/kvm/hyp/nvhe/hyp-main.c` | 2040 | 91 |
| `drivers/iommu/arm/arm-smmu-v3/pkvm/pv/arm-smmu-v3-pv.c` | 1621 | 30 |
| `arch/arm64/kvm/hyp/nvhe/ffa.c` | 1607 | 34 |
| `drivers/iommu/arm/arm-smmu-v3/arm-smmu-v3.c` | 1312 | 8 |
| `drivers/iommu/arm/arm-smmu-v3/arm-smmu-v3-common.c` | 1239 | 6 |
| `arch/arm64/kvm/hyp/nvhe/iommu/iommu.c` | 1095 | 35 |
| `arch/arm64/kvm/hyp_events.c` | 1093 | 15 |
| `arch/arm64/kvm/mmu.c` | 1075 | 27 |

`mem_protect.c` 하나에 109개 커밋이 몰려 있다. `pkvm.c`(104), `hyp-main.c`(91)도 마찬가지다. **이 세 파일이 충돌 위험의 핵심이다.** 토픽 단위로 쪼개도 서로 겹치므로, 3단계 토픽 분류 시 이 파일들을 건드리는 커밋의 순서를 먼저 확정해야 한다.

반면 `arm-smmu-v3.c`(8커밋), `arm-smmu-v3-common.c`(6커밋)는 커밋당 변경량이 크지만 커밋 수가 적다. 큰 덩어리를 통째로 옮기는 형태라 순서 의존이 낮다.

#### arch/arm64 헤더·부팅 계층 판정 (확정)

문서가 기록한 "2,674라인 33파일"은 실측으로 재현된다. 추가 2,276 / 삭제 398 / 고유 33파일이다. 구성은 T1 561건이 만드는 31파일에 T5 채택 3건이 더하는 2파일(`asm/hyp_image.h`, `kernel/alternative.c`)이다.

**33파일 전부 pKVM 사유로 변경되었다. `unrelated` 판정은 0건이다.** 따라서 이 영역을 이유로 673커밋을 줄일 필요는 없다.

| 판정 | 파일 | 라인 |
|---|---|---|
| pkvm-only (v6.18에 없는 신규 파일) | 5 | 889 |
| shared / KVM 소유 | 11 | 1,335 |
| shared / arm64 코어 | 17 | 450 |
| unrelated | 0 | 0 |

경계선이었던 두 건이다. `arch/arm64/kernel/head.S`(HCR_ATA)와 `arch/arm64/include/asm/el2_setup.h`(MPAM2_HOST_FLAGS)는 각각 `kvm/arm.c`, `hyp/switch.h`를 함께 건드리고 커밋 본문이 호스트 격리 목적을 명시한다. 유지가 맞다.

집계 시 주의할 함정 두 가지다.

- `52820b3c1e83`(gen-hyprel 이동)은 rename이라 numstat이 0/0이다. pathspec에서 `arch/arm64/kvm`을 빼면 원본이 안 보여 +462로 잘못 잡힌다.
- T3 커밋 `a1dfc257ae63`(`arch/arm64/mm/init.c` +23/-3)은 673 집합에 없다. 삭제 398이 정확히 맞아 확인된다. 이는 집계 누락이 아니라 의도적 배제다. 제목이 `ANDROID: arm64/mm: Add command line option to make ZONE_DMA32 empty`로, 3차 정제에서 배제한 `ZONE_DMA32` 옵션 건이다. 본문도 GKI 파트너의 메모리 튜닝 목적이며 pKVM과 무관하다.

##### Upstream 반려 위험

`shared/arm64` 17파일 450라인 중 11파일 406라인이 pKVM EL2 모듈 로딩에 묶여 있다. 파일은 `kernel/module.c`(269), `asm/module.h`(52), `asm/module.lds.h`(44), `asm/assembler.h`(15), `kernel/module-plts.c`(6), `asm/memory.h`(5), `arch/arm64/Makefile`(5), `mm/init.c`(4), `tools` 계열(6)이다.

빌드 영향은 `CONFIG_KVM`과 `__KVM_NVHE_HYPERVISOR__` 가드로 이미 좁혀져 있다. 쟁점은 가드가 아니라 설계 방향이다. 커밋 `f92ff4fd5ae8` 본문은 해당 모듈이 프로프라이어터리이며 GPL 심볼을 쓰면 안 된다고 밝히고, `EXPORT_SYMBOL_GPL`을 `ASM_BUILD_BUG()`로 재정의한다. arm64/KVM 메인테이너 수용 가능성은 낮다고 본다(평가).

나머지는 중간 위험 2파일 35라인(`vmlinux.lds.S`, `mm/fault.c`), 낮은 위험 4파일 9라인(`head.S`, `el2_setup.h`, `asm-offsets.c`, `alternative.c`)이다. 낮은 위험 4건은 단독 투고가 가능하다.

#### `pkvm-master-6.18` 커버리지

673커밋의 고유 제목 673개를 `pkvm-master-6.18`과 대조했다.

| 구분 | 수 |
|---|---|
| master에 있음 (일괄 추출 가능) | **356** |
| master에 없음 (개별 cherry-pick 필요) | **317** |

master만으로는 대상의 53%밖에 확보되지 않는다.

#### 재실측과 673 대조: 최종 658커밋

동일 필터로 대상 집합을 다시 뽑았다. 1차 결과는 660커밋이고 673과 13커밋 차이가 난다. 계층별로 대조해 차이를 국소화했다.

| 계층 | 문서 673 | 재실측 660 | 차 |
|---|---:|---:|---:|
| T1 코어 KVM/hyp | 561 | 561 | 0 |
| T2 IOMMU/SMMU | 62 | 63 | +1 |
| T3 장치·메모리 주변 | 36 | 22 | -14 |
| T4 셀프테스트 | 11 | 11 | 0 |
| T5 arm64 기타 | 3 | 3 | 0 |
| **합계** | **673** | **660** | **-13** |

**T1·T4·T5는 정확히 일치한다.** 차이는 T2와 T3에만 있다.

##### 673 목록 재구성

673의 SHA 목록은 남아 있지 않다. 대신 본 절이 명시한 배제 규칙(ACK 전용 파일, `uid_sys_stats` 계열, `ZONE_DMA32`, dma ops vendor hook, `CFI_CLANG` 개명)을 T3 원시 72건에 그대로 재적용했다. 결과는 채택 39건이다. 문서 기록 36건과 3건이 어긋난다. 이 잔차는 T3 원시 집합 자체의 차이(문서 67 대 재실측 72)에서 온다.

##### 쟁점 18건 (문서 채택 · 재실측 배제)

전수 특정했다. 모두 변경 파일을 직접 확인했고, **18건 전부 KVM·hyp·pKVM 경로를 단 하나도 건드리지 않는다.**

| 커밋 | 날짜 | 제목 |
|---|---|---|
| `a8d66d536ea0` | 2019-10-02 | dma-buf: heaps: Allow cma heaps to be configured as a module |
| `be65ab2ef60b` | 2021-06-03 | dma-heap: Let dma heap use dma_map_attrs to map & unmap iova |
| `41a3d93a3987` | 2021-11-15 | add dma-buf namespace to system_heap.c & cma_heap.c |
| `9b5f1c910c59` | 2022-02-14 | Replace "PDE_DATA" with "pde_data" |
| `5c5a86e82d6d` | 2022-06-17 | dma/debug: fix warning of check_sync |
| `f2e522742246` | 2024-04-15 | Export swiotlb_find_pool |
| `4f140e67f32c` | 2024-04-15 | dma-buf: system_heap: Reject uncached SWIOTLB buffers |
| `97c8923aa32c` | 2024-06-10 | dma-buf: align fd_flags and heap_flags with uapi |
| `5714d24869a6` | 2024-08-13 | dma-buf: Follow function parameter type change |
| `878e51a94ade` | 2024-08-14 | swiotlb: Follow upstream rename of swiotlb_find_pool() |
| `d7f4b8843c1c` | 2024-08-14 | dma-buf: Use is_swiotlb_buffer() direct replacement |
| `2fa3ec0ece12` | 2025-03-25 | dma-buf: system_heap: Convert symbol namespace to string literal |
| `9d25842232e8` | 2025-03-25 | dma-buf: cma_heap: Convert symbol namespace to string literal |
| `b840707bb916` | 2025-06-17 | dma-buf: heaps: system: Remove global variable |
| `c0421704b136` | 2025-09-19 | dma-buf: Export dmabuf iteration APIs |
| `f080c8f3d4f6` | 2025-10-21 | dma-buf: system_heap: import DMA_BUF_HEAP namespace |
| `1b3bd0b5affd` | 2025-10-23 | dma-buf: cma_heap: import DMA_BUF_HEAP namespace |
| `39418562e247` | 2026-03-10 | swiotlb: Add per pool encrypted property |

전부 Android 범용 dma-buf 힙과 swiotlb 유지보수다. 네임스페이스 도입, 심볼 리터럴 변환, upstream 개명 추종이 대부분이다. **경로 필터 `drivers/dma-buf`·`kernel/dma`가 끌어온 오탐이며 배제가 맞다.** pKVM의 DMA-BUF 기반 pVM 메모리 기능은 `arch/arm64/kvm` 아래에 있어 T1에 잡힌다.

##### 역방향 2건 (문서 배제 · 재실측 채택)

문서 판단이 옳다. 재실측 집합에서 추가로 뺀다.

| 커밋 | 계층 | 변경 파일 | 판정 |
|---|---|---|---|
| `35ec97b1af6e` treewide: rename CONFIG_CFI_CLANG to CONFIG_CFI | T3 | `*_defconfig` 3개, `debug_kinfo.c`, `virtio_dma_buf.c` | pKVM 무관. defconfig가 대부분이라 실질 ACK 전용 |
| `592a281e889d` mm: add vendor hook to set up dma ops | T2 | `drivers/iommu/dma-iommu.c`, `include/trace/hooks/iommu.h` | 벤더 훅. pKVM 무관 |

##### 결론

**최종 머지 대상은 658커밋이다.** 660에서 역방향 2건을 뺀 값이다.

| 구분 | 수 |
|---|---:|
| 1차 재실측 | 660 |
| 역방향 2건 배제 | -2 |
| **확정** | **658** |

673과의 차이 15건은 모두 해소했다. 쟁점 18건은 배제가 맞고, 역방향 2건은 문서 판단이 맞다. 673은 T3 오탐 18건을 남기고 T3 3건을 원시 단계에서 누락한 결과로 본다.

미해소로 남는 것은 T3 원시 집합의 3건 차이(문서 67 대 재실측 72)뿐이다. 673 목록이 없어 그 3건은 특정할 수 없다.

앞선 절의 38,844라인과 356/317 커버리지는 673 기준 수치다. 658 기준 재집계는 하지 않았다.

##### 빌드 검증에서 드러난 판정 오류 2건

이 확정 집합을 실제로 v6.18 위에 올려 빌드한 결과, 판정 오류가 확인되었다(9.2절).

| 커밋 | 본 절 판정 | 실제 |
|---|---|---|
| `b163851117b3` dma-buf: Expose is_dma_buf_file() | T3 배제 (pKVM 무관) | **오배제**. DMA-BUF 기반 pVM 메모리가 `arch/arm64/kvm/mmu.c`에서 이 함수를 쓴다 |
| `6484ce851c96` iommu: Add vendor data for custom iommu fault handler | T2 채택 (IOMMU 63건 전부 pKVM 관련) | **오탐**. 벤더 폴트 핸들러용 훅이다 |

**경로 기반 필터만으로는 확정할 수 없다.** 두 건 모두 경로는 pKVM 영역이지만 실제 성격은 반대였다. 확정 집합은 빌드로 교차 검증해야 한다.

### 8.2 단계별 절차

#### 0단계. 작업 트리 준비

```bash
git clone https://android-kvm.googlesource.com/linux pkvm-linux
cd pkvm-linux
git remote add korg https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
git fetch korg v6.18 --no-tags
git fetch origin for-android/pkvm-mainline-6.18 for-android/pkvm-master-6.18
git switch -c pkvm-6.18-merge v6.18
```

#### 1단계. 대상 집합 확정

8.1절에서 확정한 경로와 필터를 그대로 쓴다. `--filter=blob:none`으로 트리를 받아 두어야 경로 필터가 실용적인 속도로 돈다.

```bash
BASE=$(git rev-parse v6.18)
ML=origin/for-android/pkvm-mainline-6.18

AND() {
  git log --format='%H%x09%s' --no-merges $BASE..$ML -- "$@" \
    | grep -E '\t(ANDROID|SQUASH: ANDROID|BACKPORT: ANDROID)' \
    | grep -vE '\tANDROID: (GKI|INCFS|OWNERS)' | cut -f1 | sort -u
}

AND arch/arm64/kvm 'arch/arm64/include/asm/kvm*' arch/arm64/include/asm/virt.h \
    include/kvm virt/kvm Documentation/virt/kvm                       > t1.txt   # 561
AND drivers/iommu include/linux/iommu.h include/uapi/linux/iommu.h    > t2.txt   #  63
AND drivers/virt drivers/vfio drivers/dma-buf kernel/dma \
    include/linux/swiotlb.h drivers/misc drivers/virtio               > t3.txt   #  67
AND tools/testing/selftests/kvm tools/testing/selftests/hyp-trace     > t4.txt   # 선별 15
AND arch/arm64/kernel arch/arm64/configs                              > t5.txt   # 선별  7

cat t1.txt t2.txt t3.txt t4.txt t5.txt | sort -u > target.txt
```

T4와 T5는 그대로 쓰면 안 된다. 원시 286개 중 채택은 14개뿐이다. **제목이 아니라 변경 파일로 판정한다.** 제목에 `PKVM`이 있어도 `gki_defconfig`만 바꾸는 커밋이 있기 때문이다.

```bash
# 1차: upstream 에 없는 파일만 건드리는 커밋 배제
NONUP='^(arch/[a-z0-9_]+/configs/|BUILD\.bazel$|.*\.fragment$|build\.config|.*\.bzl$|OWNERS)'
git show --name-only --format='' <sha> | grep -v '^$' | grep -vE "$NONUP" | wc -l   # 0 이면 배제

# 2차: 남은 코드 커밋을 실제 경로로 판정
#   T4 채택 = tools/testing/selftests/{kvm,hyp-trace}/ 의 소스를 건드리는 것
#   T5 채택 = arch/arm64/kernel 또는 asm 헤더를 건드리는 pKVM 커밋
```

8.1절에 검토 결과를 정리해 두었다. 재작업 시 그 목록을 출발점으로 쓴다.

#### 2단계. 실제 신규 머지 대상 선별

접두사로 이미 상류에 있는 것을 걸러낸다.

- `UPSTREAM:` / `BACKPORT:` — v6.18에 이미 존재. **제외**
- `FROMGIT:` / `FROMLIST:` — maintainer tree 또는 LKML 게시 완료. **중복 투고 주의**, 별도 관리
- `ANDROID:` — 순수 out-of-tree. **실제 머지 대상**

확정 경로 안에서 상류 반영분은 다음과 같다. 이미 8.1절 필터에서 제외되어 있으나, 별도 관리가 필요하므로 목록을 따로 뽑아 둔다.

| 접두사 | 커밋 수 | 처리 |
|---|---|---|
| `FROMLIST:` 계열 | 42 | LKML 게시 완료. 상류 시리즈 추종 |
| `FROMGIT:` 계열 | 7 | maintainer tree 반영분 |
| `UPSTREAM:` | 6 | v6.18에 이미 존재 |

```bash
git log --format='%H%x09%s' --no-merges $BASE..$ML -- <8.1절 경로> \
  | grep -E '\t(FROMLIST|FROMGIT|UPSTREAM|BACKPORT: FROM)' > upstreamed.txt
```

#### 3단계. 토픽 분류 (실측 완료)

6.18용 토픽 태그는 없다(`pkvm-6.18-*` 0개). 그러나 `pkvm-7.1-*` 태그 40개가 원격에 실재하며 로컬로 받아 확인했다. 38개가 완전한 선형 사슬을 이루고 `pkvm-7.1-modtracing-v1`만 별도 가지다. 스택 규모는 376커밋이다. **상류 투고용 토픽 분할의 참고 기준이 저장소에 이미 있다.**

다만 태그 구간은 순수한 단일 토픽이 아니다. 태그는 그 작업 창에서 적용된 배치이지 그 토픽의 커밋 전부가 아니다. 예를 들어 `pkvm-7.1-smctrng` 구간 18커밋에는 무관한 수정이 섞여 있다. 따라서 태그는 순서 참고용으로만 쓰고, 구성원은 제목·경로 규칙으로 재산정했다.

858커밋을 26개 토픽으로 나눴다. 머지 대상은 660커밋이고, `ack-only` 152커밋과 `non-pkvm` 46커밋을 뺐다. 미분류는 1건이다. 이후 673 대조에서 역방향 2건을 더 빼 **확정은 658커밋**이다. 8.1절 참조.

| 토픽 | 커밋 | 토픽 | 커밋 |
|---|---:|---|---:|
| `pvm-core` | 119 | `ffa` | 35 |
| `modules` | 81 | `hyp-alloc` | 34 |
| `pviommu` | 73 | `mem-opt` | 30 |
| `tracing` | 51 | `smmu-v3` | 22 |
| `host-stage2` | 45 | `device-assign` | 22 |
| `iommu-core` | 45 | 그 외 13토픽 | 83 |

신뢰도가 낮은 두 그룹이 있다. `host-stage2` 45커밋은 기능 단위가 아니라 `nvhe/mem_protect.c`·`nvhe/setup.c`를 건드린다는 이유로 묶인 파일 단위 잔여 버킷이다. `pvm-core` 119커밋은 광역 버킷이며 오배정이 눈으로 확인된다. 둘 다 수동 재검토가 필요하다.

전체 토픽별 커밋 목록은 `work/analysis/topic-classification.md` 부록 A에 있다.

#### 4단계. 스택 순서 결정 (판단 변경)

**`for-android/pkvm-master-6.18`은 뼈대로 쓸 수 없다.** 이전 판단을 실측으로 뒤집었다. 근거는 둘이다.

첫째, master의 선형 순서는 mainline과 사실상 같다. 공통 370커밋의 Spearman 순위상관이 0.9997이고 68,265개 쌍 중 역전이 51쌍뿐이다. 토픽별로 재배열된 브랜치가 아니라 같은 시간순 이력의 더 오래된 스냅샷이다. 재배열 정보가 없다.

둘째, 커버리지가 부족하다. 858커밋 중 master에 있는 것은 370개다. 없는 488개 중 362개는 master tip(2025-11-03)보다 앞선 커밋인데도 빠져 있다. IOMMU 트랙이 통째로 없다. master 로그에서 `pviommu`는 0건이고 mainline에서는 23건이다.

뼈대로 삼을 것은 **`pkvm-7.1-*` 태그 스택**이다. 실제 토픽 재배열의 결과물이라 코어 트랙 순서를 준용할 수 있다.

#### 충돌 위험 3파일의 순서 (실측)

세 파일 모두 전체 토픽의 3분의 2 이상이 건드린다.

| 파일 | 커밋 | 건드리는 토픽 | 연속 구간 | 평균 구간 길이 | 재배열 시 이동 커밋 |
|---|---:|---:|---:|---:|---|
| `hyp/nvhe/mem_protect.c` | 109 | 17 | 70 | 1.56 | 95 (87%) |
| `pkvm.c` | 104 | 16 | 56 | 1.86 | 65 (63%) |
| `hyp/nvhe/hyp-main.c` | 91 | 17 | 49 | 1.86 | 67 (74%) |

세 파일의 합집합은 251커밋이다. 시간순으로 놓았을 때 서로 교차하는 토픽 쌍이 143쌍이다. **어떤 토픽 순서를 잡아도 이 세 파일은 시리즈 경계를 넘나든다.** 토픽 단위 재배열은 곧 이 세 파일에 대한 대규모 수동 충돌 해소를 뜻한다.

셋을 동시에 건드리는 커밋은 9건이다. 모두 호스트-게스트 메모리 이전을 EL1 진입점(`pkvm.c`), HVC 디스패치(`hyp-main.c`), 소유권 판정(`mem_protect.c`) 세 곳에 동시에 심는다. 쪼갤 수 없는 원자 단위로 본다.

#### 5단계. 추출과 적용

확정 658커밋은 이렇게 갈린다. 괄호 안은 673 기준 종전 수치다.

```bash
# (a) master 에 있는 368개(종전 356): 선형 시리즈 일괄 추출
git format-patch --no-numbered -o series/ \
  $(git merge-base v6.18-rc2 origin/for-android/pkvm-master-6.18)..origin/for-android/pkvm-master-6.18

# (b) master 에 없는 290개(종전 317): mainline 에서 개별 cherry-pick
git cherry-pick -x <sha>
```

(b)의 290개에 IOMMU/SMMU 스택 대부분과 최신 기능(device assignment, DMA-BUF 기반 pVM 메모리)이 들어 있다. 작업량이 (a)와 대등하다고 보고 일정을 잡아야 한다.

(a)를 그대로 쓰면 시간순 배치가 된다. 토픽별 투고를 하려면 8.3절 시리즈 분할안에 맞춰 재배열해야 하며, 그 비용은 위의 충돌 위험 3파일 표에 나온 그대로다.

`master`는 **v6.18-rc2** 기준이다. v6.18 정식 위에 올리면 rc2~정식 사이 변경과 충돌할 수 있으므로 재정렬을 전제로 한다.

#### 6단계. 빌드와 동작 검증

```bash
make ARCH=arm64 defconfig
./scripts/config -e KVM -e PKVM_DEBUG -e PKVM_DISABLE_STAGE2_ON_PANIC -e PKVM_STACKTRACE
make ARCH=arm64 -j"$(nproc)"
```

심볼 개명은 실측으로 확인했다. upstream v6.18의 `arch/arm64/kvm/Kconfig`에는 `NVHE_EL2_DEBUG`와 `PROTECTED_NVHE_STACKTRACE`가 있으나, 기준 트리에는 없다. 두 ANDROID 커밋이 이름을 바꿨다.

| 기존 심볼 (upstream v6.18) | 변경 후 (pKVM 트리) | 커밋 |
|---|---|---|
| `NVHE_EL2_DEBUG` | `PKVM_DEBUG` | `62c0dcbb` (2025-02-21) |
| `PROTECTED_NVHE_STACKTRACE` | `PKVM_STACKTRACE` | `8d88e567` (2025-02-21) |

새 제약이 하나 붙었다. `PKVM_STACKTRACE`는 `PKVM_DISABLE_STAGE2_ON_PANIC`에 의존하며 후자의 기본값은 `n`이다. 따라서 함께 켜야 한다.

Kconfig만으로는 부족하다. 실제 보호 모드로 부팅하려면 커널 커맨드라인에 `kvm-arm.mode=protected`가 있어야 한다. `gki_defconfig`는 이를 `CONFIG_CMDLINE`에 내장하는 방식을 쓴다.

ACK `android17-6.18`과 대조해 누락을 잡는다. `pkvm-master-6.18`의 394커밋 중 378개가 ACK에 있으므로, ACK를 정답지로 쓸 수 있다.

#### 7단계. 투고 준비

토픽별 시리즈로 쪼개 투고한다. CC 대상은 2-2절에 정리한 세 리스트다. `linux-kernel@vger.kernel.org`, `kvmarm@lists.linux.dev`, `linux-arm-kernel@lists.infradead.org`다.

### 8.3 시리즈 분할안

토픽 분류와 의존 순서를 근거로 투고 단위를 짰다. 총 **32시리즈**다. 시리즈 상한은 상류 관행에 맞춰 25~30패치로 잡았다.

| 트랙 | 시리즈 | 커밋 | 내용 |
|---|---:|---:|---|
| A 코어 pKVM | 24 (S01~S24) | 486 | pvm-core, host-stage2, hyp-alloc, modules, ffa, tracing 등 |
| B IOMMU | 7 (S25~S31) | 162 | iommu-core, smmu-v3, pviommu, device-assign |
| C 검증 | 1 (S32) | 12 | selftests |

임계 경로는 트랙 A의 S01~S07, 168커밋이다. 이것이 들어가기 전에는 나머지가 성립하지 않는다. 트랙 B는 S05와 S18만 끝나면 트랙 A와 병렬로 투고할 수 있다.

**IOMMU 트랙은 `pkvm-7.1-*` 스택에 전혀 포함되지 않는다.** 상류 투고 계획에서 별도로 다뤄야 한다.

전체 시리즈 목록과 선행 관계는 `work/analysis/topic-classification.md` 7장에 있다.

### 8.4 리스크

| 리스크 | 내용 | 대응 |
|---|---|---|
| 대상 집합 누락 | 접두사 필터만 쓰면 IOMMU/SMMU 스택 등 107개 누락 | 8.1절 경로 기반 집계 사용 |
| 작업량 과소 추정 | master로 커버되는 건 658개 중 368개(56%)뿐 | 나머지 290개 cherry-pick을 대등한 작업량으로 계상 |
| 토픽 재배열 비용 | 충돌 위험 3파일에서 토픽 쌍 143쌍이 교차한다. `mem_protect.c`는 109커밋 중 95개(87%)가 위치를 바꿔야 한다 | 시간순 적용으로 먼저 빌드를 세운 뒤 토픽 재배열을 별도 공정으로 잡는다. 세 파일 동시 변경 9건은 쪼개지 않는다 |
| 베이스 불일치 | `master-6.18`은 v6.18-rc2 기준 | 5단계에서 재정렬 전제 |
| 중복 투고 | `FROMLIST:` 42개는 이미 LKML 게시분 | 2단계에서 분리 관리 |
| 상류 진행과 충돌 | protected guest는 upstream 진행 중 (7.2절) | 해당 영역은 upstream 시리즈 추종, 독자 투고 지양 |
| 소스 갱신 정지 | `pkvm-master-6.18`은 2025-11-05 이후 갱신 없음 | `pkvm-mainline-6.18`을 기준 트리로 유지 |
| 제목 기반 선별의 오판 | 제목에 `PKVM`이 있어도 `gki_defconfig`만 바꾸는 커밋이 존재 | 제목이 아니라 **변경 파일**로 판정 |
| EL2 모듈 로딩이 전체를 막음 | `shared/arm64` 17파일 450라인 중 11파일 406라인(90%)이 pKVM EL2 모듈 로딩 하나에 묶여 있다. 프로프라이어터리 벤더 모듈을 EL2에 올리는 설계라 메인테이너 수용 가능성이 낮다 | 해당 11파일 클러스터를 별도 시리즈로 격리해 마지막에 투고. 선행 시리즈가 막히지 않게 한다 |

### 8.5 미결 사항

- **T5 원시 집합 수치 불일치.** 8.1절 T4·T5 표는 T5를 "원시 101 / ACK 전용 87 / 코드 포함 14"로 적었으나 재실측은 151 / 132 / 19다. 채택 3건은 동일해 673에는 영향이 없다. 원시 수치의 산출 기준 차이로 보이나 원인은 미확인이다.
- **T3 원시 집합의 3건 차이.** 8.1절 673 대조로 쟁점 18건과 역방향 2건을 전수 특정해 대상을 658로 확정했다. 남은 것은 T3 원시 수치의 차이(문서 67 대 재실측 72)에서 오는 3건이다. 673의 SHA 목록이 없어 특정할 수 없다.
- **`host-stage2` 45커밋의 재배치.** 파일 단위 잔여 버킷이라 그대로 시리즈가 되지 않는다. 커밋 본문을 읽고 다른 토픽으로 분산해야 한다.
- **`pvm-core` 119커밋의 정밀 분할.** 시간순 4등분은 임시안이다. `pkvm_hyp_vm`·`pkvm_hyp_vcpu` 도입 시점을 기준으로 다시 잡아야 한다.
- **심볼 수준 의존 검증 미완.** 토픽 의존 근거는 커밋 제목에 심볼명이 드러난 경우로 한정했다. 저장소가 `--filter=blob:none`이라 `git log -S`로 심볼 도입 시점을 전수 추적하지는 않았다.

#### defconfig pKVM 옵션 (확정)

`gki_defconfig`와 `microdroid_defconfig`에서 pKVM·가상화 관련 고유 심볼 20개를 수집했다. 그중 upstream v6.18에 없는 것은 3개다.

| 심볼 | 위치 | 도입 커밋 |
|---|---|---|
| `VFIO_PKVM_IOMMU` | `drivers/vfio/Kconfig` | `6b83b3c7` ANDROID: drivers/vfio: Add VFIO_PKVM_IOMMU (2023-11-13) |
| `PKVM_PVIOMMU` | `drivers/iommu/Kconfig` | `acf2e802` ANDROID: drivers: iommu: pviommu: Add basic driver structure (2023-04-18) |
| `CMDLINE_EXTEND` | `arch/arm64/Kconfig` | 신규 심볼이 아니다. upstream이 `cae118b6acc3`으로 "Kernel command line type" choice에서 이 항목만 제거했다. choice 구조 자체는 그 전부터 있었고 default는 `CMDLINE_FROM_BOOTLOADER`다 |

`ARM_PKVM_GUEST`는 두 defconfig 모두 `y`이고 upstream v6.18에 이미 있다(`drivers/virt/coco/pkvm-guest/Kconfig`). 별도 대응이 필요 없다.

`ARM_SMMU`, `NVHE`, `HYP`, `PROTECTED` 키워드는 두 defconfig 어디에도 `CONFIG_` 라인으로 없었다. `PROTECTED`는 `CONFIG_CMDLINE` 문자열 안의 `kvm-arm.mode=protected`에만 등장한다.

확인 불가 항목이 둘 남았다.

- `ARM_PKVM_GUEST`가 select 하는 `ARCH_HAS_VIRTIO_BALLOON_HYP_OPS`의 v6.18 존재 여부
- `PKVM_STACKTRACE` + `PKVM_DISABLE_STAGE2_ON_PANIC` 조합의 실제 빌드 성공 여부. Kconfig 파일 판독으로만 판단했고 빌드는 돌리지 않았다.

#### CONFIG_CMDLINE_EXTEND 판단 (확정)

결론: 머지 대상에서 제외한다. Android 다운스트림 전용으로 유지한다.

근거는 다음과 같다.

| 항목 | 내용 |
|---|---|
| upstream 제거 | cae118b6acc3 (Will Deacon, Linux 5.12, 2021-03) |
| 제거 사유 | 설계 불일치. 문서상 동작은 "부트로더 인자를 CONFIG_CMDLINE 뒤에 append"인데 arm64 FDT 처리는 반대로 동작. EFI stub 및 idreg override의 파싱 순서와도 어긋남. |
| 대체안 | CMDLINE_PREPEND/APPEND 제안 (Daniel Walker, 2019): 미머지. devicetree `/chosen/bootargs-append` (2024-05 문서화만, drivers/of/fdt.c 구현 없음) |
| 현황 (2026-08) | arch/arm64/Kconfig에 CMDLINE_EXTEND 없음. arch/arm/Kconfig(32비트 ARM)에는 남아 있음. |
| 재도입 시도 | George Davis(2022-08), Chris Packham(2023-03) 등: 모두 미머지 |
| Android 패치 | `ANDROID: Support CONFIG_CMDLINE_EXTEND`, Carlos Llamas (2021-09-19). 원 저자 Doug Anderson/Colin Cross. idreg-override.c까지 고쳐 Will Deacon이 지적한 순서 불일치를 해소함. 기술적으로는 upstream 요구 방향과 부합. 커밋 메시지에 AVF/microdroid/pKVM 언급 없음. |
| pKVM 소속 | 커밋 `e5d7c84f8167`는 `Bug: 458241298` 태그를 달고 있으며, 서명자가 Keir Fraser, Fuad Tabba(pKVM 개발자)다. 채택된 T5 커밋 `8765527b3df1`, `d833601fdcb3`과 동일한 버그 ID다. 본문이 crosvm의 device-tree `bootargs` 전달을 명시해 AVF 게스트 부팅 요건이다. |
| 필요성 | AVF/microdroid가 이 옵션을 직접 요구한다는 공개 근거 확인 불가. 관련 Buganizer 120440972는 비공개. GKI는 gki_defconfig의 CONFIG_CMDLINE에 `kvm-arm.mode=protected`를 내장하므로 벤더 device tree bootargs와 병합할 수단이 필요하다는 정황은 있으나 추론. pKVM 프로젝트 차원에서는 실제로 요구된다. |
| 배제 사유 | **Upstream 정책 충돌**. pKVM 무관이 아니다. upstream이 `arm64: Drop support for CMDLINE_EXTEND`로 의도적으로 제거한 기능이므로 재투고는 결정된 사안을 되돌리는 것이다. 기술적 개선(idreg-override.c 순서 수정)만으로는 정책 거부를 극복하기 어렵다. |

권고: 굳이 upstream에 올린다면 PREPEND/APPEND 통합 형태로 재작성해야 하며, 단순 재도입은 반려 가능성이 높다.

---

## 9. v6.18 빌드 검증 (실행 완료)

- 실행일: 2026-08-07
- 목표: upstream 투고가 아니라 **v6.18 위에서 pKVM 패치가 빌드되는지 확인**하는 것으로 범위를 좁혔다. 따라서 8장의 토픽 분류·시리즈 분할안은 이번 검증에 쓰지 않았다. 적용 순서는 시간순 그대로다.

검증은 2단계로 했다. 1단계는 `pkvm-master-6.18`의 394커밋만, 2단계는 IOMMU 트랙까지 포함한 전량이다. 양쪽 모두 clang과 gcc에서 빌드에 성공했다.

### 9.1 1단계: 코어 pKVM 394커밋

`for-android/pkvm-master-6.18`의 **394커밋을 v6.18-rc2에서 v6.18로 리베이스**했다. IOMMU 트랙은 제외했다.

| 항목 | clang 18.1.3 (`LLVM=1`) | gcc 13.2 (`aarch64-linux-gnu-`) |
|---|---|---|
| 종료 코드 | 0 | 0 |
| `arch/arm64/boot/Image` | 38.6M | 47.1M |
| `vmlinux` | 407.8M | 159.8M |
| `kvm_nvhe.o` (EL2) | 6.3M | 2.3M |
| 오류 | 0 | 0 |
| 경고 | 0 | 0 |

**양쪽 컴파일러 모두 성공했다.** 크기 차이는 clang이 `debug_info` 포함 in-tree 빌드, gcc가 out-of-tree 빌드인 데서 온다.

pKVM 코드가 실제로 링크되었는지도 확인했다. gcc `vmlinux`에 `__kvm_nvhe_` 접두 pKVM 심볼이 92개 있다. `__pkvm_host_donate_hyp`, `__pkvm_host_share_ffa`, `__pkvm_init_vm` 등이 정상 링크되었다.

### 9.2 2단계: IOMMU·EL2 모듈 포함 전량 (721커밋)

1단계 브랜치 위에 나머지를 cherry-pick 했다. 최종 트리는 **721커밋**이다. v6.18 + pKVM 394 + 추가 322 + 빌드 수정 5다. 변경 규모는 237파일 · 34,178 추가 · 3,506 삭제다.

| 항목 | clang 18.1.3 (`LLVM=1`) | gcc 13.2 (`aarch64-linux-gnu-`) |
|---|---|---|
| 종료 코드 | 0 | 0 |
| `arch/arm64/boot/Image` | 40.5M | 47.2M |
| `vmlinux` | 429.8M | 160.2M |
| `kvm_nvhe.o` (EL2) | 9.2M | 2.9M |
| `pkvm_smc.ko` | 413K | 81K |
| `pkvm_iommu_temp.ko` | 404K | 77K |
| 오류 | 0 | 0 |
| 경고 | 0 | 0 |

**IOMMU 스택이 실제로 빌드된다.** EL2 측 `iommu.nvhe.o`, `pviommu.nvhe.o`, `pviommu-host.nvhe.o`와 호스트 측 `arm-smmu-v3-kvm.o`, `arm-smmu-v3-kvm-pv.o`가 생성된다. `__pkvm_host_iommu_attach_dev` 등 하이퍼콜 핸들러와 `pkvm_pviommu_driver_init` initcall이 링크된다. clang `vmlinux`의 `__kvm_nvhe_` 심볼은 6,725개다.

빌드에는 8.1절의 확정 집합만으로 부족하다. 다음 Kconfig를 함께 켜야 IOMMU 스택이 컴파일된다.

```bash
./scripts/config -e ARM_SMMU_V3 -e ARM_SMMU_V3_PKVM -e ARM_SMMU_V3_PKVM_PV \
                 -e PKVM_PVIOMMU -e VFIO_PKVM_IOMMU
```

#### 투고용 집합과 빌드용 집합은 다르다 (중요)

8.1절의 658커밋은 **upstream 투고 기준**이다. 빌드에는 그대로 쓸 수 없다. 이번 작업에서 확인한 차이다.

| 구분 | 투고 기준 | 빌드 기준 | 근거 |
|---|---|---|---|
| `FROMLIST:` / `FROMGIT:` | 제외 | **필수** | LKML 게시분일 뿐 v6.18에 머지된 것이 아니다. 47건을 추가했다 |
| `UPSTREAM:` | 제외 | 제외 | v6.18에 이미 있다 |
| ACK 전용 헤더 | 제외 | 일부 필수 | `include/linux/android_kabi.h`가 그렇다 |

특히 IOMMU 스택의 기반 파일 `arch/arm64/kvm/hyp/nvhe/iommu/iommu.c`를 만드는 커밋이 `FROMLIST:`다. 이것을 빼면 IOMMU 관련 후속 커밋이 전부 적용되지 않는다.

#### 8.1절 판정의 오류 2건

빌드 과정에서 대상 집합 판정의 오류가 드러났다.

| 커밋 | 8.1절 판정 | 실제 | 영향 |
|---|---|---|---|
| `b163851117b3` ANDROID: dma-buf: Expose is_dma_buf_file() | T3 배제 (dma-buf 계열, pKVM 무관) | **pKVM 전제 조건** | DMA-BUF 기반 pVM 메모리가 `arch/arm64/kvm/mmu.c`에서 이 함수를 쓴다. 빠지면 빌드 실패 |
| `6484ce851c96` ANDROID: iommu: Add vendor data for custom iommu fault handler | T2 채택 (IOMMU 63건 전부 pKVM 관련) | **pKVM 무관** | 벤더 폴트 핸들러용 훅이다. ACK 전용 헤더를 요구해 빌드 실패 |

즉 8.1절의 T3 배제 30건에는 최소 1건의 오배제가, T2 채택 63건에는 최소 1건의 오탐이 있다. **경로 기반 필터의 한계다.** 확정 집합을 실제로 쓰기 전에 빌드로 교차 검증해야 한다.

#### master판과 mainline판은 건드리는 파일이 다르다 (중요)

같은 제목의 커밋이 두 브랜치에 모두 있어도 **변경 파일이 다르다.** master에는 `pkvm-smc` 같은 컴포넌트가 없으므로, master판 커밋은 그 파일을 고치지 않는다. master판을 쓰면 API 변경의 후속 수정이 조용히 빠진다.

394커밋 전수 대조로 이런 커밋 2건을 찾았고, 둘 다 `pkvm_smc`를 깨뜨렸다.

| 커밋 | master판이 놓친 파일 | 증상 |
|---|---|---|
| `Remove token from pKVM module registration path` | `drivers/misc/pkvm-smc/pkvm-smc.c` | `pkvm_load_el2_module()` 인자 수 불일치 |
| `Automate pKVM module event registration` | `drivers/misc/pkvm-smc/pkvm/pkvm-smc.c` | 제거된 `register_hyp_event_ids()` 호출 |

8.2절 5단계의 "master에 있는 것은 일괄 추출" 절차를 쓸 때는 **이 대조를 반드시 거쳐야 한다.** 재현 방법은 제목을 정규화해 양쪽 커밋을 짝지은 뒤 `git show --name-only`로 파일 집합을 비교하는 것이다.

#### EL2 모듈 검증

`pkvm_smc`는 pKVM **EL2 벤더 모듈**이다. 호스트가 TrustZone으로 보내는 SMC를 하이퍼바이저 단에서 거른다. 호스트 측이 `pkvm_load_el2_module()`로 EL2에 코드를 적재하고, 실제 판정은 EL2에서 이뤄진다. Kconfig가 스스로 템플릿이라고 밝히며 `depends on ... && m`이라 모듈로만 빌드된다.

`CONFIG_PKVM_SMC_FILTER=m`으로 빌드해 `.ko` 생성까지 확인했다. 모듈에 `.hyp.text`, `.hyp.bss`, `.hyp.event_ids` 섹션과 `__kvm_nvhe_filter_smc`, `__kvm_nvhe_pkvm_smc_filter_hyp_init` 심볼이 들어 있다. **EL2 모듈 적재 경로가 실제로 컴파일된다는 뜻이다.** defconfig는 이 옵션을 켜지 않으므로 명시적으로 켜야 검증된다.

이 영역은 8.4절이 upstream 수용 가능성 낮음으로 분류한 EL2 모듈 클러스터에 속한다. 빌드 대상으로는 유효하나 투고 시에는 별도 취급해야 한다.

#### 빌드 수정 5건

트리에 별도 커밋으로 남겼다.

| 커밋 | 내용 | 투고 시 처리 |
|---|---|---|
| `ac1d1ef38dc3` BUILD-FIX | ACK의 `include/linux/android_kabi.h` 추가 | 이 헤더 대신 `ANDROID_KABI_RESERVE` 사용부를 제거해야 한다 |
| `fc2aca86ce81` Revert | `iommu: Add vendor data for custom iommu fault handler` 되돌림 | 애초에 대상에서 빼야 한다 |
| `2e948c4a015d` BUILD-FIX | `is_dma_buf_file()`에 외부 링키지 부여 | ACK 커밋이 헤더 선언만 바꾸고 정의는 `static inline` 그대로다. v6.18에서는 `static declaration follows non-static declaration` 오류가 난다 |
| `c386e32488de` BUILD-FIX | `pkvm_smc`를 tokenless `pkvm_load_el2_module()`에 맞춤 | mainline판 커밋을 쓰면 불필요하다 |
| `281c1d3f36d5` BUILD-FIX | `pkvm_smc` EL2 측의 `register_hyp_event_ids()` 호출 제거 | 위와 같다 |

뒤의 두 건은 master판 커밋을 쓴 데서 온 것이다. mainline판을 적용하면 발생하지 않는다.

#### 제외한 14건

| 구분 | 수 | 사유 |
|---|---:|---|
| tracing `FROMLIST` | 8 | master의 ANDROID 판이 상위 버전이다. 중복 |
| 중복·빈 커밋 | 6 | 이미 반영되어 cherry-pick 시 빈 커밋이 되었다 |

### 9.3 리베이스 충돌 4건 (1단계)

394커밋 중 충돌은 4건뿐이었다. 모두 upstream v6.18이 rc2 이후 추가한 보안 강화 코드와 pKVM 패치가 같은 줄에서 겹친 경우다.

| 커밋 | 파일 | 충돌 내용 | 해소 |
|---|---|---|---|
| `fcb227c407f4` Restrict host-to-hyp MMIO donations | `hyp/nvhe/mem_protect.c` | upstream `pfn_range_is_valid` 대 락 위치 이동 | 검사 유지, 락은 호출자로 이동 |
| `a42c32d5ab8c` mem range overflow checks | `hyp/nvhe/mem_protect.c` 4곳 | `pfn_range_is_valid` 대 `check_shl_overflow` | 둘 다 유지. 후자는 `size` 대입도 겸하므로 필수 |
| `f78693fbb6c4` Support multiple FF-A partition buffers | `hyp/nvhe/ffa.c` | 지역 변수 선언 겹침 | 둘 다 선언 |
| `8c177202398a` Handle guest FF-A share/lend/reclaim | `hyp/nvhe/ffa.c` | upstream `check_add_overflow` 대 오류 처리 방식 변경 | 검사 유지, 새 오류 스타일(`ffa_to_smccc_error`) 적용 |

네 건 모두 **upstream 쪽 검사를 살리는 방향**으로 해소했다. 기능 손실은 없다.

2단계 cherry-pick에서는 충돌이 훨씬 많았다. 주요 유형 셋이다.

- upstream v6.18이 rc2 이후 추가한 보안 검사(`pfn_range_is_valid`, `check_shl_overflow`, `check_add_overflow`)와 pKVM 패치의 충돌
- master 계열과 mainline 계열의 구현 분기. `pkvm_init_features_from_host`가 대표적이다. master는 `pvm_supported_vcpu_features()` 마스크를, mainline은 `allowed_features` 비트맵을 쓴다
- 헤더 선언 중복. `HYP_ALLOC_MGT_HEAP_ID`가 `#define`에서 `enum`으로 바뀌는데, 구식 `#define`이 남아 있으면 열거자를 치환해 컴파일이 깨진다

### 9.4 절차

```bash
# 트리 준비
git clone --filter=blob:none --single-branch \
    -b for-android/pkvm-mainline-6.18 \
    https://android-kvm.googlesource.com/linux
# v6.18 태그가 원격에 없으므로 릴리스 커밋을 직접 태그
git tag v6.18     7d0a66e4bb9081d75c82ec4957c50034cb0ea449
git tag v6.18-rc2 211ddde0823f1442e4ad052a2f30f050145ccada
git switch -c pkvm-6.18-build v6.18

# 394커밋 리베이스
git rebase --onto v6.18 v6.18-rc2 origin/for-android/pkvm-master-6.18

# 설정과 빌드 (clang)
make ARCH=arm64 LLVM=1 defconfig
./scripts/config -e KVM -e PKVM_DEBUG -e PKVM_DISABLE_STAGE2_ON_PANIC -e PKVM_STACKTRACE
make ARCH=arm64 LLVM=1 olddefconfig
make ARCH=arm64 LLVM=1 -j"$(nproc)"

# 2단계: 나머지를 mainline 순서대로 cherry-pick
git switch -c pkvm-6.18-full pkvm-6.18-build
git cherry-pick -x $(cat pick-list.txt)

# gcc 검증은 out-of-tree 로 분리 (사전에 make mrproper 필요)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=../obj-gcc defconfig
```

작업 시 주의할 점이다.

- `android-kvm` 저장소에는 `v6.18` 태그가 없다. 릴리스 커밋을 찾아 직접 태그해야 한다.
- `PKVM_DEBUG`를 켜면 `PKVM_STRICT_CHECKS`, `PKVM_SELFTESTS`, `PKVM_DUMP_TRACE_ON_PANIC`이 함께 켜진다.
- ACK 히스토리에는 **부모가 하나인데 제목이 `Merge ...`인 커밋**이 있다. `--no-merges`로 걸러지지 않으며, 그중 하나는 7만 파일을 건드린다. 제목으로도 걸러야 한다.
- 충돌 판정에 `git diff --diff-filter=U`를 쓰면 안 된다. 파일 추가·삭제 충돌(`DU`, `AA`)을 놓친다. `git status --porcelain`의 상태 코드를 봐야 한다.
- 같은 트리에서 `make`를 두 개 이상 돌리면 `fixdep` 오류로 빌드가 깨진다. 소스 오류로 오인하기 쉽다.
- master판 커밋을 쓸 때는 mainline판과 변경 파일을 대조해야 한다. 9.2절 참조.
- EL2 벤더 모듈(`PKVM_SMC_FILTER`, `PKVM_IOMMU_TEMPLATE`)은 `depends on ... && m`이라 defconfig가 켜지 않는다. `-m`으로 명시해야 그 경로가 컴파일된다.

### 9.5 검증되지 않은 것

- **동작 검증은 하지 않았다.** 빌드 성공까지만 확인했다. 부팅과 pVM 생성은 미검증이다.
- **빌드 수정 5건은 upstream 투고용이 아니다.** 9.2절 표의 "투고 시 처리"를 따라야 한다.
- **EL2 모듈은 컴파일까지만 확인했다.** `pkvm_smc.ko`가 생성되고 `.hyp.text` 섹션을 갖는 것은 확인했으나, 실제 적재와 SMC 필터링 동작은 미검증이다.
- 8.1절 확정 집합(658)과 이번 빌드 집합은 다르다. 9.2절 참조.

---

## 10. 참고 자료

- [android-kvm/linux refs (전체 브랜치·태그 목록)](https://android-kvm.googlesource.com/linux/+refs)
- [for-android/pkvm-mainline-7.1](https://android-kvm.googlesource.com/linux/+/refs/heads/for-android/pkvm-mainline-7.1)
- [kernel/common refs (ACK 브랜치 목록)](https://android.googlesource.com/kernel/common/+refs)
- [KVM: arm64: Add support for protected guest memory with pKVM (LWN)](https://lwn.net/Articles/1053007/)
- [KVM: Restricted mapping of guest_memfd at the host and pKVM/arm64 support (LWN)](https://lwn.net/Articles/984255/)
- [Protected KVM (pKVM) — Linux Kernel documentation](https://www.kernel.org/doc/html/next/virt/kvm/arm/pkvm.html)
- [AVF architecture (AOSP)](https://source.android.com/docs/core/virtualization/architecture)
- [Implement a pKVM vendor module (AOSP)](https://source.android.com/docs/core/virtualization/pkvm-modules)
- [kernel.org](https://www.kernel.org/)
- [kernel.org Releases (LTS EOL 표)](https://www.kernel.org/category/releases.html)
- [arm64: Drop support for CMDLINE_EXTEND (cae118b6acc3)](https://github.com/torvalds/linux/commit/cae118b6acc309539b33339e846cbb19187c164c)
- [ANDROID: Support CONFIG_CMDLINE_EXTEND (common-patches)](https://android.googlesource.com/kernel/common-patches/+/18dcf7a0b55ecc7e289cee22751367969b8dafcb/android-mainline/ANDROID-Support-CONFIG_CMDLINE_EXTEND.patch)
- [CMDLINE_PREPEND/APPEND 제안 (Daniel Walker, 2019)](https://lore.kernel.org/lkml/20190319232448.45964-2-danielwa@cisco.com/)
- [Linux 6.18 LTS / 6.12 LTS / 6.6 LTS Support Periods Extended (Phoronix, 2026-02-25)](https://www.phoronix.com/news/Linux-6.18-LTS-6.12-6.6-Extend)
- [Linux kernel version history (Wikipedia)](https://en.wikipedia.org/wiki/Linux_kernel_version_history)
- [Linux Kernel 7.0 Reaches End of Life (9to5Linux)](https://9to5linux.com/linux-kernel-7-0-reaches-end-of-life-its-time-to-upgrade-to-linux-kernel-7-1)
- [CIP is now supporting five SLTS kernels (Civil Infrastructure Platform)](https://cip-project.org/blog/2025/05/26/cip-is-now-supporting-five-slts-kernels)
