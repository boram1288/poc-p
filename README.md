# pKVM v6.18 로컬 빌드/테스트

Android Common Kernel(ACK)의 pKVM 패치를 upstream Linux **v6.18** 위에 올려 로컬에서
빌드·부팅하는 절차를 정리한다. 조사 배경과 근거는 [`research/pkvm-kernel-version.md`](research/pkvm-kernel-version.md)에 있다.
이 문서는 그 문서 8~9장의 실행 절차를 재현 가능한 형태로 요약한 것이다.

- 범위: 로컬 빌드/테스트만 한다. upstream 투고는 하지 않는다.
- 타깃 커널: LTS 6.18 (근거는 조사 문서 5장)
- 대상 트리: v6.18 + pKVM 721커밋 (IOMMU 스택·EL2 벤더 모듈 포함)

## 1. 산출물 경로 규칙

작업 산출물은 모두 `work/` 아래에 둔다. `work/`는 git 추적 대상이 아니다(`.gitignore`).
소스트리 하나를 공유하고, 빌드 산출물은 브랜치명 기반으로 분리한다.

| 경로 | 내용 |
|---|---|
| `work/pkvm-linux` | pKVM 소스트리 (android-kvm/linux 클론) |
| `work/pkvm-full-clang` | clang 빌드 산출물 (out-of-tree, `O=`) |
| `work/pkvm-full-gcc` | gcc 빌드 산출물 (out-of-tree, `O=`) |
| `work/pkvm-qemu` | QEMU 부팅 테스트 (initramfs, `run.sh`, 콘솔 로그) |
| `work/analysis` | 대상 커밋 집계·분류 산출물 |

브랜치별로 빌드를 나눌 때는 `work/pkvm-<브랜치suffix>` 규칙을 쓴다.
예: `pkvm-6.18-full` 브랜치 → `work/pkvm-full-clang`, `work/pkvm-full-gcc`.

## 2. 사전 준비

### 2.1 도구 체인

| 도구 | 이번 검증에 쓴 버전 | 비고 |
|---|---|---|
| clang | clang-18 (18.1.8) + ld.lld-18 | `clang` 기본값이 10일 수 있으니 `CC=clang-18` 명시 필수 |
| gcc 크로스 | aarch64-linux-gnu-gcc-9 (9.4.0) | gcc 13.2가 아니어도 이 구성은 빌드된다 (조사 문서 9.6절) |
| QEMU | qemu-system-aarch64 4.2.1 | `virt,virtualization=on`으로 게스트 EL2 노출 지원 |

빌드 의존성: `libelf-dev libssl-dev bison flex bc`.

### 2.2 소스트리 준비

```bash
cd work
git clone --filter=blob:none --single-branch \
    -b for-android/pkvm-mainline-6.18 \
    https://android-kvm.googlesource.com/linux pkvm-linux
cd pkvm-linux
```

`git clone` 옵션 설명:

| 옵션 | 의미 |
|---|---|
| `--filter=blob:none` | 파일 내용(blob)은 받지 않고 커밋·트리 메타데이터만 받는다. 필요한 파일은 접근 시 자동으로 받아온다. 커널 전체 히스토리를 받으면 수 GB이므로 초기 전송량을 크게 줄인다 |
| `--single-branch` | 지정 브랜치 하나만 받는다. 다른 브랜치의 원격 추적을 만들지 않아 더 가볍다 |
| `-b for-android/pkvm-mainline-6.18` | 클론 직후 체크아웃할 브랜치. 머지 대상 673커밋 전량을 가진 기준 트리다(조사 문서 6.1절) |
| 마지막 인자 `pkvm-linux` | 클론 대상 디렉토리 이름 |

```bash
# android-kvm 저장소에는 v6.18 태그가 없으므로 릴리스 커밋을 직접 태그
git tag v6.18     7d0a66e4bb9081d75c82ec4957c50034cb0ea449   # Linux 6.18 릴리스 커밋
git tag v6.18-rc2 211ddde0823f1442e4ad052a2f30f050145ccada   # pkvm-master-6.18 의 리베이스 베이스
```

`git tag <이름> <커밋SHA>`는 해당 커밋에 로컬 태그를 붙인다. 원격에 태그를 만들지 않고
로컬에서 베이스 커밋을 이름으로 참조하기 위한 것이다. 이후 `v6.18..` 같은 범위 지정에 쓴다.

