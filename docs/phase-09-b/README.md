# Phase 09-b: 사용자 공간 end-to-end 통신

- 상태: 완료
- 목적: Host Application, Camera pVM workload, AI pVM workload 사이의 세 통신 구간을 하나의
  사용자 공간 세션으로 연결하고, 허용된 control/result만 Host에 노출한다.
- 환경: E-1에서 통신 기능 검증, E-3에서 Phase 10 파이프라인과 통합
- 관련 목표: G-10, G-10B, G-11
- 관련 결정: D-8, D-9, D-10
- 실측 결과: [VERIFICATION.md](VERIFICATION.md)

## 1. 범위와 성공 시나리오

착수 결과: `pvm-user-channel`에 versioned framing, Host↔protected guest AF_VSOCK smoke,
그리고 Camera↔AI `FRAME_DESC` 고정 descriptor/검증 루틴을 추가했다. protected guest의
virtio ring 공유에 필요한 `CONFIG_VIRT_DRIVERS`, `CONFIG_ARM_PKVM_GUEST`와 VSOCK 설정을
활성화한 뒤 `HELLO/READY/CAPTURE/ACK` 왕복을 실측했다. Host-facing transport는 MMIO
fallback 없이 AF_VSOCK으로 고정한다. Camera↔AI metadata는 Host relay가 없는 EL2 queue
구현을 사용한다.

이 Phase는 실제 추론 모델을 통합하기 전에 다음 세 구간의 사용자 공간 API와 wire protocol을
완성한다.

| 구간 | 사용자 공간에서 보이는 API | transport | 허용 payload |
|---|---|---|---|
| Host Application ↔ Camera workload | versioned command/event API | `AF_VSOCK` (`virtio-vsock`/`vhost-vsock`) | 설정, capture/stop 명령, ACK, 상태, 오류 |
| Camera workload ↔ AI workload: buffer | `libpvm_buffer` send/receive/return API | Phase 09 EL2 DMA-BUF lease | 보호된 frame backing만 전달 |
| Camera workload ↔ AI workload: descriptor/control | `libpvm_message` send/receive API | 별도 EL2 message queue + virtual IRQ | buffer size/format/plane/stride, frame correlation과 ACK/ERROR |
| AI workload ↔ Host Application | versioned command/result API | `AF_VSOCK` (`virtio-vsock`/`vhost-vsock`) | 설정, stop 명령, 허용 목록의 추론 결과, ACK, 오류 |

Phase 09-b에서는 실제 AI 추론 대신 frame marker를 확인해 만드는 deterministic result를 사용한다.
Phase 10은 같은 API와 protocol을 유지한 채 deterministic 처리부만 CPU inference runtime으로
교체한다.

성공 시나리오는 다음과 같다.

```text
Host Application (CID 2)
  │ AF_VSOCK: CONFIG / CAPTURE / ACK / STATUS
  ▼
Camera workload (CID 4102, EL2 endpoint 2)
  ├──────── libpvm_buffer: protected DMA-BUF send / return ────────┐
  └─ libpvm_message: FRAME_DESC / ACCEPT / DONE / ERROR ──────────┤
       별도 EL2 queue, Host relay 없음                            ▼
AI workload (CID 4101, EL2 endpoint 1)
  │ AF_VSOCK: CONFIG / RESULT / ACK / ERROR
  ▼
Host Application
```

VSOCK CID와 EL2 endpoint ID는 서로 다른 identity namespace다. 구현과 로그에서
`vsock_cid`와 `el2_endpoint`를 항상 구분해 표기한다.

## 2. 신뢰 경계와 transport 결정

Host가 통신의 실제 endpoint인 두 구간에는 `AF_VSOCK`을 사용한다. 표준 VSOCK의 Host backend
경유는 이 두 구간에서 의도된 동작이다. 반면 Camera↔AI frame은 Host가 endpoint가 아니므로
VSOCK으로 우회하거나 Host Application이 중계하지 않는다. frame backing은 Phase 09의 EL2
DMA-BUF lease로, buffer descriptor와 control message는 별도 EL2 message queue로 전달한다.
두 EL2 경로는 서로 독립된 UAPI, queue와 lifecycle을 가지며 `transfer_id`와 `frame_seq`로만
사용자 공간에서 결합한다.

