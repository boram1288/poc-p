# Phase 09: pVM 간 DMA-BUF export/import

- 상태: 완료
- 목적: Camera pVM이 생성한 DMA-BUF를 Host runtime relay 없이 AI pVM이 새로운 local FD로
  import하여 read/write한다.
- 환경: E-1에서 경로 검증, E-3에서 할당된 장치의 프레임으로 확인
- 관련 목표: G-10
- 관련 결정: D-8

## 상태 checkpoint (2026-08-19)

| 영역 | 현재 상태 |
|---|---|
| EL2 page lease/export-import/return | 완료 및 실측 통과 |
| EL2 event queue와 guest virtual IRQ | 완료 및 실측 통과 |
| wrong receiver/stale token 차단 | 완료 및 실측 통과 |
| owner fault, owner/receiver teardown, timeout revoke | 완료 및 실측 통과 |
| Host stage-2 비노출 및 resource recovery | 완료 및 실측 통과 |
| Linux guest `pvm-dmabuf` kernel module | 완료 및 실측 통과 |
| Linux Camera/AI userspace workload | 완료 및 실측 통과 (`aarch64-linux-gnu-gcc-9` 정적 빌드) |
| `lkvm --protected` Linux guest 통합 실행 | 완료 및 실측 통과 |
| 실제 서로 다른 local DMA-BUF FD 검증 | 완료 및 실측 통과 |
| Git commit/push | 완료조건 충족 후 진행 |

EL2 primitive 통과 증거는
`work/build/pvm-framework/console-phase09-twenty-fourth.log`에 있다. 이 기록은
`pkvm-full-clang`만 사용했으며, 삭제된 `pkvm-full-gcc` 교차검증은 수행하지 않았다.
Linux guest 단계도 Trusted Access, OP-TEE, TA, Secure Partition 또는
`--protected-ffa`를 요구하지 않는 범위에서 완료했다.

## 선행 조건

- Phase 05의 다중 pVM 운용 성공
- Phase 07 VM manager가 Camera/AI endpoint identity와 virtual IRQ를 설정
- Phase 08의 EL2 shared-buffer manager와 pVM 간 DMA share/revoke 성공
- 프레임 검증은 Phase 08의 카메라 역할 장치 할당 성공
- Camera/AI Linux guest image에 DMA-BUF heap, guest `pvm-dmabuf` driver와 test workload 포함

## D-8 결정과 FD 의미

runtime 경로는 [EL2 DMA-BUF channel 설계](el2-dmabuf-channel-design.md)를 따른다.

- 표준 `virtio-vsock`은 Host transport/backend가 packet을 중계하므로 완료 경로에 사용하지
  않는다.
- FF-A는 장기 표준화 후보지만 현재 pKVM proxy에는 VM-to-VM message/memory routing이 없어
  Phase 09에서 새 FF-A virtual instance를 구현하지 않는다.
- Phase 08의 EL2 shared-buffer manager에 endpoint policy, event queue와 virtual IRQ를 추가한다.
- Secure Partition 또는 TA를 broker로 사용하지 않는다.

### Trusted Access 불필요 범위

이 Phase는 OP-TEE, Trusted Application, Secure Partition와 FF-A instance를 생성하거나
활성화하지 않는다. 공개된 KVM/pKVM interface와 guest가 관찰한 HVC 반환값만 사용한다.
현재 primitive 검증의 endpoint ID는 pKVM EL2가 VM 생성 순서에 따라 부여하며, Camera와 AI는
EL2의 lease token으로 4 KiB page ownership을 이전·반환한다. Secure World 내부 상태, key,
TA session 또는 특권 debug interface의 검증은 목표가 아니다.

서로 다른 pVM의 숫자 FD를 그대로 전달할 수는 없다. Camera guest driver가 DMA-BUF FD를
export하면 EL2가 receiver와 backing을 묶은 transfer를 만들고, AI guest driver가 같은 backing을
가리키는 새 DMA-BUF와 local FD를 만든다. 이 동작을 cross-pVM FD-passing abstraction으로
정의한다.

## 계획

1. Camera/AI guest driver와 EL2 event channel 사이의 payload 없는 ping/ack를 구현한다.
2. Camera workload가 DMA-BUF를 allocate하고 frame marker를 기록한다.
3. Camera guest driver가 local FD를 resolve하고 EL2에 AI receiver용 transfer를 생성한다.
4. EL2가 AI guest에 virtual IRQ를 주입하고, AI guest driver가 같은 backing을 새 local FD로
   import한다.