대상 721커밋 트리(`pkvm-6.18-full`) 구성 절차는 조사 문서 8.2절·9.4절을 따른다.
핵심은 `pkvm-master-6.18`의 394커밋을 v6.18로 리베이스한 뒤, 나머지를
`pkvm-mainline-6.18`에서 시간순 cherry-pick 하고 빌드 수정 5건을 얹는 것이다.

## 3. 빌드

소스트리는 건드리지 않고 out-of-tree(`O=`)로만 빌드한다. clang·gcc 빌드는
`O=`가 다르므로 동시에 돌려도 `fixdep` 충돌이 없다.

### 3.0 주의 — 소스트리 오염 시 defconfig 실패 (2026-08-08 재현 시 확인)

out-of-tree(`O=`) 빌드라고 해도 소스트리 루트(`work/pkvm-linux`)에 이전 빌드 흔적
(`.config`, `include/config/`, `include/generated/`)이 남아 있으면 `make ... defconfig`가
아래처럼 **실패**한다.

    *** The source tree is not clean, please run 'make ARCH=arm64 mrproper'

원인: `O=`를 지정하지 않고 소스트리 루트에서 빌드를 돌린 적이 있거나, 오염된 상태로
트리를 받은 경우다. `mrproper`는 빌드 생성물만 제거하고 git 추적 파일은 건드리지
않는다(`.config`·`include/config/`·`include/generated/`는 `.gitignore` 대상이라 안전).

```bash
cd work/pkvm-linux
make ARCH=arm64 mrproper    # .config·include/config·include/generated 등 제거
git status                  # clean 확인 후 3.1로 진행
```

### 3.1 clang-18

```bash
cd work/pkvm-linux
O=$PWD/../pkvm-full-clang      # out-of-tree 산출물 디렉토리(절대경로). 소스트리를 더럽히지 않는다

make -C . O=$O ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 defconfig
```

`make` 공통 옵션 설명:

| 옵션 | 의미 |
|---|---|
| `-C .` | 현재 디렉토리(소스트리)를 make 대상으로 지정 |
| `O=$O` | 빌드 산출물을 이 디렉토리로 내보낸다(out-of-tree). 지정하면 소스트리에는 `.o`·`.config`가 생기지 않는다. clang·gcc 빌드가 `O=`만 다르면 동시 실행해도 충돌하지 않는다 |
| `ARCH=arm64` | 타깃 아키텍처. pKVM은 arm64 전용이다 |
| `LLVM=1` | binutils 대신 LLVM 툴체인(clang, ld.lld, llvm-objcopy 등)을 일괄 사용 |
| `CC=clang-18` | C 컴파일러를 clang-18로 명시. **시스템 `clang` 기본값이 10일 수 있어 반드시 버전을 못박는다.** 안 하면 구버전으로 빌드 실패 |
| `LD=ld.lld-18` | 링커를 lld-18로 명시 |
| `defconfig` | arm64 기본 config를 생성(`$O/.config`) |

```bash
# pKVM Kconfig 옵션 활성화 (조사 문서 9.2절). scripts/config 는 .config 를 직접 편집한다.
./scripts/config --file $O/.config \
    -e KVM -e PKVM_DEBUG -e PKVM_DISABLE_STAGE2_ON_PANIC -e PKVM_STACKTRACE \
    -e ARM_SMMU_V3 -e ARM_SMMU_V3_PKVM -e ARM_SMMU_V3_PKVM_PV \
    -e PKVM_PVIOMMU -e VFIO_PKVM_IOMMU
# EL2 벤더 모듈은 모듈로만 빌드된다 (Kconfig 가 depends on ... && m 이라 =y 불가)
./scripts/config --file $O/.config -m PKVM_SMC_FILTER -m PKVM_IOMMU_TEMPLATE

make -C . O=$O ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 olddefconfig   # 위 변경을 정규화(의존성 해소)
make -C . O=$O ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 -j"$(nproc)"   # 실제 빌드. -j 는 병렬 잡 수
```

`scripts/config` 옵션 설명:

| 옵션 | 의미 |
|---|---|
| `--file $O/.config` | 편집 대상 config 파일 지정. out-of-tree라 `$O/.config`를 명시한다 |
| `-e <심볼>` | 해당 CONFIG 심볼을 `y`(내장)로 설정(enable) |
| `-m <심볼>` | 해당 CONFIG 심볼을 `m`(모듈)로 설정 |

