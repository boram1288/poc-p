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
	struct pvm_buffer_receive receive = { .fd = -1, .timeout_ms = 10000 };
	struct pvm_buffer_token token;
	volatile uint64_t *mapping;
	uint32_t endpoint = 0;
	int device;

	device = open("/dev/pvm-dmabuf", O_RDWR);
	if (device < 0) {
		fprintf(stderr, "PVM_LINUX_AI_STEP_FAILED: step=open\n");
		goto fail;
	}
	if (ioctl(device, PVM_BUFFER_IOC_ID_GET, &endpoint)) {
		fprintf(stderr, "PVM_LINUX_AI_STEP_FAILED: step=id_get\n");
		goto fail;
	}
	fprintf(stderr, "PVM_LINUX_AI_ID_GET: endpoint=%u\n", endpoint);
	if (endpoint != 1) {
		fprintf(stderr,
			"PVM_LINUX_AI_STEP_FAILED: step=endpoint_check got=%u want=1\n",
			endpoint);
		goto fail;
	}
	if (ioctl(device, PVM_BUFFER_IOC_RECEIVE, &receive)) {
		fprintf(stderr, "PVM_LINUX_AI_STEP_FAILED: step=receive\n");
		goto fail;
	}
	mapping = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, receive.fd, 0);
	if (mapping == MAP_FAILED || *mapping != CAMERA_MARKER)
		goto fail;
	printf("PVM_LINUX_AI_IMPORTED: fd=%d endpoint=%u token=0x%llx\n",
	       receive.fd, endpoint, (unsigned long long)receive.token);
	*mapping = AI_MARKER;
	token.token = receive.token;
	if (ioctl(device, PVM_BUFFER_IOC_RETURN, &token))
		goto fail;
	printf("PVM_LINUX_AI_READ_WRITE_OK: fd=%d marker=0x%llx\n", receive.fd,
	       (unsigned long long)AI_MARKER);
	printf("PVM_LINUX_AI_COMPLETED\n");
	return 0;

fail:
	fprintf(stderr, "PVM_LINUX_AI_FAILED: errno=%d error=%s\n",
		errno, strerror(errno));
	return 1;
}
