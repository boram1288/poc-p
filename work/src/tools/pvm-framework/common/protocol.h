/* SPDX-License-Identifier: MIT */
#ifndef PVM_PROTOCOL_H
#define PVM_PROTOCOL_H

#include <stdint.h>
#include "pvm/pvm.h"

#define PVM_PROTOCOL_MAGIC 0x50564d46U
#define PVM_PROTOCOL_VERSION 1U

enum pvm_operation {
	PVM_OP_CREATE = 1,
	PVM_OP_START,
	PVM_OP_STATUS,
	PVM_OP_STOP,
	PVM_OP_DELETE,
};

struct pvm_request {
	uint32_t magic;
	uint16_t version;
	uint16_t operation;
	uint64_t request_id;
	char role[PVM_ROLE_MAX];
	char guest_image[PVM_PATH_MAX];
};

struct pvm_response {
	uint32_t magic;
	uint16_t version;
	uint16_t reserved;
	uint64_t request_id;
	int32_t result;
	struct pvm_info info;
};

#endif
