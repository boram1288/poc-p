# Phase 09 EL2 DMA-BUF channel 설계

## 1. 결정 요약

Phase 09는 Camera pVM이 만든 DMA-BUF를 AI pVM이 새로운 local FD로 import하여 읽고 쓰는
경로를 구현한다. runtime data/control path에는 Host EL1 kernel, Host userspace 또는 VMM
backend를 두지 않는다. pVM 사이의 격리를 유지하기 위해 trusted EL2가 buffer mapping,
receiver authorization, notification과 revoke를 중재한다.

```text
Camera test workload
  -> libpvm_buffer
  -> Camera guest /dev/pvm-dmabuf
  -> HVC
  -> EL2 pVM DMA-BUF manager
  -> virtual IRQ
  -> AI guest /dev/pvm-dmabuf
  -> libpvm_buffer
  -> AI test workload
```

서로 다른 pVM은 서로 다른 Linux kernel과 FD table을 사용한다. 따라서 Camera의 숫자 FD를
`SCM_RIGHTS`로 AI에 그대로 전달할 수 없다. 이 설계에서 FD-passing은 다음 semantics를
가진 abstraction이다.

1. Camera guest driver가 Camera process의 DMA-BUF FD를 resolve한다.
2. EL2가 backing pages와 허용된 receiver를 묶은 transfer object를 만든다.
3. AI guest driver가 transfer object를 import하고 같은 backing을 가리키는 새 DMA-BUF를 만든다.
4. AI kernel이 AI process의 FD table에 새로운 local FD를 설치한다.

두 FD의 숫자는 서로 달라도 같은 protected backing을 가리킨다. PA, guest IPA, Host VA 또는
Camera의 숫자 FD는 pVM 간 protocol field로 전달하지 않는다.

## 2. `virtio-vsock` 및 FF-A 판정

표준 `virtio-vsock`은 guest와 Host backend 사이의 transport다. sibling pVM을 CID로
addressing하더라도 Host transport/backend가 packet을 중계하므로 strict Host bypass를
충족하지 않는다. Phase 09에서는 baseline/debug transport로만 사용할 수 있고 완료 경로에는
사용하지 않는다.

FF-A는 VM endpoint 사이 message passing과 memory sharing을 표현할 수 있어 장기적으로는
표준화 후보다. 그러나 현재 pKVM FF-A proxy는 TrustZone service proxy이며 VM-to-VM
`FFA_MSG_SEND`, `FFA_MSG_POLL`, `FFA_MSG_WAIT` routing을 제공하지 않는다. FF-A를 채택하려면
EL2에 Non-secure virtual FF-A instance, endpoint discovery, RX/TX mailbox, notification,
VM-to-VM `MEM_SHARE/LEND/RETRIEVE/RELINQUISH`를 새로 구현해야 한다.

Phase 09에서는 Phase 08의 EL2 shared-buffer manager를 확장한 전용 HVC와 virtual IRQ를
사용한다. FF-A 호환 transport로의 교체는 후속 과제로 둔다. Secure Partition 또는 TA를
broker로 두지 않는다.

이 선택은 Trusted Access 권한 없이 검증할 수 있는 범위를 의도적으로 고정한다. endpoint
identity, lease token, mapping state와 event는 pKVM EL2가 관리하고, 성공/거부 여부는 guest의
HVC 반환값과 공개 console marker로만 판정한다. OP-TEE/TA/FF-A activation은 Phase 09의
dependency나 완료 조건이 아니다.

## 3. 신뢰 경계와 구성 모듈

| 모듈 | 실행 위치 | 역할 |
|---|---|---|
| `camera_workload` | Camera pVM userspace | DMA-BUF allocate, frame write, send, 반환 확인 |
| `ai_workload` | AI pVM userspace | blocking receive, local FD read/write, 반환 |
| `libpvm_buffer` | 각 pVM userspace | application API와 ioctl 세부사항 은닉 |
| `pvm-dmabuf` guest driver | 각 pVM kernel | FD resolve/import, DMA-BUF lifecycle, HVC, virtual IRQ 처리 |
| EL2 DMA-BUF manager | protected hypervisor | endpoint policy, backing-page mapping, state, revoke |
| EL2 event channel | protected hypervisor | receiver event queue와 virtual IRQ injection |
| VM manager/VMM | Host | launch-time endpoint/IRQ 설정만 수행; runtime relay에는 불참 |

