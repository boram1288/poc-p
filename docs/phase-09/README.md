# Phase 09: pVM 간 DMA-BUF export/import

- 상태: 미착수 (D-8 구현 방식 확정)
- 목적: Camera pVM이 생성한 DMA-BUF를 Host runtime relay 없이 AI pVM이 새로운 local FD로
  import하여 read/write한다.
- 환경: E-1에서 경로 검증, E-3에서 할당된 장치의 프레임으로 확인
- 관련 목표: G-10
- 관련 결정: D-8

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

## 예정 산출물

- application/guest driver/EL2 설계: [el2-dmabuf-channel-design.md](el2-dmabuf-channel-design.md)
- application library와 test workload: `work/src/tools/pvm-buffer/`
- guest driver와 EL2 manager: `work/src/pkvm-linux/`
- 실행 로그: `work/build/pvm-buffer/`
- 결과 문서: 이 디렉터리에 추가

## 한계

처리량과 지연은 측정하지 않는다. 단일 Camera/AI pair, 단일 활성 transfer와 순차 ownership
lease만 검증한다. 동시 read/write, implicit fencing과 production-grade cache synchronization은
후속 과제다.

E-3는 에뮬레이션 환경이다. 여기서 zero-copy 전달이 성립해도 실물 하드웨어에서의 성립을
주장하지 않는다.
