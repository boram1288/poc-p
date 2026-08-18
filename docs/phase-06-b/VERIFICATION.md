# Phase 06-B 수동 검증 및 결과 확인

이 문서는 Trusted Access 전용 기능을 사용하지 않고, protected Linux pVM의 표준
OP-TEE client/TA 경로를 수동으로 재현하는 절차다. 모든 명령은 저장소 루트에서
실행한다.

## 1. 사전 조건

필요한 산출물은 다음과 같다.

- Clang 기준 커널: `work/build/pkvm-full-clang/arch/arm64/boot/Image`
- OP-TEE/pKVM 실행 이미지: `work/build/optee-pkvm/`
- guest rootfs: `work/build/optee-pkvm-guest/rootfs-optee-pkvm-guest.cpio.gz`
- protected-FFA VMM: `work/src/kvmtool/lkvm`
- pKVM selftest: `work/build/pkvm-pvm/kselftest-build/arm64/pkvm`

`pkvm-full-gcc`는 사용하지 않는다. GCC 교차 검증 산출물을 삭제한 상태가 정상이다.

## 2. 필요 시 산출물 재생성

```bash
work/src/tools/optee-pkvm/build.sh
work/src/tools/optee-pkvm-guest/build-kvmtool.sh
work/src/tools/optee-pkvm-guest/mkrootfs.sh
work/src/tools/optee-pkvm/mkrootfs.sh
```

OP-TEE 빌드 후에는 `mkrootfs.sh` 두 개를 다시 실행한다. 마지막 스크립트가 Host
rootfs에 guest Image, guest rootfs, `lkvm`을 포함한다.

## 3. 전체 수동 검증 실행

```bash
SECURE_LOG=work/build/optee-pkvm/secure-manual.log \
  work/src/tools/optee-pkvm/run.sh \
  work/build/optee-pkvm/console-manual.log 1800
```

QEMU가 종료되면 반환 코드와 marker를 확인한다.

```bash
grep -E 'OPTEE_PKVM_VALIDATION_(OK|FAILED)|OPTEE_PKVM_INIT_RC' \
  work/build/optee-pkvm/console-manual.log

grep -E 'PVM_LINUX_BOOT_OK|PVM_OPTEE_PROBE_OK|PVM_TA_AES_4K_OK|\
PVM_FFA_NEGATIVE_OK|COEX_TWO_PVM_ISOLATION_OK|COEX_PVM_LINUX_TA_OK|\
COEX_AES_DURING_PVM_OK|COEX_AES_REOPEN_OK|Mlocked:' \
  work/build/optee-pkvm/console-manual.log
```

## 4. 성공 판정

### 스크립트 없이 단계별 실행

`run.sh`를 생략할 때는 QEMU를 직접 실행한다.

```bash
cd work/src/optee-pkvm/out/bin
timeout --signal=KILL 1800 qemu-system-aarch64 \
  -machine virt,acpi=off,secure=on,virtualization=on,gic-version=3 \
  -cpu cortex-a57 -smp 4 -m 3G -nographic -nic none -no-reboot \
  -semihosting-config enable=on,target=native -bios bl1.bin \
  -kernel ../../../../build/pkvm-full-clang/arch/arm64/boot/Image \
  -initrd ../../../../build/optee-pkvm/rootfs-optee-pkvm.cpio.gz \
  -append 'console=ttyAMA0,38400 keep_bootcon kvm-arm.mode=protected' \
  -serial mon:stdio -serial file:../../../../build/optee-pkvm/secure-manual.log \
  >../../../../build/optee-pkvm/console-manual.log 2>&1
cd - >/dev/null
```

`coexist-test.sh`의 Host 단계를 수동으로 재현한다.

```bash
chmod 0600 /dev/tee0 /dev/teepriv0
/usr/sbin/tee-supplicant -d /dev/teepriv0
/usr/bin/pkvm >/tmp/pkvm-manual.log 2>&1 & pkvm_pid=$!
sleep 1
ls -l /proc/${pkvm_pid}/fd | grep -E 'kvm|/dev/kvm'
/usr/bin/optee_example_aes >/tmp/aes-during-manual.log 2>&1 & aes_pid=$!
wait ${aes_pid}; grep -q 'Clear text and decoded text match' /tmp/aes-during-manual.log
wait ${pkvm_pid}; grep -q 'All ok!' /tmp/pkvm-manual.log
/usr/bin/optee_example_aes >/tmp/aes-after-manual.log 2>&1
grep -q 'Clear text and decoded text match' /tmp/aes-after-manual.log
```

