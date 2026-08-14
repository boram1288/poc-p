# Phase 03: QEMU protected 부팅

- 상태: 완료
- 실행 도구: `work/src/tools/qemu/run.sh`
- 실행 산출물: `work/build/pkvm-qemu/`
- 커널 이미지: `work/build/pkvm-full-clang/arch/arm64/boot/Image`

## 목표

x86_64 호스트의 QEMU TCG가 제공하는 arm64 EL2에서 커널을 protected 모드로 부팅하고,
pKVM 하이퍼바이저가 초기화되는지 확인한다.

## 선행 조건

- Phase 02의 clang 커널 이미지
- 정적 arm64 BusyBox를 포함한 `initramfs.cpio.gz`
- `qemu-system-aarch64`

initramfs에는 `/bin/sh -> busybox` 링크가 반드시 있어야 한다. 이 링크가 없으면 커널은
`/init`을 찾았더라도 interpreter를 실행하지 못해 `No working init found`로 패닉한다.

## 실행

도구는 저장소 루트를 자동으로 계산하며 다음 기본 경로를 사용한다.

- 커널: `work/build/pkvm-full-clang/arch/arm64/boot/Image`
- initramfs: `work/build/pkvm-qemu/initramfs.cpio.gz`
- 로그: `work/build/pkvm-qemu/console-protected.log`

```bash
work/src/tools/qemu/run.sh protected
```

핵심 QEMU 옵션은 다음과 같다.

```text
-machine virt,virtualization=on,gic-version=3
-cpu max -smp 2 -m 2G
-append "console=ttyAMA0 kvm-arm.mode=protected earlycon rdinit=/init"
```

`-nographic`은 stdin을 시리얼 콘솔로 사용한다. 실행 도구는 터미널 job control로 QEMU가
정지하는 문제를 막기 위해 stdin을 `/dev/null`로 연결한다.

## 완료 조건

콘솔 로그에서 다음 마커를 모두 확인한다.

- `CPU: All CPU(s) started at EL2`
- `CPU features: detected: Protected KVM`
- `Protected nVHE mode initialized successfully`
- `PKVM_QEMU_BOOT_OK`

## 확인된 결과

QEMU 4.2.1 TCG에서 protected 모드 부팅, EL2 pKVM 초기화, initramfs user space 진입과
정상 poweroff를 확인했다.

`Failed to init iommu driver -19`와 `Found 0 assignable devices`는 현재 QEMU가 SMMU와
할당 장치를 노출하지 않아 발생한다. pKVM 코어 부팅에는 치명적이지 않지만 DMA 기밀성은
검증할 수 없다는 의미다.