Host에 공개해도 되는 값은 command, ACK, 상태, 오류와 Phase 10에서 정의할 result allowlist뿐이다.
다음 값은 Host-facing protocol에 넣지 않는다.

- raw frame과 frame 일부
- Camera/AI의 local DMA-BUF FD
- EL2 transfer token, Camera↔AI descriptor, PA, IPA, IOVA와 Host VA
- AI model weight와 intermediate tensor

VSOCK은 Host에 대한 기밀성 또는 무결성을 제공하는 경계로 간주하지 않는다. Host는 연결을
지연, 중단, 재생하거나 payload를 변조할 수 있다. 이 Phase는 bounded message, session ID,
request ID와 frame sequence로 malformed/stale/duplicate 입력을 거부하고 안전하게 종료하지만,
악의적인 Host에 대한 availability는 보장하지 않는다.

OP-TEE, TA, Secure Partition, FF-A activation과 Trusted Access 전용 debug interface는 사용하지
않는다. VSOCK, guest device UAPI, KVM/pKVM 공개 interface와 각 endpoint가 관찰한 반환값 및
로그만으로 판정한다. 구현 중 Trusted Access가 필요하다는 메시지가 나오면 권한을 요구하거나
우회하지 않고, 공개 Host/guest interface로 확인할 수 없는 항목을 미검증으로 기록한다.

## 3. 사용자 공간 protocol

### 3.1 Host-facing 연결과 identity

- Host Application은 Host CID 2의 고정 port에서 두 연결을 accept한다.
- AI pVM은 `--vsock 4101`, Camera pVM은 `--vsock 4102`로 기동한다.
- 각 workload가 Host에 연결한 뒤 `HELLO(role, protocol_version, session_id)`를 보낸다.
- Host Application은 VSOCK peer CID와 launch manifest의 `role ↔ CID`를 대조한다. role 문자열만
  신뢰하지 않는다.
- EL2의 Camera endpoint 2와 AI endpoint 1 정책은 기존 Phase 09 경로에서 별도로 검증한다.

초기 구현은 호환성이 넓은 `SOCK_STREAM`과 명시적 length framing을 사용한다. socket read 한
번이 message 하나와 같다고 가정하지 않고 short read/write, `EINTR`, peer close와 deadline을
공통 library에서 처리한다.

### 3.2 Host-facing 공통 header

wire header는 고정 폭 정수와 E-1의 arm64 little-endian 고정 layout을 사용하며 다음 필드를 가진다.

| 필드 | 용도 |
|---|---|
| `magic`, `version`, `header_len` | protocol 식별과 확장 |
| `message_type`, `payload_len` | 허용 message와 길이 검사 |
| `session_id` | 이전 실행에서 남은 message 거부 |
| `request_id` | command와 ACK/ERROR correlation, duplicate 거부 |
| `frame_seq` | capture, DMA-BUF frame과 result correlation |
| `status` | 성공 또는 고정 오류 코드 |

payload는 message type별 고정 struct 또는 작은 상한을 가진 TLV로 제한한다. 최대 message 크기는
4 KiB로 두고, 그보다 큰 길이, 알 수 없는 필수 field와 정수 overflow는 payload를 읽거나
할당하기 전에 거부한다.

### 3.3 Host-facing message와 상태 흐름

| 방향 | message | 의미 |
|---|---|---|
| workload → Host | `HELLO`, `READY` | role/CID 확인과 준비 완료 |
| Host → Camera | `CAMERA_CONFIG`, `CAPTURE`, `STOP` | capture 설정, frame 생성, 종료 |
| Camera → Host | `ACK`, `STATUS`, `ERROR` | command 결과만 반환 |
| Host → AI | `AI_CONFIG`, `STOP` | result schema 설정과 종료 |
| AI → Host | `ACK`, `RESULT`, `ERROR` | allowlist 결과만 반환 |

`RESULT`의 Phase 09-b schema는 `frame_seq`, deterministic `class_id`, 고정소수점 `score`,
`status`로 제한한다. byte array, pointer, FD, address, transfer token과 가변 diagnostic dump는
허용하지 않는다.

### 3.4 Camera↔AI 전용 metadata/control channel

