// SPDX-License-Identifier: GPL-2.0-only
#include <linux/arm-smccc.h>
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/uaccess.h>

#include "../include/pvm_message_uapi.h"

#define PVM_MESSAGE_HVC_FID 0xc6000032
#define PVM_MESSAGE_SEND_BEGIN 10
#define PVM_MESSAGE_SEND_CHUNK 11
#define PVM_MESSAGE_SEND_COMMIT 12
#define PVM_MESSAGE_RECV_INFO 13
#define PVM_MESSAGE_RECV_CHUNK 14
#define PVM_MESSAGE_RECV_POP 15
#define PVM_MESSAGE_QUEUE_DEPTH 16
#define PVM_MESSAGE_ID_GET 9
#define PVM_MESSAGE_CHUNK_SIZE 24
#define PVM_MESSAGE_RET_QUEUE_FULL (-4)

static DEFINE_MUTEX(pvm_message_lock);

static void pvm_message_hvc(unsigned long op, unsigned long a0,
			    unsigned long a1, unsigned long a2,
			    unsigned long a3, unsigned long a4,
			    struct arm_smccc_res *res)
{
	arm_smccc_1_1_hvc(PVM_MESSAGE_HVC_FID, op, a0, a1, a2, a3, a4, res);
}

static long pvm_message_send(void __user *argp)
{
	struct pvm_message_io request;
	struct arm_smccc_res res;
	u32 offset;

	if (copy_from_user(&request, argp, sizeof(request)))
		return -EFAULT;
	if (!request.length || request.length > PVM_MESSAGE_MAX_SIZE)
		return -EMSGSIZE;
	mutex_lock(&pvm_message_lock);
	pvm_message_hvc(PVM_MESSAGE_SEND_BEGIN, request.peer_endpoint,
			request.length, 0, 0, 0, &res);
	if ((long)res.a0)
		goto invalid;
	for (offset = 0; offset < request.length; offset += PVM_MESSAGE_CHUNK_SIZE) {
		u64 words[3] = { 0 };
		u32 len = min_t(u32, PVM_MESSAGE_CHUNK_SIZE, request.length - offset);
		memcpy(words, request.data + offset, len);
		pvm_message_hvc(PVM_MESSAGE_SEND_CHUNK, offset, words[0], words[1],
				words[2], 0, &res);
		if ((long)res.a0)
			goto invalid;
	}
	pvm_message_hvc(PVM_MESSAGE_SEND_COMMIT, 0, 0, 0, 0, 0, &res);
	if ((long)res.a0 == PVM_MESSAGE_RET_QUEUE_FULL) {
		mutex_unlock(&pvm_message_lock);
		return -ENOSPC;
	}
	if ((long)res.a0)
		goto invalid;
	request.sequence = res.a1;
	mutex_unlock(&pvm_message_lock);
	return copy_to_user(argp, &request, sizeof(request)) ? -EFAULT : 0;
invalid:
	mutex_unlock(&pvm_message_lock);
	return -EINVAL;
}

static long pvm_message_receive(void __user *argp)
{
	struct pvm_message_io request;
	struct arm_smccc_res res;
	u32 waited = 0, offset;

	if (copy_from_user(&request, argp, sizeof(request)))
		return -EFAULT;
	mutex_lock(&pvm_message_lock);
	for (;;) {
		pvm_message_hvc(PVM_MESSAGE_RECV_INFO, 0, 0, 0, 0, 0, &res);
		if (!(long)res.a0)
			break;
		if (waited++ >= request.timeout_ms) {
			mutex_unlock(&pvm_message_lock);
			return -ETIMEDOUT;
		}
		msleep(1);
	}
	request.sender_endpoint = res.a1;
	request.length = res.a2;
	request.sequence = res.a3;
	if (!request.length || request.length > PVM_MESSAGE_MAX_SIZE)
		goto invalid;
	memset(request.data, 0, sizeof(request.data));
	for (offset = 0; offset < request.length; offset += PVM_MESSAGE_CHUNK_SIZE) {
		u64 words[3];
		u32 len = min_t(u32, PVM_MESSAGE_CHUNK_SIZE, request.length - offset);
		pvm_message_hvc(PVM_MESSAGE_RECV_CHUNK, offset, 0, 0, 0, 0, &res);
		if ((long)res.a0)
			goto invalid;
		words[0] = res.a1; words[1] = res.a2; words[2] = res.a3;
		memcpy(request.data + offset, words, len);
	}
	pvm_message_hvc(PVM_MESSAGE_RECV_POP, 0, 0, 0, 0, 0, &res);
	if ((long)res.a0)
		goto invalid;
	mutex_unlock(&pvm_message_lock);
	return copy_to_user(argp, &request, sizeof(request)) ? -EFAULT : 0;
invalid:
	mutex_unlock(&pvm_message_lock);
	return -EPROTO;
}

static long pvm_message_ioctl(struct file *file, unsigned int command,
			      unsigned long argument)
{
	void __user *argp = (void __user *)argument;
	struct arm_smccc_res res;
	struct pvm_message_depth depth;
	u32 endpoint;

	switch (command) {
	case PVM_MESSAGE_IOC_SEND:
		return pvm_message_send(argp);
	case PVM_MESSAGE_IOC_RECEIVE:
		return pvm_message_receive(argp);
	case PVM_MESSAGE_IOC_DEPTH:
		pvm_message_hvc(PVM_MESSAGE_QUEUE_DEPTH, 0, 0, 0, 0, 0, &res);
		if ((long)res.a0) return -EINVAL;
		depth.count = res.a1; depth.capacity = res.a2;
		return copy_to_user(argp, &depth, sizeof(depth)) ? -EFAULT : 0;
	case PVM_MESSAGE_IOC_ID_GET:
		pvm_message_hvc(PVM_MESSAGE_ID_GET, 0, 0, 0, 0, 0, &res);
		if ((long)res.a0) return -EINVAL;
		endpoint = res.a1;
		return copy_to_user(argp, &endpoint, sizeof(endpoint)) ? -EFAULT : 0;
	default:
		return -ENOTTY;
	}
}

static const struct file_operations pvm_message_fops = {
	.owner = THIS_MODULE,
	.unlocked_ioctl = pvm_message_ioctl,
	.compat_ioctl = compat_ptr_ioctl,
};

static struct miscdevice pvm_message_miscdev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "pvm-msg",
	.fops = &pvm_message_fops,
	.mode = 0600,
};

module_misc_device(pvm_message_miscdev);
MODULE_DESCRIPTION("pKVM protected peer message queue");
MODULE_LICENSE("GPL");
