/* SPDX-License-Identifier: MIT */
#ifndef PVM_BUFFER_UAPI_H
#define PVM_BUFFER_UAPI_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define PVM_BUFFER_IOC_MAGIC 'P'

struct pvm_buffer_alloc {
	__s32 fd;
	__u32 reserved;
};

struct pvm_buffer_send {
	__s32 fd;
	__u32 receiver_endpoint;
	__u64 token;
};

struct pvm_buffer_receive {
	__s32 fd;
	__u32 timeout_ms;
	__u64 token;
};

struct pvm_buffer_token {
	__u64 token;
};

#define PVM_BUFFER_IOC_ALLOC \
	_IOWR(PVM_BUFFER_IOC_MAGIC, 0, struct pvm_buffer_alloc)
#define PVM_BUFFER_IOC_SEND \
	_IOWR(PVM_BUFFER_IOC_MAGIC, 1, struct pvm_buffer_send)
#define PVM_BUFFER_IOC_RECEIVE \
	_IOWR(PVM_BUFFER_IOC_MAGIC, 2, struct pvm_buffer_receive)
#define PVM_BUFFER_IOC_RETURN \
	_IOW(PVM_BUFFER_IOC_MAGIC, 3, struct pvm_buffer_token)
#define PVM_BUFFER_IOC_WAIT_RETURN \
	_IOW(PVM_BUFFER_IOC_MAGIC, 4, struct pvm_buffer_token)
#define PVM_BUFFER_IOC_ID_GET \
	_IOR(PVM_BUFFER_IOC_MAGIC, 5, __u32)

#endif
