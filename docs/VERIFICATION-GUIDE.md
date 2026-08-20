# Phase 02~10 통합 검증 가이드

- 대상: 이 저장소(`poc-reproduce`)를 처음 받아 Phase 02부터 10까지 순서대로
  재현하려는 개발자
- 이 문서는 Phase별 문서(`docs/phase-{nn}/README.md`, `VERIFICATION.md`)를
  대체하지 않는다. 처음부터 끝까지 막힘없이 진행하기 위한 진입점이다.
- 구축 배경과 원칙은 [통합 검증 환경 구축 계획](VERIFICATION-INTEGRATION-PLAN.md)에
  있다. 핵심 원칙만 요약하면: **이 저장소 안에서 실제로 빌드/실행한 산출물만
  사용하고, `../poc-p`는 문제 해결 시 읽기 전용 참고 자료로만 쓴다.**

## 1. 무엇을 실행하는가

`work/src/tools/verify/`에 Phase마다 하나씩 있는 `phaseNN.sh`는 각 Phase가
이미 갖고 있는 도구(`work/src/tools/qemu`, `pvm`, `multi-pvm`, `optee-pkvm`,
`pvm-framework`, `pvm-buffer`, `vision-pipeline` 등)를 순서대로 호출하는
얇은 wrapper다. 새 빌드 로직은 없다 — 각 Phase 문서가 정의한 완료 조건과 marker를
그대로 이 저장소 산출물에 대고 검사할 뿐이다.

```text
work/src/tools/verify/
├── lib.sh        공통 함수(로그 확인, marker 검사, 완료 marker 기록/재사용)
├── phase02.sh ~ phase10.sh   Phase별 wrapper (06-b는 phase06b.sh, 09-b는 phase09b.sh)
└── run-all.sh    02→10 순차 실행, 이미 완료된 Phase는 건너뜀
```

각 `phaseNN.sh`는 성공하면 `work/build/verify/phase-{nn}/DONE` marker 파일을
남긴다. 다음 Phase는 `require_prev_phase`로 이 marker를 확인한 뒤에만 시작하므로,
Phase 순서를 건너뛰면 명확한 오류로 즉시 중단된다.

## 2. 사전 준비