Host가 pVM을 생성하고 vCPU를 schedule하는 역할은 남는다. 그러나 Host는 DMA-BUF page를 Host
stage-2에 map하거나 control message를 복사하지 않는다. Host가 pVM을 중단시키는 availability
공격은 이 설계가 막지 않는다.

endpoint identity는 Host가 runtime request에 넣는 CID나 process ID를 신뢰하지 않는다. EL2가
pVM 생성 시 부여한 immutable VM identity와 launch policy의 `Camera -> AI` edge를 사용한다.

## 4. Application API

Application은 HVC와 ioctl을 직접 사용하지 않고 다음 C API만 사용한다.

```c
/* work/src/tools/pvm-buffer/include/pvm_buffer.h 예정 API */

enum pvm_buffer_endpoint {
	PVM_BUFFER_CAMERA = 1,
	PVM_BUFFER_AI = 2,
};

enum pvm_buffer_access {
	PVM_BUFFER_READ  = 1U << 0,
	PVM_BUFFER_WRITE = 1U << 1,
};

struct pvm_buffer_offer {
	int dma_buf_fd;
	size_t size;
	uint32_t access;
	uint64_t application_cookie;
};

struct pvm_buffer_received {
	int dma_buf_fd;             /* AI kernel이 설치한 새로운 local FD */
	size_t size;
	uint32_t access;
	uint64_t application_cookie;
	uint64_t transfer_id;
};

struct pvm_buffer_channel;

int pvm_buffer_channel_open(enum pvm_buffer_endpoint peer,
			    struct pvm_buffer_channel **out_channel);
int pvm_buffer_alloc(size_t size, int *out_dma_buf_fd);
int pvm_buffer_send(struct pvm_buffer_channel *channel,
		    const struct pvm_buffer_offer *offer,
		    uint64_t *out_transfer_id);
int pvm_buffer_receive(struct pvm_buffer_channel *channel,
		       struct pvm_buffer_received *out_received,
		       int timeout_ms);
int pvm_buffer_return(struct pvm_buffer_channel *channel,
		      uint64_t transfer_id);
int pvm_buffer_wait_return(struct pvm_buffer_channel *channel,
			   uint64_t transfer_id, int timeout_ms);
int pvm_buffer_revoke(struct pvm_buffer_channel *channel,
		      uint64_t transfer_id);
int pvm_buffer_cpu_begin(int dma_buf_fd, uint32_t access);
int pvm_buffer_cpu_end(int dma_buf_fd, uint32_t access);
void pvm_buffer_channel_close(struct pvm_buffer_channel *channel);
```

`pvm_buffer_send()`는 export, receiver queue 등록과 notification을 하나의 transaction으로
수행한다. 중간 단계가 실패하면 AI mapping을 남기지 않는다. `pvm_buffer_receive()`는 event를
기다린 후 import를 수행하고 성공한 경우에만 local FD를 반환한다.

PoC는 한 transfer가 활성화된 동안 Camera workload의 buffer 접근을 중단한다. AI에는
`READ | WRITE` lease를 부여한다. AI가 `pvm_buffer_return()`을 호출하면 AI mapping과 local
DMA-BUF를 무효화하고 Camera가 다시 접근할 수 있게 한다. 이 규칙으로 두 pVM의 동시 write와
cache/data race를 피한다.

## 5. Camera test workload 예제

