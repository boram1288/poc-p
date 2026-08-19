// SPDX-License-Identifier: MIT
#include "include/pvm_message.h"
#include "include/pvm_user_channel.h"
#include "../pvm-buffer/include/pvm_buffer_uapi.h"
#include "../vision-pipeline/include/pvm_sha256.h"
#include "../vision-pipeline/include/pvm_vision_fixture.h"

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define VISION_SESSION_ID UINT64_C(0x9010)
#define CAMERA_ENDPOINT 2
#define AI_ENDPOINT 1
#define CAMERA_CID 4102
#define AI_CID 4101
#define FRAMES_PATH "/opt/vision/frames.bin"
#define ORACLE_PATH "/opt/vision/oracle.bin"

_Static_assert(sizeof(struct pvm_vision_detection) == sizeof(struct pvm_user_detection),
	       "fixture and protocol detection layouts differ");
_Static_assert(sizeof(struct pvm_vision_fixture_header) == 72, "fixture header ABI");
_Static_assert(sizeof(struct pvm_vision_oracle_record) == 432, "fixture record ABI");

static int read_exact_at(int fd, void *buffer, size_t length, off_t offset)
{
	uint8_t *cursor = buffer;
	while (length) {
		ssize_t ret = pread(fd, cursor, length, offset);
		if (ret < 0 && errno == EINTR) continue;
		if (ret <= 0) return ret ? -errno : -EIO;
		cursor += ret; length -= (size_t)ret; offset += ret;
	}
	return 0;
}

static int load_oracle(struct pvm_vision_fixture_header *header,
		       struct pvm_vision_oracle_record records[PVM_VISION_FRAME_COUNT])
{
	int fd = open(ORACLE_PATH, O_RDONLY | O_CLOEXEC);
	int ret;
	if (fd < 0) return -errno;
	ret = read_exact_at(fd, header, sizeof(*header), 0);
	if (!ret)
		ret = read_exact_at(fd, records,
				    sizeof(*records) * PVM_VISION_FRAME_COUNT,
				    sizeof(*header));
	close(fd);
	if (ret) return ret;
	if (memcmp(header->magic, PVM_VISION_FIXTURE_MAGIC, 8) ||
	    header->version != PVM_VISION_FIXTURE_VERSION ||
	    header->frame_count != PVM_VISION_FRAME_COUNT ||
	    header->page_size != PVM_VISION_PAGE_SIZE ||
	    header->max_detections != PVM_VISION_MAX_DETECTIONS ||
	    header->active_size != PVM_VISION_ACTIVE_SIZE)
		return -EPROTO;
	return 0;
}

static int vision_user_send(int fd, uint32_t type, uint64_t request,
			    uint64_t frame, const void *payload, uint32_t length)
{
	struct pvm_user_message message;
	int ret = pvm_user_message_init(&message, type, VISION_SESSION_ID,
					request, frame, PVM_USER_STATUS_OK,
					payload, length);
	return ret ? ret : pvm_user_send(fd, &message, 30000);
}

static int vision_user_recv(int fd, struct pvm_user_message *message)
{
	int ret = pvm_user_receive(fd, message, 60000);
	if (ret) return ret;
	return message->header.session_id == VISION_SESSION_ID ? 0 : -ESTALE;
}

static int vision_peer_send(int fd, uint32_t peer, uint32_t type,
			    uint64_t frame, uint64_t transfer,
			    const struct pvm_frame_desc *desc)
{
	struct pvm_peer_message message = { .type = type };
	if (type == PVM_USER_MSG_FRAME_DESC) {
		message.length = sizeof(message.body.frame);
		message.body.frame = *desc;
	} else {
		message.length = sizeof(message.body.control);
		message.body.control.type = type;
		message.body.control.length = sizeof(message.body.control);
		message.body.control.session_id = VISION_SESSION_ID;
		message.body.control.frame_seq = frame;
		message.body.control.transfer_id = transfer;
	}
	return pvm_message_send(fd, peer, &message,
			offsetof(struct pvm_peer_message, body) + message.length, NULL);
}

static int vision_peer_recv(int fd, uint32_t sender, struct pvm_peer_message *message)
{
	uint32_t length = 0;
	int ret = pvm_message_receive(fd, sender, message, sizeof(*message),
				      &length, NULL, 60000);
	if (ret) return ret;
	if (length < offsetof(struct pvm_peer_message, body) ||
	    message->length + offsetof(struct pvm_peer_message, body) != length)
		return -EPROTO;
	return 0;
}

