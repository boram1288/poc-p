// SPDX-License-Identifier: MIT
#include "include/pvm_message.h"
#include "include/pvm_user_channel.h"
#include "../pvm-buffer/include/pvm_buffer_uapi.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define SESSION_ID UINT64_C(0x900b)
#define FRAME_COUNT 10
#define CAMERA_ENDPOINT 2
#define AI_ENDPOINT 1
#define CAMERA_CID 4102
#define AI_CID 4101
#define FRAME_MARKER UINT64_C(0x090b000000000000)

static int user_send(int fd, uint32_t type, uint64_t req, uint64_t frame,
		     const void *payload, uint32_t len)
{
	struct pvm_user_message message;
	int ret = pvm_user_message_init(&message, type, SESSION_ID, req, frame,
					PVM_USER_STATUS_OK, payload, len);
	return ret ? ret : pvm_user_send(fd, &message, 10000);
}

static int user_recv(int fd, struct pvm_user_message *message)
{
	int ret = pvm_user_receive(fd, message, 30000);
	if (ret) return ret;
	return message->header.session_id == SESSION_ID ? 0 : -ESTALE;
}

static int peer_send(int fd, uint32_t peer, uint32_t type, uint64_t frame,
		     uint64_t transfer, const struct pvm_frame_desc *desc)
{
	struct pvm_peer_message message = { .type = type };
	if (type == PVM_USER_MSG_FRAME_DESC) {
		message.length = sizeof(message.body.frame);
		message.body.frame = *desc;
	} else {
		message.length = sizeof(message.body.control);
		message.body.control.type = type;
		message.body.control.length = sizeof(message.body.control);
		message.body.control.session_id = SESSION_ID;
		message.body.control.frame_seq = frame;
		message.body.control.transfer_id = transfer;
	}
	return pvm_message_send(fd, peer, &message,
				offsetof(struct pvm_peer_message, body) + message.length, NULL);
}

static int peer_recv(int fd, uint32_t sender, struct pvm_peer_message *message)
{
	uint32_t len = 0;
	int ret = pvm_message_receive(fd, sender, message, sizeof(*message), &len,
				      NULL, 30000);
	if (ret) return ret;
	if (len < offsetof(struct pvm_peer_message, body) ||
	    message->length + offsetof(struct pvm_peer_message, body) != len)
		return -EPROTO;
	return 0;
}

static struct pvm_frame_desc make_desc(uint64_t frame, uint64_t transfer)
{
	struct pvm_frame_desc desc = {
		.version = PVM_FRAME_DESC_VERSION, .descriptor_len = sizeof(desc),
		.session_id = SESSION_ID, .frame_seq = frame, .transfer_id = transfer,
		.total_size = 4096, .fourcc = PVM_FOURCC_GREY, .width = 64,
		.height = 64, .num_planes = 1,
		.planes = {{ .offset = 0, .stride = 64, .size = 4096 }},
	};
	return desc;
}

static int camera_negative(int host, int msg, int dev)
{
	struct pvm_peer_message response;
	struct pvm_user_message command;
	struct pvm_frame_desc desc;
	int i;
	for (i = 0; i < 64; i++)
		if (peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_PEER_ERROR, 0, 0, NULL)) return -1;
	if (!peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_PEER_ERROR, 0, 0, NULL)) return -1;
	if (user_send(host, PVM_USER_MSG_STATUS, 12, 0, NULL, 0) ||
	    user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_CAMERA_CONFIG ||
	    user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0)) return -1;
	desc = make_desc(100, 100); desc.fourcc = 0;
	if (peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 100, 100, &desc) ||
	    peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_REJECTED) return -1;
	desc = make_desc(101, 101);
	if (peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 101, 101, &desc) ||
	    peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 101, 101, &desc) ||
	    peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_REJECTED) return -1;
	desc = make_desc(102, 102);
	if (peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 102, 102, &desc) ||
	    peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_REJECTED) return -1;
	{
		struct pvm_buffer_alloc alloc = { .fd = -1 };
		struct pvm_buffer_send send = { .fd = -1, .receiver_endpoint = AI_ENDPOINT };
		struct pvm_buffer_token token;
		if (ioctl(dev, PVM_BUFFER_IOC_ALLOC, &alloc)) return -1;
		send.fd = alloc.fd;
		if (ioctl(dev, PVM_BUFFER_IOC_SEND, &send)) return -1;
		desc = make_desc(103, send.token + 1);
		if (peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 103, desc.transfer_id, &desc) ||
		    peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_REJECTED) return -1;
		token.token = send.token;
		if (ioctl(dev, PVM_BUFFER_IOC_WAIT_RETURN, &token)) return -1;
		close(alloc.fd);
	}
	printf("PVM_USER_NEGATIVE_CAMERA_OK\n");
	return user_send(host, PVM_USER_MSG_STATUS, 13, 0, NULL, 0);
}

