# Phase 07 검증 결과

- 판정: 완료
- 검증일: 2026-08-20 (Asia/Seoul)
- 환경: E-1 QEMU(TCG), Phase 02 kernel Image / Phase 04·05 산출물 재사용, C VM 관리
  프레임워크(`work/src/tools/pvm-framework`)
- 검증 스크립트: `work/src/tools/verify/phase07.sh`

## 재현 명령

```bash
work/src/tools/pvm-framework/verify-static.sh
work/src/tools/pvm-framework/mkinitramfs.sh
work/src/tools/pvm-framework/run.sh work/build/pvm-framework/console-pvm-framework-final.log 900
```

`verify-static.sh`는 C 바이너리/guest workload/guest image를 빌드하고, backend에서
KVM ioctl 참조가 daemon private 링크 맵에만 존재하는지(runner 프로세스만 KVM에
직접 접근) 소스 스캔으로 확인한다.

### 이 Phase에서 해결한 문제

이후 Phase 08(장치 할당) 작업이 `pvm_kvm_arm64.c`/`phase07_guest.S`에 edu 장치
가정을 하드코딩하면서, edu 장치가 없는 순수 Phase 07 재현 경로에서 회귀가
발생했다. `edu_device_present()`로 장치 유무를 확인해 없으면
`PVM_DEVICE_ASSIGN_SKIPPED`를 출력하도록 backend를 고치고, guest 쪽에도 장치
미할당 시 post-revoke DMA 검증을 건너뛰는 guard를 추가했다.

## 완료 조건 결과 (docs/phase-07/README.md CC-01~CC-15 기준)

| CC | 결과 |
|---|---|
| CC-01~CC-04 설계/build/KVM 경계 | 통과 — arm64 정적 바이너리 생성, KVM 참조는 runner private backend link map에만 존재 |
| CC-05~CC-08 artifact/무결성/실행 | 통과 — `PVM_FRAMEWORK_WORKLOAD_VERIFIED`(sha256) 4건, `PVM_FRAMEWORK_WORKLOAD_REJECTED`(변조 거부) |
| CC-09~CC-10 API/인증/policy | 통과 — `PVM_FRAMEWORK_PROTOCOL_NEGATIVE_OK`, `PVM_FRAMEWORK_AUTH_TEST_OK`, `PVM_FRAMEWORK_POLICY_TEST_OK`, `PVM_FRAMEWORK_IMAGE_REJECTION_OK` |
| CC-11 다중 pVM | 통과 — `PVM_FRAMEWORK_OVERLAP: camera_pid=85 camera_resources=6 ai_pid=86 ai_resources=6` |
| CC-12 장애 격리 | 통과 — `PVM_FRAMEWORK_FAULT_ISOLATION_OK` |
| CC-13 회수 | 통과 — `PVM_FRAMEWORK_RESOURCE_RECOVERY_OK`, `Mlocked: 0 kB` |
| CC-14 E-1 runtime | 통과 — `PVM_FRAMEWORK_VALIDATION_OK`, QEMU rc=0 |
| CC-15 재현성 | 통과 — 본 문서에 명령/revision/로그 경로 기록 |
| panic/Oops/BUG 없음 | 통과 |

## 핵심 marker

```text
PVM_FRAMEWORK_WORKLOAD_VERIFIED: sha256=...
PVM_FRAMEWORK_WORKLOAD_REJECTED
PVM_FRAMEWORK_PROTOCOL_NEGATIVE_OK
PVM_FRAMEWORK_AUTH_TEST_OK
PVM_FRAMEWORK_POLICY_TEST_OK
PVM_FRAMEWORK_IMAGE_REJECTION_OK: kvm_fds=0
PVM_FRAMEWORK_NORMAL_LIFECYCLE_OK
PVM_FRAMEWORK_DAEMON_RECOVERY_OK
PVM_FRAMEWORK_OVERLAP: camera_pid=85 camera_resources=6 ai_pid=86 ai_resources=6
PVM_FRAMEWORK_FAULT_ISOLATION_OK
PVM_FRAMEWORK_RESOURCE_RECOVERY_OK
PVM_FRAMEWORK_VALIDATION_OK
```

## Revision과 digest

Phase 02와 동일한 `pkvm-linux` revision(`7034ea6fc1e0`)의 kernel Image를 재사용했다.

최종 로그: `work/build/pvm-framework/console-pvm-framework-final.log`

Phase 08은 이 Phase의 pVM 수명주기 관리 경로(생성/실행/정지/삭제, 장애 격리)를
장치 할당 시나리오에 그대로 확장해서 재사용한다.