주요 심볼 의미: `KVM`(가상화 코어), `PKVM_DEBUG`·`PKVM_STACKTRACE`·`PKVM_DISABLE_STAGE2_ON_PANIC`(pKVM 디버그, `STACKTRACE`는 `DISABLE_STAGE2_ON_PANIC` 의존), `ARM_SMMU_V3*`·`PKVM_PVIOMMU`·`VFIO_PKVM_IOMMU`(IOMMU/SMMU 스택), `PKVM_SMC_FILTER`·`PKVM_IOMMU_TEMPLATE`(EL2 벤더 모듈).

`olddefconfig`는 `.config`를 읽어 새로 켠 옵션의 의존성·하위 옵션을 자동으로 채우고,
모순되는 설정을 정리한다. `-j"$(nproc)"`의 `nproc`는 코어 수를 반환하므로 전체 코어로 병렬 빌드한다.

> **주의 (2026-08-08 재현 시 확인) — 중단된 빌드 재개 시 fixdep 일시 오류:**
> `make -j` 를 도중에 Ctrl-C 로 중단했던 산출물 트리(`O=`)에서 재빌드를 시작하면
> `fixdep: error opening file: <경로>/*.o.d: No such file or directory` 로 실패하는
> 경우가 있다. 중단 시점에 `.o` 는 기록됐지만 `.d`(의존성 파일)가 안 쓰인 채 남는
> 불일치 상태 때문이다. 이때는 **한 번 더 `make` 를 재실행**하면 정상 진행된다.
> (단일 오브젝트 `make ... <드라이버>/<file>.o` 로 상태를 되돌린 뒤 전체 빌드를
> 다시 돌려도 된다.)

### 3.2 gcc 9.4.0

```bash
cd work/pkvm-linux
O=$PWD/../pkvm-full-gcc

make -C . O=$O ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-9 defconfig
# (여기서 3.1과 동일한 scripts/config 옵션을 적용한다)
make -C . O=$O ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-9 olddefconfig
make -C . O=$O ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-9 -j"$(nproc)"
```

clang 빌드와 달라지는 옵션:

| 옵션 | 의미 |
|---|---|
| `CROSS_COMPILE=aarch64-linux-gnu-` | 크로스 툴체인 접두사. 링커·objcopy 등 binutils가 `aarch64-linux-gnu-ld` 형태로 호출된다. x86 호스트에서 arm64 바이너리를 만들기 위함이다 |
| `CC=aarch64-linux-gnu-gcc-9` | C 컴파일러만 gcc-9로 명시. 접두사 기본 `gcc`가 아니라 버전을 못박아 9.4.0을 쓴다 |

`LLVM=1`·`LD=`는 지정하지 않는다. gcc 빌드는 `CROSS_COMPILE` 접두사의 binutils(ld 2.34)를 쓴다.

### 3.3 산출물 확인

빌드 성공 시 생성물이다(크기는 조사 문서 9.6절 표 참조).

- `$O/arch/arm64/boot/Image` — 부팅 커널 이미지
- `$O/vmlinux`
- `$O/arch/arm64/kvm/hyp/nvhe/kvm_nvhe.o` — EL2 하이퍼바이저 오브젝트
- `$O/drivers/misc/pkvm-smc/pkvm_smc.ko`, `$O/drivers/misc/pkvm-iommu-temp/pkvm_iommu_temp.ko`

pKVM 코드 링크 확인:

```bash
llvm-nm-18 $O/vmlinux | grep -c '__kvm_nvhe_'            # clang 빌드
aarch64-linux-gnu-nm  $O/vmlinux | grep -c '__kvm_nvhe_'  # gcc 빌드
```

- `nm <파일>`: 오브젝트/실행파일의 심볼 목록을 출력한다. 빌드한 컴파일러와 짝을 맞춘다(clang → `llvm-nm-18`, gcc → `aarch64-linux-gnu-nm`).
- `grep -c '__kvm_nvhe_'`: EL2 하이퍼바이저(nVHE) 심볼만 골라 **개수**를 센다(`-c`). 0보다 크면 pKVM 코드가 `vmlinux`에 링크된 것이다.

## 4. QEMU 부팅 테스트

호스트가 x86_64이므로 arm64는 KVM 가속 없이 **TCG 순수 에뮬레이션**으로 부팅한다(느림).
pKVM은 EL2에서 동작하므로 `-machine virt,virtualization=on`으로 게스트에 EL2를 노출하는 것이 핵심이다.

### 4.1 initramfs