Camera와 AI는 DMA-BUF와 별개로 `/dev/pvm-msg`와 `libpvm_message`를 사용한다. guest driver는
고정 크기 message를 EL2의 receiver별 queue에 넣고 bounded poll로 수신한다. 성공한 recv-info는
EL2에서 guest IRQ state에도 반영된다. 이 queue는
DMA-BUF transfer event queue와 저장 공간, sequence, overflow 처리와 teardown state를 공유하지
않는다. sibling pVM VSOCK 또는 Host userspace backend는 이 경로에 참여하지 않는다.

초기 상한은 message payload 256 bytes, endpoint별 queue 64개로 고정한다. descriptor와 ACK는
EL2가 두 guest 사이에서 복사한다. 이는 작은 control metadata의 의도된 copy이며, zero-copy
주장은 DMA-BUF frame backing에만 적용한다. queue가 가득 차면 기존 entry를 덮어쓰지 않고
`-ENOSPC`를 반환하며 application이 deadline 안에서 재시도하거나 해당 frame을 취소한다.

구현된 guest driver는 별도 공유 page를 만들지 않고 24-byte SMCCC register fragment로 message를
EL2에 전달한다. EL2는 `BEGIN/CHUNK/COMMIT` 상태와 256-byte 상한, sender identity, receiver
policy를 검사한 뒤 receiver별 64-entry queue에 조립한다. RECEIVE도 `INFO/CHUNK/POP` HVC로
반환하고 수신 poll 시 virtual IRQ를 주입한다. 따라서 message slot의 Host mapping 자체가 없고,
pVM teardown 때 EL2 queue와 미완성 staging fragment를 함께 zeroize한다.

초기 message 집합은 다음과 같다.

| 방향 | message | 의미 |
|---|---|---|
| Camera → AI | `FRAME_DESC` | 별도로 전송한 DMA-BUF의 크기와 영상 layout 설명 |
| AI → Camera | `FRAME_ACCEPTED` | descriptor와 imported DMA-BUF의 결합 및 검증 성공 |
| AI → Camera | `FRAME_REJECTED` | format, bounds, correlation 또는 state 검증 실패 |
| AI → Camera | `FRAME_DONE` | buffer 처리를 끝내고 ownership을 반환했음을 알림 |
| 양방향 | `PEER_STOP`, `PEER_ERROR` | 정상 종료와 frame 단위 오류 통지 |

`FRAME_DESC`는 raw frame을 포함하지 않는 고정 크기 descriptor다.

| 필드 | 의미와 검증 |
|---|---|
| `version`, `descriptor_len` | 알려진 version과 정확한 struct 길이만 허용 |
| `session_id`, `frame_seq` | Host session 및 frame correlation |
| `transfer_id` | `libpvm_buffer`가 반환한 opaque ID. Host-facing channel에는 전송 금지 |
| `total_size` | imported DMA-BUF의 실제 크기와 일치해야 함 |
| `fourcc` | 허용 pixel format. 첫 검증은 64×64 `V4L2_PIX_FMT_GREY` 사용 |
| `width`, `height` | 0이 아니고 정적 상한 이내여야 함 |
| `num_planes` | 1~4 범위 |
| `planes[4]` | 각 plane의 `offset`, `stride`, `size`; overflow 없이 `total_size` 안에 있어야 함 |
| `timestamp_ns`, `flags` | capture correlation용 값과 알려진 flag만 허용 |

사용자 공간 API의 최소 형태는 다음과 같이 고정한다.

```c
struct pvm_frame_desc {
	uint32_t version;
	uint32_t descriptor_len;
	uint64_t session_id;
	uint64_t frame_seq;
	uint64_t transfer_id;
	uint64_t total_size;
	uint32_t fourcc;
	uint32_t width;
	uint32_t height;
	uint32_t num_planes;
	struct pvm_plane_desc planes[4];
	uint64_t timestamp_ns;
	uint32_t flags;
};

int pvm_message_open(void);
int pvm_message_send(int fd, uint32_t peer_endpoint, const void *data,
		     uint32_t length, uint64_t *sequence);
int pvm_message_receive(int fd, uint32_t expected_sender, void *data,
			uint32_t capacity, uint32_t *length,
			uint64_t *sequence, uint32_t timeout_ms);
```

EL2가 확인한 sender endpoint는 receive ioctl로 반환되고 `pvm_message_receive()`가
`expected_sender`와 대조한다. application이 payload의 role이나 endpoint 숫자만으로 sender를
판단하지 않는다. 또한 `libpvm_buffer` receive 결과와
guest driver UAPI를 확장해 imported DMA-BUF의 kernel-reported `actual_size`를 반환하고,
descriptor의 `total_size` 검사는 이 값을 기준으로 수행한다.

