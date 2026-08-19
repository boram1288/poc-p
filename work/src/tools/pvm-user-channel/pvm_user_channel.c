// SPDX-License-Identifier: MIT
#define _GNU_SOURCE

#include "include/pvm_user_channel.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <linux/vm_sockets.h>

static int wait_fd(int fd, short events, int timeout_ms)
{
	struct pollfd pfd = { .fd = fd, .events = events };
	int ret;

	for (;;) {
		ret = poll(&pfd, 1, timeout_ms);
		if (ret < 0 && errno == EINTR)
			continue;
		if (ret <= 0)
			return ret ? -errno : -ETIMEDOUT;
		if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL))
			return -ECONNRESET;
		return 0;
	}
}

static int write_all(int fd, const void *buf, size_t len, int timeout_ms)
{
	const uint8_t *cursor = buf;

	while (len) {
		ssize_t ret;
		int wait = wait_fd(fd, POLLOUT, timeout_ms);

		if (wait)
			return wait;
		ret = send(fd, cursor, len, MSG_NOSIGNAL);
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			return -errno;
		}
		if (!ret)
			return -ECONNRESET;
		cursor += ret;
		len -= (size_t)ret;
	}
	return 0;
}

static int read_all(int fd, void *buf, size_t len, int timeout_ms)
{
	uint8_t *cursor = buf;

	while (len) {
		ssize_t ret;
		int wait = wait_fd(fd, POLLIN, timeout_ms);

		if (wait)
			return wait;
		ret = recv(fd, cursor, len, 0);
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			return -errno;
		}
		if (!ret)
			return -ECONNRESET;
		cursor += ret;
		len -= (size_t)ret;
	}
	return 0;
}

int pvm_user_vsock_connect(uint32_t cid, uint32_t port, int timeout_ms)
{
	struct sockaddr_vm address = {
		.svm_family = AF_VSOCK,
		.svm_cid = cid,
		.svm_port = port,
	};
	int fd;
	int ret;

	fd = socket(AF_VSOCK, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -errno;
	int flags = fcntl(fd, F_GETFL, 0);
	if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) { close(fd); return -errno; }
	ret = connect(fd, (struct sockaddr *)&address, sizeof(address));
	if (ret < 0 && errno == EINPROGRESS) ret = wait_fd(fd, POLLOUT, timeout_ms);
	if (!ret) {
		int error = 0; socklen_t len = sizeof(error);
		if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &len) < 0) ret = -errno;
		else if (error) ret = -error;
	}
	if (ret < 0) {
		if (ret == -1) ret = -errno;
		close(fd);
		return ret;
	}
	if (fcntl(fd, F_SETFL, flags) < 0) { ret = -errno; close(fd); return ret; }
	return fd;
}

int pvm_user_vsock_listen(uint32_t port, int backlog)
{
	struct sockaddr_vm address = {
		.svm_family = AF_VSOCK,
		.svm_cid = VMADDR_CID_ANY,
		.svm_port = port,
	};
	int fd;

	fd = socket(AF_VSOCK, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -errno;
	if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0 ||
	    listen(fd, backlog) < 0) {
		int error = -errno;
		close(fd);
		return error;
	}
	return fd;
}

int pvm_user_vsock_accept(int listener, uint32_t *peer_cid, int timeout_ms)
{
	struct sockaddr_vm address;
	socklen_t length = sizeof(address);
	int fd;

	fd = wait_fd(listener, POLLIN, timeout_ms);
	if (fd)
		return fd;
	fd = accept4(listener, (struct sockaddr *)&address, &length,
		     SOCK_CLOEXEC);
	if (fd < 0)
		return -errno;
	if (address.svm_family != AF_VSOCK) {
		close(fd);
		return -EPROTO;
	}
	if (peer_cid)
		*peer_cid = address.svm_cid;
	return fd;
}

int pvm_user_message_init(struct pvm_user_message *message,
			  uint32_t type, uint64_t session_id,
			  uint64_t request_id, uint64_t frame_seq,
			  uint32_t status, const void *payload,
			  uint32_t payload_len)
{
	if (!message || payload_len > PVM_USER_MAX_PAYLOAD ||
	    (payload_len && !payload))
		return -EINVAL;
	memset(message, 0, sizeof(*message));
	message->header.magic = PVM_USER_PROTO_MAGIC;
	message->header.version = PVM_USER_PROTO_VERSION;
	message->header.header_len = sizeof(message->header);
	message->header.message_type = type;
	message->header.payload_len = payload_len;
	message->header.session_id = session_id;
	message->header.request_id = request_id;
	message->header.frame_seq = frame_seq;
	message->header.status = status;
	if (payload_len)
		memcpy(message->payload, payload, payload_len);
	return 0;
}