`aarch64-linux-gnu-gcc`로 정적 busybox를 크로스 빌드해 최소 루트를 만든다.
`bin/sh -> busybox` 심링크가 반드시 있어야 한다(없으면 `No working init found` 패닉).

> **주의 (2026-08-08 재현 시 확인) — `bin/sh` 없이 만든 initramfs는 패닉:**
> 이전에 만든 `initramfs.cpio.gz`에 `bin/sh` 심링크가 빠져 있고 `initramfs-fixed.cpio.gz`에
> 들어 있었다. 실제로 `bin/sh` 없는 initramfs로 부팅하면
> `Kernel panic - not syncing: No working init found` 가 그대로 발생한다.
> (이때 pKVM 하이퍼바이저는 직전에 `Protected nVHE mode initialized successfully` 로
> 정상 초기화된 상태 — 문제는 initramfs 구성에만 있다.)
> 확인 방법:
> ```bash
> zcat initramfs.cpio.gz | cpio -t | grep -x 'bin/sh'   # 없으면 패닉
> ```

### 4.2 부팅 실행

준비물이 `work/pkvm-qemu/`에 있으면 `run.sh`로 실행한다. **`run.sh`가 사용하는
initramfs가 위 4.1의 `bin/sh`를 포함한 버전인지 확인한다**(현재 파일 기준으로는
`initramfs-fixed.cpio.gz`가 정상본).

```bash
cd work/pkvm-qemu
./run.sh   # console.log 에 콘솔 출력 저장
```

핵심 QEMU 인자:

```bash
qemu-system-aarch64 \
    -machine virt,virtualization=on,gic-version=3 \
    -cpu max -smp 2 -m 2G -nographic -no-reboot \
    -kernel .../work/pkvm-full-clang/arch/arm64/boot/Image \
    -initrd initramfs.cpio.gz \
    -append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init"
```

QEMU 인자 설명:

| 인자 | 의미 |
|---|---|
| `-machine virt,virtualization=on,gic-version=3` | `virt`는 반가상 arm64 머신. **`virtualization=on`이 게스트에 EL2(ARM 가상화 확장)를 노출한다 — pKVM 동작의 필수 조건.** `gic-version=3`은 인터럽트 컨트롤러를 GICv3로 지정(최신 커널에 적합) |
| `-cpu max` | QEMU가 에뮬레이트 가능한 최대 CPU 기능 집합(EL2 포함)을 노출 |
| `-smp 2` | vCPU 2개 |
| `-m 2G` | 게스트 메모리 2GB |
| `-nographic` | 그래픽 출력 없이 시리얼 콘솔을 현재 터미널에 연결 |
| `-no-reboot` | 게스트가 reboot을 요청하면 재부팅 대신 QEMU를 종료(무한 재부팅 방지) |
| `-kernel <Image>` | 부팅할 arm64 커널 이미지 |
| `-initrd <cpio.gz>` | 초기 램디스크(루트파일시스템) |
| `-append "<cmdline>"` | 커널 커맨드라인. 아래 표 참조 |

커널 커맨드라인(`-append`) 항목:

| 항목 | 의미 |
|---|---|
| `console=ttyAMA0` | 콘솔을 PL011 UART(`ttyAMA0`)로 지정. virt 머신의 시리얼 |
| `kvm-arm.mode=protected` | **pKVM protected 모드를 강제.** `nvhe`(일반 nVHE), 생략(기본) 등으로 바꿀 수 있다 |
| `earlycon` | 콘솔 드라이버 초기화 전 단계부터 로그 출력(초기 부팅 로그 확보) |
| `rdinit=/init` | initramfs의 `/init`를 첫 유저스페이스 프로세스로 실행 |

TCG(순수 소프트웨어 에뮬레이션)라 느리므로 timeout은 300초 이상을 권장한다.
스크립트에서는 `timeout --signal=KILL 300 qemu-system-aarch64 ...`로 감싸 hang을 방지한다
(`--signal=KILL`은 시간 초과 시 SIGKILL로 강제 종료, `300`은 초 단위 제한).

### 4.3 성공 판정

콘솔 로그(`work/pkvm-qemu/console-protected.log`)에서 다음을 확인한다.

- `CPU: All CPU(s) started at EL2` — 게스트 EL2 진입
- `CPU features: detected: Protected KVM`
- `kvm [1]: Protected nVHE mode initialized successfully` — **pKVM 하이퍼바이저 초기화 성공**
- `=== PKVM_QEMU_BOOT_OK ===` — 유저스페이스 도달

