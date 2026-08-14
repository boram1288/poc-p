# `arch/arm64` 헤더·부팅 계층 경계 판정

- 측정일: 2026-08-07
- 저장소: `work/src/pkvm-linux`
- 기준: `v6.18`(`7d0a66e4`) → `origin/for-android/pkvm-mainline-6.18`(`b3b90af8`)
- 대상: [커널 버전 및 패치 소스 조사](pkvm-kernel-version.md)의 arm64 경계 판정 근거

## 1. 결론 요약

- `arch/arm64` (헤더·부팅) 영역은 **2,276 추가 / 398 삭제 = 2,674 라인, 고유 파일 33개**다. 문서 8.1절 수치와 **정확히 일치**한다.
- 33파일 중 `unrelated` 판정은 **0개**다. 전부 pKVM 사유로 변경되었다.
- 판정 분포: `pkvm-only` 5, `shared`(KVM 소유) 11, `shared`(arm64 코어) 17.
- T5 채택은 **3건**이다. 문서 수치가 맞다.
- 이 영역의 파일·라인 수와 T5 채택 3건은 재현됐다. 전체 집합의 초기 673 수치는 이후
  T2/T3 재검증으로 658로 정리됐으므로 현재 기준으로 사용하지 않는다.

## 2. T5 선별 (`e5.txt` 151건)

### 2.1 1차 배제 — ACK 전용 파일만 건드리는 커밋

CONTEXT.md의 ACK 전용 규칙을 적용했다.

| 단계 | 건수 |
|---|---|
| T5 배타 할당 원시 (`e5.txt`) | 151 |
| ACK 전용 파일만 변경 → 배제 | **132** |
| 코드 포함 → 다음 단계 | **19** |

배제 132건이 건드린 파일 유형이다. 코드 파일은 하나도 없다.

| 파일 유형 | 등장 횟수 |
|---|---|
| `arch/arm64/configs/*` | 134 |
| `arch/x86/configs/*` | 82 |
| `BUILD.bazel` | 16 |
| `arch/riscv/configs/*` | 11 |
| `build.config*` | 10 |
| `*.bzl` | 4 |
| `arch/arm/configs/*` | 2 |
| `tools/testing/kunit/android/*`, `tools/testing/android/bin/*` | 4 |

문서는 T5 원시를 101, ACK 전용을 87로 기록했다. 이번 실측은 151/132다. 원시 집합 정의가 다르다(`t5.txt` 167 → 상위 우선 배타 할당 후 `e5.txt` 151). **채택 결과는 동일하므로 673에는 영향이 없다.**

### 2.2 2차 선별 — 코드 커밋 19건 개별 판정

커밋 본문과 변경 파일을 모두 확인했다.

**채택 3건**

| SHA | 제목 | 변경 파일 | 근거 |
|---|---|---|---|
| `54a8e7e137b0` | ANDROID: KVM: arm64: Fix pKVM module symbols import | `arch/arm64/kernel/module.c` | `pkvm_sym::name`이 NULL 종단이 아니어서 `strcpy` → `strscpy` 교체. pKVM EL2 모듈 심볼 임포트 버그 수정 |
| `8765527b3df1` | ANDROID: KVM: arm64: add CONFIG_KVM guard | `arch/arm64/kernel/module-plts.c` | `pkvm_el2_mod_frob_sections` 호출을 `IS_ENABLED(CONFIG_KVM)`으로 감쌈. `CONFIG_KVM=n` 링크 오류 수정 |
| `d833601fdcb3` | ANDROID: KVM: arm64: Export kvm_nvhe alias of alt_cb_patch_nops | `arch/arm64/include/asm/hyp_image.h`, `arch/arm64/kernel/alternative.c` | `EXPORT_KVM_NVHE_ALT_CB` 매크로 신설. pKVM EL2 모듈이 `alternative_has_cap_likely()` 경로를 쓸 때 modpost 미해결 심볼 방지 |

**배제 16건**

`arch/arm64`를 건드리지만 pKVM과 무관한 6건이다.

