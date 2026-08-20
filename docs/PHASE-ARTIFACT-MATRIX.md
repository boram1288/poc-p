# Phase별 사용 이미지/바이너리 매트릭스

- 작성일: 2026-08-20
- 범위: Phase 02~10 (06-B, 09-B 포함), 이 저장소(`poc-reproduce`) 안에서 실제로
  빌드/실행해 확인한 산출물만 기록한다.
- 근거: `work/src/tools/verify/phase*.sh`와 각 Phase 도구 스크립트
  (`work/src/tools/{qemu,pvm,multi-pvm,optee-pkvm,optee-pkvm-guest,pvm-framework,
  pvm-buffer,pvm-user-channel,vision-pipeline}`)
- kernel Image는 모든 Phase가 Phase 02가 빌드한 `work/build/pkvm-full-clang`
  하나를 재사용한다. Phase 06/08은 이 트리를 추가 Kconfig로 재구성한 뒤 같은
  경로에 다시 빌드한다(별도 트리를 두지 않음).

| Phase | qemu | optee | host kernel | host rootfs | guest kernel | guest rootfs | host apps | guest workloads | libs(framework) | scripts(tools) |
|---|---|---|---|---|---|---|---|---|---|---|
| 02 소스 통합/커널 빌드 | 미사용(빌드만) | 미사용 | `pkvm-full-clang/arch/arm64/boot/Image`, `vmlinux` (신규 빌드) | 없음 | 없음 | 없음 | 없음 | 없음 | 없음(커널 모듈 `pkvm_smc.ko`, `pkvm_iommu_temp.ko`만 생성) | `verify/phase02.sh` |
| 03 protected 부팅 | Host apt `qemu-system-aarch64` (E-1, `CPU=cortex-a57`) | 미사용 | Phase 02 Image 재사용 | `pkvm-qemu/initramfs.cpio.gz` (정적 BusyBox) | 없음(pVM 미생성) | 없음 | BusyBox init 스크립트(마커 출력)뿐 | 없음 | 없음 | `qemu/run.sh`, `qemu/mkinitramfs.sh`, `verify/phase03.sh` |
| 04 단일 pVM | Host apt `qemu-system-aarch64` (E-1, `CPU=cortex-a57`) | 미사용 | Phase 02 Image 재사용 | `pkvm-pvm/initramfs-pvm.cpio.gz` (BusyBox + capcheck/hello_el2/pkvm) | 없음(별도 이미지 아님) | 없음(selftest 내장 guest payload) | `capcheck`, `hello_el2`, `pkvm` (kernel selftest, arm64 정적 빌드) | pkvm selftest 내장 protected VM guest 코드(파일 없음) | kernel `tools/testing/selftests/kvm/lib` (kselftest 공용 lib, 정적 링크) | `pvm/build-selftest.sh`, `pvm/mkinitramfs.sh`, `pvm/run-pvm.sh`, `verify/phase04.sh` |
| 05 다중 pVM | Host apt `qemu-system-aarch64` (E-1, `CPU=cortex-a57`) | 미사용 | Phase 02 Image 재사용 | `multi-pvm/initramfs-multi-pvm.cpio.gz` (BusyBox + pkvm selftest + `run-two-pvms.sh`) | 없음(Phase 04와 동일) | 없음 | `run-two-pvms.sh` (Camera/AI 역할로 `pkvm` selftest 2회 구동) | pkvm selftest 내장 payload를 Camera/AI 역할 2 instance로 실행 | Phase 04와 동일 kselftest lib | `multi-pvm/run.sh`, `multi-pvm/mkinitramfs.sh`, `multi-pvm/run-two-pvms.sh`, `verify/phase05.sh` |
| 06 OP-TEE 공존(E-2) | Host apt `qemu-system-aarch64` (E-2, `secure=on,virtualization=on`, TF-A BL1 부팅, `CPU=cortex-a57`) | OP-TEE 4.7.0-dev, `SPMC_AT_EL=1`(S-EL1 SPMC), `CFG_NS_VIRTUALIZATION=y`, `CFG_VIRT_GUEST_COUNT=3` | Phase 02 Image + `CONFIG_ARM_FFA_TRANSPORT=y` 재구성 후 재빌드 | `optee-pkvm/rootfs-optee-pkvm.cpio.gz` (Buildroot target + `pkvm`/`lkvm`/`coexist-test.sh` 주입) | 같은 Image를 `lkvm --protected-ffa`로 nested Linux pVM에 재사용(`/opt/pvm/Image`) | `optee-pkvm-guest/rootfs-optee-pkvm-guest.cpio.gz` (Buildroot target + guest `init.sh`, `optee_example_aes`) | `pkvm` selftest, `lkvm`(kvmtool), `coexist-test.sh`, `tee-supplicant`, `optee_example_aes`(Host) | `optee_example_aes`(Linux guest 안, guest `init.sh`가 구동) | `libteec`(OP-TEE client lib), OP-TEE AES 예제 TA | `optee-pkvm/{bootstrap.sh,build.sh,mkrootfs.sh,run.sh,init.sh,coexist-test.sh}`, `optee-pkvm-guest/{mkrootfs.sh,init.sh}`, `verify/phase06.sh` |
| 06-B pVM 내부 TA 호출 | Host apt `qemu-system-aarch64` (E-2, TF-A `bl1.bin` 직접 부팅, semihosting `hostfs`) | Phase 06과 동일 OP-TEE 4.7.0-dev 빌드 재사용 | Phase 06 Image 재사용(`mkimage`로 `uImage` 래핑) | `optee-pkvm/rootfs-optee-pkvm-manual.cpio.gz` (Buildroot target + `pkvm`/`lkvm`/자동 실행 `optee-pkvm-coexist`, `rootfs.cpio.uboot`로 래핑) | 같은 Image 재사용(`lkvm --protected-ffa`, 2개 pVM 동시) | Phase 06의 `optee-pkvm-guest` rootfs 재사용 | `pkvm` selftest, `lkvm`, `tee-supplicant`, `optee_example_aes`(Host) | `optee_example_aes`(Linux guest, 독립 endpoint/session 분리 검증용 2 instance) | Phase 06과 동일 `libteec`, OP-TEE AES 예제 TA | `verify/phase06b.sh`(수동 절차 자동화), `u-boot/tools/mkimage`, `optee-pkvm/{init.sh,coexist-test.sh}` |
| 07 동적 수명주기 | Host apt `qemu-system-aarch64` (E-1, `CPU=cortex-a57`) | 미사용 | Phase 02 Image 재사용 | `pvm-framework/initramfs-pvm-framework.cpio.gz` (BusyBox + `pvmd`/`pvm-runner`/`pvmctl`/`phase07-app`/`protocol-negative` + guest 이미지 5종) | 없음(Runner가 KVM ioctl로 만든 protected VM에 bare-metal payload 직접 주입) | 없음 | `pvmd`(daemon), `pvmctl`(CLI), `pvm-runner`(private KVM backend), `phase07-app`(테스트 드라이버), `protocol-negative` | `phase07-guest.img`/`phase07-guest-tampered.img` (`phase07_guest.S`를 `pvm-image-pack`으로 서명한 bare-metal payload) | `libpvm.a`(`pvm_client.c`), kselftest `pvm-entry.S`/lib(`pvm-runner`에 정적 링크), `pvm_image.c`(이미지 검증 공통 코드) | `pvm-framework/{build.sh,mkinitramfs.sh,run.sh,verify-static.sh}`, `verify/phase07.sh` |
| 08 장치 할당/DMA 격리(E-3) | `qemu-phase08` submodule 빌드(`qemu-v10-aarch64/qemu-system-aarch64`, v10.0.0, SMMUv3+edu 지원, `CPU=max`) | 미사용 | Phase 02 Image + PV IOMMU/edu/DMA share/VSOCK Kconfig 재구성 후 재빌드 | Phase 07과 동일 `pvm-framework` rootfs 재사용(vfio-platform bind 로직 포함) + E-3 자체 smoke test용 `pkvm-qemu/initramfs.cpio.gz` | 없음(Phase 07과 동일하게 bare-metal guest workload에 edu 장치를 직접 VFIO 할당) | 없음 | Phase 07과 동일(`pvmd`/`pvmctl`/`pvm-runner`/`phase07-app`) | `phase07-guest.img` 재사용(edu 장치 DMA 시나리오로 확장된 `phase07_guest.S`) | Phase 07과 동일 `libpvm.a` 등 + `backend/pvm_kvm_arm64.c`의 edu 장치 할당/DMA share 로직 | `qemu-phase08`(submodule) `configure`/`make`, `qemu/{mkinitramfs.sh,run-e3.sh}`, `verify/phase08.sh` |
| 09 EL2 DMA-BUF | Host apt `qemu-system-aarch64` (E-1, `CPU=cortex-a57`) | 미사용 | Phase 08 재구성 Image 재사용 | (A) `pvm-framework` rootfs(`PHASE09=1`, `phase09-app`) (B) `pvm-buffer/initramfs-pvm-buffer-host.cpio.gz`(`lkvm`+`pvm_e2e`/`pvm_vision`) | (B)에서 같은 Image를 `lkvm`으로 nested 재사용 | `pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz` (`camera`/`ai` 바이너리 + `pvm_dmabuf.ko`) | (A) `phase09-app` (B) `lkvm`, `pvm_e2e`/`pvm_vision`(Host 측) | (A) `phase09-guest.img` 등 bare-metal payload (B) `camera`/`ai` 바이너리(Linux guest 안) | `libpvm.a`, `pvm_dmabuf` 커널 모듈(`pvm-buffer/driver`) | `pvm-buffer/{build.sh,run.sh}`, `verify/phase09.sh` |
| 09-B 사용자 공간 end-to-end | Host apt `qemu-system-aarch64` (E-1, `CPU=cortex-a57`) | 미사용 | Phase 08 재구성 Image에서 PV IOMMU 설정 재확인 후 Image만 재빌드 | `pvm-buffer/initramfs-pvm-buffer-host.cpio.gz` (`lkvm` + `pvm_vsock_smoke`/`pvm_e2e`/`pvm_vision`) | 같은 Image 재사용(`lkvm` 3-way, Camera/AI `vsock` CID 4101/4102) | `pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz` (`camera`/`ai`/`pvm_vsock_smoke`/`pvm_e2e`/`pvm_vision` + `pvm_dmabuf.ko` + `pvm_message.ko`) | `lkvm`, `pvm_vsock_smoke`(Host), `pvm_e2e`(Host) | `pvm_vsock_smoke`(guest), `pvm_e2e`(camera/ai/faultcamera/faultai 역할) | `libpvm_user_channel.a`, `libpvm_message.a` (`pvm_user_channel.c`/`pvm_message.c`), `pvm_dmabuf.ko`/`pvm_message.ko` 커널 모듈 | `pvm-buffer/{build.sh,run-vsock-smoke.sh,run-user-channel-e2e.sh,run-user-channel-fault.sh}`, `pvm-user-channel/Makefile`, `verify/phase09b.sh` |
| 10 Reference Scenario | E-3 `qemu-v10-aarch64`(Phase 08 재사용, vision pipeline/fault) + Host apt `qemu-system-aarch64`(E-1, Phase 09-B 회귀 재실행) | 미사용 | Phase 08 재구성 Image 재사용 | Phase 09-B와 동일 `pvm-buffer/initramfs-pvm-buffer-host.cpio.gz`(+ `oracle.bin` fixture 포함) | 같은 Image 재사용(`lkvm`, `vsock` CID 4101/4102, Camera/AI vision 역할) | `pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz`(+ `frames.bin`/`oracle.bin` fixture 포함) | `lkvm`, `pvm_vision`(Host), `prepare-fixture.sh`(Open Model Zoo/OpenVINO 준비, Python venv) | `pvm_vision`(camera/ai/visioncamera/visionai/fault 역할, 30-frame replay) | Phase 09-B와 동일 `libpvm_user_channel.a`/`libpvm_message.a` + `pvm_sha256.c`(vision-pipeline), OpenVINO `person-vehicle-bike-detection-2000` 모델(OMZ) | `vision-pipeline/{prepare-fixture.sh,prepare_fixture.py,verify_fixture.py,Makefile}`, `pvm-buffer/{run-vision-pipeline.sh,run-vision-fault.sh}`, `verify/phase10.sh` |

