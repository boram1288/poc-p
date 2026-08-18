/* SPDX-License-Identifier: MIT */
#include "pvm_image.h"
#include "sha256.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int read_full(int fd, void *buffer, size_t size)
{
	uint8_t *p = buffer;
	while (size) {
		ssize_t n = read(fd, p, size);
		if (n <= 0) return -1;
		p += n;
		size -= (size_t)n;
	}
	return 0;
}

int pvm_image_read(const char *path, void **workload, size_t *workload_size)
{
	struct pvm_image_header header;
	struct pvm_sha256_ctx ctx;
	struct stat st;
	uint8_t digest[PVM_SHA256_SIZE];
	void *data = NULL;
	int fd = -1, ret = -1;

	fd = open(path, O_RDONLY);
	if (fd < 0 || fstat(fd, &st) || read_full(fd, &header, sizeof(header)))
		goto out;
	if (header.magic != PVM_IMAGE_MAGIC || header.version != PVM_IMAGE_VERSION ||
	    header.header_size != sizeof(header) || !header.workload_size ||
	    header.workload_size > PVM_IMAGE_MAX_WORKLOAD ||
	    (uint64_t)st.st_size != sizeof(header) + header.workload_size) {
		errno = EINVAL;
		goto out;
	}
	data = malloc((size_t)header.workload_size);
	if (!data || read_full(fd, data, (size_t)header.workload_size))
		goto out;
	pvm_sha256_init(&ctx);
	pvm_sha256_update(&ctx, data, (size_t)header.workload_size);
	pvm_sha256_final(&ctx, digest);
	if (memcmp(digest, header.workload_sha256, sizeof(digest))) {
		errno = EBADMSG;
		goto out;
	}
	*workload = data;
	*workload_size = (size_t)header.workload_size;
	data = NULL;
	ret = 0;
out:
	free(data);
	if (fd >= 0) close(fd);
	return ret;
}
