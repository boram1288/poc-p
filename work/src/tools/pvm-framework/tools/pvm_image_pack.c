/* SPDX-License-Identifier: MIT */
#include "pvm_image.h"
#include "sha256.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int copy_bytes(int in, int out, size_t size)
{
	uint8_t buffer[4096];
	while (size) {
		size_t want = size < sizeof(buffer) ? size : sizeof(buffer);
		ssize_t n = read(in, buffer, want);
		if (n <= 0 || write(out, buffer, (size_t)n) != n) return -1;
		size -= (size_t)n;
	}
	return 0;
}

int main(int argc, char **argv)
{
	struct pvm_image_header header = { 0 };
	struct stat st;
	uint8_t expected[PVM_SHA256_SIZE], actual[PVM_SHA256_SIZE];
	char hex[PVM_SHA256_HEX_SIZE];
	int in = -1, out = -1, rc = 1;

	if (argc != 4) {
		fprintf(stderr, "usage: %s WORKLOAD EXPECTED_SHA256 OUTPUT\n", argv[0]);
		return 2;
	}
	if (pvm_sha256_parse(argv[2], expected) || pvm_sha256_file(argv[1], actual) ||
	    memcmp(expected, actual, sizeof(actual))) {
		puts("PVM_FRAMEWORK_WORKLOAD_REJECTED");
		return 3;
	}
	if (stat(argv[1], &st) || st.st_size <= 0 || st.st_size > PVM_IMAGE_MAX_WORKLOAD)
		return 4;
	in = open(argv[1], O_RDONLY);
	out = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (in < 0 || out < 0) goto out;
	header.magic = PVM_IMAGE_MAGIC;
	header.version = PVM_IMAGE_VERSION;
	header.header_size = sizeof(header);
	header.workload_size = (uint64_t)st.st_size;
	memcpy(header.workload_sha256, actual, sizeof(actual));
	if (write(out, &header, sizeof(header)) != sizeof(header) ||
	    copy_bytes(in, out, (size_t)st.st_size))
		goto out;
	pvm_sha256_hex(actual, hex);
	printf("PVM_FRAMEWORK_WORKLOAD_VERIFIED: sha256=%s\n", hex);
	rc = 0;
out:
	if (in >= 0) close(in);
	if (out >= 0) close(out);
	return rc;
}
