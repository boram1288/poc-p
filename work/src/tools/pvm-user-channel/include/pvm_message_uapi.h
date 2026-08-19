/* SPDX-License-Identifier: MIT */
#ifndef PVM_MESSAGE_UAPI_H
#define PVM_MESSAGE_UAPI_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define PVM_MESSAGE_MAX_SIZE 256
#define PVM_MESSAGE_IOC_MAGIC 'M'

struct pvm_message_io {
	__u32 peer_endpoint;
	__u32 sender_endpoint;
	__u32 length;
	__u32 timeout_ms;
	__u64 sequence;
	__u8 data[PVM_MESSAGE_MAX_SIZE];
};

struct pvm_message_depth {
	__u32 count;
	__u32 capacity;
};

#define PVM_MESSAGE_IOC_SEND _IOWR(PVM_MESSAGE_IOC_MAGIC, 0, struct pvm_message_io)
#define PVM_MESSAGE_IOC_RECEIVE _IOWR(PVM_MESSAGE_IOC_MAGIC, 1, struct pvm_message_io)
#define PVM_MESSAGE_IOC_DEPTH _IOR(PVM_MESSAGE_IOC_MAGIC, 2, struct pvm_message_depth)
#define PVM_MESSAGE_IOC_ID_GET _IOR(PVM_MESSAGE_IOC_MAGIC, 3, __u32)

#endif
