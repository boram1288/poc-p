# Phase 04: 단일 pVM과 메모리 격리

- 상태: 완료
- 목적: 단일 protected VM을 실행하고 Host CPU의 private page 접근 차단을 확인한다.
- 환경: E-1
- 관련 목표: G-3, G-4
- 관련 결정: D-3
- 실행 도구: `work/src/tools/pvm/run-pvm.sh`
- selftest 소스: `work/src/pkvm-linux/tools/testing/selftests/kvm/arm64/pkvm.c`
- 실행 산출물: `work/build/pkvm-pvm/`

## 선행 조건

- Phase 03의 protected 부팅 성공
- 커널 UAPI 헤더와 정적 arm64 크로스 툴체인

## 목표

protected VM과 vCPU를 생성하고 게스트 코드를 실행한 뒤, Host CPU가 pVM private page에
접근하지 못하는지 확인한다.

## selftest 준비

커널 UAPI 헤더를 `work/build/pkvm-pvm/usr`에 설치하고 pKVM selftest를 정적 arm64 ELF로
크로스 빌드한다. 생성물은 다음 위치에 둔다.

- `work/build/pkvm-pvm/kselftest-build/arm64/pkvm`
- `work/build/pkvm-pvm/kselftest-build/arm64/hello_el2`
- `work/build/pkvm-pvm/bin/capcheck`
- `work/build/pkvm-pvm/initramfs-pvm.cpio.gz`

시스템 UAPI 헤더가 오래된 경우 `headers_install` 결과를 `-isystem`으로 우선하고,
`tools/include/linux/arm-smccc.h`의 pKVM FUNC_ID 누락은 소스트리가 아닌 빌드 디렉터리의
override 헤더에서 보충한다.

## 실행

```bash
work/src/tools/pvm/run-pvm.sh protected
```

QEMU가 VHE를 제공하는 버전에서 nVHE 경로를 재현하려면 다음과 같이 실행한다.

```bash
CPU=cortex-a57 work/src/tools/pvm/run-pvm.sh protected
```

기본 로그는 `work/build/pkvm-pvm/console-pvm-protected.log`에 생성된다.

## 완료 조건

| 검사 | 성공 마커 |
|---|---|
| KVM 장치 | `PVM_TEST_KVM_DEV: PRESENT` |
| pVM capability | `KVM_CAP_ARM_PROTECTED_VM -> 1` |
| VM 생성 | `KVM_CREATE_VM(type=PROTECTED 1<<31) -> OK` |
| vCPU 생성 | `KVM_CREATE_VCPU -> OK` |
| 게스트 실행 | `Guest heartbeat`, `Guest done`, `All ok!` |
| private page 접근 차단 | `Caught expected segfault` |
| selftest | `PVM_TEST_PKVM: rc=0` |

## 확인된 결과

- `/dev/kvm`과 protected VM capability가 노출됐다.
- protected VM과 vCPU를 만들고 `KVM_RUN`으로 게스트 코드를 완료했다.
- regular page와 THP 시나리오가 모두 통과했다.
- Host가 private page에 접근했을 때 예상된 segfault가 발생했다.
- share, unshare, relinquish, MMIO guard와 private page poison 경로가 통과했다.
- teardown 뒤 Host의 locked memory가 0으로 돌아왔다.

2026-08-16에는 QEMU 8.2.2 TCG와 `CPU=cortex-a57`로 다시 실행했다. QEMU 종료 코드 0,
capcheck rc=0, `All ok!`, selftest rc=0, 예상된 segfault와 정상 poweroff를 다시 확인했다.
재실행 로그는 `work/build/pkvm-pvm/console-pvm-protected-rerun.log`에 있다.

## 한계

이 결과는 Host CPU의 매핑을 통한 private page 접근 차단을 기능 수준에서 실증한다. QEMU가
S2MPU와 assignable device를 제공하지 않으므로 DMA master의 접근 차단은 검증하지 않았다.
DMA 격리는 Phase 08에서 판정한다.

`hello_el2`가 `KVM_CAP_ARM_EL2=0`으로 skip된 것은 nested virtualization 미지원 결과이며,
pVM 생성/실행 성공과는 별개다.

이 Phase에서는 단일 selftest 흐름만 검증했다. 독립된 pVM 2개의 동시 운용은 Phase 05에서,
Host 요청 기반의 동적 생성과 종료는 Phase 07에서 별도로 수행한다.
