# Phase 04 검증 결과

- 판정: 완료
- 검증일: 2026-08-20 (Asia/Seoul)
- 환경: E-1 QEMU(TCG), Phase 02 kernel Image 재사용, `CPU=cortex-a57`로 nVHE 경로 강제
- 검증 스크립트: `work/src/tools/verify/phase04.sh`

## 재현 명령

```bash
work/src/tools/pvm/build-selftest.sh
work/src/tools/pvm/mkinitramfs.sh
CPU=cortex-a57 work/src/tools/pvm/run-pvm.sh protected
```

`build-selftest.sh`는 pKVM 커널 트리의 `tools/testing/selftests/kvm/arm64`
selftest(`pkvm`, `hello_el2`)와 `capcheck`를 arm64 정적 바이너리로 빌드한다. 최신
kernel 소스가 `tools/include/linux/arm-smccc.h`에 없는 MMIO_GUARD/MEM_SHARE 계열
SMCCC 매크로를 요구해, override 헤더(`USERCFLAGS="-include ..."`)로 보완한다.

## 완료 조건 결과 (docs/phase-04/README.md 기준)

| 검사 | 성공 marker | 결과 |
|---|---|---|
| KVM 장치 | `PVM_TEST_KVM_DEV: PRESENT` | 통과 |
| pVM capability | `KVM_CAP_ARM_PROTECTED_VM -> 1` | 통과 |
| VM 생성 | `KVM_CREATE_VM(type=PROTECTED 1<<31) -> OK` | 통과 |
| vCPU 생성 | `KVM_CREATE_VCPU -> OK` | 통과 |
| 게스트 실행 | `Guest heartbeat`, `Guest done`, `All ok!` | 통과 |
| private page 접근 차단 | `Caught expected segfault` | 통과 |
| selftest | `PVM_TEST_PKVM: rc=0` | 통과 |
| panic/Oops/BUG 없음 | - | 통과 |

## 핵심 marker

```text
PVM_TEST_KVM_DEV: PRESENT
KVM_CAP_ARM_PROTECTED_VM -> 1
KVM_CREATE_VM(type=PROTECTED 1<<31) -> OK
KVM_CREATE_VCPU -> OK
Guest heartbeat.
Caught expected segfault at address 0xffff9396f000
Guest done
All ok!
PVM_TEST_PKVM: rc=0
```

## Revision과 digest

Phase 02와 동일한 `pkvm-linux` revision(`7034ea6fc1e0`)의 kernel Image를 재사용했다.
selftest 정적 바이너리는 이 Phase에서 새로 빌드했다(`work/build/pkvm-pvm/kselftest-build`).

최종 로그: `work/build/pkvm-pvm/console-pvm-protected.log`

Phase 05는 이 selftest 정적 바이너리를 재사용하고, Phase 06-B는 Phase 04가 만든
`pkvm` 바이너리(`work/build/pkvm-pvm/kselftest-build/arm64/pkvm`)를 Host rootfs에
그대로 조립해 재사용한다.
