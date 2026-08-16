# Phase 06: OP-TEE 공존

- 상태: 완료
- 목적: Secure World의 OP-TEE와 Normal World의 pKVM이 같은 시스템에서 함께 동작하는지 확인한다.
- 환경: E-2
- 관련 목표: G-6
- 관련 결정: D-5

## 선행 조건

- Phase 02의 pKVM 커널 구성
- Phase 03, 04의 E-1 결과
- QEMU v8, TF-A, OP-TEE 빌드 환경

E-1과 분리된 소스, initramfs, 로그 디렉터리로 E-2를 구성했다.

## E-2 구성

| 구성 요소 | 버전 또는 커밋 |
|---|---|
| QEMU 실행 바이너리 | 8.2.2 (Debian 패키지) |
| OP-TEE 매니페스트 | `qemu_v8.xml`, 태그 4.7.0 |
| OP-TEE build | `dcff191dafb2` |
| TF-A | v2.13-rc0, `842ce6391fec` |
| OP-TEE OS | 4.7.0, `86846f4fdf14` |
| OP-TEE client/test/examples | `23c112a6f05c` / `a15be9eca1b7` / `14321a0607db` |
| U-Boot | v2025.07-rc1, `b249e08ec9b7` |
| Normal World Linux | Phase 02 pKVM, `281fa709853a` |
| CPU/메모리 | `cortex-a57`, 4 vCPU, 3 GiB |

`qemu_v8`은 Armv8 보드 프로필 이름이다. OP-TEE 4.7.0 매니페스트가 소스로 고정하는 QEMU는
v10.0.0이지만, E-2 실행은 Phase 요구사항에 맞춰 호스트의 QEMU 8.2.2로 수행했다.

Secure World는 두 번째 PL011을 `secure-optee.log`로, TF-A/U-Boot/Linux의 첫 번째 PL011은
`console-optee-pkvm.log`로 분리했다. `secure=on,virtualization=on`과 TF-A의 OPTEED 경로를
사용했고, `cortex-a57`로 VHE를 노출하지 않아 protected nVHE를 선택했다.

## 구현 및 실행

- `bootstrap.sh`: OP-TEE 4.7.0 매니페스트 동기화
- `build.sh`: 로컬 툴체인, OP-TEE OS, U-Boot, Buildroot, TF-A/FIP 빌드
- `mkrootfs.sh`: OP-TEE rootfs에 pKVM selftest와 공존 오케스트레이터 주입
- `coexist-test.sh`: KVM FD 장벽, AES TA와 pVM 동시 재개, 재호출 및 회수 검사
- `run.sh`: E-2 부팅, UART 분리 수집, 성공 마커 판정

```bash
work/src/tools/optee-pkvm/bootstrap.sh
work/src/tools/optee-pkvm/build.sh
work/src/tools/optee-pkvm/mkrootfs.sh
work/src/tools/optee-pkvm/run.sh
```

Buildroot target 디렉터리는 fakeroot 적용 전이므로 `/init`에서 devtmpfs를 먼저 마운트한다.
또한 최종 cpio에만 추가되는 `tee` 계정에 의존하지 않도록 검증 전용 initramfs에서는 root로
`tee-supplicant`를 기동한다. 제품 권한 모델을 뜻하지 않으며 이 Phase의 서비스 호출 검증에만
사용한다.

## 동시성 및 암복호화 절차

1. 정적 pKVM selftest를 시작하고 `/dev/kvm`, VM, vCPU에 해당하는 KVM FD 3개를 확인한다.
2. selftest에 `SIGSTOP` 장벽을 걸고 AES TA client를 시작한다.
3. pVM과 TA client를 함께 재개한다.
4. AES TA가 4 KiB 카메라 프레임 모사 버퍼를 AES-CTR로 암호화한 뒤 같은 세션에서 복호화한다.
5. pVM의 regular/THP 검사를 완료하고 private memory를 회수한다.
6. 새 TA 세션을 열어 암복호화를 다시 수행하고 OP-TEE 호출 경로의 재사용을 확인한다.

## 완료 조건

- TF-A, OP-TEE, Linux와 pKVM 초기화 로그가 한 실행에서 확인되어야 한다.
- OP-TEE TA 호출과 pVM 게스트 실행이 모두 성공해야 한다.
- 암호화한 데이터를 같은 세션에서 복호화해 원본과 일치함을 확인해야 한다.
- 한쪽 작업이 다른 실행 환경을 중단시키지 않아야 한다.

## 결과

2026-08-16 실행에서 QEMU rc=0과 `OPTEE_PKVM_VALIDATION_OK`를 확인했다.

| 검사 | 결과 및 마커 |
|---|---|
| TF-A 부팅 | `NOTICE: Booting Trusted Firmware` |
| Secure World | `I/TC: OP-TEE version: 4.7.0` |
| Linux OP-TEE | `optee: initialized driver` |
| pKVM | `Protected nVHE mode initialized successfully` |
| 동시 KVM 객체 | `COEX_KVM_ACTIVE: pid=<pid> kvm_fds=3` |
| 실행 중 TA 호출 | `COEX_AES_DURING_PVM_OK` |
| 암복호화 일치 | `Clear text and decoded text match` |
| pVM 완료 | `All ok!`, `COEX_PVM_OK: rc=0` |
| TA 재개방 | `COEX_AES_REOPEN_OK` |
| 자원 회수 | `Host VmLck after teardown: 0`, `Mlocked: 0 kB` |
| 최종 판정 | `OPTEE_PKVM_COEX_ALL_OK`, QEMU rc=0 |

AES 예제는 4 KiB 입력을 Secure World TA에서 AES-CTR로 암호화/복호화하고 `memcmp()`로 원본
일치를 판정한다. 이 마커는 pVM 실행 중 한 번, pVM 종료 후 새 세션에서 한 번 확인됐다.

## 산출물

- 공식 소스 체크아웃: `work/src/optee-pkvm/`
- 재현 도구: `work/src/tools/optee-pkvm/`
- 통합 rootfs: `work/build/optee-pkvm/rootfs-optee-pkvm.cpio.gz`
- Normal World 로그: `work/build/optee-pkvm/console-optee-pkvm.log`
- Secure World 로그: `work/build/optee-pkvm/secure-optee.log`

## 한계

이 Phase는 공존과 서비스 호출 성립만 확인한다. 키 관리, 비밀 프로비저닝, 암호화 저장
파이프라인은 범위 밖이다.

QEMU 8.2.2 기반 결과이므로 실제 하드웨어의 Secure World 동작을 대신하지 않는다.

pVM 내부에서 OP-TEE를 직접 호출하는 경로는 다루지 않는다. pVM 실행 중 Host 측 OP-TEE
호출이 성립하는지까지만 확인한다.

동시성 증빙은 TA client를 시작한 뒤 정지해 둔 pVM을 재개하고, KVM FD 3개와 양쪽 완료
마커를 결합한 기능 증빙이다. 명령 단위 실행 시간을 계측하거나 성능상 병렬성을 주장하지 않는다.
