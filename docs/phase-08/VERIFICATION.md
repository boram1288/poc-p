# Phase 08 검증 결과

- 판정: 완료
- 검증일: 2026-08-20 (Asia/Seoul)
- 환경: E-3 QEMU(qemu-phase08 submodule, v10.0.0), `iommu=smmuv3,pkvm-edu-assignment=on`,
  edu PCI 장치 2개
- 검증 스크립트: `work/src/tools/verify/phase08.sh`
- 기존 `docs/phase-08/validation-results.md`를 대체하지 않고 이 저장소 재현 결과로 보완

## 재현 명령

```bash
work/src/tools/qemu/configure-pv-iommu-kernel.sh work/build/pkvm-full-clang
make -C work/src/pkvm-linux O=work/build/pkvm-full-clang ARCH=arm64 LLVM=1 \
  CC=clang-18 LD=ld.lld-18 -j"$(nproc)"
( cd work/build/qemu-v10-aarch64 && \
  work/src/qemu-phase08/configure --target-list=aarch64-softmmu --enable-slirp \
    --disable-docs --prefix=work/build/qemu-v10-aarch64/install )
make -C work/build/qemu-v10-aarch64 -j"$(nproc)"
QEMU=work/build/qemu-v10-aarch64/qemu-system-aarch64 \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
CPU=max HYP_IOMMU_PAGES=4096 \
CMDLINE_EXTRA='vfio_platform.reset_required=0' \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
PHASE08=1 work/src/tools/pvm-framework/run.sh \
  work/build/pvm-framework/console-phase08-share-final.log 900
```

vfio-platform은 기본적으로 device의 reset 콜백 등록을 요구하는데, QEMU edu
장치는 그런 콜백이 없어 probe가 "-2" 오류로 실패한다. `vfio_platform.reset_required=0`으로
이를 끈다.

## 완료 조건 결과 (docs/phase-08/README.md 기준)

| 검사 | 판정 | 실측 증거 |
|---|---|---|
| PV driver 초기화 | 통과 | nested probe 없이 등록 |
| 할당 가능 장치 인식 | 통과 | `Found 2 assignable devices` |
| 장치 배타 할당 | 통과 | `PVM_DEVICE_ASSIGNED: role=camera ... vsid=0x10`, `PVM_DEVICE_ASSIGNED: role=ai ... vsid=0x18` |
| Host 접근 차단 | 통과 | `PVM_DEVICE_HOST_ACCESS_BLOCKED: role=camera signal=11` |
| 비소유 pVM 접근 차단 | 통과 | `PVM_DEVICE_NONOWNER_BLOCKED` |
| DMA 범위 위반 차단 | 통과 | `PVM_DEVICE_DMA_NORMAL_OK` 후 `PVM_DEVICE_DMA_RANGE_BLOCKED` |
| pVM 간 DMA 공유 | 통과 | `PVM_DMA_SHARE_GRANTED` → `PVM_DMA_SHARE_ACCEPTED` → `PVM_DMA_SHARE_READ_OK` |
| 미승인 공유 차단 | 통과 | `PVM_DMA_SHARE_UNAPPROVED_BLOCKED: role=ai sid=0x10` |
| 공유 revoke | 통과 | `PVM_DMA_SHARE_REVOKE_BLOCKED` |
| pVM 내부 드라이버 기동 | 통과 | `PVM_DEVICE_DRIVER_OK` |
| 회수와 재할당 | 통과 | `PVM_DEVICE_REASSIGN_OK`, `Mlocked: 0 kB` |
| panic/Oops/BUG 없음 | 통과 | |

## 핵심 marker

```text
kvm [1]: Found 2 assignable devices
PVM_FRAMEWORK_VFIO_READY: device=10000000.pkvm-edu group=1
PVM_DEVICE_ASSIGNED: role=camera group=1 device=10000000.pkvm-edu phys=0x10000000 pviommu=14 vsid=0x10
PVM_DEVICE_DRIVER_OK: role=camera
PVM_DEVICE_NONOWNER_BLOCKED: role=camera
PVM_DEVICE_DMA_NORMAL_OK: role=camera
PVM_DEVICE_DMA_RANGE_BLOCKED: role=camera
PVM_DMA_SHARE_GRANTED: role=camera receiver_sid=0x18 bytes=4096
PVM_DEVICE_HOST_ACCESS_BLOCKED: role=camera signal=11
PVM_DMA_SHARE_ACCEPTED: role=ai sender_sid=0x10 bytes=4096
PVM_DMA_SHARE_READ_OK: role=ai bytes=8
PVM_DMA_SHARE_UNAPPROVED_BLOCKED: role=ai sid=0x10
PVM_DMA_SHARE_REVOKE_BLOCKED: role=ai bytes=8
PVM_DEVICE_REASSIGN_OK
Mlocked:               0 kB
```

## Revision과 digest

| 항목 | 값 |
|---|---|
| `pkvm-linux` submodule revision | `7034ea6fc1e0b031127130666a7d1d8990dc84d1` |
| `qemu-phase08` submodule revision | `5b3965e9c44ce7e8135f2a6ef7680eb563ab8bef` (v10.0.0-2-g5b3965e9c4) |

최종 로그:

- `work/build/pkvm-qemu/console-phase08-e3-smoke.log` (E-3 환경 자체 smoke test)
- `work/build/pvm-framework/console-phase08-share-final.log` (장치 할당/DMA 격리 시나리오)

Phase 09, 09-B, 10은 이 Phase가 빌드한 E-3 QEMU(`work/build/qemu-v10-aarch64`)와
PV IOMMU 커널 설정을 그대로 재사용한다.