AI는 descriptor와 DMA-BUF를 도착 순서와 무관하게 `transfer_id`로 join한다. 두 항목 중 하나만
도착하면 bounded pending table에서 deadline까지 기다리고, timeout, duplicate 또는 mismatch면
buffer를 return/revoke하고 `FRAME_REJECTED`를 보낸다. descriptor를 받았다는 이유만으로 FD를
만들거나 backing을 map하지 않으며, DMA-BUF import만으로 format을 추정하지 않는다.

AI는 다음 조건을 모두 확인한 뒤에만 buffer payload를 읽는다.

1. message sender가 EL2 launch policy의 Camera endpoint다.
2. session, frame sequence와 transfer ID가 유일하고 현재 state에 맞는다.
3. `total_size`가 imported DMA-BUF의 kernel-reported size와 일치한다.
4. FOURCC, dimension, plane 수가 allowlist와 상한을 만족한다.
5. 모든 `offset + size`, `stride × height` 계산이 overflow 없이 buffer 범위 안에 있다.

한 iteration의 순서는 다음과 같다.

1. 두 workload가 `HELLO/READY`를 보내고 Host가 role/CID/session을 확정한다.
2. Host가 AI에 `AI_CONFIG`, Camera에 `CAMERA_CONFIG`를 보내고 각각 ACK를 받는다.
3. Host가 새 `request_id`와 `frame_seq`를 가진 `CAPTURE`를 Camera에 보낸다.
4. Camera가 protected DMA-BUF를 만들고 `pvm_buffer_send()`로 AI에 보낸 뒤 `transfer_id`를 얻는다.
5. Camera가 size/format/plane layout과 `transfer_id`, `frame_seq`를 담은 `FRAME_DESC`를 별도
   `pvm_message_send()`로 AI에 보낸다. 두 send의 도착 순서는 보장하지 않는다.
6. AI가 `pvm_buffer_receive()`로 얻은 local FD와 `pvm_message_receive()`로 얻은 descriptor를
   `transfer_id`로 join하고 bounds/format 검증 뒤 `FRAME_ACCEPTED`를 보낸다.
7. AI가 buffer marker를 읽어 deterministic result를 생성하고 DMA-BUF를 return한 뒤 Camera에
   `FRAME_DONE`, Host에 allowlist `RESULT`를 각각 보낸다.
8. Camera가 return과 `FRAME_DONE`을 모두 확인해 원 FD를 닫고 Host에 capture ACK를 보낸다.
9. Host가 같은 `frame_seq`의 Camera ACK와 AI RESULT를 결합해 iteration을 완료한다.
10. 반복 종료 뒤 Host가 두 workload에 `STOP`을 보내고, Camera/AI는 `PEER_STOP`으로 서로의
    pending descriptor/buffer를 정리한 후 ACK, pVM 종료와 자원 회수를 확인한다.

## 4. 구현 계획

### P09B-0. VSOCK compatibility gate

1. `pkvm-full-clang`에 `CONFIG_VIRT_DRIVERS`, `CONFIG_ARM_PKVM_GUEST`,
   `CONFIG_VSOCKETS`, `CONFIG_VIRTIO_VSOCKETS`, `CONFIG_VHOST_VSOCK`을 built-in으로
   활성화한다.
2. Host와 protected Linux guest에 같은 Image를 사용하는 현재 구성을 유지한다.
3. `lkvm --protected --vsock <cid>` 한 대에서 Host↔guest bidirectional ping/ack를 실측한다.
4. `/dev/vhost-vsock`, restricted DMA pool, virtqueue와 teardown 결과를 기록한다.

이 gate가 실패하면 Trusted Access를 요구하지 않는다. 공개된 VSOCK 반환값과 로그로 원인을
기록하고 VSOCK 구성 자체를 수정한다. Host-facing 경로를 MMIO mailbox로 전환하거나
Camera↔AI 경로를 Host relay로 바꾸는 fallback은 허용하지 않는다.

### P09B-1. 공통 protocol/library

