# Phase 10 검증 결과

- 판정: 완료
- 검증일: 2026-08-19 (Asia/Seoul)
- 실행 환경: E-3 커스텀 QEMU 10.0.0, `virt,iommu=smmuv3`, pKVM protected mode
- 입력/추론 대체: Open Model Zoo 동영상 frame replay와 사전 생성 detection oracle
- Trusted Access: 요구하거나 사용하지 않음

## 실행 명령

Fixture 준비 도구는 원본 동영상과 model digest를 먼저 검사하고 CPU demo를 두 번 실행한다.
두 실행에서 선택 frame page와 normalized oracle이 같은지 비교한 뒤 최종 fixture를 만든다.

```bash
rtk work/src/tools/vision-pipeline/prepare-fixture.sh
rtk make -C work/src/tools/pvm-user-channel clean all test

VISION_E3=1 \
QEMU="$PWD/work/build/qemu-v10-aarch64/qemu-system-aarch64" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
CPU=max HYP_IOMMU_PAGES=4096 \
CMDLINE_EXTRA='vfio_platform.reset_required=0' \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
rtk work/src/tools/pvm-buffer/run-vision-pipeline.sh \
  work/build/vision-pipeline/console-vision-pipeline-e3-final.log 360

VISION_E3=1 \
QEMU="$PWD/work/build/qemu-v10-aarch64/qemu-system-aarch64" \
MACHINE='virt,virtualization=on,gic-version=3,iommu=smmuv3,pkvm-edu-assignment=on' \
CPU=max HYP_IOMMU_PAGES=4096 \
CMDLINE_EXTRA='vfio_platform.reset_required=0' \
QEMU_EXTRA_ARGS='-device edu,addr=2 -device edu,addr=3' \
rtk work/src/tools/pvm-buffer/run-vision-fault.sh \
  work/build/vision-pipeline/console-vision-fault-e3.log 300
```

Phase 09-b 회귀 명령은 다음과 같다.

```bash
rtk make -C work/src/tools/pvm-user-channel test
rtk work/src/tools/pvm-buffer/run-vsock-smoke.sh \
  work/build/pvm-buffer/console-phase10-vsock-regression.log 240
rtk work/src/tools/pvm-buffer/run-user-channel-e2e.sh \
  work/build/pvm-buffer/console-phase10-user-channel-e2e.log 300
rtk work/src/tools/pvm-buffer/run-user-channel-fault.sh \
  work/build/pvm-buffer/console-phase10-user-channel-fault.log 240
PHASE09=1 PHASE09_ONLY=1 rtk work/src/tools/pvm-framework/run.sh \
  work/build/pvm-framework/console-phase10-phase09b-primitive.log 900
```

## 완료 조건 결과

