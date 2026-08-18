/* SPDX-License-Identifier: MIT */
#include "protocol.h"

#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static int send_request(struct pvm_request *request)
{
	struct sockaddr_un address = { .sun_family = AF_UNIX };
	struct pvm_response response;
	int fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
	if (fd < 0) return PVM_ERR_SYSTEM;
	strcpy(address.sun_path, PVM_SOCKET_DEFAULT);
	if (connect(fd, (struct sockaddr *)&address, sizeof(address)) ||
	    send(fd, request, sizeof(*request), 0) != sizeof(*request) ||
	    recv(fd, &response, sizeof(response), MSG_WAITALL) != sizeof(response)) {
		close(fd);
		return PVM_ERR_SYSTEM;
	}
	close(fd);
	return response.result;
}

int main(void)
{
	struct pvm_request request = {
		.magic = PVM_PROTOCOL_MAGIC,
		.version = PVM_PROTOCOL_VERSION + 1,
		.operation = PVM_OP_STATUS,
		.request_id = 0x700000001ULL,
	};
	int ret;
	strcpy(request.role, "camera");
	ret = send_request(&request);
	if (ret != PVM_ERR_INVALID) return 1;
	request.version = PVM_PROTOCOL_VERSION;
	ret = send_request(&request);
	if (ret != PVM_ERR_NOT_FOUND) return 2;
	ret = send_request(&request);
	if (ret != PVM_ERR_INVALID) return 3;
	puts("PVM_FRAMEWORK_PROTOCOL_NEGATIVE_OK");
	return 0;
}