1. `work/src/tools/pvm-user-channel/include/`에 public message/API header를 둔다.
2. framing, endian 변환, exact I/O, deadline과 오류 mapping을 공통 C library로 구현한다.
3. Host Application과 guest workload에서 KVM/VSOCK ioctl 세부사항을 public API 밖으로 감춘다.
4. malformed header, oversized payload, unknown type와 partial I/O unit test를 만든다.

### P09B-2. Host Application ↔ Camera

1. Camera workload에 VSOCK client와 command state machine을 추가한다.
2. Host Application에서 `CAMERA_CONFIG`, `CAPTURE`, `STOP`을 보내고 request-correlated
   ACK/STATUS/ERROR를 받는다.
3. 중복 CAPTURE, 오래된 session/frame, 잘못된 순서의 command를 거부한다.
4. Host 연결 종료 또는 deadline 때 활성 DMA-BUF를 revoke/close하고 workload를 안전 종료한다.

### P09B-3. Camera ↔ AI

1. Phase 09의 raw ioctl 사용을 `libpvm_buffer` API로 감싼다.
2. `/dev/pvm-msg` guest driver, 별도 EL2 fixed-size message queue/virtual IRQ와
   `libpvm_message`를 구현한다.
3. `libpvm_buffer` import UAPI에 EL2/kernel이 확인한 `actual_size` 반환값을 추가한다.
4. `FRAME_DESC`에 size, FOURCC, dimension, plane offset/stride/size와 correlation field를 담고
   descriptor 자체에 frame byte를 넣지 못하게 고정 schema와 상한을 둔다.
5. AI가 buffer와 descriptor를 `transfer_id`로 join한 뒤 실제 DMA-BUF size, format allowlist와
   모든 plane bounds를 검증하도록 한다.
6. Camera send/AI import/return은 `libpvm_buffer`, descriptor/accept/done/error는
   `libpvm_message`를 통하게 하며 어느 한 채널의 데이터도 다른 채널에 piggyback하지 않는다.
7. descriptor-first, buffer-first, duplicate, mismatch, missing-half timeout과 queue-full을 검증한다.
8. 이 두 구간에 sibling VSOCK, Host Application callback 또는 Host frame/descriptor copy가
   없는지 정적/동적으로 검사한다.

### P09B-4. AI ↔ Host Application

1. AI workload에 VSOCK client와 result state machine을 추가한다.
2. Phase 09-b deterministic 처리 결과를 allowlist `RESULT` struct로 직렬화한다.
3. Host가 AI의 peer CID, session, request와 frame sequence를 확인한 뒤에만 결과를 수락한다.
4. raw frame, transfer token 또는 허용하지 않은 result field의 전송 시도를 API 단계에서
   거부한다.

### P09B-5. end-to-end orchestration

1. Host Application을 먼저 실행해 listener와 새 session을 만든다.
2. AI pVM(CID 4101, EL2 endpoint 1)을 먼저, Camera pVM(CID 4102, EL2 endpoint 2)을 다음에
   기동한다.
3. `READY → CONFIG → CAPTURE → DMA-BUF + FRAME_DESC join → RESULT/ACK`를 10회 반복한다.
4. shell은 build, initramfs packaging, QEMU 시작과 marker 수집에만 사용하고 runtime command와
   result 처리는 C Application/workload가 담당한다.
5. STOP과 비정상 연결 종료 모두에서 socket, DMA-BUF FD, EL2 lease, VM/vCPU와 page reference를
   회수한다.

### P09B-6. Phase 10 인계

1. deterministic result 생성 함수를 inference adapter interface 뒤로 격리한다.
2. Phase 10이 CPU inference를 연결할 입력 DMA-BUF view와 output result schema를 고정한다.
3. Phase 10에서 새 transport를 만들지 않고 Phase 09-b protocol을 회귀 시험하도록 한다.

## 5. 검증 계획

### 5.1 단계별 검증

