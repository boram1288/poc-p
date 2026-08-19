# Phase 09-b 검증 결과

- 판정: 완료
- 검증일: 2026-08-19 (Asia/Seoul)
- 환경: E-1 QEMU 위 pKVM Host와 `lkvm --protected` Camera/AI guest 2대
- Host-facing transport: AF_VSOCK 전용(CID 4101/4102), MMIO fallback 없음
- Camera↔AI metadata transport: `/dev/pvm-msg` → SMCCC register fragment → EL2 receiver queue

## 재현 명령

```bash
rtk work/src/tools/qemu/configure-pv-iommu-kernel.sh work/build/pkvm-full-clang
rtk make -C work/build/pkvm-full-clang ARCH=arm64 LLVM=1 CC=clang-18 LD=ld.lld-18 -j16 Image
rtk make -C work/src/tools/pvm-user-channel test
rtk work/src/tools/pvm-buffer/run-vsock-smoke.sh work/build/pvm-buffer/console-pvm-vsock-release.log 240
rtk work/src/tools/pvm-buffer/run-user-channel-e2e.sh work/build/pvm-buffer/console-user-channel-e2e-final.log 300
rtk work/src/tools/pvm-buffer/run-user-channel-fault.sh work/build/pvm-buffer/console-user-channel-fault-final2.log 240
PHASE09=1 PHASE09_ONLY=1 rtk work/src/tools/pvm-framework/run.sh \
  work/build/pvm-framework/console-phase09b-primitive-final.log 900
```

모든 shell 명령은 실제 실행 시 저장소 지침에 따라 `rtk`를 앞에 붙였다.

## 완료 조건 결과

| ID | 결과 | 실측 증거 |
|---|---|---|
| CC-09B-01 | 통과 | AI CID 4101/endpoint 1과 Camera CID 4102/endpoint 2 동시 연결, Host role/CID 검사 |
| CC-09B-02 | 통과 | `PVM_USER_HOST_CAMERA_OK`; CONFIG/CAPTURE 10회/STOP ACK correlation |
| CC-09B-03 | 통과 | `PVM_USER_CAMERA_AI_BUFFER_OK`, `PVM_BUFFER_GUEST_TO_GUEST_OK` |
| CC-09B-04 | 통과 | `/dev/pvm-msg`, receiver별 EL2 64-entry queue, `PVM_USER_CAMERA_AI_METADATA_OK` |
| CC-09B-05 | 통과 | kernel `actual_size`, GREY allowlist 및 plane bounds 검사, `PVM_USER_CAMERA_AI_JOIN_OK` |
| CC-09B-06 | 통과 | `PVM_USER_AI_HOST_OK`, allowlist 크기의 RESULT 10개와 STOP ACK |
| CC-09B-07 | 통과 | Host/Camera/AI가 각각 frame 1~10을 한 번씩 기록, `PVM_USER_E2E_OK: frames=10` |
| CC-09B-08 | 통과 | unit malformed/oversized/wrong-CID/duplicate/replay, queue-full, invalid/missing/mismatch descriptor, Phase 09 stale token |
| CC-09B-09 | 통과 | `PVM_USER_HOST_PROTOCOL_ALLOWLIST_OK`; Host payload는 HELLO/command/ACK/RESULT만 사용 |
| CC-09B-10 | 통과 | `PVM_BUFFER_HOST_ACCESS_BLOCKED`, `PVM_BUFFER_EL2_DIRECT_OK`; message 구현 source scan에서 socket/Host backend 참조 0건 |
| CC-09B-11 | 통과 | 정상 STOP, Camera/AI/Host 연결 장애, owner/receiver teardown과 timeout revoke 후 `Mlocked: 0 kB` |
| CC-09B-12 | 통과 | 네 최종 로그에 panic/Oops/BUG 0건, `PVM_USER_CHANNEL_VALIDATION_OK` |
| CC-09B-13 | 통과 | 본 문서에 명령, revision, config/artifact digest와 로그 경로 기록 |

## 핵심 marker

```text
PVM_USER_VSOCK_SMOKE_OK
PVM_USER_NEGATIVE_OK
PVM_USER_QUEUE_FULL_OK
PVM_USER_DESCRIPTOR_NEGATIVE_OK
PVM_USER_CAMERA_AI_BUFFER_OK
PVM_USER_CAMERA_AI_METADATA_OK
PVM_USER_CAMERA_AI_JOIN_OK
PVM_USER_AI_HOST_OK
PVM_USER_E2E_OK: frames=10
PVM_USER_E2E_RC: host=0 ai=0 camera=0
PVM_USER_CHANNEL_VALIDATION_OK
PVM_USER_CHANNEL_E2E_OK
PVM_USER_FAULT_RC: host=0 ai=0 camera=0
PVM_USER_CHANNEL_FAULT_OK
PVM_BUFFER_HOST_ACCESS_BLOCKED: role=camera signal=11
PVM_BUFFER_STALE_HANDLE_BLOCKED: role=ai
PVM_BUFFER_TEST_RC=0
PVM_FRAMEWORK_RUN_OK
Mlocked: 0 kB
```

## Revision과 digest

| 항목 | 값 |
|---|---|
| root 기준 commit | `0ec6bf6ab45b90fe21301fc52a57ce205d42ba21` (완료 commit 전 기준) |
| pKVM Linux 완료 commit | `6763e27c1ad0` |
| kvmtool commit | `6866a248977d16bc293c6f4f6609daa4f465b073` |
| kernel Image SHA-256 | `a58cf72f405d1c67266532b4a49bbf17ab5ea834962ea1a6cb84094f93efcdf4` |
| kernel config SHA-256 | `7ef1e6b3d688f516ac9e98730ff65429d42d748bd2a835d59fe639c5898ac77e` |
| lkvm SHA-256 | `9b718dd8c7fe239f3d73eeedffb4de3a0074696451724477ca9d67ce065707c4` |
| pvm_e2e SHA-256 | `3cc9b032787f18128b1475874eafb7923b2129db007e94e62d2d95a8a182ab61` |
| pvm_message.ko SHA-256 | `3eafe10bb5c7fc5f8d2d73786bc32717a8c660d3ae997db4fb641e04a93af693` |
| Host initramfs SHA-256 | `787949376466e4e9e943bd055103b00ab806378973ad1034f041209cd074ef35` |
| guest initramfs SHA-256 | `390dde3aaa76872475b7e62b441c7668f86b8d9805d7ff7eda1356c12079c718` |

최종 로그:

- `work/build/pvm-buffer/console-pvm-vsock-release.log`
- `work/build/pvm-buffer/console-user-channel-e2e-final.log`
- `work/build/pvm-buffer/console-user-channel-fault-final2.log`
- `work/build/pvm-framework/console-phase09b-primitive-final.log`

VSOCK guest 부팅 중 pKVM MMIO guard의 `WARN_ON_ONCE`가 관찰되지만 VSOCK queue 초기화,
왕복, guest 종료와 자원 회수에는 영향을 주지 않았다. 완료 조건이 금지하는 panic/Oops/BUG와
unexpected timeout은 없었다.
