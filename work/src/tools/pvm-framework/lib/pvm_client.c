/* SPDX-License-Identifier: MIT */
#include "pvm/pvm.h"
#include "protocol.h"

#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static uint64_t next_request_id(void)
{
	static uint32_t sequence;
	return ((uint64_t)(uint32_t)getpid() << 32) | ++sequence;
}

static int transact(const char *socket_path, enum pvm_operation operation,
		    const char *role, const char *image, struct pvm_info *info)
{
	struct sockaddr_un address = { .sun_family = AF_UNIX };
	struct pvm_request request = { 0 };
	struct pvm_response response;
	const char *path = socket_path ? socket_path : PVM_SOCKET_DEFAULT;
	int fd, ret = PVM_ERR_SYSTEM;

	if (!role || strlen(role) >= sizeof(request.role) ||
	    (image && strlen(image) >= sizeof(request.guest_image)) ||
	    strlen(path) >= sizeof(address.sun_path))
		return PVM_ERR_INVALID;
	request.magic = PVM_PROTOCOL_MAGIC;
	request.version = PVM_PROTOCOL_VERSION;
	request.operation = operation;
	request.request_id = next_request_id();
	strcpy(request.role, role);
	if (image) strcpy(request.guest_image, image);
	strcpy(address.sun_path, path);

	fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
	if (fd < 0) return ret;
	if (connect(fd, (struct sockaddr *)&address, sizeof(address))) goto out;
	if (send(fd, &request, sizeof(request), 0) != sizeof(request)) goto out;
	if (recv(fd, &response, sizeof(response), MSG_WAITALL) != sizeof(response)) goto out;
	if (response.magic != PVM_PROTOCOL_MAGIC ||
	    response.version != PVM_PROTOCOL_VERSION ||
	    response.request_id != request.request_id)
		goto out;
	if (info && response.result == PVM_OK) *info = response.info;
	ret = response.result;
out:
	close(fd);
	return ret;
}

int pvm_create(const char *socket_path, const char *role, const char *guest_image,
	       struct pvm_info *info)
{
	return transact(socket_path, PVM_OP_CREATE, role, guest_image, info);
}

int pvm_start(const char *socket_path, const char *role, struct pvm_info *info)
{
	return transact(socket_path, PVM_OP_START, role, NULL, info);
}

int pvm_status(const char *socket_path, const char *role, struct pvm_info *info)
{
	return transact(socket_path, PVM_OP_STATUS, role, NULL, info);
}

int pvm_stop(const char *socket_path, const char *role, struct pvm_info *info)
{
	return transact(socket_path, PVM_OP_STOP, role, NULL, info);
}

int pvm_delete(const char *socket_path, const char *role)
{
	return transact(socket_path, PVM_OP_DELETE, role, NULL, NULL);
}

int pvm_list(const char *socket_path, struct pvm_info *infos, unsigned int capacity)
{
	static const char *roles[] = { "camera", "ai" };
	unsigned int i, count = 0;
	if (!infos && capacity) return PVM_ERR_INVALID;
	for (i = 0; i < sizeof(roles) / sizeof(roles[0]); ++i) {
		struct pvm_info info;
		int ret = pvm_status(socket_path, roles[i], &info);
		if (ret == PVM_ERR_NOT_FOUND) continue;
		if (ret) return ret;
		if (count < capacity) infos[count] = info;
		++count;
	}
	return (int)count;
}

const char *pvm_state_name(enum pvm_state state)
{
	switch (state) {
	case PVM_STATE_CREATED: return "CREATED";
	case PVM_STATE_RUNNING: return "RUNNING";
	case PVM_STATE_STOPPING: return "STOPPING";
	case PVM_STATE_STOPPED: return "STOPPED";
	case PVM_STATE_FAILED: return "FAILED";
	default: return "NONE";
	}
}

const char *pvm_error_name(int error)
{
	switch (error) {
	case PVM_OK: return "OK";
	case PVM_ERR_INVALID: return "INVALID";
	case PVM_ERR_AUTH: return "AUTH";
	case PVM_ERR_POLICY: return "POLICY";
	case PVM_ERR_IMAGE: return "IMAGE";
	case PVM_ERR_EXISTS: return "EXISTS";
	case PVM_ERR_NOT_FOUND: return "NOT_FOUND";
	case PVM_ERR_STATE: return "STATE";
	default: return "SYSTEM";
	}
}
