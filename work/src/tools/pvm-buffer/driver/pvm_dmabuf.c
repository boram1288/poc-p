// SPDX-License-Identifier: GPL-2.0-only
#include <linux/arm-smccc.h>
#include <linux/delay.h>
#include <linux/dma-buf.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

#include "pvm_buffer_uapi.h"

#define PVM_BUFFER_HVC_FID	0xc6000032
#define PVM_BUFFER_EXPORT	3
#define PVM_BUFFER_IMPORT	4
#define PVM_BUFFER_RETURN	5
#define PVM_BUFFER_QUERY	7
#define PVM_BUFFER_EVENT_POLL	8
#define PVM_BUFFER_ID_GET	9
#define PVM_BUFFER_IMPORT_IPA	0x70000000UL

struct pvm_buffer_backing {
	struct page *page;
	unsigned long pfn;
	bool imported;
	u64 token;
};

static struct pvm_buffer_backing *active_import;

static void pvm_hvc(unsigned long op, unsigned long arg0,
		    unsigned long arg1, unsigned long arg2,
		    struct arm_smccc_res *res)
{
	arm_smccc_1_1_hvc(PVM_BUFFER_HVC_FID, op, arg0, arg1, arg2, 0, 0, res);
}

static struct sg_table *pvm_map_dma_buf(struct dma_buf_attachment *attach,
					enum dma_data_direction direction)
{
	return ERR_PTR(-EOPNOTSUPP);
}

static void pvm_unmap_dma_buf(struct dma_buf_attachment *attach,
			      struct sg_table *sgt,
			      enum dma_data_direction direction)
{
}

static int pvm_mmap(struct dma_buf *dmabuf, struct vm_area_struct *vma)
{
	struct pvm_buffer_backing *backing = dmabuf->priv;

	if (backing->imported)
		return remap_pfn_range(vma, vma->vm_start, backing->pfn,
				       PAGE_SIZE, vma->vm_page_prot);
	return vm_insert_page(vma, vma->vm_start, backing->page);
}

static int pvm_begin_cpu_access(struct dma_buf *dmabuf,
				enum dma_data_direction direction)
{
	return 0;
}

static int pvm_end_cpu_access(struct dma_buf *dmabuf,
			      enum dma_data_direction direction)
{
	return 0;
}

static void pvm_release(struct dma_buf *dmabuf)
{
	struct pvm_buffer_backing *backing = dmabuf->priv;

	if (!backing->imported)
		__free_page(backing->page);
	else if (active_import == backing)
		active_import = NULL;
	kfree(backing);
}

static const struct dma_buf_ops pvm_dma_buf_ops = {
	.map_dma_buf = pvm_map_dma_buf,
	.unmap_dma_buf = pvm_unmap_dma_buf,
	.mmap = pvm_mmap,
	.begin_cpu_access = pvm_begin_cpu_access,
	.end_cpu_access = pvm_end_cpu_access,
	.release = pvm_release,
};

static struct dma_buf *pvm_export_backing(struct pvm_buffer_backing *backing)
{
	DEFINE_DMA_BUF_EXPORT_INFO(info);

	info.exp_name = KBUILD_MODNAME;
	info.owner = THIS_MODULE;
	info.ops = &pvm_dma_buf_ops;
	info.size = PAGE_SIZE;
	info.flags = O_RDWR;
	info.priv = backing;
	return dma_buf_export(&info);
}

static long pvm_ioctl_alloc(void __user *argp)
{
	struct pvm_buffer_alloc request = { .fd = -1 };
	struct pvm_buffer_backing *backing;
	struct dma_buf *dmabuf;
	int fd;

	backing = kzalloc(sizeof(*backing), GFP_KERNEL);
	if (!backing)
		return -ENOMEM;
	backing->page = alloc_page(GFP_KERNEL | __GFP_ZERO);
	if (!backing->page) {
		kfree(backing);
		return -ENOMEM;
	}
	backing->pfn = page_to_pfn(backing->page);
	dmabuf = pvm_export_backing(backing);
	if (IS_ERR(dmabuf)) {
		__free_page(backing->page);
		kfree(backing);
		return PTR_ERR(dmabuf);
	}
	fd = dma_buf_fd(dmabuf, O_CLOEXEC | O_RDWR);
	if (fd < 0) {
		dma_buf_put(dmabuf);
		return fd;
	}
	request.fd = fd;
	if (copy_to_user(argp, &request, sizeof(request)))
		return -EFAULT;
	return 0;
}

static long pvm_ioctl_send(void __user *argp)
{
	struct pvm_buffer_send request;
	struct pvm_buffer_backing *backing;
	struct arm_smccc_res res;
	struct dma_buf *dmabuf;

	if (copy_from_user(&request, argp, sizeof(request)))
		return -EFAULT;
	dmabuf = dma_buf_get(request.fd);
	if (IS_ERR(dmabuf))
		return PTR_ERR(dmabuf);
	if (dmabuf->ops != &pvm_dma_buf_ops) {
		dma_buf_put(dmabuf);
		return -EINVAL;
	}
	backing = dmabuf->priv;
	if (backing->imported) {
		dma_buf_put(dmabuf);
		return -EINVAL;
	}
	pvm_hvc(PVM_BUFFER_EXPORT, page_to_phys(backing->page),
		request.receiver_endpoint, PAGE_SIZE, &res);
	dma_buf_put(dmabuf);
	if ((long)res.a0)
		return -EINVAL;
	request.token = res.a1;
	if (copy_to_user(argp, &request, sizeof(request)))
		return -EFAULT;
	return 0;
}