static struct pvm_frame_desc vision_desc(uint64_t frame, uint64_t transfer)
{
	struct pvm_frame_desc desc = {
		.version = PVM_FRAME_DESC_VERSION,
		.descriptor_len = sizeof(desc),
		.session_id = VISION_SESSION_ID,
		.frame_seq = frame,
		.transfer_id = transfer,
		.total_size = PVM_VISION_PAGE_SIZE,
		.fourcc = PVM_FOURCC_BGR3,
		.width = PVM_VISION_WIDTH,
		.height = PVM_VISION_HEIGHT,
		.num_planes = 1,
		.planes = {{ .offset = 0, .stride = PVM_VISION_STRIDE,
			     .size = PVM_VISION_ACTIVE_SIZE }},
	};
	return desc;
}

static int oracle_find(const struct pvm_vision_oracle_record *records,
		       const uint8_t hash[32])
{
	uint32_t index;
	for (index = 0; index < PVM_VISION_FRAME_COUNT; ++index)
		if (!memcmp(records[index].frame_sha256, hash, 32)) return (int)index;
	return -ENOENT;
}

static int alloc_send_page(int dev, const uint8_t page[PVM_VISION_PAGE_SIZE],
			   int mutate, int *fd_out, void **mapping_out,
			   uint64_t *token_out)
{
	struct pvm_buffer_alloc alloc = { .fd = -1 };
	struct pvm_buffer_send send = { .fd = -1, .receiver_endpoint = AI_ENDPOINT };
	uint8_t *mapping;
	if (ioctl(dev, PVM_BUFFER_IOC_ALLOC, &alloc)) return -errno;
	mapping = mmap(NULL, PVM_VISION_PAGE_SIZE, PROT_READ | PROT_WRITE,
		       MAP_SHARED, alloc.fd, 0);
	if (mapping == MAP_FAILED) { close(alloc.fd); return -errno; }
	memcpy(mapping, page, PVM_VISION_PAGE_SIZE);
	if (mutate) mapping[0] ^= 1;
	send.fd = alloc.fd;
	if (ioctl(dev, PVM_BUFFER_IOC_SEND, &send)) {
		int error = -errno; munmap(mapping, PVM_VISION_PAGE_SIZE); close(alloc.fd); return error;
	}
	*fd_out = alloc.fd; *mapping_out = mapping; *token_out = send.token;
	return 0;
}

static int wait_return_close(int dev, int fd, void *mapping, uint64_t token)
{
	struct pvm_buffer_token request = { .token = token };
	if (ioctl(dev, PVM_BUFFER_IOC_WAIT_RETURN, &request)) return -errno;
	munmap(mapping, PVM_VISION_PAGE_SIZE);
	close(fd);
	return 0;
}

static int vision_camera_negative(int host, int msg, int dev, int frames)
{
	uint8_t page[PVM_VISION_PAGE_SIZE];
	struct pvm_peer_message response;
	struct pvm_frame_desc desc;
	int fd;
	void *mapping;
	uint64_t token;
	if (read_exact_at(frames, page, sizeof(page), 0)) return -1;

	desc = vision_desc(1001, 1001); desc.planes[0].stride = PVM_VISION_STRIDE - 1;
	if (vision_peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 1001, 1001, &desc) ||
	    vision_peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_REJECTED)
		return -1;

	if (alloc_send_page(dev, page, 1, &fd, &mapping, &token)) return -1;
	desc = vision_desc(1002, token);
	if (vision_peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 1002, token, &desc) ||
	    vision_peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_REJECTED ||
	    wait_return_close(dev, fd, mapping, token)) return -1;

	if (alloc_send_page(dev, page, 0, &fd, &mapping, &token)) return -1;
	desc = vision_desc(1003, token + 1);
	if (vision_peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 1003, token + 1, &desc) ||
	    vision_peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_REJECTED ||
	    wait_return_close(dev, fd, mapping, token)) return -1;

	desc = vision_desc(1004, 7777);
	if (vision_peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 1004, 7777, &desc) ||
	    vision_peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, 1004, 7777, &desc) ||
	    vision_peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_REJECTED)
		return -1;
	printf("PVM_VISION_CAMERA_NEGATIVE_OK\n");
	return vision_user_send(host, PVM_USER_MSG_STATUS, 2, 0, NULL, 0);
}