| SHA | 제목 | 배제 근거 (커밋 본문) |
|---|---|---|
| `0413ebe13428` | ANDROID: arm64: Export system_32bit_el0_cpumask symbol | "Qualcomm's vendor modules"의 비대칭 32/64비트 지원용 |
| `1505ec475522` | ANDROID: arm64: stacktrace: Export arch_stack_walk symbol | vendor module의 스택 덤프 커스터마이즈용 |
| `76bbef6aa934` | ANDROID: arm64: vdso32: support user-supplied flags | `KCPPFLAGS_COMPAT` 도입. 빌드 재현성(`-ffile-prefix-map`)용 |
| `99ad7464a2ac` | ANDROID: arm64: Forcefully disable SME at runtime | KMI freeze 전 `CONFIG_ARM64_SME` 무력화 |
| `e8ac88bbf71b` | ANDROID: vendor_hooks: FPSIMD save/restore by using vendor_hooks | 커널 태스크 FPSIMD용 vendor hook |
| `e5d7c84f8167` | ANDROID: Reintroduce support for CONFIG_CMDLINE_EXTEND | 아래 보류 항목 참조 |

`arch/arm64`를 전혀 건드리지 않는 10건이다. 전부 pKVM 무관이다.

`094f5702db86`(debug_kinfo 이동), `957b40b3b769`(usb gadget uevent), `bdf5a5a3ec68`/`f3583fb7b6bc`(memhealth 드라이버 추가·삭제), `bf309bfecfed`(debug_kinfo Kconfig), `d23db69132ac`(usb gadget revert), `da8143d0fedb`(dm-bow 삭제), `dccd5d2cf7e2`(GKI_HIDDEN_MEDIA_CONFIGS), `e260bb27a67b`(UAPI_HEADER_TEST), `eb5e5c1f626e`(Tegra SoC Kconfig)

**보류 1건 — `e5d7c84f8167` (CONFIG_CMDLINE_EXTEND)**

문서는 이를 단순 배제로 기록했다. 실측 결과 추가 정보가 있다.

- `Bug: 458241298`이다. 채택 3건 중 `8765527b3df1`, `d833601fdcb3`과 **동일한 버그 ID**다. 이 버그는 pKVM 6.18 mainline 작업 트래커로 보인다.
- 서명자가 Keir Fraser, Fuad Tabba다. 둘 다 pKVM 개발자다.
- 본문이 crosvm의 device-tree `bootargs` 전달을 명시한다. AVF 게스트 부팅 요건이다.

그럼에도 배제 유지가 타당하다. upstream이 `arm64: Drop support for CMDLINE_EXTEND`로 의도적으로 제거한 기능이다. 재투고는 결정을 되돌리는 일이다. **다만 "pKVM 무관"이 아니라 "pKVM 프로젝트 소속이나 upstream 정책 충돌로 배제"로 사유를 바꿔 기록해야 한다.**

## 3. 33파일 재현

### 3.1 재현 방법

`arch/arm64/**` 중 `arch/arm64/kvm/**`과 `arch/arm64/configs/**`를 뺀 경로다.

- T1(`e1.txt`, 561건) 중 이 경로를 건드리는 커밋: **221건**, 고유 파일 **31개**
- T5 채택 3건이 추가하는 고유 파일: `asm/hyp_image.h`, `kernel/alternative.c` (`module.c`·`module-plts.c`는 T1과 중복)
- T2(`e2.txt`)는 이 경로에 기여가 없다
- T4(`e4.txt`)도 기여가 없다
- T3(`e3.txt`)에서 `a1dfc257ae63`이 `arch/arm64/mm/init.c`를 건드린다

**31 + 2 = 33파일.** 문서 수치와 일치한다.

### 3.2 라인 수 검증

| 집합 | 추가 | 삭제 | 합계 | 파일 |
|---|---|---|---|---|
| T1 561 + T5 채택 3 (문서의 673 집합) | **2276** | **398** | **2674** | **33** |
| 위 + T3 `a1dfc257ae63` | 2299 | 401 | 2700 | 33 |
| 경로 필터로 rename 탐지가 깨진 원시 측정 | 2761 | 401 | 3162 | 33 |

