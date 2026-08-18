/* SPDX-License-Identifier: MIT */
#ifndef PVM_IMAGE_H
#define PVM_IMAGE_H

#include <stddef.h>
#include <stdint.h>

#define PVM_IMAGE_MAGIC 0x3130474d49564d50ULL
#define PVM_IMAGE_VERSION 1U
#define PVM_IMAGE_MAX_WORKLOAD (64U * 1024U)

struct pvm_image_header {
	uint64_t magic;
	uint32_t version;
	uint32_t header_size;
	uint64_t workload_size;
	uint8_t workload_sha256[32];
	uint8_t reserved[8];
};

_Static_assert(sizeof(struct pvm_image_header) == 64, "pVM guest image header must be 64 bytes");

int pvm_image_read(const char *path, void **workload, size_t *workload_size);

#endif
