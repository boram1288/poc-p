# Phase 08 validation evidence

## 실행

```bash
# Phase 08 marker 검사를 활성화한 protected-QEMU 회귀 실행
PHASE08=1 \
QEMU="$PWD/work/build/qemu-v10-aarch64/qemu-system-aarch64" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
CPU=max HYP_IOMMU_PAGES=4096 \
CMDLINE_EXTRA='vfio_platform.reset_required=0' \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
work/src/tools/pvm-framework/run.sh \
work/build/pvm-framework/console-phase08-share-second.log 300
```

`run.sh`는 기존 Phase 07 protocol/auth/policy/lifecycle/recovery/fault-isolation 검사를
먼저 수행한 후 Phase 08 marker를 검사한다. 최종 결과는 `PVM_FRAMEWORK_RUN_OK`와
`QEMU_RC=0`이다.

## 증거 marker

| 단계 | marker 또는 로그 |
|---|---|
| PV/VFIO 준비 | `PVM_FRAMEWORK_VFIO_READY` 2개 |
| assignment | `PVM_DEVICE_ASSIGNED` Camera/AI 각각 1개 이상 |
| 정상 driver·DMA | `PVM_DEVICE_DRIVER_OK`, `PVM_DEVICE_DMA_NORMAL_OK` |
| denial | `PVM_DEVICE_NONOWNER_BLOCKED`, `PVM_DEVICE_HOST_ACCESS_BLOCKED` |
| out-of-range | `PVM_DEVICE_DMA_RANGE_BLOCKED` 및 SMMU `F_TRANSLATION` |
| grant/accept | `PVM_DMA_SHARE_GRANTED`, `PVM_DMA_SHARE_ACCEPTED`, `PVM_DMA_SHARE_READ_OK` |
| unapproved accept | `PVM_DMA_SHARE_UNAPPROVED_BLOCKED` |
| revoke | Owner SIGKILL 뒤 IOVA `0x300000`의 SMMU `F_TRANSLATION` 및 `PVM_DMA_SHARE_REVOKE_BLOCKED` |
| lifecycle | `PVM_DEVICE_REASSIGN_OK`, `Mlocked: 0 kB`, `PVM_FRAMEWORK_RESOURCE_RECOVERY_OK` |

## 소스 변경 요약

| 모듈 | 변경 |
|---|---|
| `arch/arm64/kvm/hyp/nvhe/iommu/pvm-dma-share.c` | EL2 grant/accept/query, physical-SID authorization, teardown revoke |
| `arch/arm64/kvm/hyp/nvhe/iommu/iommu.c` | receiver VM context를 지정하는 cross-pVM unmap |
| `arch/arm64/kvm/hyp/nvhe/iommu/pviommu.c` | guest domain ownership 확인 helper |
| `arch/arm64/kvm/hyp/nvhe/pkvm.c` | vendor HVC dispatch, feature advertisement, teardown hook |
| `guest/phase07_guest.S` | Camera marker grant, AI direct DMA read, wrong-SID denial, post-revoke DMA |
| `backend/pvm_kvm_arm64.c` | share/revoke evidence markers |
| `run.sh` | Phase 08 required marker/count assertions |

## 범위와 한계

- Host는 shared page의 CPU mapping 또는 data relay 경로에 참여하지 않는다. Host는 VM
  lifecycle과 device assignment를 제어하는 control plane이다.
- 현재 slot은 4 KiB 한 페이지, 한 owner/receiver pair, 하나의 물리 receiver SID만 지원한다.
- QEMU edu/SMMUv3는 에뮬레이션이므로 실제 camera/GPU와 실물 SMMUv3의 성능·기밀성은
  검증하지 않는다.
- `pkvm-full-gcc`는 삭제되었고 교차 검증하지 않았다.