static long pvm_ioctl_receive(void __user *argp)
{
	struct pvm_buffer_receive request;
	struct pvm_buffer_backing *backing;
	struct arm_smccc_res res;
	struct dma_buf *dmabuf;
	unsigned int waited = 0;
	int fd;

	if (copy_from_user(&request, argp, sizeof(request)))
		return -EFAULT;
	if (active_import)
		return -EBUSY;
	for (;;) {
		pvm_hvc(PVM_BUFFER_EVENT_POLL, 0, 0, 0, &res);
		if (!(long)res.a0)
			break;
		if (waited++ >= request.timeout_ms)
			return -ETIMEDOUT;
		msleep(1);
	}
	request.token = res.a1;
	pvm_hvc(PVM_BUFFER_IMPORT, request.token, PVM_BUFFER_IMPORT_IPA, 0,
		&res);
	if ((long)res.a0)
		return -EINVAL;
	backing = kzalloc(sizeof(*backing), GFP_KERNEL);
	if (!backing)
		return -ENOMEM;
	backing->imported = true;
	backing->pfn = PVM_BUFFER_IMPORT_IPA >> PAGE_SHIFT;
	backing->token = request.token;
	dmabuf = pvm_export_backing(backing);
	if (IS_ERR(dmabuf)) {
		kfree(backing);
		return PTR_ERR(dmabuf);
	}
	fd = dma_buf_fd(dmabuf, O_CLOEXEC | O_RDWR);
	if (fd < 0) {
		dma_buf_put(dmabuf);
		return fd;
	}
	active_import = backing;
	request.fd = fd;
	if (copy_to_user(argp, &request, sizeof(request)))
		return -EFAULT;
	return 0;
}

static long pvm_ioctl_return(void __user *argp)
{
	struct pvm_buffer_token request;
	struct arm_smccc_res res;

	if (copy_from_user(&request, argp, sizeof(request)))
		return -EFAULT;
	if (!active_import || active_import->token != request.token)
		return -EINVAL;
	pvm_hvc(PVM_BUFFER_RETURN, request.token, 0, 0, &res);
	if ((long)res.a0)
		return -EINVAL;
	active_import->token = 0;
	active_import = NULL;
	return 0;
}

static long pvm_ioctl_wait_return(void __user *argp)
{
	struct pvm_buffer_token request;
	struct arm_smccc_res res;
	unsigned int waited;

	if (copy_from_user(&request, argp, sizeof(request)))
		return -EFAULT;
	for (waited = 0; waited < 10000; waited++) {
		pvm_hvc(PVM_BUFFER_QUERY, request.token, 0, 0, &res);
		if ((long)res.a0)
			return 0;
		msleep(1);
	}
	return -ETIMEDOUT;
}

static long pvm_ioctl_id_get(void __user *argp)
{
	struct arm_smccc_res res;
	u32 endpoint;

	pvm_hvc(PVM_BUFFER_ID_GET, 0, 0, 0, &res);
	if ((long)res.a0)
		return -EINVAL;
	endpoint = res.a1;
	return copy_to_user(argp, &endpoint, sizeof(endpoint)) ? -EFAULT : 0;
}

static long pvm_ioctl(struct file *file, unsigned int command,
		      unsigned long argument)
{
	void __user *argp = (void __user *)argument;

	switch (command) {
	case PVM_BUFFER_IOC_ALLOC:
		return pvm_ioctl_alloc(argp);
	case PVM_BUFFER_IOC_SEND:
		return pvm_ioctl_send(argp);
	case PVM_BUFFER_IOC_RECEIVE:
		return pvm_ioctl_receive(argp);
	case PVM_BUFFER_IOC_RETURN:
		return pvm_ioctl_return(argp);
	case PVM_BUFFER_IOC_WAIT_RETURN:
		return pvm_ioctl_wait_return(argp);
	case PVM_BUFFER_IOC_ID_GET:
		return pvm_ioctl_id_get(argp);
	default:
		return -ENOTTY;
	}
}

static const struct file_operations pvm_fops = {
	.owner = THIS_MODULE,
	.unlocked_ioctl = pvm_ioctl,
	.compat_ioctl = compat_ptr_ioctl,
};

static struct miscdevice pvm_miscdev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "pvm-dmabuf",
	.fops = &pvm_fops,
	.mode = 0600,
};

static int __init pvm_init(void)
{
	return misc_register(&pvm_miscdev);
}

static void __exit pvm_exit(void)
{
	misc_deregister(&pvm_miscdev);
}

module_init(pvm_init);
module_exit(pvm_exit);
MODULE_DESCRIPTION("pKVM cross-pVM DMA-BUF PoC");
MODULE_LICENSE("GPL");
MODULE_IMPORT_NS("DMA_BUF");