static int vision_camera(void)
{
	struct pvm_user_hello hello = { PVM_USER_ROLE_CAMERA, CAMERA_CID, CAMERA_ENDPOINT, 0 };
	struct pvm_user_message command;
	uint8_t page[PVM_VISION_PAGE_SIZE];
	int host = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT, 30000);
	int msg = pvm_message_open();
	int dev = open("/dev/pvm-dmabuf", O_RDWR | O_CLOEXEC);
	int frames = open(FRAMES_PATH, O_RDONLY | O_CLOEXEC);
	uint64_t frame;
	if (host < 0 || msg < 0 || dev < 0 || frames < 0) return 1;
	if (vision_user_send(host, PVM_USER_MSG_HELLO, 1, 0, &hello, sizeof(hello)) ||
	    vision_user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_CAMERA_CONFIG ||
	    vision_user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0) ||
	    vision_camera_negative(host, msg, dev, frames)) return 1;

	for (frame = 1; frame <= PVM_VISION_FRAME_COUNT; ++frame) {
		struct pvm_peer_message response;
		struct pvm_frame_desc desc;
		int fd;
		void *mapping;
		uint64_t token;
		if (vision_user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_CAPTURE ||
		    command.header.frame_seq != frame ||
		    read_exact_at(frames, page, sizeof(page), (off_t)(frame - 1) * sizeof(page)) ||
		    alloc_send_page(dev, page, 0, &fd, &mapping, &token)) return 1;
		desc = vision_desc(frame, token);
		if (pvm_frame_desc_validate(&desc) ||
		    vision_peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_FRAME_DESC, frame, token, &desc) ||
		    vision_peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_ACCEPTED ||
		    vision_peer_recv(msg, AI_ENDPOINT, &response) || response.type != PVM_USER_MSG_FRAME_DONE ||
		    wait_return_close(dev, fd, mapping, token) ||
		    vision_user_send(host, PVM_USER_MSG_ACK, command.header.request_id, frame, NULL, 0)) return 1;
		printf("PVM_VISION_CAMERA_FRAME_OK: frame=%llu\n", (unsigned long long)frame);
	}
	if (vision_user_send(host, PVM_USER_MSG_EOS, 90, PVM_VISION_FRAME_COUNT, NULL, 0) ||
	    vision_user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_STOP ||
	    vision_peer_send(msg, AI_ENDPOINT, PVM_USER_MSG_PEER_STOP, 0, 0, NULL) ||
	    vision_user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0)) return 1;
	printf("PVM_VISION_CAMERA_REPLAY_OK: frames=30\nPVM_VISION_EOS_CAMERA_OK\n");
	close(frames); close(dev); close(msg); close(host); return 0;
}

static int receive_buffer(int dev, struct pvm_buffer_receive *receive)
{
	memset(receive, 0, sizeof(*receive));
	receive->fd = -1; receive->timeout_ms = 60000;
	return ioctl(dev, PVM_BUFFER_IOC_RECEIVE, receive) ? -errno : 0;
}

static int return_buffer(int dev, struct pvm_buffer_receive *receive)
{
	struct pvm_buffer_token token = { .token = receive->token };
	return ioctl(dev, PVM_BUFFER_IOC_RETURN, &token) ? -errno : 0;
}

static int page_hash(int fd, uint8_t digest[32])
{
	uint8_t *mapping = mmap(NULL, PVM_VISION_PAGE_SIZE, PROT_READ,
				MAP_SHARED, fd, 0);
	uint32_t index;
	if (mapping == MAP_FAILED) return -errno;
	for (index = PVM_VISION_ACTIVE_SIZE; index < PVM_VISION_PAGE_SIZE; ++index)
		if (mapping[index]) { munmap(mapping, PVM_VISION_PAGE_SIZE); return -EPROTO; }
	pvm_sha256(mapping, PVM_VISION_PAGE_SIZE, digest);
	munmap(mapping, PVM_VISION_PAGE_SIZE);
	return 0;
}