```c
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "pvm_buffer.h"

#define FRAME_SIZE 4096U

int main(void)
{
	struct pvm_buffer_channel *channel = NULL;
	struct pvm_buffer_offer offer = { 0 };
	uint64_t transfer_id;
	uint8_t *frame;
	int fd = -1;
	int rc;

	rc = pvm_buffer_channel_open(PVM_BUFFER_AI, &channel);
	if (rc)
		goto out;

	rc = pvm_buffer_alloc(FRAME_SIZE, &fd);
	if (rc)
		goto out;

	frame = mmap(NULL, FRAME_SIZE, PROT_READ | PROT_WRITE,
		     MAP_SHARED, fd, 0);
	if (frame == MAP_FAILED) {
		rc = -1;
		goto out;
	}

	/* DMA-BUF CPU access protocol 안에서 test frame을 기록한다. */
	rc = pvm_buffer_cpu_begin(fd, PVM_BUFFER_WRITE);
	if (rc)
		goto out_unmap;
	memset(frame, 0, FRAME_SIZE);
	memcpy(frame, "CAMERA_FRAME_V1", sizeof("CAMERA_FRAME_V1"));
	pvm_buffer_cpu_end(fd, PVM_BUFFER_WRITE);

	offer.dma_buf_fd = fd;
	offer.size = FRAME_SIZE;
	offer.access = PVM_BUFFER_READ | PVM_BUFFER_WRITE;
	offer.application_cookie = 1;

	/* 이 호출 뒤에는 AI가 반환할 때까지 frame을 접근하지 않는다. */
	rc = pvm_buffer_send(channel, &offer, &transfer_id);
	if (rc)
		goto out_unmap;

	rc = pvm_buffer_wait_return(channel, transfer_id, 5000);
	if (rc) {
		pvm_buffer_revoke(channel, transfer_id);
		goto out_unmap;
	}

	/* AI가 같은 backing에 기록한 결과를 확인한다. */
	pvm_buffer_cpu_begin(fd, PVM_BUFFER_READ);
	if (memcmp(frame + 64, "AI_WRITE_OK", sizeof("AI_WRITE_OK")) != 0)
		rc = -1;
	pvm_buffer_cpu_end(fd, PVM_BUFFER_READ);

	if (!rc)
		puts("PVM_DMABUF_CAMERA_ROUNDTRIP_OK");

out_unmap:
	munmap(frame, FRAME_SIZE);
out:
	if (fd >= 0)
		close(fd);
	pvm_buffer_channel_close(channel);
	return rc ? 1 : 0;
}
```

## 6. AI test workload 예제

```c
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "pvm_buffer.h"

int main(void)
{
	struct pvm_buffer_channel *channel = NULL;
	struct pvm_buffer_received received = { .dma_buf_fd = -1 };
	uint8_t *frame;
	int rc;

	rc = pvm_buffer_channel_open(PVM_BUFFER_CAMERA, &channel);
	if (rc)
		goto out;

	/* EL2 event channel을 기다리고 같은 backing의 새 local FD를 받는다. */
	rc = pvm_buffer_receive(channel, &received, 5000);
	if (rc)
		goto out;

	if (received.size != 4096 ||
	    received.access != (PVM_BUFFER_READ | PVM_BUFFER_WRITE)) {
		rc = -1;
		goto out_fd;
	}

	frame = mmap(NULL, received.size, PROT_READ | PROT_WRITE,
		     MAP_SHARED, received.dma_buf_fd, 0);
	if (frame == MAP_FAILED) {
		rc = -1;
		goto out_fd;
	}

	pvm_buffer_cpu_begin(received.dma_buf_fd,
			     PVM_BUFFER_READ | PVM_BUFFER_WRITE);
	if (memcmp(frame, "CAMERA_FRAME_V1", sizeof("CAMERA_FRAME_V1")) != 0)
		rc = -1;
	else
		memcpy(frame + 64, "AI_WRITE_OK", sizeof("AI_WRITE_OK"));
	pvm_buffer_cpu_end(received.dma_buf_fd,
			   PVM_BUFFER_READ | PVM_BUFFER_WRITE);

	munmap(frame, received.size);
	if (rc)
		goto out_fd;

	/* 반환이 완료되면 이 FD의 backing 접근은 더 이상 허용되지 않는다. */
	rc = pvm_buffer_return(channel, received.transfer_id);
	if (!rc)
		puts("PVM_DMABUF_AI_READ_WRITE_OK");

out_fd:
	close(received.dma_buf_fd);
out:
	pvm_buffer_channel_close(channel);
	return rc ? 1 : 0;
}
```

예제는 API 형태와 ownership rule을 설명하기 위한 설계 코드다. `libpvm_buffer`, guest driver와
EL2 HVC가 구현되기 전에는 build 또는 실행되지 않는다.

## 7. 전체 sequence diagram