`Failed to init iommu driver -19`, `Found 0 assignable devices` 등은 QEMU virt 머신이
SMMU·할당 장치를 노출하지 않는 데서 오는 비치명적 경고다. pKVM 코어 초기화와 무관하다.

### 4.4 pVM 생성·실행 테스트

4.2의 부팅 위에서 한 걸음 더 나아가, 게스트 안에서 **protected VM(pVM)을 실제로 생성·실행**한다.
커널 트리의 pKVM selftest(`tools/testing/selftests/kvm/arm64/pkvm.c`)를 arm64 정적 바이너리로
크로스 빌드해 initramfs에 넣고, `kvm-arm.mode=protected`로 부팅한 게스트 안에서 실행한다.
산출물은 `work/pkvm-pvm/`에 있다(`run-pvm.sh`, `console-pvm-protected.log`).

#### 4.4.1 selftest 크로스 빌드

selftest 바이너리는 게스트 안에서 독립 실행돼야 하므로 **정적 링크**(`-static`)로 만든다.

```bash
cd work/pkvm-linux
PVM=$PWD/../pkvm-pvm         # pVM 테스트 작업 디렉토리

# (1) 커널 uapi 헤더를 out-of-tree로 설치 (KVM_CAP_ARM_EL2 등 신규 정의 확보)
make -C . O=$PVM/khdr-build ARCH=arm64 headers_install INSTALL_HDR_PATH=$PVM/usr

# (2) KVM selftest 크로스 빌드 (대상을 pkvm/hello_el2 로 좁힘)
make -C tools/testing/selftests/kvm \
     O=$PVM/kselftest-build \
     ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-9 \
     LDFLAGS=-static LDLIBS=-lpthread
```

크로스 빌드 옵션 설명:

| 옵션 | 의미 |
|---|---|
| `headers_install` | 커널의 uapi 헤더를 `INSTALL_HDR_PATH` 아래로 설치. selftest가 최신 `KVM_CAP_*` 정의를 참조하도록 한다 |
| `INSTALL_HDR_PATH=$PVM/usr` | 헤더 설치 경로. 컴파일 시 `-isystem $PVM/usr/include`로 지정한다 |
| `LDFLAGS=-static` | **정적 링크.** 게스트 initramfs에는 공유 라이브러리가 없으므로 필수 |
| `LDLIBS=-lpthread` | selftest가 pthread를 쓰므로 정적 링크 시 명시 |

주의점(이번 환경에서 실제로 걸린 것):
- 전체 `make`는 시스템 노후 uapi 헤더 탓에 일부 테스트(demand_paging 등)가 실패한다. 대상을 `pkvm`(항상 빌드되는 CUSTOM)과 `hello_el2`로 좁힌다.
- `tools/include/linux/arm-smccc.h`가 노후해 pKVM 메모리공유·MMIO-guard FUNC_ID 매크로가 없다. `#include_next` 기반 override 헤더로 보충한다. **소스트리는 수정하지 않는다.**

빌드 결과가 정적 arm64 ELF인지 확인:

```bash
file $PVM/bin/pkvm    # → ELF 64-bit ... ARM aarch64 ... statically linked
```

#### 4.4.2 initramfs 구성과 실행

4.1의 busybox 루트에 selftest 바이너리를 넣고, `/init`이 selftest를 실행하도록 한다.

```bash
cd work/pkvm-pvm
./run-pvm.sh protected                       # 1번째 인자: 모드(protected|nvhe)
# 또는 인자로 세부 제어:
#   ./run-pvm.sh <mode> <로그경로> <timeout초>
#   예) ./run-pvm.sh protected console-pvm-protected.log 400
```

`run-pvm.sh`는 4.2와 동일한 QEMU 인자에 `kvm-arm.mode=$1`만 바꿔 부팅한다.
`/init`은 게스트 안에서 순서대로 다음을 수행한다.

1. `/proc`·`/sys`·`/dev` 마운트 후 `ls -l /dev/kvm`으로 KVM 디바이스 노출 확인
2. `capcheck`로 `KVM_CHECK_EXTENSION` 및 `KVM_CREATE_VM(type=PROTECTED)` 직접 시도
3. `hello_el2`(nested/EL2 테스트), `pkvm`(protected VM 테스트) 실행
4. 표식 문자열 출력 후 `poweroff`

#### 4.4.3 성공 판정

