// SPDX-License-Identifier: MIT
#include "include/pvm_user_channel.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int fail(const char *step, int error)
{
	fprintf(stderr, "PVM_USER_VSOCK_STEP_FAILED: step=%s errno=%d error=%s\n",
		step, -error, strerror(-error));
	return 1;
}

static int guest(void)
{
	struct pvm_user_message message;
	struct pvm_user_hello hello = {
		.role = PVM_USER_ROLE_CAMERA,
		.vsock_cid = 4102,
		.el2_endpoint = 2,
	};
	int fd;
	int ret;

	fprintf(stderr, "PVM_USER_VSOCK_GUEST_CONNECT_START: cid=2 port=9009\n");
	fd = pvm_user_vsock_connect(PVM_USER_HOST_CID, PVM_USER_DEFAULT_PORT,
				    5000);
	if (fd < 0)
		return fail("connect", fd);
	ret = pvm_user_message_init(&message, PVM_USER_MSG_HELLO, 0x9009, 1,
				    0, PVM_USER_STATUS_OK, &hello,
				    sizeof(hello));
	if (ret || (ret = pvm_user_send(fd, &message, 5000)))
		return fail("hello_send", ret ?: -EIO);
	ret = pvm_user_receive(fd, &message, 5000);
	if (ret)
		return fail("ready_receive", ret);
	if (message.header.message_type != PVM_USER_MSG_READY ||
	    message.header.session_id != 0x9009)
		return fail("ready_validate", -EPROTO);
	ret = pvm_user_message_init(&message, PVM_USER_MSG_CAPTURE, 0x9009, 2,
				    1, PVM_USER_STATUS_OK, NULL, 0);
	if (ret || (ret = pvm_user_send(fd, &message, 5000)))
		return fail("capture_send", ret ?: -EIO);
	ret = pvm_user_receive(fd, &message, 5000);
	if (ret)
		return fail("ack_receive", ret);
	if (message.header.message_type != PVM_USER_MSG_ACK ||
	    message.header.request_id != 2 ||
	    message.header.frame_seq != 1)
		return fail("ack_validate", -EPROTO);
	printf("PVM_USER_VSOCK_GUEST_OK: cid=4102 session=0x9009 frame=1\n");
	close(fd);
	return 0;
}

static int host(void)
{
	struct pvm_user_message message;
	struct pvm_user_hello hello;
	uint32_t peer_cid = 0;
	int listener;
	int fd;
	int ret;

	fprintf(stderr, "PVM_USER_VSOCK_HOST_LISTEN_START: port=9009\n");
	listener = pvm_user_vsock_listen(PVM_USER_DEFAULT_PORT, 1);
	if (listener < 0)
		return fail("listen", listener);
	fd = pvm_user_vsock_accept(listener, &peer_cid, 60000);
	close(listener);
	if (fd < 0)
		return fail("accept", fd);
	ret = pvm_user_receive(fd, &message, 5000);
	if (ret)
		return fail("hello_receive", ret);
	if (message.header.message_type != PVM_USER_MSG_HELLO ||
	    message.header.payload_len != sizeof(hello) ||
	    peer_cid != 4102) {
		close(fd);
		return fail("hello_validate", -EPROTO);
	}
	memcpy(&hello, message.payload, sizeof(hello));
	if (hello.role != PVM_USER_ROLE_CAMERA || hello.vsock_cid != peer_cid) {
		close(fd);
		return fail("identity_validate", -EPERM);
	}
	ret = pvm_user_message_init(&message, PVM_USER_MSG_READY, 0x9009, 1,
				    0, PVM_USER_STATUS_OK, NULL, 0);
	if (ret || (ret = pvm_user_send(fd, &message, 5000)))
		return fail("ready_send", ret ?: -EIO);
	ret = pvm_user_receive(fd, &message, 5000);
	if (ret)
		return fail("capture_receive", ret);
	if (message.header.message_type != PVM_USER_MSG_CAPTURE ||
	    message.header.session_id != 0x9009 ||
	    message.header.request_id != 2 || message.header.frame_seq != 1)
		return fail("capture_validate", -EPROTO);
	ret = pvm_user_message_init(&message, PVM_USER_MSG_ACK, 0x9009, 2, 1,
				    PVM_USER_STATUS_OK, NULL, 0);
	if (ret || (ret = pvm_user_send(fd, &message, 5000)))
		return fail("ack_send", ret ?: -EIO);
	printf("PVM_USER_VSOCK_HOST_OK: peer_cid=%u session=0x9009 frame=1\n",
	       peer_cid);
	close(fd);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 2)
		return fail("argument", -EINVAL);
	if (!strcmp(argv[1], "host"))
		return host();
	if (!strcmp(argv[1], "guest"))
		return guest();
	return fail("argument", -EINVAL);
}