README의 [권장 Host 환경](../README.md#1-권장-host-환경)과
[package 설치 명령](../README.md#1-권장-host-환경)을 먼저 따른다. 요약:

- Ubuntu 24.04 LTS 계열 x86-64, RAM 8 GiB 이상, 빈 디스크 50 GiB 이상
- `git submodule update --init --filter=blob:none`로 5개 submodule
  (`pkvm-linux`, `dtc`, `kvmtool`, `qemu-phase08`, `optee-pkvm/u-boot`) 초기화
- clang-18/lld-18, `gcc-9-aarch64-linux-gnu` 계열 arm64 cross toolchain,
  `qemu-system-arm`, python3-venv, ffmpeg 등 README 2절의 package 목록

`git submodule status`의 첫 글자가 `-`/`+`/`U`이면 아래 단계를 시작하지 않는다.

## 3. 전체 실행

```bash
work/src/tools/verify/run-all.sh
```

- 이미 완료 marker가 있는 Phase는 다시 빌드하지 않고 건너뛴다(산출물 재사용).
- 특정 Phase만 다시 실행하려면 `FORCE=1 work/src/tools/verify/run-all.sh --only 08`
- 특정 Phase부터 이어서 실행하려면 `work/src/tools/verify/run-all.sh --from 06`
- 개별 Phase만 실행하려면 `work/src/tools/verify/phase08.sh`처럼 직접 호출해도 된다.

커널/OP-TEE 빌드와 E-3 QEMU 빌드에 각각 수십 분이 걸릴 수 있다. 백그라운드 실행 후
로그를 tail하는 방식을 권장한다.

## 4. Phase 순서와 문서

| Phase | 스크립트 | 검증 결과 문서 | 이 Phase가 재사용하는 이전 산출물 |
|---|---|---|---|
| 02 소스 통합/커널 빌드 | `phase02.sh` | [phase-02/VERIFICATION.md](phase-02/VERIFICATION.md) | 없음 |
| 03 protected 부팅 | `phase03.sh` | [phase-03/VERIFICATION.md](phase-03/VERIFICATION.md) | Phase 02 kernel Image |
| 04 단일 pVM | `phase04.sh` | [phase-04/VERIFICATION.md](phase-04/VERIFICATION.md) | Phase 02 kernel Image |
| 05 다중 pVM | `phase05.sh` | [phase-05/VERIFICATION.md](phase-05/VERIFICATION.md) | Phase 02, 04 산출물 |
| 06 OP-TEE 공존(E-2) | `phase06.sh` | [phase-06/VERIFICATION.md](phase-06/VERIFICATION.md) | Phase 02 kernel Image |
| 06-B pVM 내부 TA 호출 | `phase06b.sh` | [phase-06-b/VERIFICATION.md](phase-06-b/VERIFICATION.md) | Phase 04, 06 산출물 |
| 07 동적 수명주기 | `phase07.sh` | [phase-07/VERIFICATION.md](phase-07/VERIFICATION.md) | Phase 02, 04, 05 산출물 |
| 08 장치 할당/DMA 격리(E-3) | `phase08.sh` | [phase-08/VERIFICATION.md](phase-08/VERIFICATION.md) | Phase 05, 07 산출물 |
| 09 EL2 DMA-BUF | `phase09.sh` | [phase-09/VERIFICATION.md](phase-09/VERIFICATION.md) | Phase 08 E-3 QEMU/커널 설정 |
| 09-B 사용자 공간 end-to-end | `phase09b.sh` | [phase-09-b/VERIFICATION.md](phase-09-b/VERIFICATION.md) | Phase 08, 09 산출물 |
| 10 Reference Scenario | `phase10.sh` | [phase-10/VERIFICATION.md](phase-10/VERIFICATION.md) | Phase 08, 09, 09-B 산출물 |

## 5. 실패했을 때

1. 먼저 `work/src/tools/verify/phaseNN.sh`가 출력한 로그와, 위 표가 가리키는
   `console-*.log` 파일을 이 저장소 안에서 직접 읽고 원인을 분석한다.
2. 원인을 못 찾겠으면 `../poc-p`의 동일 Phase 문서/스크립트를 **읽기 전용**으로
   참고해 방향만 잡는다. `../poc-p`의 파일을 복사하거나 symlink로 가져오지 않는다.
3. 원인을 찾으면 이 저장소의 소스/도구/문서에 직접 수정한다.
4. 같은 `phaseNN.sh`를 다시 실행해 완료 marker가 갱신되는지 확인한다.

### 이번 재현에서 실제로 만난 문제와 조치

- **QEMU 기본 CPU가 hVHE를 노출**: 호스트 QEMU 8.x 이상은 `CPU=max` 기본값에서
  `Protected hVHE mode initialized successfully`를 출력해 nVHE marker 검사가
  실패한다. Phase 03/04는 `CPU=cortex-a57`로 nVHE 경로를 강제한다.
  ([phase-03](phase-03/VERIFICATION.md), [phase-04](phase-04/VERIFICATION.md))
- **FF-A 협상 selftest가 Secure Monitor 부재 환경에서 assert**: Phase 06-B 이후
  공유 selftest 코드(`tools/testing/selftests/kvm/arm64/pkvm.c`)가 FF-A 협상을
  무조건 요구하게 되어 Phase 04/05/07/09가 막혔다. `pkvm-linux` submodule에서
  Secure Monitor가 없는 환경을 허용하도록 완화했다.
- **`do_ffa_mem_reclaim`의 `spm_handles` pool 고갈**: Phase 06에서 가장 깊게 판
  결함. SPMC의 reclaim 응답이 `FFA_SUCCESS`가 아니어도 host-local bookkeeping은
  항상 해제하도록 `arch/arm64/kvm/hyp/nvhe/ffa.c`를 수정했다. 자세한 배경은
  [phase-06/VERIFICATION.md](phase-06/VERIFICATION.md) 참고.
- **U-Boot `hostfs` semihosting이 symlink를 신뢰할 수 없게 따라감**: Phase 06-B의
  TF-A+U-Boot 부팅 경로는 QEMU의 `-kernel`/`-initrd`를 무시하고 작업 디렉터리의
  `uImage`/`rootfs.cpio.uboot`를 U-Boot의 `CONFIG_BOOTCOMMAND`로 읽는다. symlink는
  이전 실행이 남긴 stale 파일을 계속 가리키는 사례가 있어 `cp -f`로 바꿨다.
- **`vfio-platform`이 QEMU edu 장치의 reset 콜백 부재로 probe 실패**: Phase 08은
  `vfio_platform.reset_required=0`으로 이 요구를 끈다.
- **wrapper 스크립트의 자체 성공 marker가 로그 파일이 아닌 자신의 stdout에만
  출력됨**: `run-vsock-smoke.sh`, `run-user-channel-e2e.sh`,
  `run-vision-pipeline.sh` 등은 `..._OK` 요약을 자신의 stdout으로만 출력하고
  로그 파일에는 쓰지 않는다. `phaseNN.sh`의 `check_markers`가 이 문자열을 로그
  파일에서 찾으면 항상 실패하므로, `set -eu` 하에서 wrapper가 이미 실패 시
  종료한다는 점을 이용해 로그 파일에 실제로 기록되는 marker만 검사하도록
  `phase09b.sh`/`phase10.sh`를 고쳤다.
- **무거운 E-3 QEMU 프로세스 종료 직후 로컬 유닛 테스트의 짧은 타임아웃이
  간헐적으로 초과됨**: `phase10.sh`가 vision pipeline/fault QEMU 실행 직후 곧바로
  `pvm-user-channel`의 `protocol_test`(1000ms 수신 타임아웃)를 재실행하면
  시스템 자원 정리 지연으로 가끔 실패했다. 재실행 전 5초 대기를 추가했다.

## 6. 재현 완료 확인

```bash
for p in 02 03 04 05 06 06b 07 08 09 09b 10; do
  test -f "work/build/verify/phase-${p}/DONE" && echo "phase-${p}: OK" || echo "phase-${p}: MISSING"
done
```

11개 모두 `OK`이면 Phase 02~10 전체 완료 조건이 이 저장소 산출물로 재현된 것이다.
최종 Reference Scenario 판정 기준은 [Phase 11 최종 결과](phase-11/RESULT.md)를 따른다.