## 참고

- "guest kernel"이 "없음"인 Phase(03~05, 07, 08)는 protected VM을 Linux가 아닌
  bare-metal 어셈블리 payload(kselftest `pkvm` 또는 `phase07_guest.S`)로 만들기
  때문에 별도의 guest kernel Image가 없다. Linux guest가 실제로 부팅되는 Phase는
  06, 06-B, 09(B 경로), 09-B, 10이며, 이때도 guest kernel은 항상 Phase 02가 만든
  Host kernel Image를 `lkvm`으로 그대로 재사용한다(별도로 빌드하지 않음).
- OP-TEE는 Phase 06, 06-B에서만 쓰인다. 나머지 Phase는 OP-TEE Secure World 없이
  Normal World(pKVM Host/Guest)만으로 검증한다.
- 상세 재현 명령과 완료 조건은 [통합 검증 가이드](VERIFICATION-GUIDE.md)와 각
  `docs/phase-{nn}/VERIFICATION.md`를 참고한다.

## 모든 Phase를 한 번에 통합 재현할 때 사용할 산출물

Phase 02~10을 **QEMU 한 프로세스**로 한 번에 통합할 수는 없다. Phase 06/06-B는
TF-A(`bl1.bin`)가 BL2/BL31/BL32(OP-TEE)/BL33(U-Boot)를 순서대로 검증/기동하는
Secure Monitor 부팅 경로를 쓰고, U-Boot가 `CONFIG_BOOTCOMMAND`로 자체적으로 커널을
읽기 때문에 QEMU의 `-kernel`/`-initrd`가 아예 무시된다. 반면 나머지 Phase는
`-kernel`/`-initrd`로 직접 부팅한다. 두 부팅 경로는 같은 QEMU 인스턴스 안에 공존할
수 없다.