int pvm_frame_desc_validate(const struct pvm_frame_desc *d)
{
	uint32_t i;
	if (!d || d->version != PVM_FRAME_DESC_VERSION ||
	    d->descriptor_len != sizeof(*d) || !d->session_id || !d->frame_seq ||
	    !d->transfer_id || !d->total_size || !d->width || !d->height ||
	    !d->num_planes || d->num_planes > PVM_FRAME_MAX_PLANES ||
	    d->fourcc != PVM_FOURCC_GREY || d->width > 4096 || d->height > 4096 ||
	    (d->flags & ~PVM_FRAME_FLAG_EOS))
		return -EINVAL;
	for (i = 0; i < d->num_planes; ++i) {
		uint64_t end = d->planes[i].offset + d->planes[i].size;
		uint64_t required = (uint64_t)d->planes[i].stride * d->height;
		if (!d->planes[i].stride || required > d->planes[i].size ||
		    !d->planes[i].size || end < d->planes[i].offset || end > d->total_size)
			return -EINVAL;
	}
	for (; i < PVM_FRAME_MAX_PLANES; ++i)
		if (d->planes[i].size || d->planes[i].offset || d->planes[i].stride)
			return -EINVAL;
	return 0;
}

int pvm_user_send(int fd, const struct pvm_user_message *message,
		  int timeout_ms)
{
	if (fd < 0 || !message || message->header.magic != PVM_USER_PROTO_MAGIC ||
	    message->header.version != PVM_USER_PROTO_VERSION ||
	    message->header.header_len != sizeof(message->header) ||
	    message->header.payload_len > PVM_USER_MAX_PAYLOAD)
		return -EINVAL;
	if (write_all(fd, &message->header, sizeof(message->header), timeout_ms))
		return -EIO;
	return write_all(fd, message->payload, message->header.payload_len,
			 timeout_ms);
}

int pvm_user_receive(int fd, struct pvm_user_message *message,
		     int timeout_ms)
{
	int ret;

	if (fd < 0 || !message)
		return -EINVAL;
	memset(message, 0, sizeof(*message));
	ret = read_all(fd, &message->header, sizeof(message->header), timeout_ms);
	if (ret)
		return ret;
	if (message->header.payload_len > PVM_USER_MAX_PAYLOAD)
		return -EMSGSIZE;
	if (message->header.magic != PVM_USER_PROTO_MAGIC ||
	    message->header.version != PVM_USER_PROTO_VERSION ||
	    message->header.header_len != sizeof(message->header) ||
	    message->header.message_type < PVM_USER_MSG_HELLO ||
	    message->header.message_type > PVM_USER_MSG_PEER_ERROR)
		return -EPROTO;
	return read_all(fd, message->payload, message->header.payload_len,
			       timeout_ms);
}

int pvm_user_validate_peer(uint32_t expected_role, uint32_t peer_cid,
			   const struct pvm_user_hello *hello)
{
	if (!hello || hello->role != expected_role || hello->vsock_cid != peer_cid)
		return -EPERM;
	if ((expected_role == PVM_USER_ROLE_CAMERA && hello->el2_endpoint != 2) ||
	    (expected_role == PVM_USER_ROLE_AI && hello->el2_endpoint != 1))
		return -EPERM;
	return 0;
}

int pvm_user_session_accept(struct pvm_user_session_state *state,
			    uint64_t session_id, uint64_t request_id,
			    uint64_t frame_seq)
{
	if (!state || !session_id || !request_id) return -EINVAL;
	if (!state->session_id) state->session_id = session_id;
	if (state->session_id != session_id) return -ESTALE;
	if (request_id <= state->last_request_id) return -EALREADY;
	if (frame_seq && frame_seq <= state->last_frame_seq) return -EALREADY;
	state->last_request_id = request_id;
	if (frame_seq) state->last_frame_seq = frame_seq;
	return 0;
}