| 단계 | 검사 | 필수 증거 |
|---|---|---|
| Host unit | framing, partial I/O, length/version/type 검사 | unit test rc=0 |
| VSOCK smoke | protected guest 한 대와 양방향 ping/ack | `PVM_USER_VSOCK_SMOKE_OK` |
| Host↔Camera | CONFIG/CAPTURE/STOP과 correlated ACK | `PVM_USER_HOST_CAMERA_OK` |
| Camera↔AI buffer | 서로 다른 local FD, 같은 transfer ID, return | Phase 09 marker + `PVM_USER_CAMERA_AI_BUFFER_OK` |
| Camera↔AI metadata | 별도 message queue에서 size/format/plane descriptor와 ACK/DONE 왕복 | `PVM_USER_CAMERA_AI_METADATA_OK` |
| buffer/metadata join | 두 도착 순서 모두 같은 transfer/frame으로 결합 | `PVM_USER_CAMERA_AI_JOIN_OK` |
| AI↔Host | allowlist RESULT 수신과 ACK | `PVM_USER_AI_HOST_OK` |
| E2E 반복 | 10개 frame sequence가 누락·중복 없이 완료 | frame별 marker + `PVM_USER_E2E_OK` |
| 종료·회수 | 정상/비정상 종료 뒤 socket, lease, FD, page 회수 | `Mlocked: 0 kB`, `PVM_USER_RECOVERY_OK` |

### 5.2 negative/fault 검증

| 주입 | 기대 결과 |
|---|---|
| 잘못된 magic/version/header length | 연결 또는 message를 protocol error로 거부 |
| 4 KiB 초과 payload와 length overflow | allocation/read 전에 거부 |
| role과 peer CID 불일치 | `HELLO` 거부, session 미등록 |
| duplicate request ID/frame sequence | 두 번째 message 거부, 결과 중복 생성 없음 |
| 이전 session의 ACK/RESULT replay | stale session으로 거부 |
| 허용되지 않은 RESULT field/type | AI API 또는 Host decoder에서 거부 |
| descriptor의 잘못된 FOURCC/plane 수 | AI가 payload 접근 전에 `FRAME_REJECTED` |
| plane offset/size/stride overflow 또는 DMA-BUF size 불일치 | AI가 payload 접근 전에 `FRAME_REJECTED`, buffer 반환 |
| descriptor/버퍼의 transfer ID 불일치 | 둘을 결합하지 않고 timeout 뒤 양쪽 state 정리 |
| descriptor-first와 buffer-first | 두 순서 모두 같은 frame으로 한 번만 결합 |
| duplicate descriptor 또는 message queue full | 중복/초과 message 거부, 기존 frame state 보존 |
| descriptor 또는 buffer 한쪽만 도착 | deadline 뒤 pending entry와 buffer/lease 회수 |
| Camera 연결 종료 | 활성 transfer revoke/close, AI/Host process 생존 |
| AI 연결/VM 종료 | Host가 false success를 만들지 않고 오류 기록, Camera lease 회수 |
| Host 연결 종료 | 두 workload가 deadline 뒤 안전 종료하고 자원 회수 |
| wrong EL2 receiver/stale token | 기존 Phase 09와 동일하게 import/return 거부 |

fault 시험은 availability 보장을 주장하기 위한 것이 아니라, 공격 또는 장애 뒤 stale resource와
잘못된 success가 남지 않는지를 확인하기 위한 것이다.

### 5.3 Host 비노출 검증

1. Host-facing encoder에 raw byte buffer/FD/token message type이 없음을 source scan한다.
2. VSOCK protocol capture에는 정의된 command/ACK/status/result만 있고 Camera marker, frame
   payload와 `FRAME_DESC`가 없음을 확인한다.
3. 기존 Phase 09 방식으로 transfer 중 Host stage-2의 frame backing 접근이 차단되는지 다시
   확인한다.
4. register fragment 방식이라 guest↔EL2 공유 message slot이 존재하지 않고, EL2 queue가 Host
   stage-2/Host userspace에 매핑되지 않는지 확인한다.
5. Camera↔AI buffer 및 metadata 전송 중 Host relay/backend callback과 Host-side
   frame/descriptor copy counter가 0인지 확인한다. EL2 내부의 bounded descriptor copy는
   허용한다.
6. AI result가 allowlist struct 크기와 field 집합을 정확히 만족하는지 Host decoder에서
   검증한다.

VSOCK virtqueue와 protocol payload는 Host가 볼 수 있으므로 이를 "Host 비노출"이라고 주장하지
않는다. 비노출 주장은 raw frame, DMA-BUF/EL2 식별자, model/intermediate data에만 적용한다.

## 6. 완료 조건

아래 조건을 모두 실제 E-1 QEMU session에서 통과해야 Phase 09-b를 완료로 판정한다.

