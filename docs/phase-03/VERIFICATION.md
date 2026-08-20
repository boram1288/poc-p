# Phase 03 검증 결과

- 판정: 완료
- 검증일: 2026-08-20 (Asia/Seoul)
- 환경: E-1 QEMU(TCG), Phase 02 kernel Image 재사용, `CPU=cortex-a57`로 nVHE 경로 강제
- 검증 스크립트: `work/src/tools/verify/phase03.sh`

## 재현 명령

```bash
work/src/tools/qemu/mkinitramfs.sh
CPU=cortex-a57 work/src/tools/qemu/run.sh protected
```

호스트에 설치된 QEMU가 8.x 이상이면 `CPU=max` 기본값이 hVHE 경로
(`Protected hVHE mode initialized successfully`)를 노출한다. 완료 조건이 요구하는
nVHE marker를 재현하려면 `CPU=cortex-a57`를 명시해야 한다.

## 완료 조건 결과 (docs/phase-03/README.md 기준)

콘솔 로그(`work/build/pkvm-qemu/console-protected.log`)에서 4개 marker 모두 확인.

| Marker | 결과 |
|---|---|
| `CPU: All CPU(s) started at EL2` | 통과 (line 97) |
| `CPU features: detected: Protected KVM` | 통과 (line 102) |
| `Protected nVHE mode initialized successfully` | 통과 (line 182) |
| `PKVM_QEMU_BOOT_OK` | 통과 (line 274) |
| panic/Oops/BUG 없음 | 통과 |

## 핵심 marker

```text
[    0.080749] CPU: All CPU(s) started at EL2
[    0.082061] CPU features: detected: Protected KVM
[    0.615433] kvm [1]: Protected nVHE mode initialized successfully
PKVM_QEMU_BOOT_OK
```

## Revision과 digest

Phase 02와 동일한 `pkvm-linux` revision(`7034ea6fc1e0`)과 kernel Image를 재사용했다.

최종 로그: `work/build/pkvm-qemu/console-protected.log`

Phase 04, 05는 이 Phase가 확인한 protected 부팅 판정 방식(marker 순서/의미)을
그대로 재사용한다.
