/* SPDX-License-Identifier: MIT */
#ifndef PVM_SHA256_H
#define PVM_SHA256_H

#include <stddef.h>
#include <stdint.h>

struct pvm_sha256_ctx {
	uint32_t state[8];
	uint64_t bit_count;
	uint8_t block[64];
	size_t block_used;
};

void pvm_sha256_init(struct pvm_sha256_ctx *ctx);
void pvm_sha256_update(struct pvm_sha256_ctx *ctx, const void *data, size_t length);
void pvm_sha256_final(struct pvm_sha256_ctx *ctx, uint8_t digest[32]);
void pvm_sha256(const void *data, size_t length, uint8_t digest[32]);

#endif