static int ai_negative(int host, int msg, int dev)
{
	struct pvm_peer_message peer, duplicate;
	struct pvm_buffer_receive receive = { .fd = -1, .timeout_ms = 100 };
	struct pvm_buffer_token token;
	int i;
	for (i = 0; i < 64; i++)
		if (peer_recv(msg, CAMERA_ENDPOINT, &peer) || peer.type != PVM_USER_MSG_PEER_ERROR) return -1;
	if (user_send(host, PVM_USER_MSG_STATUS, 12, 0, NULL, 0)) return -1;
	if (peer_recv(msg, CAMERA_ENDPOINT, &peer) || peer.type != PVM_USER_MSG_FRAME_DESC ||
	    !pvm_frame_desc_validate(&peer.body.frame) ||
	    peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_REJECTED, 100, 100, NULL)) return -1;
	if (peer_recv(msg, CAMERA_ENDPOINT, &peer) || peer_recv(msg, CAMERA_ENDPOINT, &duplicate) ||
	    peer.body.frame.frame_seq != duplicate.body.frame.frame_seq ||
	    peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_REJECTED, 101, 101, NULL)) return -1;
	if (peer_recv(msg, CAMERA_ENDPOINT, &peer) || ioctl(dev, PVM_BUFFER_IOC_RECEIVE, &receive) == 0 ||
	    errno != ETIMEDOUT || peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_REJECTED, 102, 102, NULL)) return -1;
	receive.timeout_ms = 30000;
	if (peer_recv(msg, CAMERA_ENDPOINT, &peer) || ioctl(dev, PVM_BUFFER_IOC_RECEIVE, &receive)) return -1;
	if (receive.token == peer.body.frame.transfer_id) return -1;
	token.token = receive.token;
	if (ioctl(dev, PVM_BUFFER_IOC_RETURN, &token) ||
	    peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_REJECTED, 103,
		      peer.body.frame.transfer_id, NULL)) return -1;
	close(receive.fd);
	printf("PVM_USER_QUEUE_FULL_OK\nPVM_USER_DESCRIPTOR_NEGATIVE_OK\n");
	return user_send(host, PVM_USER_MSG_STATUS, 13, 0, NULL, 0);
}

