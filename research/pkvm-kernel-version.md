# Android Common Kernel pKVM 패치의 베이스 커널 버전 조사

- 조사일: 2026-08-06
- 목적: Android AVF가 사용하는 Android Common Kernel(ACK)의 pKVM 패치를 upstream Linux kernel에 머지하기 위해, 해당 패치들이 어떤 Linux 버전을 베이스로 하고 있는지 확인
- 조사 방법: `android.googlesource.com/kernel/common` 및 `android-kvm.googlesource.com/linux` 저장소의 브랜치/태그 목록과 각 브랜치의 `Makefile` 버전 변수 직접 확인

---

## 1. 결론 요약

ACK의 pKVM 패치는 **ACK 브랜치별 LTS 버전**을 베이스로 한다. 그러나 upstream 머지 작업의 소스로 사용해야 할 것은 ACK가 아니라, **`android-kvm.googlesource.com/linux`의 mainline 리베이스 브랜치**다.

- 현재 최신 통합 브랜치: `for-android/pkvm-mainline-7.1` (베이스 = mainline v7.1.0)
- ACK(`kernel/common`)는 pKVM 개발의 원본 트리가 아니라 **하류(downstream) 배포처**다.

---

## 2. pKVM 개발 트리 구조

pKVM의 원본 개발은 `android-kvm.googlesource.com/linux`에서 이루어지며, 세 갈래로 관리된다.

| 브랜치 계열 | 용도 | 베이스 |
|---|---|---|
| `for-upstream/pkvm-*` | LKML 투고용 토픽 시리즈 (core, modules, smmu-v3, tracing, pviommu, dev-assign, sme, kcov 등 약 25개) | 투고 당시 mainline |
| `for-android/pkvm-mainline-<VER>` | 전체 pKVM 스택을 mainline 릴리스 위에 리베이스한 통합 브랜치 | mainline v`<VER>` |
| `for-android<NN>/pkvm-*` | 특정 ACK 릴리스를 타깃으로 한 백포트 | 해당 ACK 포크 지점 |

### 커밋 태그로 본 출처 구분

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
| 17 | `android17-6.18` | **6.18.32** | `for-android/pkvm-mainline-6.18`, `for-android/pkvm-master-6.18` | **v6.18.0** |
| (개발 최신) | — | — | **`for-android/pkvm-mainline-7.1`** | **v7.1.0** (tip: 2026-07-31) |

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

## 4. 머지 전략 권고

### 4.1 타깃 커널 버전별 소스 선택

| 머지 타깃 | 사용할 브랜치 | 근거 |
|---|---|---|
| 최신 mainline (7.1 / 7.2) | `for-android/pkvm-mainline-7.1` | 이미 v7.1.0 위에 리베이스 완료. ACK 역포팅 대비 충돌 최소 |
| LTS 6.18 | `for-android/pkvm-mainline-6.18` | v6.18.0 베이스 |
| LTS 6.12 | `for-android16/pkvm-integration` | v6.12.0-rc2 베이스 |
| LTS 6.6 | `pkvm-integration-6.6` | v6.6 베이스 |

**ACK 브랜치(`kernel/common`)에서 직접 패치를 추출하는 것은 권장하지 않는다.** ACK에는 pKVM 외의 대량의 Android 전용 패치가 뒤섞여 있어 pKVM 패치만 분리하기 어렵고, LTS 백포트가 누적되어 mainline과의 diff가 불필요하게 커진다.

### 4.2 기능 단위 분할 머지

`pkvm-7.1-*` 태그 약 40개가 토픽별 스냅샷으로 제공되며, 스택 순서대로 태그가 찍혀 있어 단계별 머지 계획에 그대로 활용할 수 있다.

주요 태그 (스택 하단 → 상단 경향):

```
pkvm-7.1-base
pkvm-7.1-pvm-core
pkvm-7.1-hypmem          / pkvm-7.1-hypexport
pkvm-7.1-modules-core    / pkvm-7.1-modules-perms
pkvm-7.1-modearly        / pkvm-7.1-modlock / pkvm-7.1-modprot
pkvm-7.1-psci-memprotect
pkvm-7.1-mem-relinquish
pkvm-7.1-mmioguard       / pkvm-7.1-mmio-autoenroll
pkvm-7.1-ffa-foundation  / pkvm-7.1-ffa-blockb / pkvm-7.1-ffa-backhalf
pkvm-7.1-sve / pkvm-7.1-sve-donate / pkvm-7.1-sme
pkvm-7.1-pvmfw
pkvm-7.1-cma / pkvm-7.1-pinpage / pkvm-7.1-buddyrace / pkvm-7.1-coalesce
pkvm-7.1-tlbi / pkvm-7.1-fgt / pkvm-7.1-rwlock / pkvm-7.1-getleaf
pkvm-7.1-smchandlers / pkvm-7.1-smctrng
pkvm-7.1-modtracing-v1 / pkvm-7.1-mondebug
pkvm-7.1-hyp-req
pkvm-7.1-audit-fixes / pkvm-7.1-sidefixes
pkvm-7.1-thp-infra / pkvm-7.1-gki
pkvm-7.1-spine-complete / pkvm-7.1-postsnap
```

---

## 5. Upstream 반영 현황

### 5.1 이미 mainline에 있는 부분

pKVM 호스트 측 기반(nVHE protected mode, host stage-2 격리)은 **v5.13 ~ v5.16 시기에 mainline 진입 완료**. `Documentation/virt/kvm/arm/pkvm.rst`가 mainline에 존재한다.

### 5.2 아직 out-of-tree인 부분

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

## 6. 후속 작업 제안

1. `android-kvm/linux` clone 후 `for-android/pkvm-mainline-7.1`과 `v7.1` 사이 커밋 수 / 파일별 diff 규모 실측
2. `ANDROID:` 접두사 커밋만 필터링하여 실제 머지 대상 목록 확정
3. 타깃 커널 버전 확정 후 토픽 태그 단위 머지 순서 수립

```bash
# 실측 명령 예시
git clone https://android-kvm.googlesource.com/linux pkvm-linux
cd pkvm-linux
git fetch origin for-android/pkvm-mainline-7.1
git log --oneline v7.1..FETCH_HEAD | wc -l
git log --oneline v7.1..FETCH_HEAD --grep='^ANDROID:' | wc -l
git diff --stat v7.1..FETCH_HEAD -- arch/arm64/kvm
```

---

## 7. 참고 자료

- [android-kvm/linux refs (전체 브랜치·태그 목록)](https://android-kvm.googlesource.com/linux/+refs)
- [for-android/pkvm-mainline-7.1](https://android-kvm.googlesource.com/linux/+/refs/heads/for-android/pkvm-mainline-7.1)
- [kernel/common refs (ACK 브랜치 목록)](https://android.googlesource.com/kernel/common/+refs)
- [KVM: arm64: Add support for protected guest memory with pKVM (LWN)](https://lwn.net/Articles/1053007/)
- [KVM: Restricted mapping of guest_memfd at the host and pKVM/arm64 support (LWN)](https://lwn.net/Articles/984255/)
- [Protected KVM (pKVM) — Linux Kernel documentation](https://www.kernel.org/doc/html/next/virt/kvm/arm/pkvm.html)
- [AVF architecture (AOSP)](https://source.android.com/docs/core/virtualization/architecture)
- [Implement a pKVM vendor module (AOSP)](https://source.android.com/docs/core/virtualization/pkvm-modules)
- [kernel.org](https://www.kernel.org/)