문서의 `2,674 / 33`이 **첫 행과 정확히 일치**한다.

주의할 함정 두 가지를 기록한다.

1. `52820b3c1e83`(gen-hyprel 이동)은 `arch/arm64/kvm/hyp/nvhe/gen-hyprel.c` → `arch/arm64/tools/gen-hyprel.c` rename이다. 전체 numstat에서는 rename으로 탐지되어 `0/0`이다. 경로 pathspec으로 `arch/arm64/kvm`을 제외하면 원본이 안 보여 **+462로 잘못 집계**된다.
2. T3 커밋 `a1dfc257ae63`(`arch/arm64/mm/init.c` +23/-3)은 문서의 673 집합에 **포함되지 않았다**. 삭제 라인 398이 정확히 맞아떨어지는 것으로 확인된다.

### 3.3 파일별 판정표

`판정` 열의 의미다.

- `pkvm-only`: upstream v6.18에 존재하지 않는 신규 파일. pKVM 없이는 존재 이유가 없다.
- `shared/KVM`: upstream에 있으나 KVM/arm64 서브시스템 소유 파일. 리뷰어가 KVM 메인테이너다.
- `shared/arm64`: upstream에 있는 arm64 코어 파일. 리뷰어가 arm64 메인테이너다.

| # | 파일 | 라인 | 커밋 | v6.18 | 판정 | 변경 사유 (훅/심볼/가드) |
|---|---|---|---|---|---|---|
| 1 | `include/asm/kvm_pkvm_module.h` | 684 | 64 | 없음 | pkvm-only | pKVM EL2 모듈 ABI(`struct pkvm_module_ops`) 전체 |
| 2 | `include/asm/kvm_host.h` | 567 | 58 | 있음 | shared/KVM | pKVM 호스트측 상태·핸들 필드 추가 |
| 3 | `kernel/module.c` | 269 | 7 | 있음 | shared/arm64 | `#ifdef CONFIG_KVM` 블록. `module_init_hyp_imported_sym()`, `.hyp.*` 섹션 파싱 |
| 4 | `include/asm/kvm_pkvm.h` | 261 | 33 | 있음 | shared/KVM | pKVM 호스트-hyp 인터페이스 확장 |
| 5 | `include/asm/kvm_hypevents.h` | 174 | 15 | 없음 | pkvm-only | hyp 트레이스 이벤트 정의 |
| 6 | `include/asm/kvm_pgtable.h` | 144 | 15 | 있음 | shared/KVM | stage-2 페이지테이블 pKVM 확장 |
| 7 | `include/asm/kvm_asm.h` | 122 | 34 | 있음 | shared/KVM | `__KVM_HOST_SMCCC_FUNC_*` hypercall ID 추가 |
| 8 | `include/asm/kvm_mmu.h` | 94 | 9 | 있음 | shared/KVM | hyp VA 매핑 헬퍼 |
| 9 | `include/asm/kvm_emulate.h` | 74 | 4 | 있음 | shared/KVM | `enter_exception64()` 리팩터, ALLINT 트랩, vcpu sysreg 접근 hyp 노출 |
| 10 | `include/asm/module.h` | 52 | 8 | 있음 | shared/arm64 | `struct pkvm_el2_module`, `struct pkvm_el2_sym`를 `mod_arch_specific`에 추가 |
| 11 | `include/asm/module.lds.h` | 44 | 6 | 있음 | shared/arm64 | `#ifdef CONFIG_KVM` 가드된 `.hyp.text/.bss/.rodata/.data/.reloc` 섹션 |
| 12 | `mm/fault.c` | 22 | 1 | 있음 | shared/arm64 | `is_pkvm_stage2_abort()` 신설. `is_pkvm_initialized()` 런타임 가드. S1PTW 기반 SIGSEGV 주입 |
| 13 | `include/asm/kvm_arm.h` | 19 | 4 | 있음 | shared/KVM | `HCR_ATA`, `MPAM2_HOST_FLAGS`, pstate reset 값, fault IPA 헬퍼 |
| 14 | `include/asm/kvm_hyp.h` | 19 | 9 | 있음 | shared/KVM | hyp 전용 선언 추가 |
| 15 | `include/asm/assembler.h` | 15 | 1 | 있음 | shared/arm64 | `#if defined(__KVM_NVHE_HYPERVISOR__)` 가드로 `EXPORT_SYMBOL_GPL`을 `ASM_BUILD_BUG()`로 재정의. GPL 심볼이 EL2 모듈로 새는 것 방지 |
| 16 | `include/asm/kvm_hypevents_defs.h` | 15 | 1 | 없음 | pkvm-only | hyp 이벤트 매크로 정의 |
| 17 | `include/uapi/asm/kvm.h` | 14 | 2 | 있음 | shared/KVM | `KVM_CAP_ARM_PROTECTED_VM`, `..._FLAGS_SET_FFA` uapi |
| 18 | `include/asm/hyp_image.h` | 13 | 1 | 있음 | shared/KVM | `EXPORT_KVM_NVHE_ALT_CB(name)` 매크로. `__kvm_nvhe_` 별칭 export |
| 19 | `kernel/vmlinux.lds.S` | 13 | 3 | 있음 | shared/arm64 | `CONFIG_TRACING` 가드 안 `HYPERVISOR_EVENT_IDS`에 `__hyp_patchable_function_entries_*` 심볼 추가 |
| 20 | `include/asm/kvm_hyptrace.h` | 12 | 3 | 없음 | pkvm-only | hyp ring buffer 트레이스 헤더 |
| 21 | `kernel/image-vars.h` | 8 | 4 | 있음 | shared/KVM | `KVM_NVHE_ALIAS(__hyp_printk_fmts_start)` 등 nVHE 별칭 |
| 22 | `kernel/module-plts.c` | 6 | 2 | 있음 | shared/arm64 | `pkvm_el2_mod_frob_sections()` 호출 + `IS_ENABLED(CONFIG_KVM)` 가드 |
| 23 | `include/asm/memory.h` | 5 | 1 | 있음 | shared/arm64 | `#ifdef CONFIG_EXECMEM` 안에서 `module_direct_base`, `module_plt_base`를 extern 선언 |
| 24 | `Makefile` | 5 | 1 | 있음 | shared/arm64 | `ifeq ($(CONFIG_KVM),y)` 가드로 `archscripts`에서 gen-hyprel 빌드 |
| 25 | `include/asm/el2_setup.h` | 4 | 1 | 있음 | shared/arm64 | `MPAM2_HOST_FLAGS` 적용. `MPAMSM_EL1` 트랩 해제(EnMPAMSM 비트) |
| 26 | `include/asm/kvm_define_hypevents.h` | 4 | 2 | 없음 | pkvm-only | hyp 이벤트 정의 매크로 |
| 27 | `mm/init.c` | 4 | 1 | 있음 | shared/arm64 | `module_direct_base`/`module_plt_base`의 `static` 제거. pKVM 모듈 전용 hyp VA 공간 정렬용 |
| 28 | `tools/Makefile` | 4 | 1 | 있음 | shared/arm64 | gen-hyprel 빌드 규칙 이동 |
| 29 | `kernel/alternative.c` | 2 | 1 | 있음 | shared/arm64 | `EXPORT_KVM_NVHE_ALT_CB(alt_cb_patch_nops)` 추가 |
| 30 | `kernel/head.S` | 2 | 1 | 있음 | shared/arm64 | `init_el2_hcr HCR_HOST_NVHE_FLAGS` → `| HCR_ATA`. MTE 미지원·비활성 시 EL2 트랩 |
| 31 | `tools/.gitignore` | 2 | 1 | 없음 | shared/arm64 | gen-hyprel 이동 부산물 |
| 32 | `kernel/asm-offsets.c` | 1 | 1 | 있음 | shared/arm64 | `NVHE_INIT_HFGWTR_EL2` 오프셋. KVM nVHE 블록 안 |
| 33 | `tools/gen-hyprel.c` | 0 (rename) | 1 | 이동 | shared/arm64 | `kvm/hyp/nvhe/`에서 이동. 향후 hyp 모듈 빌드 재사용 목적 |