static int vision_ai_negative(int host, int msg, int dev,
			      const struct pvm_vision_oracle_record *records)
{
	struct pvm_peer_message peer, duplicate;
	struct pvm_buffer_receive receive;
	uint8_t hash[32];
	if (vision_peer_recv(msg, CAMERA_ENDPOINT, &peer) ||
	    peer.type != PVM_USER_MSG_FRAME_DESC || !pvm_frame_desc_validate(&peer.body.frame) ||
	    vision_peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_REJECTED, 1001, 1001, NULL)) return -1;

	if (vision_peer_recv(msg, CAMERA_ENDPOINT, &peer) || receive_buffer(dev, &receive) ||
	    receive.token != peer.body.frame.transfer_id || page_hash(receive.fd, hash) ||
	    oracle_find(records, hash) != -ENOENT || return_buffer(dev, &receive) ||
	    vision_peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_REJECTED, 1002, receive.token, NULL)) return -1;
	close(receive.fd);

	if (vision_peer_recv(msg, CAMERA_ENDPOINT, &peer) || receive_buffer(dev, &receive) ||
	    receive.token == peer.body.frame.transfer_id || return_buffer(dev, &receive) ||
	    vision_peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_REJECTED, 1003,
			     peer.body.frame.transfer_id, NULL)) return -1;
	close(receive.fd);

	if (vision_peer_recv(msg, CAMERA_ENDPOINT, &peer) ||
	    vision_peer_recv(msg, CAMERA_ENDPOINT, &duplicate) ||
	    peer.type != PVM_USER_MSG_FRAME_DESC || duplicate.type != PVM_USER_MSG_FRAME_DESC ||
	    memcmp(&peer.body.frame, &duplicate.body.frame, sizeof(peer.body.frame)) ||
	    vision_peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_REJECTED, 1004, 7777, NULL)) return -1;
	printf("PVM_VISION_LAYOUT_REJECT_OK\nPVM_VISION_MUTATION_REJECT_OK\n"
	       "PVM_VISION_HASH_REJECT_OK\nPVM_VISION_MISMATCH_REJECT_OK\n"
	       "PVM_VISION_DUPLICATE_REPLAY_REJECT_OK\n");
	return vision_user_send(host, PVM_USER_MSG_STATUS, 2, 0, NULL, 0);
}

static int build_result(uint64_t frame, const struct pvm_vision_oracle_record *record,
			struct pvm_user_detection_result *result)
{
	memset(result, 0, sizeof(*result));
	result->frame_seq = frame;
	result->detection_count = record->detection_count;
	result->truncated = record->truncated;
	result->status = PVM_USER_STATUS_OK;
	memcpy(result->detections, record->detections,
	       sizeof(record->detections));
	return pvm_user_detection_result_validate(result);
}

static int vision_ai(void)
{
	struct pvm_user_hello hello = { PVM_USER_ROLE_AI, AI_CID, AI_ENDPOINT, 0 };
	struct pvm_vision_fixture_header header;
	struct pvm_vision_oracle_record records[PVM_VISION_FRAME_COUNT];
	struct pvm_user_message command;
	int host = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT, 30000);
	int msg = pvm_message_open();
	int dev = open("/dev/pvm-dmabuf", O_RDWR | O_CLOEXEC);
	uint64_t frame;
	if (host < 0 || msg < 0 || dev < 0 || load_oracle(&header, records)) return 1;
	if (vision_user_send(host, PVM_USER_MSG_HELLO, 1, 0, &hello, sizeof(hello)) ||
	    vision_user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_AI_CONFIG ||
	    vision_user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0) ||
	    vision_ai_negative(host, msg, dev, records)) return 1;

	for (frame = 1; frame <= PVM_VISION_FRAME_COUNT; ++frame) {
		struct pvm_peer_message peer;
		struct pvm_buffer_receive receive;
		struct pvm_user_detection_result result;
		uint8_t hash[32];
		int record_index;
		if (frame & 1) {
			if (vision_peer_recv(msg, CAMERA_ENDPOINT, &peer) || receive_buffer(dev, &receive)) return 1;
		} else {
			if (receive_buffer(dev, &receive) || vision_peer_recv(msg, CAMERA_ENDPOINT, &peer)) return 1;
		}
		if (peer.type != PVM_USER_MSG_FRAME_DESC || peer.length != sizeof(peer.body.frame) ||
		    pvm_frame_desc_validate(&peer.body.frame) ||
		    receive.token != peer.body.frame.transfer_id ||
		    receive.actual_size != peer.body.frame.total_size ||
		    page_hash(receive.fd, hash)) return 1;
		record_index = oracle_find(records, hash);
		if (record_index != (int)(frame - 1) || build_result(frame, &records[record_index], &result) ||
		    vision_peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_ACCEPTED,
			     frame, receive.token, NULL) || return_buffer(dev, &receive)) return 1;
		close(receive.fd);
		if (vision_peer_send(msg, CAMERA_ENDPOINT, PVM_USER_MSG_FRAME_DONE, frame,
			     receive.token, NULL) ||
		    vision_user_send(host, PVM_USER_MSG_DETECTION_RESULT, 100 + frame,
			     frame, &result, sizeof(result))) return 1;
		printf("PVM_VISION_AI_FRAME_OK: frame=%llu detections=%u\n",
		       (unsigned long long)frame, result.detection_count);
	}
	{
		struct pvm_peer_message peer;
		if (vision_peer_recv(msg, CAMERA_ENDPOINT, &peer) ||
		    peer.type != PVM_USER_MSG_PEER_STOP) return 1;
	}
	if (vision_user_recv(host, &command) || command.header.message_type != PVM_USER_MSG_STOP ||
	    vision_user_send(host, PVM_USER_MSG_ACK, command.header.request_id, 0, NULL, 0)) return 1;
	printf("PVM_VISION_ORACLE_LOOKUP_OK: frames=30\nPVM_VISION_AI_STOP_OK\n");
	close(dev); close(msg); close(host); return 0;
}