게스트 콘솔(`console-pvm-protected.log`)에서 다음을 확인한다.

- `/dev/kvm` 노출: `PVM_TEST_KVM_DEV: PRESENT`
- cap 값: `KVM_CAP_ARM_PROTECTED_VM -> 1`
- `KVM_CREATE_VM(type=PROTECTED 1<<31) -> OK`, `KVM_CREATE_VCPU -> OK`
- pVM 실행: `Guest heartbeat` → `Guest done` → `All ok!` (`PVM_TEST_PKVM: rc=0`)
- 메모리 격리: 호스트가 pVM 사설 페이지에 접근하면 `Caught expected segfault`

`hello_el2`는 `KVM_CAP_ARM_EL2` 미충족으로 SKIP된다(nested virt 미지원). 이는 pVM과 별개다.

주의: 이 검증은 **기능 검증용**이다. IOMMU 기반 DMA 격리(기밀성 보증)는 QEMU 환경 제약으로
동작하지 않으며(`do not run confidential workloads`), nested virtualization(`KVM_CAP_ARM_EL2`)도
이 환경에서는 미지원이다. 상세는 조사 문서 9.8절 참조.

## 5. 검증 상태

| 항목 | 상태 |
|---|---|
| v6.18 + 721커밋 빌드 (clang 18.1.8) | 성공 (오류·경고 0) |
| v6.18 + 721커밋 빌드 (gcc 9.4.0) | 성공 (오류·경고 0) |
| QEMU protected 모드 부팅 | 성공 |
| EL2 pKVM 하이퍼바이저 초기화 | 관측됨 |
| pVM(protected guest) 생성·실행 | 성공 (pkvm selftest PASS, 9.8절) |
| pVM 메모리 격리 (호스트→사설페이지 차단) | 관측됨 |
| IOMMU 기반 DMA 격리 (기밀성 보증) | 미검증 (QEMU 환경 제약) |
| nested virtualization (`KVM_CAP_ARM_EL2`) | 미지원 (pVM과 별개) |

상세 근거와 수치는 [`research/pkvm-kernel-version.md`](research/pkvm-kernel-version.md) 9장을 참조한다.

### 5.1 재현 이력 (2026-08-08)

섹션 3부터 절차를 처음부터 다시 실행하면서 확인한 상태.

| 절차 | 결과 | 비고 |
|---|---|---|
| 3.0 소스트리 클린 상태 | 문제 확인 | `.config`·`include/config` 오염으로 defconfig 실패 → `mrproper`로 해소 (3.0 참조) |
| 3.1 clang `defconfig` | 성공 | 오염 제거 후 정상 생성 |
| 3.1 Kconfig 활성화 (`scripts/config`) | 성공 | KVM·PKVM_DEBUG·PKVM_STACKTRACE·ARM_SMMU_V3*·PKVM_PVIOMMU·VFIO_PKVM_IOMMU·PKVM_SMC_FILTER·PKVM_IOMMU_TEMPLATE 등 11개 심볼 반영 확인 |
| 3.1 `olddefconfig` | 성공 | 의존성 정규화 정상 |
| 3.1 `make -j$(nproc)` (clang) | 성공 | 중단된 트리 재개 시 `fixdep: error ... .o.d` 일시 오류 1회 → 재실행으로 해소, EXIT=0 (3.1 주의 참조) |
| 3.2 gcc `defconfig`·Kconfig·`olddefconfig`·`make -j` | 성공 | 11개 심볼 반영 확인, EXIT=0 |
| 3.3 산출물 확인 | 성공 | Image·vmlinux·kvm_nvhe.o·pkvm_smc.ko·pkvm_iommu_temp.ko 모두 생성. `__kvm_nvhe_` 심볼: clang 6724 / gcc 1723 |
| 4.2/4.3 QEMU 부팅 | 성공 | `bin/sh` 있는 initramfs로 EL2 진입·Protected KVM·`Protected nVHE mode initialized successfully`·`PKVM_QEMU_BOOT_OK` 확인 (4.1 주의 참조) |
| 4.4 pVM 생성·실행 | 성공 | `/dev/kvm` PRESENT, `KVM_CAP_ARM_PROTECTED_VM -> 1`, `KVM_CREATE_VM(type=PROTECTED)`·`KVM_CREATE_VCPU` OK, pkvm selftest `All ok!`(rc=0), `Caught expected segfault` 4회 관측. `hello_el2`는 rc=4로 SKIP(nested 미지원) |