```mermaid
sequenceDiagram
    autonumber
    participant Host as Host VM manager/VMM
    participant CApp as Camera workload
    participant CLib as Camera libpvm_buffer
    participant Heap as Camera DMA-BUF heap
    participant CDrv as Camera pvm-dmabuf driver
    participant EL2 as EL2 DMA-BUF manager/event channel
    participant ADrv as AI pvm-dmabuf driver
    participant ALib as AI libpvm_buffer
    participant AApp as AI workload

    Host->>EL2: Launch Camera/AI pVM and bind immutable endpoint policy
    Note over Host: Launch-time control only<br/>No runtime relay or buffer mapping

    AApp->>ALib: pvm_buffer_receive(timeout)
    ALib->>ADrv: PVM_DMABUF_IOC_RECEIVE
    ADrv->>EL2: HVC WAIT_EVENT
    EL2-->>ADrv: Block until receiver event

    CApp->>CLib: pvm_buffer_alloc(4096)
    CLib->>Heap: DMA_HEAP_IOCTL_ALLOC
    Heap-->>CApp: Camera local dma_buf_fd
    CApp->>CApp: mmap + write CAMERA_FRAME_V1
    CApp->>CLib: pvm_buffer_send(fd, AI, RW)
    CLib->>CDrv: PVM_DMABUF_IOC_SEND
    CDrv->>CDrv: Resolve FD and backing pages
    CDrv->>EL2: HVC EXPORT(receiver=AI, pages, RW)
    EL2->>EL2: Validate Camera identity and Camera-to-AI policy
    EL2->>EL2: Remove/suspend Camera access and map backing into AI
    EL2->>EL2: Create transfer_id and enqueue receiver event
    EL2->>ADrv: Inject protected virtual IRQ
    EL2-->>CDrv: transfer_id
    CDrv-->>CLib: send success
    CLib-->>CApp: transfer_id; do not access during lease

    ADrv->>EL2: HVC IMPORT(transfer_id)
    EL2->>EL2: Validate receiver identity and active generation
    EL2-->>ADrv: Authorized AI import mapping
    ADrv->>ADrv: Create dma_buf and install AI local FD
    ADrv-->>ALib: received metadata + new FD
    ALib-->>AApp: pvm_buffer_received
    AApp->>AApp: mmap, read CAMERA_FRAME_V1
    AApp->>AApp: write AI_WRITE_OK
    AApp->>ALib: pvm_buffer_return(transfer_id)
    ALib->>ADrv: PVM_DMABUF_IOC_RETURN
    ADrv->>EL2: HVC RETURN
    EL2->>EL2: Unmap AI and restore Camera ownership
    EL2->>CDrv: Inject return virtual IRQ
    EL2-->>ADrv: return complete
    ADrv-->>AApp: success; imported FD no longer grants access

    CApp->>CLib: pvm_buffer_wait_return(transfer_id)
    CLib->>CDrv: PVM_DMABUF_IOC_WAIT_RETURN
    CDrv-->>CApp: ownership restored
    CApp->>CApp: read AI_WRITE_OK from original FD
```

## 8. Transfer state와 오류 처리

```text
ALLOCATED
  -> EXPORTED
  -> AI_IMPORTED_RW
  -> RETURNING
  -> CAMERA_OWNED
  -> REVOKED
```

| 상황 | 필요한 처리 |
|---|---|
| 잘못된 receiver endpoint | EL2가 export를 거부하고 mapping을 만들지 않음 |
| 위조·stale `transfer_id` | VM identity와 generation 불일치로 import 거부 |
| AI import 전 Camera 종료 | transfer 폐기, page reference와 event 회수 |
| AI lease 중 Camera 종료 | AI mapping revoke 후 모든 reference 회수 |
| AI 종료 또는 timeout | EL2가 AI mapping을 revoke하고 Camera ownership 복구 |
| 중복 import/return | state mismatch로 거부 |
| revoke 이후 FD 접근 | mapping 제거 후 fault 또는 `-EIO`로 실패 |
| size/권한 변조 | EL2가 보관한 metadata를 기준으로 검증하고 guest 값을 신뢰하지 않음 |

## 9. 구현 순서와 완료 조건

1. 두 guest에 `pvm-dmabuf` driver와 고정 virtual IRQ를 추가한다.
2. EL2 event queue로 payload 없는 Camera-to-AI ping/ack를 검증한다.
3. 한 페이지 DMA-BUF의 Camera export와 AI read-only import를 구현한다.
4. ownership lease와 AI write, return 뒤 Camera read를 구현한다.
5. timeout, wrong receiver, stale handle, teardown revoke를 검증한다.
6. multi-page frame과 DMA device mapping으로 확장한다.

| 완료 조건 | 필수 증거 |
|---|---|
| Host 없는 control path | runtime 중 Host relay/backend callback이 없고 EL2 virtual IRQ만 발생 |
| FD abstraction | Camera FD와 AI FD가 서로 다른 local FD이면서 동일 backing marker를 관찰 |
| AI read/write | AI가 Camera marker를 읽고 결과를 쓰며 Camera가 반환 뒤 결과를 읽음 |
| Host 비노출 | transfer 동안 Host stage-2에 data/control page가 매핑되지 않음 |
| 단일 writer | AI lease 동안 Camera 접근이 차단되고 반환 뒤에만 복구 |
| receiver 격리 | 승인되지 않은 pVM의 import가 거부됨 |
| revoke | timeout, close, pVM teardown 뒤 imported mapping과 FD access가 무효화됨 |
| zero-copy | Camera backing page가 유지되고 Host relay/copy가 발생하지 않음 |