| ID | 결과 | 실측 증거 |
|---|---|---|
| CC-10-01 | 통과 | OMZ commit, URL, Apache-2.0 license, 도구 버전과 아래 입력/fixture digest를 고정했다. 동영상은 재배포 조건을 확인하지 못해 Git에 넣지 않았다. |
| CC-10-02 | 통과 | 두 CPU demo 실행에서 `PVM_VISION_FIXTURE_REPRODUCIBLE_OK`; 30 page와 oracle digest가 같고 class `0,1,2`를 포함한다. |
| CC-10-03 | 통과 | Camera pVM의 `PVM_VISION_CAMERA_FRAME_OK`가 정확히 30개다. 각 4 KiB DMA-BUF와 별도 BGR3 descriptor를 전달했다. |
| CC-10-04 | 통과 | AI pVM이 kernel `actual_size`, BGR3 stride/plane/padding을 검사하고 page SHA-256으로 oracle을 찾았다. `PVM_VISION_ORACLE_LOOKUP_OK: frames=30`. |
| CC-10-05 | 통과 | layout, one-byte mutation/hash miss, transfer mismatch, duplicate/replay를 모두 result 생성 전에 거부했다. |
| CC-10-06 | 통과 | Host/AI/Camera frame marker가 각각 30개고 `PVM_VISION_RESULTS_MATCH_OK`; vehicle/person/bike 결과가 class/score/bbox까지 oracle과 byte 단위로 일치했다. |
| CC-10-07 | 통과 | Host result ABI는 session/request/frame/status, count/truncated와 최대 16개 class/Q16 score/Q16 bbox만 가진다. `PVM_VISION_HOST_ALLOWLIST_OK`; raw frame/hash/descriptor/FD/token/address/oracle path를 보내는 Host-facing encoder는 없다. |
| CC-10-08 | 통과 | 정상 EOS/STOP 및 Phase 10 전용 Camera/AI/Host 연결 상실 주입이 모두 성공했다. 정상·fault 실행 모두 RC `0/0/0`, `Mlocked: 0 kB`다. Phase 09 primitive teardown/timeout revoke도 통과했다. |
| CC-10-09 | 통과 | AF_VSOCK smoke, 기존 10-frame metadata/DMA-BUF E2E, channel fault, Phase 09 buffer primitive 회귀가 모두 통과했다. |
| CC-10-10 | 통과 | 여섯 최종 로그에서 panic/Oops/BUG 0건, unexpected timeout 0건이며 `PVM_VISION_PIPELINE_OK`를 출력했다. |
| CC-10-11 | 통과 | 아래 제한에 실제 camera/GPU/inference/model 보호를 검증하지 않았음을 명시했다. |

## 핵심 실측 marker

```text
kvm [1]: Found 2 assignable devices
kvm-arm-smmu-v3 9050000.smmuv3: ias 44-bit, oas 44-bit
PVM_VISION_FIXTURE_REPRODUCIBLE_OK
PVM_VISION_FIXTURE_VERIFY_OK: source=768x432 classes=[0, 1, 2]
PVM_VISION_CAMERA_REPLAY_OK: frames=30
PVM_VISION_ORACLE_LOOKUP_OK: frames=30
PVM_VISION_RESULTS_MATCH_OK: frames=30
PVM_VISION_HOST_ALLOWLIST_OK
PVM_VISION_EOS_OK
PVM_VISION_RC: host=0 ai=0 camera=0
PVM_VISION_PIPELINE_VALIDATION_OK
PVM_VISION_E3_ENVIRONMENT_OK
PVM_VISION_PIPELINE_OK
PVM_VISION_CAMERA_FAILURE_RECOVERY_OK
PVM_VISION_AI_FAILURE_RECOVERY_OK
PVM_VISION_HOST_FAILURE_INJECTED_OK
PVM_VISION_FAULT_RC: host=0 ai=0 camera=0
PVM_VISION_FAULT_E3_ENVIRONMENT_OK
PVM_VISION_FAULT_OK
Mlocked: 0 kB
```

Negative marker는 `PVM_VISION_LAYOUT_REJECT_OK`, `PVM_VISION_MUTATION_REJECT_OK`,
`PVM_VISION_HASH_REJECT_OK`, `PVM_VISION_MISMATCH_REJECT_OK`와
`PVM_VISION_DUPLICATE_REPLAY_REJECT_OK`다.

## Revision, 도구와 digest