| ID | 완료 조건 |
|---|---|
| CC-09B-01 | protected guest 두 대가 고유 CID로 Host Application과 동시에 연결되고 role/CID가 일치한다. |
| CC-09B-02 | Host↔Camera CONFIG/CAPTURE/STOP과 ACK/STATUS/ERROR가 request ID로 정확히 대응한다. |
| CC-09B-03 | Camera↔AI buffer는 Phase 09 EL2 DMA-BUF 경로만 사용해 전달되고 반환된다. |
| CC-09B-04 | Camera↔AI descriptor는 별도 EL2 message queue로 size/FOURCC/dimension/plane layout을 전달하며 buffer channel에 piggyback하지 않는다. |
| CC-09B-05 | AI가 buffer와 descriptor를 transfer ID로 결합하고 실제 size, format allowlist와 모든 plane bounds를 payload 접근 전에 검증한다. |
| CC-09B-06 | AI↔Host CONFIG/STOP과 allowlist RESULT/ACK/ERROR가 정상 왕복한다. |
| CC-09B-07 | 10회 반복에서 frame sequence 누락, 중복, cross-session 결과가 없다. |
| CC-09B-08 | malformed, oversized, wrong-CID, duplicate, replay, stale-token과 invalid/missing/mismatched descriptor 시험이 모두 예상대로 거부된다. |
| CC-09B-09 | Host protocol에 raw frame, descriptor, FD, PA/IPA/IOVA, EL2 token, model/intermediate data가 나타나지 않는다. |
| CC-09B-10 | transfer 중 Host의 frame backing과 message slot 접근 차단, Camera↔AI buffer/metadata Host relay/copy 부재가 재확인된다. |
| CC-09B-11 | 정상 STOP과 세 endpoint 장애 주입 뒤 false success 없이 message queue, pending join, lease, FD, socket, VM/vCPU와 page가 회수된다. |
| CC-09B-12 | panic/Oops/BUG와 unexpected timeout이 없고 최종 `PVM_USER_CHANNEL_VALIDATION_OK` marker가 출력된다. |
| CC-09B-13 | 재현 명령, 커널/kvmtool SHA, config, artifact digest와 전체 로그 경로가 문서화된다. |

Host unit test, build 또는 VSOCK smoke만 통과한 상태는 완료가 아니다. CC-09B-01~13을 모두
구현하고 실측한 뒤에만 상태를 완료로 변경하고, 관련 소스와 문서를 Phase 완료 커밋으로
commit한 후 현재 upstream에 push한다. 하나라도 실패하면 완료 커밋과 push를 하지 않는다.

## 7. 산출물

- protocol과 public API: `work/src/tools/pvm-user-channel/include/`
- 공통 C library와 Host Application: `work/src/tools/pvm-user-channel/`
- Camera/AI workload adapter: `work/src/tools/pvm-buffer/`
- Camera↔AI message API/driver: `work/src/tools/pvm-user-channel/driver/`
- EL2 message queue와 virtual IRQ: `work/src/pkvm-linux/`
- kernel config와 guest/Host initramfs packaging: `work/src/tools/qemu/`,
  `work/src/tools/pvm-buffer/build.sh`
- unit/negative/E2E test와 실행 도구: `work/src/tools/pvm-user-channel/tests/`,
  `work/src/tools/pvm-buffer/run-user-channel-*.sh`
- 실행 로그와 protocol evidence: `work/build/pvm-buffer/`, `work/build/pvm-framework/`
- 구현 및 검증 How-to와 결과: 이 디렉터리의 `README.md`, `VERIFICATION.md`

## 8. 한계

- E-1/E-3 QEMU 결과는 기능 검증이며 실물 하드웨어 보안 보증이 아니다.
- VSOCK payload는 의도적으로 Host에 노출되며 Host의 drop/delay/modify를 막지 않는다.
- cryptographic peer authentication, secure boot/pvmfw identity와 end-to-end result attestation은
  범위 밖이다.
- 단일 Host Application, Camera pVM 한 대, AI pVM 한 대와 단일 순차 pipeline만 다룬다.
- 처리량, 지연, backpressure tuning과 production-grade reconnect는 평가하지 않는다.
- metadata message는 EL2에서 복사되며 metadata zero-copy는 목표가 아니다. frame backing만
  zero-copy 판정 대상이다.
- 실제 inference, model secrecy 재검증과 result allowlist의 최종 의미는 Phase 10에서 완료한다.