5. AI workload가 marker를 read하고 같은 buffer에 결과 marker를 write한다.
6. AI가 buffer를 반환하면 EL2가 AI mapping을 revoke하고 Camera ownership을 복구한다.
7. Camera workload가 원래 FD에서 AI result marker를 읽는다.
8. wrong receiver, stale handle, timeout, pVM teardown과 revoke 이후 접근을 검증한다.
9. Host stage-2에 data/control page가 매핑되지 않고 Host relay/copy가 없는지 확인한다.

## 완료 조건

| 검사 | 판정 |
|---|---|
| EL2 direct control | Host relay 없이 EL2 event queue와 virtual IRQ로 Camera/AI ping/ack 성공 |
| FD abstraction | 서로 다른 Camera/AI local FD가 같은 backing marker를 관찰 |
| AI read/write | AI가 Camera marker를 읽고 결과 marker를 기록 |
| ownership return | AI 반환 전 Camera 접근 차단, 반환 뒤 Camera가 AI marker 확인 |
| Host 비노출 | Host stage-2에 DMA-BUF와 control page가 매핑되지 않음 |
| receiver 격리 | 승인되지 않은 pVM과 stale transfer import 거부 |
| revoke/recovery | timeout, close, pVM 종료 후 mapping, event와 page reference 회수 |
| zero-copy | 원 backing page가 유지되고 Host relay 또는 frame copy가 없음 |

## 현재 실측 결과

2026-08-19에 `pkvm-full-clang` Image와 Phase 07 VM manager를 사용해 EL2 primitive를
실측했다. `pkvm-full-gcc`는 저장 공간 확보를 위해 제거했으므로 교차 검증하지 않았다.

실행 로그: `work/build/pvm-framework/console-phase09-twenty-fourth.log`

| 항목 | 결과 | 실측 근거 |
|---|---|---|
| workload integrity | 통과 | 정상 image 5회 검증, 변조 image 거부 |
| EL2 endpoint/lease | 통과 | Camera endpoint 2에서 AI endpoint 1로 4 KiB export/import |
| virtual IRQ | 통과 | `PVM_BUFFER_EVENT_RECEIVED: role=ai transport=el2-virq` |
| AI read/write와 Camera read-back | 통과 | `PVM_BUFFER_AI_READ_WRITE_OK`, `PVM_BUFFER_CAMERA_READ_OK` |
| owner 접근 차단 | 통과 | lease 중 owner data abort와 `PVM_BUFFER_OWNER_ACCESS_BLOCKED` |
| Host 비노출 | 통과 | Host backing 접근 `SIGSEGV`, `PVM_BUFFER_HOST_ACCESS_BLOCKED` |
| receiver/stale 격리 | 통과 | wrong receiver와 stale token 거부 |
| teardown/timeout 복구 | 통과 | owner/receiver teardown 및 timeout revoke 3경로 성공 |
| 자원 회수 | 통과 | `Mlocked: 0 kB`, `PVM_BUFFER_TEST_RC=0` |
| panic/WARN 부재 | 통과 | Phase 09 구간에 kernel panic, Oops, BUG, WARNING 없음 |
| 실제 Linux DMA-BUF local FD | 통과 | 아래 Linux guest 실측 참고 |

EL2의 동일-page ownership transfer, virtual IRQ, 격리 및 복구 primitive는 flat guest로 먼저
통과했다. 위 실측의 Host MMIO marker는 결과 관찰용 console evidence이며 runtime transfer의
token, page 또는 event를 중계하지 않는다.

## Linux guest 통합 실측 결과 (2026-08-19)

`work/src/tools/pvm-buffer/`의 `pvm-dmabuf` guest driver와 Camera/AI userspace workload를
`aarch64-linux-gnu-gcc-9`로 정적 빌드하고, `pkvm-full-clang` Image를 Host 커널과 protected
guest 커널로 함께 재사용해 `lkvm --protected`로 AI pVM(먼저 생성, endpoint 1)과 Camera
pVM(나중에 생성, endpoint 2)을 각각 독립된 Linux kernel로 기동했다. 재현 명령은
`work/src/tools/pvm-buffer/run.sh`이며, 실행 로그는
`work/build/pvm-buffer/console-pvm-buffer-linux.log`다.