대신 이 저장소는 **환경 프로파일 3개(E-1/E-2/E-3)** 로 나뉘고, 프로파일 안에서는
이미 산출물을 공유/재사용한다. "통합 재현"의 실질적 의미는 프로파일별로 아래 최소
산출물 한 벌씩만 준비하면 그 프로파일에 속한 모든 Phase를 다시 실행할 수 있다는
뜻이다. `work/src/tools/verify/run-all.sh`가 정확히 이 순서로 실행한다.

핵심 사실: **host kernel Image는 세 프로파일 전부가 물리적으로 같은 파일 하나**
(`work/build/pkvm-full-clang/arch/arm64/boot/Image`)다. Phase 06이 켠
`CONFIG_ARM_FFA_TRANSPORT`와 Phase 08이 켠 PV IOMMU/edu/DMA-share/VSOCK 옵션은
서로 끄지 않고 같은 `.config`에 계속 누적되므로(`work/src/tools/qemu/
configure-pv-iommu-kernel.sh`가 `--disable`하는 대상은 `ARM_SMMU_V3` 계열뿐),
Phase 08까지 진행한 뒤의 최종 Image 하나로 E-1/E-2/E-3 어느 쪽으로도 재부팅할 수
있다. 실제로 이 저장소의 현재 `.config`에 두 계열이 함께 켜져 있음을 확인했다.

