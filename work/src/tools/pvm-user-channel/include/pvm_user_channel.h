/* SPDX-License-Identifier: MIT */
#ifndef PVM_USER_CHANNEL_H
#define PVM_USER_CHANNEL_H

#include <stdint.h>

#define PVM_USER_PROTO_MAGIC UINT32_C(0x50564d55) /* "PVMU" */
#define PVM_USER_PROTO_VERSION UINT16_C(1)
#define PVM_USER_MAX_PAYLOAD UINT32_C(4096)
#define PVM_USER_DEFAULT_PORT UINT32_C(9009)
#define PVM_USER_HOST_CID UINT32_C(2)

enum pvm_user_role {
	PVM_USER_ROLE_UNKNOWN = 0,
	PVM_USER_ROLE_CAMERA = 1,
	PVM_USER_ROLE_AI = 2,
	PVM_USER_ROLE_HOST = 3,
};

enum pvm_user_message_type {
	PVM_USER_MSG_HELLO = 1,
	PVM_USER_MSG_READY = 2,
	PVM_USER_MSG_CAMERA_CONFIG = 3,
	PVM_USER_MSG_AI_CONFIG = 4,
	PVM_USER_MSG_CAPTURE = 5,
	PVM_USER_MSG_STOP = 6,
	PVM_USER_MSG_ACK = 7,
	PVM_USER_MSG_STATUS = 8,
	PVM_USER_MSG_RESULT = 9,
	PVM_USER_MSG_ERROR = 10,
	PVM_USER_MSG_FRAME_DESC = 11,
	PVM_USER_MSG_FRAME_ACCEPTED = 12,
	PVM_USER_MSG_FRAME_REJECTED = 13,
	PVM_USER_MSG_FRAME_DONE = 14,
	PVM_USER_MSG_PEER_STOP = 15,
	PVM_USER_MSG_PEER_ERROR = 16,
};

enum pvm_user_status {
	PVM_USER_STATUS_OK = 0,
	PVM_USER_STATUS_BAD_REQUEST = 1,
	PVM_USER_STATUS_BAD_SESSION = 2,
	PVM_USER_STATUS_BAD_SEQUENCE = 3,
	PVM_USER_STATUS_TIMEOUT = 4,
	PVM_USER_STATUS_UNSUPPORTED = 5,
	PVM_USER_STATUS_INTERNAL = 6,
};

struct pvm_user_header {
	uint32_t magic;
	uint16_t version;
	uint16_t header_len;
	uint32_t message_type;
	uint32_t payload_len;
	uint64_t session_id;
	uint64_t request_id;
	uint64_t frame_seq;
	uint32_t status;
	uint32_t reserved;
};

struct pvm_user_message {
	struct pvm_user_header header;
	uint8_t payload[PVM_USER_MAX_PAYLOAD];
};

struct pvm_user_hello {
	uint32_t role;
	uint32_t vsock_cid;
	uint32_t el2_endpoint;
	uint32_t reserved;
};

struct pvm_user_result {
	uint64_t frame_seq;
	uint32_t class_id;
	uint32_t score_q16;
	uint32_t status;
	uint32_t reserved;
};

struct pvm_user_session_state {
	uint64_t session_id;
	uint64_t last_request_id;
	uint64_t last_frame_seq;
};

#define PVM_FRAME_DESC_VERSION UINT32_C(1)
#define PVM_FRAME_MAX_PLANES 4
#define PVM_FRAME_FLAG_EOS UINT32_C(1)
#define PVM_FOURCC_GREY UINT32_C(0x59455247)

struct pvm_plane_desc {
	uint64_t offset;
	uint32_t stride;
	uint32_t size;
};

/* Camera↔AI metadata. This never contains a frame or an address. */
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
	struct pvm_plane_desc planes[PVM_FRAME_MAX_PLANES];
	uint64_t timestamp_ns;
	uint32_t flags;
	uint32_t reserved;
};

struct pvm_peer_control {
	uint32_t type;
	uint32_t length;
	uint32_t status;
	uint32_t reserved;
	uint64_t session_id;
	uint64_t frame_seq;
	uint64_t transfer_id;
};

struct pvm_peer_message {
	uint32_t type;
	uint32_t length;
	union {
		struct pvm_frame_desc frame;
		struct pvm_peer_control control;
	} body;
};

int pvm_frame_desc_validate(const struct pvm_frame_desc *desc);
int pvm_user_validate_peer(uint32_t expected_role, uint32_t peer_cid,
			   const struct pvm_user_hello *hello);
int pvm_user_session_accept(struct pvm_user_session_state *state,
			    uint64_t session_id, uint64_t request_id,
			    uint64_t frame_seq);

int pvm_user_vsock_connect(uint32_t cid, uint32_t port, int timeout_ms);
int pvm_user_vsock_listen(uint32_t port, int backlog);
int pvm_user_vsock_accept(int listener, uint32_t *peer_cid, int timeout_ms);
int pvm_user_send(int fd, const struct pvm_user_message *message,
		  int timeout_ms);
int pvm_user_receive(int fd, struct pvm_user_message *message,
		     int timeout_ms);
int pvm_user_message_init(struct pvm_user_message *message,
			  uint32_t type, uint64_t session_id,
			  uint64_t request_id, uint64_t frame_seq,
			  uint32_t status, const void *payload,
			  uint32_t payload_len);

#endif