| 항목 | 값 |
|---|---|
| root 기준 commit | `ceaffb5da598348d8caca169662ff4b7dbb2ce3e` (Phase 10 완료 commit 전 기준) |
| pKVM Linux | `6763e27c1ad00e0f5caf6e6cde5fcb33976e50e0` |
| kvmtool | `6866a248977d16bc293c6f4f6609daa4f465b073` |
| E-3 QEMU source | `5b3965e` (`boram1288/qemu`, Phase 08 고정 revision) |
| Open Model Zoo | `7cc29a91472b4cb1289a11e655ba3e188e1d4a31` |
| OpenVINO / OpenCV / NumPy | `2024.6.0-17404-4c0f47d2335-releases/2024/6` / `4.10.0` / `1.26.4` |
| FFmpeg | `6.1.1-3ubuntu5` |
| source video SHA-256 | `452b11b7e0efbd019f1d9570d0c790e90416ad4ad29eec6003872d08443140ef` |
| model XML SHA-384 | `8c4f1a14c1e00709391c2bded1157d4497cf56be6a1d919b09747cecef183380dbae659a5c555dedbc81b9e4da579096` |
| model BIN SHA-384 | `2217e4a07f0fe94a2e13bb80c359c4d6125454956e08e806eacc81176a888060f573a7f7352c5a4f4fa0288f2c53bb78` |
| `frames.bin` SHA-256 / size | `655cd5aa44c2585ee435466015bdb38f6abbdb8623877d92847bd02aad415030` / 122,880 bytes |
| `oracle.bin` SHA-256 / size | `37905752542e5c43551cc18e911ed4c0394333f25882b7c9ef4890ff5ace177f` / 13,032 bytes |
| kernel Image / config SHA-256 | `a58cf72f405d1c67266532b4a49bbf17ab5ea834962ea1a6cb84094f93efcdf4` / `7ef1e6b3d688f516ac9e98730ff65429d42d748bd2a835d59fe639c5898ac77e` |
| QEMU / lkvm SHA-256 | `913b9b97ab9d47db5764d565faa945de5f14a1a39984fdb5c4cda321c920d384` / `9b718dd8c7fe239f3d73eeedffb4de3a0074696451724477ca9d67ce065707c4` |
| `pvm_vision` SHA-256 | `1cd5284f616fdd0bc53aada833e593e52c5e9bdd29c574dc385fce64bccb9a43` |
| `pvm_message.ko` / `pvm_dmabuf.ko` SHA-256 | `3eafe10bb5c7fc5f8d2d73786bc32717a8c660d3ae997db4fb641e04a93af693` / `dff6ad1da851f448a0360fc12eb3db9a47478e14041da082dd33484e2900db2e` |
| Host / guest initramfs SHA-256 | `a3a119ec4096649befd7c9b1b4447383d7d97121a10c503d7c60a3ba4cac693c` / `c094357b0e133626cacd67599fe20d922e8a921bb9801dd7e992f0434fb88361` |

최종 로그는 다음과 같다.

- `work/build/vision-pipeline/console-vision-pipeline-e3-final.log`
- `work/build/vision-pipeline/console-vision-fault-e3.log`
- `work/build/pvm-buffer/console-phase10-vsock-regression.log`
- `work/build/pvm-buffer/console-phase10-user-channel-e2e.log`
- `work/build/pvm-buffer/console-phase10-user-channel-fault.log`
- `work/build/pvm-framework/console-phase10-phase09b-primitive.log`

## 판정 범위와 제한

- 실물 USB camera, sensor capture/driver/timing은 사용하거나 검증하지 않았다.
- 실제 NVIDIA GPU assignment/driver/inference와 model weight/intermediate tensor 기밀성은
  검증하지 않았다. AI pVM은 실제 inference 대신 공개 demo의 사전 생성 oracle을 page hash로
  조회한다.
- 공개 동영상과 파생 fixture 자체의 비밀성은 주장하지 않는다. Host 비노출 판정은 E-3 runtime
  Camera↔AI DMA-BUF를 Host가 relay/copy하지 않고 Host-facing result allowlist에 frame 또는 내부
  handle을 포함하지 않는다는 경로 특성에 한정한다.
- QEMU edu/SMMUv3는 에뮬레이션이므로 실물 IOMMU·camera·GPU의 성능과 기밀성을 보증하지 않는다.
- 객체 탐지 정확도, FPS, latency, backpressure와 production reconnect는 판정하지 않았다.
- VSOCK guest 부팅 중 알려진 pKVM MMIO guard `WARN_ON_ONCE`가 관찰되지만 queue 초기화, 왕복,
  guest 종료와 회수에 영향은 없었다. 완료 조건이 금지한 panic/Oops/BUG는 없었다.