static int vision_accept(int listener, uint32_t expected_role, uint32_t expected_cid)
{
	struct pvm_user_message message;
	struct pvm_user_hello hello;
	uint32_t cid = 0;
	int fd = pvm_user_vsock_accept(listener, &cid, 60000);
	if (fd < 0 || vision_user_recv(fd, &message) ||
	    message.header.message_type != PVM_USER_MSG_HELLO ||
	    message.header.payload_len != sizeof(hello)) return -1;
	memcpy(&hello, message.payload, sizeof(hello));
	if (cid != expected_cid || pvm_user_validate_peer(expected_role, cid, &hello)) return -1;
	return fd;
}

static int vision_fault_guest(uint32_t role, uint32_t cid, uint32_t endpoint)
{
	struct pvm_user_hello hello = { role, cid, endpoint, 0 };
	struct pvm_user_message message;
	int fd = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT, 10000);
	if (fd < 0 || vision_user_send(fd, PVM_USER_MSG_HELLO, 1, 0,
					&hello, sizeof(hello)) ||
	    vision_user_recv(fd, &message) ||
	    message.header.message_type != PVM_USER_MSG_ERROR)
		return 1;
	close(fd);
	fd = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT, 10000);
	if (fd < 0 || vision_user_send(fd, PVM_USER_MSG_HELLO, 2, 0,
					&hello, sizeof(hello)))
		return 1;
	if (!vision_user_recv(fd, &message))
		return 1;
	printf("PVM_VISION_%s_HOST_FAILURE_RECOVERY_OK\n",
	       role == PVM_USER_ROLE_CAMERA ? "CAMERA" : "AI");
	close(fd);
	return 0;
}

static int vision_fault_host(void)
{
	struct pvm_user_message message;
	int listener = pvm_user_vsock_listen(PVM_USER_DEFAULT_PORT, 2);
	int ai_fd, camera_fd, camera_reconnect, ai_reconnect;
	if (listener < 0)
		return 1;
	ai_fd = vision_accept(listener, PVM_USER_ROLE_AI, AI_CID);
	camera_fd = vision_accept(listener, PVM_USER_ROLE_CAMERA, CAMERA_CID);
	if (ai_fd < 0 || camera_fd < 0)
		return 1;
	if (vision_user_send(camera_fd, PVM_USER_MSG_ERROR, 10, 0, NULL, 0) ||
	    !vision_user_recv(camera_fd, &message))
		return 1;
	close(camera_fd);
	camera_reconnect = vision_accept(listener, PVM_USER_ROLE_CAMERA, CAMERA_CID);
	if (camera_reconnect < 0 ||
	    vision_user_send(ai_fd, PVM_USER_MSG_ERROR, 11, 0, NULL, 0) ||
	    !vision_user_recv(ai_fd, &message))
		return 1;
	close(ai_fd);
	ai_reconnect = vision_accept(listener, PVM_USER_ROLE_AI, AI_CID);
	if (ai_reconnect < 0)
		return 1;
	close(camera_reconnect);
	close(ai_reconnect);
	close(listener);
	printf("PVM_VISION_CAMERA_FAILURE_RECOVERY_OK\n"
	       "PVM_VISION_AI_FAILURE_RECOVERY_OK\n"
	       "PVM_VISION_HOST_FAILURE_INJECTED_OK\n");
	return 0;
}

static int result_matches(const struct pvm_user_detection_result *result,
			  const struct pvm_vision_oracle_record *record, uint64_t frame)
{
	struct pvm_user_detection_result expected;
	if (build_result(frame, record, &expected) ||
	    pvm_user_detection_result_validate(result)) return -1;
	return memcmp(result, &expected, sizeof(expected)) ? -1 : 0;
}