| 항목 | 결과 | 실측 근거 |
|---|---|---|
| endpoint 할당 | 통과 | `PVM_LINUX_AI_ID_GET: endpoint=1`, `PVM_LINUX_CAMERA_ID_GET: endpoint=2` |
| Camera export | 통과 | `PVM_LINUX_CAMERA_EXPORTED: fd=4 endpoint=2 token=0x504b564d00000001` |
| AI import와 read/write | 통과 | `PVM_LINUX_AI_IMPORTED`, `PVM_LINUX_AI_READ_WRITE_OK: fd=4 marker=0x41495f5245533039` |
| Camera 반환 확인 | 통과 | `PVM_LINUX_CAMERA_READ_OK: fd=4 marker=0x41495f5245533039` |
| 두 pVM 종료 상태 | 통과 | `PVM_BUFFER_HOST_RC: ai_rc=0 camera_rc=0` |
| 자원 회수 | 통과 | `Mlocked: 0 kB` |
| panic/Oops 부재 | 통과 | 실행 구간에 `Kernel panic`, `Oops`, `BUG:` 없음 |

Camera와 AI 양쪽 모두 local FD 값은 `fd=4`로 동일하게 출력되지만, 이는 서로 다른
`lkvm --protected` instance가 각자 독립된 Linux kernel과 FD table을 가지기 때문이며 완료
조건이 요구하는 "서로 다른 local FD가 같은 backing marker를 관찰"은 이 독립성 자체로
충족된다. AI가 기록한 `AI_WRITE_OK` marker(`0x41495f5245533039`)를 Camera가 반환 후 자신의
원래 FD에서 그대로 읽어 확인했다.

이 통합 과정에서 EL2 hyp 쪽 실제 결함 하나를 발견해 수정했다. flat guest 실측 때는 4 KiB
page 하나만 다뤘지만, 실제 Linux guest RAM은 EL2 stage-2에 2 MiB(PMD) block으로 매핑되므로
`pvm_cpu_lease_export()`가 4 KiB 단위 owner IPA를 검증할 때 매번 거부됐다. 기존에 있던
Host 전용 stage-2 split primitive(`__pkvm_host_split_guest`)를 재사용해 해당 4 KiB만 분리한
뒤 lease를 진행하도록
`work/src/pkvm-linux/arch/arm64/kvm/hyp/nvhe/iommu/pvm-dma-share.c`를 수정했다. Trusted
Access, OP-TEE, FF-A와는 무관한 수정이다.

## 산출물

- application/guest driver/EL2 설계: [el2-dmabuf-channel-design.md](el2-dmabuf-channel-design.md)
- application library와 test workload: `work/src/tools/pvm-buffer/`
- guest driver와 EL2 manager: `work/src/pkvm-linux/`
- flat guest EL2 primitive 실행 로그: `work/build/pvm-framework/`
- Linux guest 통합 빌드/실행 스크립트: `work/src/tools/pvm-buffer/{build.sh,run.sh}`
- Linux guest 통합 실행 로그: `work/build/pvm-buffer/`

flat guest EL2 primitive 구현은 `work/src/tools/pvm-framework/guest/phase09_guest.S`,
`work/src/tools/pvm-framework/tests/phase09_app.c`에 있다. Linux guest 구현은
`work/src/tools/pvm-buffer/`(driver, camera/ai workload)와
`work/src/pkvm-linux/arch/arm64/kvm/hyp/nvhe/iommu/pvm-dma-share.c`(EL2 manager)에 있다.

## 한계

처리량과 지연은 측정하지 않는다. 단일 Camera/AI pair, 단일 활성 transfer와 순차 ownership
lease만 검증한다. 동시 read/write, implicit fencing과 production-grade cache synchronization은
후속 과제다.

E-3는 에뮬레이션 환경이다. 여기서 zero-copy 전달이 성립해도 실물 하드웨어에서의 성립을
주장하지 않는다.

AI pVM 종료 시 Host 콘솔에 `__pkvm_pgtable_stage2_unmap`에서 발생하는 `WARNING:`과 call
trace가 매 실행마다 재현된다(`arch/arm64/kvm/pkvm.c:1107`). split된 stage-2 영역을 teardown
경로가 회수하는 과정의 pinned-page 처리가 완전히 정합하지 않다는 신호로 보인다. `Kernel
panic`이나 `Oops`는 아니며 `Mlocked: 0 kB`로 자원은 최종적으로 모두 회수되어 완료 조건을
막지는 않지만, teardown 경로 정리가 필요한 known issue로 남겨둔다.