guest rootfs 내부에서는 `/init`의 각 단계를 직접 실행할 수 있다.

```sh
mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev
echo PVM_LINUX_BOOT_OK
test -e /dev/teepriv0
chmod 0600 /dev/tee0 /dev/teepriv0
/usr/sbin/tee-supplicant -d /dev/teepriv0
echo PVM_OPTEE_PROBE_OK
/usr/bin/optee_example_aes
test $? -eq 0 && echo 'PVM_TA_AES_4K_OK: bytes=4096 encrypt=ok decrypt=ok compare=ok'
```

두 pVM 분리는 `lkvm run --protected --protected-ffa`를 `--name optee-pvm-a`와
`--name optee-pvm-b`로 각각 background 실행한 뒤 두 로그에서
`PVM_TA_AES_4K_OK`를 확인한다. 두 프로세스가 모두 0으로 종료되면
`COEX_TWO_PVM_ISOLATION_OK: independent_endpoints=2 independent_sessions=2`로 기록한다.

`PVM_FFA_NEGATIVE_OK: bad_rxtx bad_share bad_endpoint`는 selftest가 수행하는 오류
경계 시험이므로, 수동 확인 시 selftest 로그에서 세 항목을 모두 확인한다.

다음 marker가 모두 있어야 한다.

| 영역 | 성공 marker |
|---|---|
| protected pVM 실행 | `COEX_KVM_ACTIVE` |
| Host 동시 AES | `COEX_AES_DURING_PVM_OK` |
| 최소 pVM FF-A | `PVM_FFA_MINIMAL_OK` |
| 잘못된 FF-A 요청 거부 | `PVM_FFA_NEGATIVE_OK: bad_rxtx bad_share bad_endpoint` |
| private page 접근 차단 | `Caught expected segfault` |
| pVM teardown | `COEX_PVM_OK: rc=0` |
| Host AES 재호출 | `COEX_AES_REOPEN_OK` |
| guest Linux 부팅 | `PVM_LINUX_BOOT_OK` |
| guest OP-TEE probe | `PVM_OPTEE_PROBE_OK` |
| guest 4 KiB TA 호출 | `PVM_TA_AES_4K_OK: bytes=4096 encrypt=ok decrypt=ok compare=ok` |
| 두 pVM endpoint/session 분리 | `COEX_TWO_PVM_ISOLATION_OK: independent_endpoints=2 independent_sessions=2` |
| 메모리 회수 | `Mlocked:               0 kB` |
| 전체 판정 | `OPTEE_PKVM_VALIDATION_OK`, `OPTEE_PKVM_INIT_RC=0` |

Secure log에서는 다음을 추가로 확인한다.

```bash
grep -E 'Added guest|Removing guest|OP-TEE version' \
  work/build/optee-pkvm/secure-manual.log
```

각 pVM endpoint가 `Added guest`와 `Removing guest` 쌍을 가져야 하며, 정상 종료 시
QEMU panic/EL2 `BRK`가 없어야 한다.

## 5. 실패 시 분류

- `COEX_KVM_ACTIVE_FAILED`: pKVM selftest가 KVM fd를 만들지 못한 경우다. 커널 Image,
  `/dev/kvm`, protected capability를 확인한다.
- `PVM_OPTEE_DEVICE_FAILED`: guest DT/FF-A/OP-TEE probe 문제다. guest console에서
  `ARM FF-A`와 `optee: initialized driver`를 확인한다.
- `PVM_TA_AES_FAILED`: guest `tee-supplicant`, TA 파일, `/dev/teepriv0`를 확인한다.
- `COEX_AES_DURING_PVM_FAILED` 또는 `mem_reclaim: -22`: Host endpoint 0 reclaim과
  FF-A handle 상태를 secure log에서 확인한다.
- `COEX_TWO_PVM_ISOLATION_FAILED`: 두 VMM 로그(`/tmp/optee-pvm-a.log`,
  `/tmp/optee-pvm-b.log`)를 각각 확인한다.
- `OPTEE_PKVM_VALIDATION_FAILED`: 위 marker 중 누락된 첫 항목부터 역순이 아니라
  실행 순서대로 조사한다.

## 6. 수동 결과 기록 양식

```text
Date:
Kernel Image:
Console log:
Secure log:
OPTEE_PKVM_VALIDATION_OK: yes/no
PVM_TA_AES_4K_OK: yes/no
PVM_FFA_NEGATIVE_OK: yes/no
COEX_TWO_PVM_ISOLATION_OK: yes/no
Mlocked: ____ kB
Notes:
```
