/* SPDX-License-Identifier: MIT */
#ifndef PVM_SHA256_H
#define PVM_SHA256_H

#include <stddef.h>
#include <stdint.h>

#define PVM_SHA256_SIZE 32
#define PVM_SHA256_HEX_SIZE 65

struct pvm_sha256_ctx {
	uint8_t data[64];
	uint32_t datalen;
	uint64_t bitlen;
	uint32_t state[8];
};

void pvm_sha256_init(struct pvm_sha256_ctx *ctx);
void pvm_sha256_update(struct pvm_sha256_ctx *ctx, const void *data, size_t len);
void pvm_sha256_final(struct pvm_sha256_ctx *ctx, uint8_t hash[PVM_SHA256_SIZE]);
int pvm_sha256_file(const char *path, uint8_t hash[PVM_SHA256_SIZE]);
void pvm_sha256_hex(const uint8_t hash[PVM_SHA256_SIZE], char hex[PVM_SHA256_HEX_SIZE]);
int pvm_sha256_parse(const char *hex, uint8_t hash[PVM_SHA256_SIZE]);

#endif
