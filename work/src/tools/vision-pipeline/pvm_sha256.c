// SPDX-License-Identifier: MIT
#include "include/pvm_sha256.h"

#include <string.h>

static const uint32_t round_constants[64] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

static uint32_t rotate_right(uint32_t value, unsigned int bits)
{
	return (value >> bits) | (value << (32 - bits));
}

static uint32_t load_be32(const uint8_t *data)
{
	return ((uint32_t)data[0] << 24) | ((uint32_t)data[1] << 16) |
	       ((uint32_t)data[2] << 8) | data[3];
}

static void store_be32(uint8_t *data, uint32_t value)
{
	data[0] = value >> 24; data[1] = value >> 16;
	data[2] = value >> 8; data[3] = value;
}

static void transform(struct pvm_sha256_ctx *ctx, const uint8_t block[64])
{
	uint32_t words[64], a, b, c, d, e, f, g, h;
	unsigned int index;

	for (index = 0; index < 16; ++index)
		words[index] = load_be32(block + index * 4);
	for (; index < 64; ++index) {
		uint32_t s0 = rotate_right(words[index - 15], 7) ^
			rotate_right(words[index - 15], 18) ^ (words[index - 15] >> 3);
		uint32_t s1 = rotate_right(words[index - 2], 17) ^
			rotate_right(words[index - 2], 19) ^ (words[index - 2] >> 10);
		words[index] = words[index - 16] + s0 + words[index - 7] + s1;
	}
	a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
	e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];
	for (index = 0; index < 64; ++index) {
		uint32_t sum1 = rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25);
		uint32_t choice = (e & f) ^ (~e & g);
		uint32_t temp1 = h + sum1 + choice + round_constants[index] + words[index];
		uint32_t sum0 = rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22);
		uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
		uint32_t temp2 = sum0 + majority;
		h = g; g = f; f = e; e = d + temp1;
		d = c; c = b; b = a; a = temp1 + temp2;
	}
	ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
	ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

void pvm_sha256_init(struct pvm_sha256_ctx *ctx)
{
	static const uint32_t initial[8] = {
		0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
	};
	memset(ctx, 0, sizeof(*ctx));
	memcpy(ctx->state, initial, sizeof(initial));
}

void pvm_sha256_update(struct pvm_sha256_ctx *ctx, const void *data, size_t length)
{
	const uint8_t *input = data;
	ctx->bit_count += (uint64_t)length * 8;
	while (length) {
		size_t copy = 64 - ctx->block_used;
		if (copy > length) copy = length;
		memcpy(ctx->block + ctx->block_used, input, copy);
		ctx->block_used += copy; input += copy; length -= copy;
		if (ctx->block_used == 64) {
			transform(ctx, ctx->block);
			ctx->block_used = 0;
		}
	}
}

void pvm_sha256_final(struct pvm_sha256_ctx *ctx, uint8_t digest[32])
{
	uint64_t bits = ctx->bit_count;
	unsigned int index;
	ctx->block[ctx->block_used++] = 0x80;
	if (ctx->block_used > 56) {
		memset(ctx->block + ctx->block_used, 0, 64 - ctx->block_used);
		transform(ctx, ctx->block);
		ctx->block_used = 0;
	}
	memset(ctx->block + ctx->block_used, 0, 56 - ctx->block_used);
	for (index = 0; index < 8; ++index)
		ctx->block[63 - index] = bits >> (index * 8);
	transform(ctx, ctx->block);
	for (index = 0; index < 8; ++index)
		store_be32(digest + index * 4, ctx->state[index]);
	memset(ctx, 0, sizeof(*ctx));
}

void pvm_sha256(const void *data, size_t length, uint8_t digest[32])
{
	struct pvm_sha256_ctx ctx;
	pvm_sha256_init(&ctx);
	pvm_sha256_update(&ctx, data, length);
	pvm_sha256_final(&ctx, digest);
}