static int camera(void)
{
	struct pvm_user_hello hello = { PVM_USER_ROLE_CAMERA, CAMERA_CID, CAMERA_ENDPOINT, 0 };
	struct pvm_user_message command;
	int host = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT, 10000);
	int msg = pvm_message_open();
	int dev = open("/dev/pvm-dmabuf", O_RDWR | O_CLOEXEC);
	uint64_t frame;
	if (host < 0 || msg < 0 || dev < 0) return 1;
	if (user_send(host, PVM_USER_MSG_HELLO, 1, 0, &hello, sizeof(hello)) ||
	    user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_CAMERA_CONFIG ||
	    user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0) ||
	    camera_negative(host, msg, dev)) return 1;
	for (frame = 1; frame <= FRAME_COUNT; frame++) {
		struct pvm_buffer_alloc alloc = { .fd = -1 };
		struct pvm_buffer_send send = { .fd = -1, .receiver_endpoint = AI_ENDPOINT };
		struct pvm_buffer_token token;
		struct pvm_frame_desc desc;
		struct pvm_peer_message response;
		volatile uint64_t *mapping;
		if (user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_CAPTURE ||
		    command.header.frame_seq != frame) return 1;
		if (ioctl(dev, PVM_BUFFER_IOC_ALLOC, &alloc)) return 1;
		mapping = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, alloc.fd, 0);
		if (mapping == MAP_FAILED) return 1;
		*mapping = FRAME_MARKER | frame;
		send.fd = alloc.fd;
		if (ioctl(dev, PVM_BUFFER_IOC_SEND, &send)) return 1;
		desc = make_desc(frame, send.token);
		if (pvm_frame_desc_validate(&desc) ||
		    peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, frame, send.token, &desc) ||
		    peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_ACCEPTED ||
		    peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_DONE) return 1;
		token.token = send.token;
		if (ioctl(dev, PVM_BUFFER_IOC_WAIT_RETURN, &token)) return 1;
		munmap((void *)mapping, 4096); close(alloc.fd);
		if (user_send(host, PVM_USER_MSG_ACK, command.header.request_id, frame, NULL, 0)) return 1;
		printf("PVM_USER_E2E_CAMERA_FRAME_OK: frame=%llu\n", (unsigned long long)frame);
	}
	if (user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_STOP ||
	    peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_PEER_STOP, 0, 0, NULL) ||
	    user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0)) return 1;
	printf("PVM_USER_HOST_CAMERA_OK\nPVM_USER_CAMERA_AI_BUFFER_OK\n");
	close(dev); close(msg); close(host); return 0;
}

static int ai(void)
{
	struct pvm_user_hello hello = { PVM_USER_ROLE_AI, AI_CID, AI_ENDPOINT, 0 };
	struct pvm_user_message command;
	int host = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT, 10000);
	int msg = pvm_message_open();
	int dev = open("/dev/pvm-dmabuf", O_RDWR | O_CLOEXEC);
	uint64_t frame;
	if (host < 0 || msg < 0 || dev < 0) return 1;
	if (user_send(host, PVM_USER_MSG_HELLO, 1, 0, &hello, sizeof(hello)) ||
	    user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_AI_CONFIG ||
	    user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0) ||
	    ai_negative(host, msg, dev)) return 1;
	for (frame = 1; frame <= FRAME_COUNT; frame++) {
		struct pvm_peer_message peer;
		struct pvm_buffer_receive receive = { .fd = -1, .timeout_ms = 30000 };
		struct pvm_buffer_token token;
		struct pvm_user_result result = { .frame_seq = frame, .class_id = 9,
			.score_q16 = 65535, .status = PVM_USER_STATUS_OK };
		volatile uint64_t *mapping;
		if (frame & 1) {
			if (peer_recv(msg, CAMERA_ENDPOINT, &peer) || ioctl(dev, PVM_BUFFER_IOC_RECEIVE, &receive)) return 1;
		} else {
			if (ioctl(dev, PVM_BUFFER_IOC_RECEIVE, &receive) || peer_recv(msg, CAMERA_ENDPOINT, &peer)) return 1;
		}
		if (peer.type != PVM_USER_MSG_FRAME_DESC || peer.length != sizeof(peer.body.frame) ||
		    pvm_frame_desc_validate(&peer.body.frame)) return 1;
		if (receive.token != peer.body.frame.transfer_id ||
		    receive.actual_size != peer.body.frame.total_size) return 1;
		mapping = mmap(NULL, receive.actual_size, PROT_READ | PROT_WRITE,
			       MAP_SHARED, receive.fd, 0);
		if (mapping == MAP_FAILED || *mapping != (FRAME_MARKER | frame)) return 1;
		if (peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_ACCEPTED, frame,
			      receive.token, NULL)) return 1;
		*mapping ^= UINT64_C(0x100000000);
		token.token = receive.token;
		if (ioctl(dev, PVM_BUFFER_IOC_RETURN, &token)) return 1;
		munmap((void *)mapping, receive.actual_size); close(receive.fd);
		if (peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_DONE, frame,
			      token.token, NULL) ||
		    user_send(host, PVM_USER_MSG_RESULT, frame + 100, frame,
			      &result, sizeof(result))) return 1;
		printf("PVM_USER_E2E_AI_FRAME_OK: frame=%llu\n", (unsigned long long)frame);
	}
	{
		struct pvm_peer_message peer;
		if (peer_recv(msg, CAMERA_ENDPOINT, &peer) || peer.type != PVM_USER_MSG_PEER_STOP) return 1;
	}
	if (user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_STOP ||
	    user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0)) return 1;
	printf("PVM_USER_CAMERA_AI_METADATA_OK\nPVM_USER_CAMERA_AI_JOIN_OK\nPVM_USER_AI_HOST_OK\n");
	close(dev); close(msg); close(host); return 0;
}