```text
CONFIG_ARM_FFA_TRANSPORT=y        (Phase 06)
CONFIG_ARM_SMMU_V3_PKVM_PV=y      (Phase 08)
CONFIG_PKVM_PVIOMMU=y             (Phase 08)
CONFIG_VFIO_PLATFORM=y            (Phase 08)
CONFIG_PKVM_QEMU_EDU=y            (Phase 08)
CONFIG_PKVM_PVM_DMA_SHARE=y       (Phase 08)
CONFIG_VSOCKETS=y / VIRTIO_VSOCKETS=y / VHOST_VSOCK=y   (Phase 08)
```

달라지는 것은 QEMU 바이너리, 이 Image를 감싸는 방식(U-Boot용 `uImage`/
`rootfs.cpio.uboot`로 감쌀지, 그대로 `-kernel`로 넘길지), 그리고 host/guest rootfs다.

### 프로파일 E-1 (기본 pKVM, OP-TEE/장치 미사용) — Phase 03, 04, 05, 07, 09, 09-B

| 항목 | 값 |
|---|---|
| 대상 Phase | 03, 04, 05, 07, 09, 09-B |
| qemu | Host apt `qemu-system-aarch64` |
| host kernel | `work/build/pkvm-full-clang/arch/arm64/boot/Image` (공용, Phase 08까지 진행한 최종본도 그대로 통과) |
| host rootfs | Phase마다 다른 파일이지만 전부 같은 방식(BusyBox 정적 + 해당 Phase 바이너리)으로 재생성: `pkvm-qemu/initramfs.cpio.gz`, `pkvm-pvm/initramfs-pvm.cpio.gz`, `multi-pvm/initramfs-multi-pvm.cpio.gz`, `pvm-framework/initramfs-pvm-framework.cpio.gz`, `pvm-buffer/initramfs-pvm-buffer-host.cpio.gz` |
| guest kernel/rootfs | Phase 09/09-B만 `lkvm`으로 위 host kernel Image를 nested guest로 재사용, guest rootfs는 `pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz` |
| 재빌드 필요 여부 | 이 프로파일 안에서는 Image를 다시 만들 필요가 없다. 각 rootfs만 해당 `mkinitramfs.sh`/`build.sh`로 새로 조립하면 된다 |

### 프로파일 E-2 (OP-TEE Secure World, TF-A/U-Boot 부팅) — Phase 06, 06-B