static int vision_host(void)
{
	struct pvm_vision_fixture_header header;
	struct pvm_vision_oracle_record records[PVM_VISION_FRAME_COUNT];
	struct pvm_user_message message;
	int listener = pvm_user_vsock_listen(PVM_USER_DEFAULT_PORT, 2);
	int ai_fd, camera_fd;
	uint32_t frame;
	if (listener < 0 || load_oracle(&header, records)) return 1;
	ai_fd = vision_accept(listener, PVM_USER_ROLE_AI, AI_CID);
	camera_fd = vision_accept(listener, PVM_USER_ROLE_CAMERA, CAMERA_CID);
	close(listener);
	if (ai_fd < 0 || camera_fd < 0) return 1;
	if (vision_user_send(ai_fd, PVM_USER_MSG_AI_CONFIG, 10, 0, NULL, 0) ||
	    vision_user_recv(ai_fd, &message) || message.header.message_type != PVM_USER_MSG_ACK ||
	    vision_user_send(camera_fd, PVM_USER_MSG_CAMERA_CONFIG, 11, 0, NULL, 0) ||
	    vision_user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_ACK ||
	    vision_user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_STATUS ||
	    vision_user_recv(ai_fd, &message) || message.header.message_type != PVM_USER_MSG_STATUS) return 1;
	printf("PVM_VISION_NEGATIVE_OK\n");

	for (frame = 1; frame <= PVM_VISION_FRAME_COUNT; ++frame) {
		struct pvm_user_detection_result result;
		uint32_t index;
		if (vision_user_send(camera_fd, PVM_USER_MSG_CAPTURE, 20 + frame, frame, NULL, 0) ||
		    vision_user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_ACK ||
		    message.header.request_id != 20 + frame || message.header.frame_seq != frame ||
		    vision_user_recv(ai_fd, &message) ||
		    message.header.message_type != PVM_USER_MSG_DETECTION_RESULT ||
		    message.header.frame_seq != frame || message.header.payload_len != sizeof(result)) return 1;
		memcpy(&result, message.payload, sizeof(result));
		if (result_matches(&result, &records[frame - 1], frame)) return 1;
		for (index = 0; index < result.detection_count; ++index)
			printf("PVM_VISION_DETECTION: frame=%u class=%u score_q16=%u "
			       "bbox_q16=%u,%u,%u,%u\n", frame,
			       result.detections[index].class_id,
			       result.detections[index].confidence_q16,
			       result.detections[index].xmin_q16,
			       result.detections[index].ymin_q16,
			       result.detections[index].xmax_q16,
			       result.detections[index].ymax_q16);
		printf("PVM_VISION_HOST_FRAME_OK: frame=%u detections=%u\n",
		       frame, result.detection_count);
	}
	if (vision_user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_EOS ||
	    message.header.frame_seq != PVM_VISION_FRAME_COUNT ||
	    vision_user_send(camera_fd, PVM_USER_MSG_STOP, 80, 0, NULL, 0) ||
	    vision_user_recv(camera_fd, &message) || message.header.message_type != PVM_USER_MSG_ACK ||
	    vision_user_send(ai_fd, PVM_USER_MSG_STOP, 81, 0, NULL, 0) ||
	    vision_user_recv(ai_fd, &message) || message.header.message_type != PVM_USER_MSG_ACK) return 1;
	printf("PVM_VISION_RESULTS_MATCH_OK: frames=30\nPVM_VISION_HOST_ALLOWLIST_OK\n"
	       "PVM_VISION_EOS_OK\nPVM_VISION_RUNTIME_RECOVERY_OK\n");
	close(camera_fd); close(ai_fd); return 0;
}

int main(int argc, char **argv)
{
	if (argc != 2) return 2;
	if (!strcmp(argv[1], "host")) return vision_host();
	if (!strcmp(argv[1], "camera")) return vision_camera();
	if (!strcmp(argv[1], "ai")) return vision_ai();
	if (!strcmp(argv[1], "fault-host")) return vision_fault_host();
	if (!strcmp(argv[1], "fault-camera"))
		return vision_fault_guest(PVM_USER_ROLE_CAMERA, CAMERA_CID,
					  CAMERA_ENDPOINT);
	if (!strcmp(argv[1], "fault-ai"))
		return vision_fault_guest(PVM_USER_ROLE_AI, AI_CID, AI_ENDPOINT);
	return 2;
}