static int host(void)
{
	int listener = pvm_user_vsock_listen(PVM_USER_DEFAULT_PORT, 2);
	int camera_fd = -1, ai_fd = -1, i;
	struct pvm_user_message message;
	if (listener < 0) return 1;
	for (i = 0; i < 2; i++) {
		uint32_t cid = 0; struct pvm_user_hello hello; int fd;
		fd = pvm_user_vsock_accept(listener, &cid, 60000);
		if (fd < 0 || user_recv(fd, &message) || message.header.message_type != PVM_USER_MSG_HELLO ||
		    message.header.payload_len != sizeof(hello)) return 1;
		memcpy(&hello, message.payload, sizeof(hello));
		if (hello.vsock_cid != cid) return 1;
		if (hello.role == PVM_USER_ROLE_CAMERA && cid == CAMERA_CID) camera_fd = fd;
		else if (hello.role == PVM_USER_ROLE_AI && cid == AI_CID) ai_fd = fd;
		else return 1;
	}
	close(listener);
	if (camera_fd < 0 || ai_fd < 0) return 1;
	if (user_send(camera_fd, PVM_USER_MSG_CAMERA_CONFIG, 11, 0, NULL, 0) ||
	    user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_ACK ||
	    message.header.request_id != 11 || user_recv(camera_fd, &message) ||
	    message.header.message_type != PVM_USER_MSG_STATUS ||
	    user_send(ai_fd, PVM_USER_MSG_AI_CONFIG, 10, 0, NULL, 0) || user_recv(ai_fd, &message) ||
	    message.header.message_type != PVM_USER_MSG_ACK || message.header.request_id != 10 ||
	    user_recv(ai_fd, &message) || message.header.message_type != PVM_USER_MSG_STATUS ||
	    user_send(camera_fd, PVM_USER_MSG_CAMERA_CONFIG, 12, 0, NULL, 0) ||
	    user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_ACK ||
	    message.header.request_id != 12 ||
	    user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_STATUS ||
	    user_recv(ai_fd, &message) || message.header.message_type != PVM_USER_MSG_STATUS) return 1;
	printf("PVM_USER_NEGATIVE_OK\n");
	for (i = 1; i <= FRAME_COUNT; i++) {
		if (user_send(camera_fd, PVM_USER_MSG_CAPTURE, 20 + i, i, NULL, 0) ||
		    user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_ACK ||
		    message.header.request_id != (uint64_t)(20 + i) || message.header.frame_seq != (uint64_t)i ||
		    user_recv(ai_fd, &message) || message.header.message_type != PVM_USER_MSG_RESULT ||
		    message.header.frame_seq != (uint64_t)i || message.header.payload_len != sizeof(struct pvm_user_result)) return 1;
		printf("PVM_USER_E2E_HOST_FRAME_OK: frame=%d\n", i);
	}
	if (user_send(camera_fd, PVM_USER_MSG_STOP, 40, 0, NULL, 0) || user_recv(camera_fd, &message) ||
	    message.header.message_type != PVM_USER_MSG_ACK ||
	    user_send(ai_fd, PVM_USER_MSG_STOP, 41, 0, NULL, 0) || user_recv(ai_fd, &message) ||
	    message.header.message_type != PVM_USER_MSG_ACK) return 1;
	printf("PVM_USER_E2E_OK: frames=10\nPVM_USER_HOST_PROTOCOL_ALLOWLIST_OK\nPVM_USER_RECOVERY_OK\n");
	close(camera_fd); close(ai_fd); return 0;
}

