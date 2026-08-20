# Phase 06 검증 결과

- 판정: 완료
- 검증일: 2026-08-20 (Asia/Seoul)
- 환경: E-2 QEMU(TF-A BL1 부팅, `secure=on,virtualization=on`), OP-TEE 4.7.0
  (`CFG_CORE_SEL1_SPMC=1`, `CFG_NS_VIRTUALIZATION=y`, `CFG_DYN_CONFIG=y`)
- 검증 스크립트: `work/src/tools/verify/phase06.sh`

## 재현 명령

```bash
work/src/pkvm-linux/scripts/config --file work/build/pkvm-full-clang/.config -e ARM_FFA_TRANSPORT
make -C work/src/pkvm-linux O=work/build/pkvm-full-clang ARCH=arm64 LLVM=1 \
  CC=clang-18 LD=ld.lld-18 olddefconfig
make -C work/src/pkvm-linux O=work/build/pkvm-full-clang ARCH=arm64 LLVM=1 \
  CC=clang-18 LD=ld.lld-18 -j"$(nproc)" Image
work/src/tools/optee-pkvm/bootstrap.sh
work/src/tools/optee-pkvm/build.sh
TOOLCHAIN=work/src/optee-pkvm/toolchains/aarch64/bin/aarch64-linux-gnu- \
  work/src/tools/optee-pkvm-guest/build-kvmtool.sh
work/src/tools/optee-pkvm-guest/mkrootfs.sh
work/src/tools/optee-pkvm/mkrootfs.sh
work/src/tools/optee-pkvm/run.sh
```

Host Linux의 `optee` 드라이버가 FF-A로 SPMC를 찾으려면 `CONFIG_ARM_FFA_TRANSPORT`가
필요하다. Phase 02의 base defconfig는 이 옵션을 켜지 않으므로 이 Phase에서 활성화하고
Image를 다시 빌드한다(증분 빌드).

### 이 Phase에서 해결한 문제

가장 깊게 파고든 결함은 `arch/arm64/kvm/hyp/nvhe/ffa.c`의
`do_ffa_mem_reclaim()`이었다. SPMC의 reclaim 응답이 `FFA_SUCCESS`가 아니면
`ffa_host_unshare_ranges()`/`ffa_host_clear_handle()`을 건너뛰고 바로
`out_unlock`으로 빠져나가, `spm_handles` pool이 점진적으로 고갈되는 상태 누수가
있었다. Host-local bookkeeping은 SPMC 응답과 무관하게 항상 해제하도록 고쳤다.
그 외에 `kvm_host_ffa_signal_availability()`의 오류 코드 산출 오류,
`optee_os`의 `virt_guest_created()`/`HYP_CLNT_ID` 충돌 처리(원 저장소 커밋
`c6bda5d`에 이미 반영된 조건부 완화 로직으로 원복)도 함께 확인했다.
`tools/testing/selftests/kvm/arm64/pkvm.c`의 FF-A 협상 assert도 Secure Monitor가
없는 환경을 허용하도록 완화했다(`pkvm-linux` submodule, revision
`7034ea6fc1e0`).

## 완료 조건 결과 (docs/phase-06/README.md 기준)

| 조건 | 결과 |
|---|---|
| TF-A/OP-TEE/Linux/pKVM 초기화 로그가 한 실행에서 확인 | 통과 |
| OP-TEE TA 호출과 pVM 게스트 실행 모두 성공 | 통과 |
| 암호화 데이터를 같은 세션에서 복호화해 원본과 일치 | 통과 — `Clear text and decoded text match` |
| 한쪽 작업이 다른 실행 환경을 중단시키지 않음 | 통과 — pVM 실행 중/후 AES 재오픈 모두 성공 |
| panic/Oops/BUG 없음 | 통과 |

## 핵심 marker

```text
NOTICE:  Booting Trusted Firmware
I/TC: OP-TEE version: 4.7.0-dev ...
[    2.720672] optee: initialized driver
[    0.730921] kvm [1]: Protected nVHE mode initialized successfully
COEX_KVM_ACTIVE: pid=126 kvm_fds=6
Clear text and decoded text match
COEX_AES_DURING_PVM_OK
Host VmLck after teardown: 0
All ok!
COEX_PVM_OK: rc=0
COEX_AES_REOPEN_OK
Mlocked:               0 kB
OPTEE_PKVM_COEX_ALL_OK
```

## Revision과 digest

| 항목 | 값 |
|---|---|
| `pkvm-linux` submodule revision | `7034ea6fc1e0b031127130666a7d1d8990dc84d1` |
| `kvmtool` submodule revision | `6866a248977d16bc293c6f4f6609daa4f465b073` (boram1288/phase07-kvmtool) |
| OP-TEE version | `4.7.0-dev` |

최종 로그: `work/build/optee-pkvm/console-optee-pkvm.log`(Normal World),
`work/build/optee-pkvm/secure-optee.log`(Secure World)

Phase 06-B는 이 Phase의 OP-TEE/TF-A/U-Boot/Buildroot 빌드 산출물과 arm64 kvmtool,
guest rootfs를 그대로 재사용한다.