| 항목 | 값 |
|---|---|
| 대상 Phase | 06, 06-B |
| qemu | Host apt `qemu-system-aarch64` (`-bios bl1.bin`, `secure=on,virtualization=on`) |
| Secure World | OP-TEE 4.7.0-dev(`SPMC_AT_EL=1`, `CFG_NS_VIRTUALIZATION=y`), TF-A BL1/BL2/BL31, U-Boot(BL33) — 전부 `work/src/tools/optee-pkvm/{bootstrap.sh,build.sh}` 산출물 |
| host kernel | 위와 같은 `work/build/pkvm-full-clang/.../Image`. Phase 06-B는 이 Image를 `mkimage`로 `uImage`로 한 번 더 감싼다(U-Boot `hostfs` semihosting 경로 전용, symlink 대신 반드시 `cp`로 배치) |
| host rootfs | Phase 06: `optee-pkvm/rootfs-optee-pkvm.cpio.gz` → `rootfs.cpio.uboot`로 래핑. Phase 06-B: `optee-pkvm/rootfs-optee-pkvm-manual.cpio.gz` → 별도 `rootfs-phase06b.cpio.uboot`로 래핑(자동 실행 init 차이만 있고 나머지는 06과 동일) |
| guest kernel/rootfs | 같은 Image를 `lkvm --protected-ffa`로 재사용, guest rootfs는 `optee-pkvm-guest/rootfs-optee-pkvm-guest.cpio.gz` (06/06-B 공용) |
| 재빌드 필요 여부 | OP-TEE/TF-A/U-Boot/Buildroot는 한 번만 빌드하면 06과 06-B가 그대로 재사용한다 |

### 프로파일 E-3 (장치 할당/DMA 격리, SMMUv3+edu) — Phase 08, 10

| 항목 | 값 |
|---|---|
| 대상 Phase | 08, 10 |
| qemu | `work/build/qemu-v10-aarch64/qemu-system-aarch64` (`qemu-phase08` submodule, v10.0.0, `iommu=smmuv3,pkvm-edu-assignment=on`, edu PCI 장치 2개) |
| host kernel | 위와 같은 `work/build/pkvm-full-clang/.../Image`, PV IOMMU Kconfig 적용 후 재빌드된 상태(E-1/E-2와 파일 경로 동일) |
| host rootfs | Phase 08: `pvm-framework/initramfs-pvm-framework.cpio.gz`(vfio-platform bind 로직 포함, E-1과 파일은 같지만 edu 장치가 있을 때만 관련 marker 출력). Phase 10: `pvm-buffer/initramfs-pvm-buffer-host.cpio.gz`(Phase 09-B와 동일 파일에 fixture만 추가) |
| guest kernel/rootfs | Phase 08은 별도 guest 이미지 없이 bare-metal payload(`phase07-guest.img`)에 장치를 직접 할당. Phase 10은 같은 host kernel Image를 `lkvm`으로 재사용하고 guest rootfs는 `pvm-buffer/rootfs-pvm-buffer-guest.cpio.gz`(+ `frames.bin`/`oracle.bin`) |
| 재빌드 필요 여부 | E-3 QEMU는 한 번만 빌드하면 08과 10이 그대로 재사용한다 |

### 정리: 한 번에 준비해 두면 되는 최소 파일 목록

```text
work/build/pkvm-full-clang/arch/arm64/boot/Image   (Phase 02 빌드 + Phase 06/08 Kconfig 누적, 전 Phase 공용)
work/build/qemu-v10-aarch64/qemu-system-aarch64    (Phase 08 빌드, E-3 전용, Phase 08/10 공용)
work/src/kvmtool/lkvm                              (Phase 06 빌드, nested guest 기동에 쓰는 모든 Phase 공용)
work/src/optee-pkvm/out/bin/bl1.bin 등 TF-A/OP-TEE 산출물   (Phase 06 빌드, E-2 전용, Phase 06/06-B 공용)
optee-pkvm-guest/rootfs-optee-pkvm-guest.cpio.gz    (Phase 06 조립, E-2 guest 공용)
pvm-buffer/{initramfs-pvm-buffer-host,rootfs-pvm-buffer-guest}.cpio.gz  (Phase 09-B 조립, Phase 09/09-B/10 공용)
```

나머지 host rootfs(Phase 03/04/05/07/08의 initramfs)는 파일 자체가 가볍고
`mkinitramfs.sh`/`mkrootfs.sh` 실행 시간도 짧아 매번 새로 조립해도 부담이 적다.
`work/src/tools/verify/run-all.sh`는 이 구조 그대로, DONE marker가 있는 Phase는
건너뛰고 위 3개 프로파일의 공용 산출물을 자연스럽게 재사용한다.
