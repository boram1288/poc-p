// SPDX-License-Identifier: MIT
#include "include/pvm_message.h"
#include "include/pvm_message_uapi.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int pvm_message_open(void)
{
	int fd = open("/dev/pvm-msg", O_RDWR | O_CLOEXEC);
	return fd < 0 ? -errno : fd;
}

int pvm_message_send(int fd, uint32_t peer_endpoint, const void *data,
		     uint32_t length, uint64_t *sequence)
{
	struct pvm_message_io request = { .peer_endpoint = peer_endpoint, .length = length };
	if (!data || !length || length > sizeof(request.data)) return -EINVAL;
	memcpy(request.data, data, length);
	if (ioctl(fd, PVM_MESSAGE_IOC_SEND, &request)) return -errno;
	if (sequence) *sequence = request.sequence;
	return 0;
}

int pvm_message_receive(int fd, uint32_t expected_sender, void *data,
			uint32_t capacity, uint32_t *length,
			uint64_t *sequence, uint32_t timeout_ms)
{
	struct pvm_message_io request = { .timeout_ms = timeout_ms };
	if (!data || !capacity) return -EINVAL;
	if (ioctl(fd, PVM_MESSAGE_IOC_RECEIVE, &request)) return -errno;
	if (expected_sender && request.sender_endpoint != expected_sender) return -EPERM;
	if (request.length > capacity) return -EMSGSIZE;
	memcpy(data, request.data, request.length);
	if (length) *length = request.length;
	if (sequence) *sequence = request.sequence;
	return 0;
}

int pvm_message_depth(int fd, uint32_t *count, uint32_t *capacity)
{
	struct pvm_message_depth depth;
	if (ioctl(fd, PVM_MESSAGE_IOC_DEPTH, &depth)) return -errno;
	if (count) *count = depth.count;
	if (capacity) *capacity = depth.capacity;
	return 0;
}