성능, 동시 multi-producer, implicit fencing 및 production-grade DMA-BUF synchronization은 이
PoC의 완료 조건에 포함하지 않는다.

### 9.1 EL2 primitive 실측 checkpoint

2026-08-19 QEMU E-1 실행에서 단계 2와 한 페이지 ownership lease primitive를 실측했다.
Camera export가 만든 event를 AI의 `EVENT_POLL` HVC가 consume할 때 EL2가 Host exit 없이
guest EL1 IRQ vector를 주입했다. nVHE fast HVC loop에서는 saved context만 갱신해서는 IRQ가
반영되지 않으므로, guest `ELR_EL1/SPSR_EL1`은 EL12 accessor로, 재진입
`ELR_EL2/SPSR_EL2`는 live context로 함께 갱신한다.

정상 read/write/return, lease 중 owner data abort, wrong receiver, stale token, owner와 receiver
teardown, timeout revoke가 모두 통과했다. 근거 로그는
`work/build/pvm-framework/console-phase09-twenty-fourth.log`다. 이 checkpoint는 flat guest의
4 KiB page를 사용하므로 Linux DMA-BUF object와 서로 다른 local FD를 증명하지 않는다.
다음 구현 단위는 Linux guest의 `pvm-dmabuf` exporter/importer와 userspace FD test다.

## 9.2 Linux guest 통합 완료 (2026-08-19)

`work/src/tools/pvm-buffer/` 아래 Linux guest용 UAPI, DMA-BUF export/import driver, Camera
workload, AI workload를 `aarch64-linux-gnu-gcc-9`로 정적 ARM64 바이너리까지 빌드했다.
`pvm_dmabuf.ko`는 `pkvm-full-clang` 커널 설정을 기준으로 module 빌드를 통과했다.

`work/src/tools/pvm-buffer/run.sh`가 `pkvm-full-clang` Image를 Host 커널과 protected guest
커널로 함께 재사용해 `lkvm --protected`로 AI pVM(먼저 생성되어 endpoint 1)과 Camera
pVM(나중에 생성되어 endpoint 2)을 독립된 Linux kernel로 각각 기동한다. Camera가 4 KiB
DMA-BUF를 alloc/export하고, AI가 새로운 local FD로 import해 marker를 read/write한 뒤
반환하면 Camera가 원래 FD에서 AI의 결과를 읽는 전체 sequence(본 문서 7절)를 실제 Linux
guest 두 개로 재현해 통과했다. 실행 로그는
`work/build/pvm-buffer/console-pvm-buffer-linux.log`이며 상세 마커는
[phase-09 README](README.md#linux-guest-통합-실측-결과-2026-08-19)에 있다.

이 통합 과정에서 `pvm_cpu_lease_export()`가 실제 Linux guest RAM의 PMD(2 MiB) stage-2 block을
4 KiB 단위로 검증하다 매번 거부하던 결함을 발견해, 기존 Host 전용 stage-2 split
primitive(`__pkvm_host_split_guest`)를 재사용하는 방식으로 수정했다. flat guest만으로는
드러나지 않던 결함이었다.

이 단계에서도 FF-A activation, OP-TEE/TA 호출, Secure Partition broker,
`--protected-ffa`는 사용하지 않았다.

## 10. 근거 자료

- [Arm Firmware Framework for Arm A-profile specification](https://developer.arm.com/documentation/den0077/latest/):
  FF-A endpoint, message passing과 memory transaction 규격
- [Linux VSOCK documentation](https://docs.kernel.org/7.1/admin-guide/sysctl/net.html#vsock-sockets):
  VM/Host transport와 CID routing 동작
- [Linux pKVM documentation](https://www.kernel.org/doc/html/latest/virt/kvm/arm/pkvm.html#proxying-of-trustzone-services):
  현재 pKVM FF-A proxy의 TrustZone service 경계
- [현재 pKVM `ffa_call_supported()`](../../work/src/pkvm-linux/arch/arm64/kvm/hyp/nvhe/ffa.c):
  indirect message/notification 미지원과 direct request의 Secure Monitor forwarding을 확인한 소스
