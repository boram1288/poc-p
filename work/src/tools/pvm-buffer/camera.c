// SPDX-License-Identifier: MIT
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "include/pvm_buffer_uapi.h"

#define CAMERA_MARKER UINT64_C(0x43414d4552413039)
#define AI_MARKER UINT64_C(0x41495f5245533039)

int main(void)
{
	struct pvm_buffer_alloc alloc = { .fd = -1 };
	struct pvm_buffer_send send = { .fd = -1, .receiver_endpoint = 1 };
	struct pvm_buffer_token token;
	volatile uint64_t *mapping;
	uint32_t endpoint = 0;
	int device;

	device = open("/dev/pvm-dmabuf", O_RDWR);
	if (device < 0) {
		fprintf(stderr, "PVM_LINUX_CAMERA_STEP_FAILED: step=open\n");
		goto fail;
	}
	if (ioctl(device, PVM_BUFFER_IOC_ID_GET, &endpoint)) {
		fprintf(stderr, "PVM_LINUX_CAMERA_STEP_FAILED: step=id_get\n");
		goto fail;
	}
	fprintf(stderr, "PVM_LINUX_CAMERA_ID_GET: endpoint=%u\n", endpoint);
	if (endpoint != 2) {
		fprintf(stderr,
			"PVM_LINUX_CAMERA_STEP_FAILED: step=endpoint_check got=%u want=2\n",
			endpoint);
		goto fail;
	}
	if (ioctl(device, PVM_BUFFER_IOC_ALLOC, &alloc)) {
		fprintf(stderr, "PVM_LINUX_CAMERA_STEP_FAILED: step=alloc\n");
		goto fail;
	}
	mapping = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, alloc.fd, 0);
	if (mapping == MAP_FAILED)
		goto fail;
	*mapping = CAMERA_MARKER;
	send.fd = alloc.fd;
	if (ioctl(device, PVM_BUFFER_IOC_SEND, &send) || !send.token)
		goto fail;
	printf("PVM_LINUX_CAMERA_EXPORTED: fd=%d endpoint=%u token=0x%llx\n",
	       alloc.fd, endpoint, (unsigned long long)send.token);
	fflush(stdout);
	token.token = send.token;
	if (ioctl(device, PVM_BUFFER_IOC_WAIT_RETURN, &token))
		goto fail;
	if (*mapping != AI_MARKER)
		goto fail;
	printf("PVM_LINUX_CAMERA_READ_OK: fd=%d marker=0x%llx\n", alloc.fd,
	       (unsigned long long)*mapping);
	printf("PVM_LINUX_CAMERA_COMPLETED\n");
	return 0;

fail:
	fprintf(stderr, "PVM_LINUX_CAMERA_FAILED: errno=%d error=%s\n",
		errno, strerror(errno));
	return 1;
}
