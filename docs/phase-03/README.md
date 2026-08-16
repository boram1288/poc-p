# Phase 03: QEMU protected 부팅

- 상태: 완료
- 목적: QEMU TCG의 arm64 EL2에서 커널을 protected 모드로 부팅한다.
- 환경: E-1
- 관련 목표: G-2
- 실행 도구: `work/src/tools/qemu/run.sh`
- 실행 산출물: `work/build/pkvm-qemu/`
- 커널 이미지: `work/build/pkvm-full-clang/arch/arm64/boot/Image`

## 목표

x86_64 호스트의 QEMU TCG가 제공하는 arm64 EL2에서 커널을 protected 모드로 부팅하고,
pKVM Hypervisor가 초기화되는지 확인한다.

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

QEMU가 VHE를 제공하는 버전에서 nVHE 경로를 재현하려면 다음과 같이 CPU를 선택한다.

```bash
CPU=cortex-a57 work/src/tools/qemu/run.sh protected
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

2026-08-16에는 QEMU 8.2.2 TCG와 `CPU=cortex-a57`로 다시 실행해 네 성공 마커와 종료 코드
0을 확인했다. 로그는 `work/build/pkvm-qemu/console-protected-nvhe-rerun.log`에 있다. 기본
`max` CPU는 이 QEMU 버전에서 hVHE를 제공하므로 nVHE 완료 조건 확인에는 사용하지 않았다.

## 한계

`Failed to init iommu driver -19`와 `Found 0 assignable devices`는 현재 QEMU가 S2MPU와
할당 장치를 노출하지 않아 발생한다. 두 문자열은 커널 로그 원문이다. pKVM 코어 부팅에는
치명적이지 않지만 DMA 기밀성은 검증할 수 없다는 의미다.

`Found 0 assignable devices`는 Phase 08에서 0이 아닌 값으로 바뀌어야 한다. E-1에서는 장치
직접 할당을 검증할 수 없다.
