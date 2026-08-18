/* SPDX-License-Identifier: MIT */
#ifndef PVM_PVM_H
#define PVM_PVM_H

#include <stdint.h>
#include <sys/types.h>

#define PVM_ROLE_MAX 16
#define PVM_PATH_MAX 256
#define PVM_SOCKET_DEFAULT "/run/pvm-framework/pvmd.sock"

enum pvm_state {
	PVM_STATE_NONE = 0,
	PVM_STATE_CREATED,
	PVM_STATE_RUNNING,
	PVM_STATE_STOPPING,
	PVM_STATE_STOPPED,
	PVM_STATE_FAILED,
};

enum pvm_error {
	PVM_OK = 0,
	PVM_ERR_INVALID = -1,
	PVM_ERR_AUTH = -2,
	PVM_ERR_POLICY = -3,
	PVM_ERR_IMAGE = -4,
	PVM_ERR_EXISTS = -5,
	PVM_ERR_NOT_FOUND = -6,
	PVM_ERR_STATE = -7,
	PVM_ERR_SYSTEM = -8,
};

struct pvm_info {
	char role[PVM_ROLE_MAX];
	enum pvm_state state;
	pid_t pid;
	int exit_status;
	uint32_t resource_fd_count;
	uint32_t vcpu_count;
	uint64_t memory_bytes;
	uint64_t instance_id;
};

int pvm_create(const char *socket_path, const char *role, const char *guest_image,
	       struct pvm_info *info);
int pvm_start(const char *socket_path, const char *role, struct pvm_info *info);
int pvm_status(const char *socket_path, const char *role, struct pvm_info *info);
int pvm_stop(const char *socket_path, const char *role, struct pvm_info *info);
int pvm_delete(const char *socket_path, const char *role);
int pvm_list(const char *socket_path, struct pvm_info *infos, unsigned int capacity);
const char *pvm_state_name(enum pvm_state state);
const char *pvm_error_name(int error);

#endif