`unrelated` 판정은 없다. 33파일 전부 pKVM 사유로 변경되었다.

경계선에 있던 두 파일을 별도로 기록한다.

- `kernel/head.S`(#30)와 `include/asm/el2_setup.h`(#25)는 커밋 제목이 `ANDROID: arm64:`로 시작해 pKVM 무관으로 보인다. 실제로는 각각 `arch/arm64/kvm/arm.c`, `arch/arm64/kvm/hyp/include/hyp/switch.h`를 함께 건드리고, 본문이 "malicious host가 MTE로 게스트를 침해"·"host의 MPAMSM_EL1 트랩 해제"를 명시한다. **pKVM 호스트 격리 목적이 확인되므로 유지가 맞다.** 문서 판단과 일치한다.

## 4. `shared` 파일 upstream 반려 위험

`shared/KVM` 11개는 KVM/arm64 메인테이너(Marc Zyngier, Oliver Upton) 관할이다. pKVM 기능 자체의 수용 여부에 종속되며, arm64 코어 메인테이너와의 마찰 요인은 아니다. 여기서는 `shared/arm64` 17개를 평가한다.

### 4.1 위험 높음 — pKVM EL2 모듈 로딩 클러스터 (11파일, 406라인)

`kernel/module.c`(269), `include/asm/module.h`(52), `include/asm/module.lds.h`(44), `include/asm/assembler.h`(15), `kernel/module-plts.c`(6), `include/asm/memory.h`(5), `Makefile`(5), `mm/init.c`(4), `tools/Makefile`(4), `tools/.gitignore`(2), `tools/gen-hyprel.c`(rename)

- `shared/arm64` 17파일 합계는 450라인이다. 이 클러스터가 11파일 406라인으로 **90%**를 차지한다.
- 빌드 영향은 이미 좁혀져 있다. `module.c`는 `#ifdef CONFIG_KVM`, `module.lds.h`는 `#ifdef CONFIG_KVM`, `module-plts.c`는 `IS_ENABLED(CONFIG_KVM)`, `Makefile`은 `ifeq ($(CONFIG_KVM),y)`, `assembler.h`는 `__KVM_NVHE_HYPERVISOR__` 가드다.
- **문제는 가드가 아니라 설계 방향이다.** `assembler.h` 커밋(`f92ff4fd5ae8`) 본문이 "said module is proprietary, and must NOT be allowed to use GPL symbols"라고 명시한다. EL2 특권 레벨에 프로프라이어터리 벤더 바이너리를 올리는 구조를 arm64/KVM 메인테이너가 수용할 가능성은 낮다.
- `EXPORT_SYMBOL_GPL`을 `ASM_BUILD_BUG()`로 재정의하는 방식은 그 자체로도 반려 사유가 된다. GPL 준수 수단으로 매크로를 무력화하는 것은 라이선스 논쟁을 코드로 끌어들인다.
- `memory.h` + `mm/init.c`는 `module_direct_base`/`module_plt_base`의 `static`을 제거해 arm64 코어 심볼 가시성을 넓힌다. **접근자 함수(`arm64_module_alloc_base()` 형태)로 좁히면 마찰이 줄어든다.** 다만 상위 기능이 반려되면 무의미하다.
- 완화책: 이 클러스터를 별도 시리즈로 분리해 마지막에 투고한다. 앞선 시리즈가 이것 때문에 막히지 않게 한다.

### 4.2 위험 중간 (2파일)

- `kernel/vmlinux.lds.S` (13라인): `CONFIG_TRACING` 가드 안이지만 hyp ftrace/patchable-function-entries 섹션을 링커 스크립트에 추가한다. hyp 트레이싱 기능 전체의 수용 여부에 종속된다. 링커 스크립트 자체는 arm64 메인테이너가 보수적으로 다루는 파일이다.
- `mm/fault.c` (22라인): `is_pkvm_initialized()` 런타임 가드가 있고 진단 품질을 개선한다(`"access to hypervisor-protected memory"`). 논리적으로 방어 가능하다. 다만 `is_spurious_el1_translation_fault()`와 `do_page_fault()` 두 핫패스에 조건을 추가하므로 성능·정확성 리뷰를 거친다.

### 4.3 위험 낮음 (4파일, 9라인)

- `kernel/head.S` (2라인, `HCR_ATA` 추가): pKVM 없이도 방어 논리가 성립한다. Will Deacon 본인이 유사 성격의 SME 무력화 패치를 작성한 이력이 있다. 수용 가능성이 높다.
- `include/asm/el2_setup.h` (4라인, `MPAM2_HOST_FLAGS`): 아키텍처 매뉴얼(DDI0487L.a D24.12.3) 근거가 본문에 있다. MPAM 관련은 James Morse 리뷰 대상이나 논쟁 여지가 작다.
- `kernel/asm-offsets.c` (1라인): 기존 KVM nVHE 블록 안 한 줄이다. 무해하다.
- `kernel/alternative.c` (2라인): `EXPORT_KVM_NVHE_ALT_CB(alt_cb_patch_nops)` 한 줄이다. 단독으로는 무해하다.

`kernel/alternative.c`와 짝을 이루는 `include/asm/hyp_image.h`(13라인)는 `shared/KVM`으로 분류했다. 매크로 자체는 `#else` 분기에서 no-op이라 위험이 낮으나, **존재 이유가 EL2 모듈 로딩이므로 4.1 클러스터가 반려되면 함께 의미를 잃는다.**

### 4.4 요약

`shared/arm64` 17파일 450라인 기준이다.

| 위험 | 파일 수 | 라인 | 비고 |
|---|---|---|---|
| 높음 (EL2 모듈 로딩) | 11 | 406 | 설계 방향 자체가 쟁점. 별도 시리즈로 격리 권고 |
| 중간 | 2 | 35 | 상위 기능 수용 여부에 종속 |
| 낮음 | 4 | 9 | 단독 투고 가능 |

`shared/arm64` 17파일 중 **11파일이 EL2 모듈 로딩 하나에 묶여 있다.** 이 기능의 upstream 수용 여부가 arm64 경계 마찰의 거의 전부를 결정한다.

## 5. 남은 불확실성

1. **T3 `a1dfc257ae63`의 위치.** 이 커밋은 `arch/arm64/mm/init.c`를 +23/-3 건드리지만 문서의 673 집합에 없다. T3 채택 36건의 확정 목록이 없어 의도적 배제인지 집계 누락인지 판별하지 못했다. 라인 수가 정확히 맞아떨어지는 것으로 보아 673 집합에서 빠진 것은 확실하다.
2. **`shared/KVM` 11파일의 개별 diff 전수 확인은 하지 않았다.** 커밋 제목·본문과 대표 diff로 판정했다. `kvm_host.h`(567라인, 58커밋), `kvm_pkvm.h`(261라인, 33커밋)는 변경 밀도가 높아 비pKVM 변경이 섞였을 가능성이 남는다. 다만 전부 T1 pKVM 커밋에서 왔고 KVM 서브시스템 소유 파일이므로 arm64 경계 판정에는 영향이 없다.
3. **T5 원시 집합 정의 차이.** 문서는 101, 실측은 151(`e5.txt`)이다. 채택 결과가 같아 673에는 영향이 없으나, 문서 표의 "원시 101"과 "ACK 전용 87"은 재현되지 않는다.
4. **`e5d7c84f8167`(CMDLINE_EXTEND)의 사유 분류.** 배제는 유지하되 "pKVM 무관"이 아니라 "upstream 정책 충돌"이 정확하다. AVF 게스트 부팅에는 필요하다.
