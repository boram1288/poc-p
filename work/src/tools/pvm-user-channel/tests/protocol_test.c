// SPDX-License-Identifier: MIT
#include "../include/pvm_user_channel.h"

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

static void receive_header_case(struct pvm_user_header header, int expected)
{
	struct pvm_user_message message;
	int sockets[2];
	pid_t child;
	assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
	child = fork();
	assert(child >= 0);
	if (!child) {
		const uint8_t *bytes = (const uint8_t *)&header;
		size_t i;
		close(sockets[0]);
		for (i = 0; i < sizeof(header); i++) assert(write(sockets[1], bytes + i, 1) == 1);
		close(sockets[1]);
		_exit(0);
	}
	close(sockets[1]);
	assert(pvm_user_receive(sockets[0], &message, 1000) == expected);
	close(sockets[0]);
	assert(waitpid(child, NULL, 0) == child);
}

int main(void)
{
	struct pvm_user_message message;
	struct pvm_user_result result = {
		.frame_seq = 7,
		.class_id = 3,
		.score_q16 = 65535,
		.status = PVM_USER_STATUS_OK,
	};

	assert(pvm_user_message_init(&message, PVM_USER_MSG_RESULT, 11, 12, 7,
					PVM_USER_STATUS_OK, &result,
					sizeof(result)) == 0);
	assert(message.header.magic == PVM_USER_PROTO_MAGIC);
	assert(message.header.header_len == sizeof(message.header));
	assert(message.header.payload_len == sizeof(result));
	assert(!memcmp(message.payload, &result, sizeof(result)));
	assert(pvm_user_message_init(&message, PVM_USER_MSG_RESULT, 0, 0, 0, 0,
					NULL, PVM_USER_MAX_PAYLOAD + 1) == -EINVAL);
	struct pvm_frame_desc desc = {
		.version = PVM_FRAME_DESC_VERSION, .descriptor_len = sizeof(desc),
		.session_id = 1, .frame_seq = 7, .transfer_id = 9, .total_size = 4096,
		.fourcc = PVM_FOURCC_GREY, .width = 64, .height = 64, .num_planes = 1,
		.planes = {{ .offset = 0, .stride = 64, .size = 4096 }},
	};
	assert(pvm_frame_desc_validate(&desc) == 0);
	desc.planes[0].size++;
	assert(pvm_frame_desc_validate(&desc) == -EINVAL);
	desc.planes[0].size = 4096; desc.fourcc = PVM_FOURCC_BGR3;
	desc.width = 32; desc.height = 32; desc.planes[0].stride = 96;
	desc.planes[0].size = 3072;
	assert(pvm_frame_desc_validate(&desc) == 0);
	desc.planes[0].stride = 95;
	assert(pvm_frame_desc_validate(&desc) == -EINVAL);
	{
		struct pvm_user_detection_result detection_result = {
			.frame_seq = 1, .detection_count = 1,
			.detections = {{ .class_id = 2, .confidence_q16 = 32768,
				.xmin_q16 = 1, .ymin_q16 = 2,
				.xmax_q16 = 3, .ymax_q16 = 4 }},
		};
		assert(pvm_user_detection_result_validate(&detection_result) == 0);
		detection_result.detections[0].xmax_q16 = 0;
		assert(pvm_user_detection_result_validate(&detection_result) == -EINVAL);
	}
	{
		struct pvm_user_session_state state = { 0 };
		struct pvm_user_hello hello = { PVM_USER_ROLE_CAMERA, 4102, 2, 0 };
		struct pvm_user_header header = {
			.magic = PVM_USER_PROTO_MAGIC, .version = PVM_USER_PROTO_VERSION,
			.header_len = sizeof(header), .message_type = PVM_USER_MSG_ACK,
		};
		assert(pvm_user_validate_peer(PVM_USER_ROLE_CAMERA, 4102, &hello) == 0);
		assert(pvm_user_validate_peer(PVM_USER_ROLE_CAMERA, 4101, &hello) == -EPERM);
		assert(pvm_user_session_accept(&state, 1, 1, 1) == 0);
		assert(pvm_user_session_accept(&state, 1, 1, 1) == -EALREADY);
		assert(pvm_user_session_accept(&state, 2, 2, 2) == -ESTALE);
		receive_header_case(header, 0);
		header.magic = 0; receive_header_case(header, -EPROTO);
		header.magic = PVM_USER_PROTO_MAGIC; header.version++;
		receive_header_case(header, -EPROTO);
		header.version = PVM_USER_PROTO_VERSION; header.message_type = 999;
		receive_header_case(header, -EPROTO);
		header.message_type = PVM_USER_MSG_ACK; header.payload_len = PVM_USER_MAX_PAYLOAD + 1;
		receive_header_case(header, -EMSGSIZE);
	}
	return 0;
}