static int fault_guest(uint32_t role, uint32_t cid, uint32_t endpoint)
{
	struct pvm_user_hello hello = { role, cid, endpoint, 0 };
	struct pvm_user_message message;
	int fd = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT, 10000);
	if (fd < 0 || user_send(fd, PVM_USER_MSG_HELLO, 1, 0, &hello, sizeof(hello)) ||
	    user_recv(fd, &message) || message.header.message_type != PVM_USER_MSG_ERROR) return 1;
	close(fd);
	fd = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT, 10000);
	if (fd < 0 || user_send(fd, PVM_USER_MSG_HELLO, 2, 0, &hello, sizeof(hello))) return 1;
	if (!user_recv(fd, &message)) return 1;
	printf("PVM_USER_%s_HOST_FAILURE_RECOVERY_OK\n",
	       role == PVM_USER_ROLE_CAMERA ? "CAMERA" : "AI");
	close(fd); return 0;
}

static int fault_accept(int listener, uint32_t expected_role, uint32_t expected_cid)
{
	struct pvm_user_message message;
	struct pvm_user_hello hello;
	uint32_t cid = 0;
	int fd = pvm_user_vsock_accept(listener, &cid, 60000);
	if (fd < 0 || user_recv(fd, &message) || message.header.message_type != PVM_USER_MSG_HELLO ||
	    message.header.payload_len != sizeof(hello)) return -1;
	memcpy(&hello, message.payload, sizeof(hello));
	if (cid != expected_cid || pvm_user_validate_peer(expected_role, cid, &hello)) return -1;
	return fd;
}

static int fault_host(void)
{
	struct pvm_user_message message;
	int listener = pvm_user_vsock_listen(PVM_USER_DEFAULT_PORT, 2);
	int ai_fd, camera_fd, camera_reconnect, ai_reconnect;
	if (listener < 0) return 1;
	ai_fd = fault_accept(listener, PVM_USER_ROLE_AI, AI_CID);
	camera_fd = fault_accept(listener, PVM_USER_ROLE_CAMERA, CAMERA_CID);
	if (ai_fd < 0 || camera_fd < 0) return 1;
	if (user_send(camera_fd, PVM_USER_MSG_ERROR, 10, 0, NULL, 0) ||
	    !user_recv(camera_fd, &message)) return 1;
	close(camera_fd);
	camera_reconnect = fault_accept(listener, PVM_USER_ROLE_CAMERA, CAMERA_CID);
	if (camera_reconnect < 0 || user_send(ai_fd, PVM_USER_MSG_ERROR, 11, 0, NULL, 0) ||
	    !user_recv(ai_fd, &message)) return 1;
	close(ai_fd);
	ai_reconnect = fault_accept(listener, PVM_USER_ROLE_AI, AI_CID);
	if (ai_reconnect < 0) return 1;
	close(camera_reconnect); close(ai_reconnect); close(listener);
	printf("PVM_USER_CAMERA_FAILURE_RECOVERY_OK\nPVM_USER_AI_FAILURE_RECOVERY_OK\n"
	       "PVM_USER_HOST_FAILURE_INJECTED_OK\n");
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 2) return 2;
	if (!strcmp(argv[1], "host")) return host();
	if (!strcmp(argv[1], "camera")) return camera();
	if (!strcmp(argv[1], "ai")) return ai();
	if (!strcmp(argv[1], "fault-host")) return fault_host();
	if (!strcmp(argv[1], "fault-camera")) return fault_guest(PVM_USER_ROLE_CAMERA, CAMERA_CID, CAMERA_ENDPOINT);
	if (!strcmp(argv[1], "fault-ai")) return fault_guest(PVM_USER_ROLE_AI, AI_CID, AI_ENDPOINT);
	return 2;
}
