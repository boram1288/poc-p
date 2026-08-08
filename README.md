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

# android-kvm 저장소에는 v6.18 태그가 없으므로 릴리스 커밋을 직접 태그
git tag v6.18     7d0a66e4bb9081d75c82ec4957c50034cb0ea449
git tag v6.18-rc2 211ddde0823f1442e4ad052a2f30f050145ccada
```

대상 721커밋 트리(`pkvm-6.18-full`) 구성 절차는 조사 문서 8.2절·9.4절을 따른다.
핵심은 `pkvm-master-6.18`의 394커밋을 v6.18로 리베이스한 뒤, 나머지를
`pkvm-mainline-6.18`에서 시간순 cherry-pick 하고 빌드 수정 5건을 얹는 것이다.

## 3. 빌드

소스트리는 건드리지 않고 out-of-tree(`O=`)로만 빌드한다. clang·gcc 빌드는
`O=`가 다르므로 동시에 돌려도 `fixdep` 충돌이 없다.

### 3.1 clang-18

```bash
cd work/pkvm-linux
O=$PWD/../pkvm-full-clang

make -C . O=$O ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 defconfig

# pKVM Kconfig 옵션 (조사 문서 9.2절)
./scripts/config --file $O/.config \
    -e KVM -e PKVM_DEBUG -e PKVM_DISABLE_STAGE2_ON_PANIC -e PKVM_STACKTRACE \
    -e ARM_SMMU_V3 -e ARM_SMMU_V3_PKVM -e ARM_SMMU_V3_PKVM_PV \
    -e PKVM_PVIOMMU -e VFIO_PKVM_IOMMU
# EL2 벤더 모듈은 모듈로만 빌드된다 (depends on ... && m)
./scripts/config --file $O/.config -m PKVM_SMC_FILTER -m PKVM_IOMMU_TEMPLATE

make -C . O=$O ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 olddefconfig
make -C . O=$O ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 -j"$(nproc)"
```

### 3.2 gcc 9.4.0

```bash
cd work/pkvm-linux
O=$PWD/../pkvm-full-gcc

make -C . O=$O ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-9 defconfig
# (3.1과 동일한 scripts/config 옵션 적용)
make -C . O=$O ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-9 olddefconfig
make -C . O=$O ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-9 -j"$(nproc)"
```

### 3.3 산출물 확인

빌드 성공 시 생성물이다(크기는 조사 문서 9.6절 표 참조).

- `$O/arch/arm64/boot/Image` — 부팅 커널 이미지
- `$O/vmlinux`
- `$O/arch/arm64/kvm/hyp/nvhe/kvm_nvhe.o` — EL2 하이퍼바이저 오브젝트
- `$O/drivers/misc/pkvm-smc/pkvm_smc.ko`, `$O/drivers/misc/pkvm-iommu-temp/pkvm_iommu_temp.ko`

pKVM 코드 링크 확인:

```bash
llvm-nm-18 $O/vmlinux | grep -c '__kvm_nvhe_'          # clang 빌드
aarch64-linux-gnu-nm  $O/vmlinux | grep -c '__kvm_nvhe_'  # gcc 빌드
```

## 4. QEMU 부팅 테스트

호스트가 x86_64이므로 arm64는 KVM 가속 없이 **TCG 순수 에뮬레이션**으로 부팅한다(느림).
pKVM은 EL2에서 동작하므로 `-machine virt,virtualization=on`으로 게스트에 EL2를 노출하는 것이 핵심이다.

### 4.1 initramfs

`aarch64-linux-gnu-gcc`로 정적 busybox를 크로스 빌드해 최소 루트를 만든다.
`bin/sh -> busybox` 심링크가 반드시 있어야 한다(없으면 `No working init found` 패닉).

### 4.2 부팅 실행

준비물이 `work/pkvm-qemu/`에 있으면 `run.sh`로 실행한다.

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

TCG라 느리므로 timeout은 300초 이상을 권장한다.

### 4.3 성공 판정

콘솔 로그(`work/pkvm-qemu/console-protected.log`)에서 다음을 확인한다.

- `CPU: All CPU(s) started at EL2` — 게스트 EL2 진입
- `CPU features: detected: Protected KVM`
- `kvm [1]: Protected nVHE mode initialized successfully` — **pKVM 하이퍼바이저 초기화 성공**
- `=== PKVM_QEMU_BOOT_OK ===` — 유저스페이스 도달

`Failed to init iommu driver -19`, `Found 0 assignable devices` 등은 QEMU virt 머신이
SMMU·할당 장치를 노출하지 않는 데서 오는 비치명적 경고다. pKVM 코어 초기화와 무관하다.

### 4.4 pVM 생성·실행 테스트

커널 트리의 pKVM selftest(`tools/testing/selftests/kvm/arm64/pkvm.c`)를 게스트에서 실행해
protected VM 생성·실행을 검증한다. selftest를 `aarch64-linux-gnu-gcc`로 정적 크로스 빌드해
initramfs에 넣고, `kvm-arm.mode=protected`로 부팅한 게스트 안에서 실행한다. 산출물은
`work/pkvm-pvm/`에 있다(`run-pvm.sh`, `console-pvm-protected.log`).

성공 시 게스트 콘솔에서 다음을 확인한다.

- `KVM_CREATE_VM(type=PROTECTED, 1<<31) -> OK`, `KVM_CREATE_VCPU -> OK`
- pVM 실행: `Guest heartbeat` → `Guest done` → `All ok!`
- 메모리 격리: 호스트가 pVM 사설 페이지에 접근하면 `Caught expected segfault`

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
