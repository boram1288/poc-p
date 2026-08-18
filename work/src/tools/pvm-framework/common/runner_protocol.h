/* SPDX-License-Identifier: MIT */
#ifndef PVM_RUNNER_PROTOCOL_H
#define PVM_RUNNER_PROTOCOL_H

#include <stdint.h>

#define PVM_RUNNER_READY_MAGIC 0x52564d50U

struct pvm_runner_ready {
	uint32_t magic;
	uint32_t resource_fd_count;
	uint32_t vcpu_count;
	uint32_t reserved;
	uint64_t memory_bytes;
};

#endif
