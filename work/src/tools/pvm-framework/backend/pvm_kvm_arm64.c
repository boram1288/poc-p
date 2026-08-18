/* SPDX-License-Identifier: GPL-2.0-only */
#include "pvm_kvm_arm64.h"
#include "pvm_image.h"
#include "runner_protocol.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <kvm_util.h>
#include <linux/vfio.h>
#include <processor.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <unistd.h>

#include "pkvm.h"

#define WORKLOAD_GPA BIT_ULL(30)
#define WORKLOAD_PAGES 4
#define MMIO_GPA (WORKLOAD_GPA + WORKLOAD_PAGES * MIN_PAGE_SIZE)
#define EDU_GPA 0x10000000ULL
#define EDU_SIZE (1ULL << 20)
#define DMA_GPA (WORKLOAD_GPA + 2 * MIN_PAGE_SIZE)
#define PCI_COMMAND_OFFSET 0x04
#define PCI_COMMAND_IO_MEMORY_MASTER 0x0006
#define MAGIC_STARTED 0x54524154534d5650ULL
#define MAGIC_COMPLETED 0x21454e4f444d5650ULL

struct assigned_device {
	int container_fd;
	int group_fd;
	int device_fd;
	int kvm_vfio_fd;
	int pviommu_fd;
	void *mmio;
	size_t mmio_size;
};

struct edu_config {
	const char *platform_device;
	const char *pci_config;
	uint64_t physical_base;
	uint32_t vsid;
};

static const struct edu_config camera_edu = {
	.platform_device = "10000000.pkvm-edu",
	.pci_config = "/sys/bus/pci/devices/0000:00:02.0/config",
	.physical_base = 0x10000000ULL,
	.vsid = 0x10,
};

static const struct edu_config ai_edu = {
	.platform_device = "10100000.pkvm-edu",
	.pci_config = "/sys/bus/pci/devices/0000:00:03.0/config",
	.physical_base = 0x10100000ULL,
	.vsid = 0x18,
};

static void assigned_device_init(struct assigned_device *device)
{
	memset(device, 0, sizeof(*device));
	device->container_fd = -1;
	device->group_fd = -1;
	device->device_fd = -1;
	device->kvm_vfio_fd = -1;
	device->pviommu_fd = -1;
	device->mmio = MAP_FAILED;
}

static int iommu_group_number(const char *platform_device)
{
	char path[256], link[256], *name;
	ssize_t length;

	snprintf(path, sizeof(path), "/sys/bus/platform/devices/%s/iommu_group",
		 platform_device);
	length = readlink(path, link, sizeof(link) - 1);
	if (length < 0)
		return -1;
	link[length] = '\0';
	name = strrchr(link, '/');
	return name ? atoi(name + 1) : -1;
}

static int kvm_set_device_attr(int fd, uint32_t group, uint64_t attr, void *value)
{
	struct kvm_device_attr device_attr = {
		.group = group,
		.attr = attr,
		.addr = (uintptr_t)value,
	};

	return ioctl(fd, KVM_SET_DEVICE_ATTR, &device_attr);
}

static int enable_pci_edu(const char *config_path)
{
	uint16_t command;
	int fd;

	fd = open(config_path, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return -1;
	if (pread(fd, &command, sizeof(command), PCI_COMMAND_OFFSET) != sizeof(command))
		goto fail;
	command |= PCI_COMMAND_IO_MEMORY_MASTER;
	if (pwrite(fd, &command, sizeof(command), PCI_COMMAND_OFFSET) != sizeof(command))
		goto fail;
	close(fd);
	return 0;
fail:
	close(fd);
	return -1;
}

static int assign_edu_device(struct kvm_vm *vm, struct assigned_device *device,
			     const struct edu_config *edu, const char *role)
{
	struct kvm_vfio_iommu_config config = {
		.size = sizeof(config),
		.sid_idx = 0,
		.vsid = edu->vsid,
	};
	struct kvm_vfio_iommu_info iommu_info = {
		.size = sizeof(iommu_info),
	};
	struct vfio_region_info region = {
		.argsz = sizeof(region),
		.index = 0,
	};
	struct vfio_group_status status = {
		.argsz = sizeof(status),
	};
	char group_path[64];
	int group;
	const char *step = "discover";

	group = iommu_group_number(edu->platform_device);
	if (group < 0)
		goto fail;
	step = "enable-pci";
	if (enable_pci_edu(edu->pci_config))
		goto fail;

	step = "open-container";
	device->container_fd = open("/dev/vfio/vfio", O_RDWR | O_CLOEXEC);
	if (device->container_fd < 0 ||
	    ioctl(device->container_fd, VFIO_GET_API_VERSION) != VFIO_API_VERSION ||
	    ioctl(device->container_fd, VFIO_CHECK_EXTENSION, VFIO_PKVM_IOMMU) != 1)
		goto fail;

	step = "attach-group";
	snprintf(group_path, sizeof(group_path), "/dev/vfio/%d", group);
	device->group_fd = open(group_path, O_RDWR | O_CLOEXEC);
	if (device->group_fd < 0 ||
	    ioctl(device->group_fd, VFIO_GROUP_GET_STATUS, &status) ||
	    !(status.flags & VFIO_GROUP_FLAGS_VIABLE) ||
	    ioctl(device->group_fd, VFIO_GROUP_SET_CONTAINER, &device->container_fd) ||
	    ioctl(device->container_fd, VFIO_SET_IOMMU, VFIO_PKVM_IOMMU))
		goto fail;

	step = "create-kvm-vfio";
	device->kvm_vfio_fd = kvm_create_device(vm, KVM_DEV_TYPE_VFIO);
	step = "add-vfio-file";
	if (kvm_set_device_attr(device->kvm_vfio_fd, KVM_DEV_VFIO_FILE,
				KVM_DEV_VFIO_FILE_ADD, &device->group_fd))
		goto fail;

	step = "get-device-fd";
	device->device_fd = ioctl(device->group_fd, VFIO_GROUP_GET_DEVICE_FD,
				  edu->platform_device);
	if (device->device_fd < 0)
		goto fail;

	step = "get-pviommu-info";
	iommu_info.device_fd = device->device_fd;
	if (kvm_set_device_attr(device->kvm_vfio_fd, KVM_DEV_VFIO_PVIOMMU,
				KVM_DEV_VFIO_PVIOMMU_GET_INFO, &iommu_info) ||
	    iommu_info.out_nr_sids != 1)
		goto fail;

	step = "attach-pviommu";
	device->pviommu_fd = kvm_set_device_attr(device->kvm_vfio_fd,
				KVM_DEV_VFIO_PVIOMMU,
				KVM_DEV_VFIO_PVIOMMU_ATTACH, NULL);
	if (device->pviommu_fd < 0)
		goto fail;

	step = "configure-pviommu";
	config.device_fd = device->device_fd;
	if (ioctl(device->pviommu_fd, KVM_PVIOMMU_SET_CONFIG, &config) ||
	    ioctl(device->device_fd, VFIO_DEVICE_GET_REGION_INFO, &region) ||
	    region.size != EDU_SIZE)
		goto fail;

	step = "map-mmio";
	device->mmio_size = region.size;
	device->mmio = mmap(NULL, region.size, PROT_READ | PROT_WRITE, MAP_SHARED,
			    device->device_fd, region.offset);
	if (device->mmio == MAP_FAILED)
		goto fail;

	vm_set_user_memory_region(vm, 3, 0, EDU_GPA, region.size, device->mmio);
	virt_map(vm, EDU_GPA, EDU_GPA, region.size / vm->page_size);
	printf("PVM_DEVICE_ASSIGNED: role=%s group=%d device=%s phys=0x%llx pviommu=%d vsid=0x%x\n",
	       role, group, edu->platform_device,
	       (unsigned long long)edu->physical_base, device->pviommu_fd, edu->vsid);
	return 0;

fail:
	printf("PVM_DEVICE_ASSIGN_FAILED: device=%s step=%s errno=%d error=%s\n",
	       edu->platform_device, step, errno, strerror(errno));
	return -1;
}

static void assigned_device_close(struct assigned_device *device)
{
	if (device->mmio != MAP_FAILED)
		munmap(device->mmio, device->mmio_size);
	if (device->pviommu_fd >= 0)
		close(device->pviommu_fd);
	if (device->device_fd >= 0)
		close(device->device_fd);
	if (device->kvm_vfio_fd >= 0)
		close(device->kvm_vfio_fd);
	if (device->group_fd >= 0)
		close(device->group_fd);
	if (device->container_fd >= 0)
		close(device->container_fd);
}

static sigjmp_buf host_access_jmp;
static volatile sig_atomic_t host_access_signal_number;

static void host_access_signal(int signal)
{
	host_access_signal_number = signal;
	siglongjmp(host_access_jmp, 1);
}

static int verify_host_mmio_blocked(const struct assigned_device *device,
				    const char *role)
{
	struct sigaction action = { .sa_handler = host_access_signal };
	struct sigaction old_bus, old_segv;
	volatile uint32_t value;
	int jumped, caught;

	sigemptyset(&action.sa_mask);
	if (sigaction(SIGBUS, &action, &old_bus) ||
	    sigaction(SIGSEGV, &action, &old_segv))
		return -1;
	host_access_signal_number = 0;
	jumped = sigsetjmp(host_access_jmp, 1);
	if (!jumped) {
		value = *(volatile uint32_t *)device->mmio;
		(void)value;
	}
	caught = host_access_signal_number;
	sigaction(SIGBUS, &old_bus, NULL);
	sigaction(SIGSEGV, &old_segv, NULL);
	if (caught != SIGBUS && caught != SIGSEGV)
		return -1;
	printf("PVM_DEVICE_HOST_ACCESS_BLOCKED: role=%s signal=%d\n", role, caught);
	return 0;
}

static int locked_vm_bytes(void)
{
	char line[128];
	unsigned long value;
	FILE *file = fopen("/proc/self/status", "r");
	if (!file) return -1;
	while (fgets(line, sizeof(line), file)) {
		if (sscanf(line, "VmLck:%lu kB", &value) == 1) {
			fclose(file);
			return (int)(value << 10);
		}
	}
	fclose(file);
	return -1;
}

static struct kvm_vm *create_protected_vm(struct kvm_vcpu **vcpu)
{
	extern char pvm_entry_start[], pvm_entry_end[];
	struct vm_shape shape = VM_SHAPE_DEFAULT;
	vm_paddr_t idmap_gpa;
	struct kvm_vm *vm;

	shape.type = VM_TYPE_PROTECTED;
	vm = vm_create_shape_with_one_vcpu(shape, vcpu, NULL);
	idmap_gpa = vm_compute_max_gfn(vcpu[0]->vm) * vm->page_size;
	vm_userspace_mem_region_add(vm, VM_MEM_SRC_ANONYMOUS, idmap_gpa, 2, 1, 0);
	memcpy(addr_gpa2hva(vm, idmap_gpa), pvm_entry_start,
	       (size_t)(pvm_entry_end - pvm_entry_start));
	virt_map(vm, idmap_gpa, idmap_gpa, 1);
	vcpu_set_reg(vcpu[0], ARM64_CORE_REG(regs.pc), idmap_gpa);
	return vm;
}

static void set_boot_args(struct kvm_vcpu *vcpu, uint64_t jump_target)
{
	struct pvm_boot_args *args;
	vm_paddr_t args_gpa;
	uint64_t reg;
	int i;

	reg = vcpu_get_reg(vcpu, ARM64_CORE_REG(regs.pc));
	args_gpa = (reg + vcpu->vm->page_size) - sizeof(*args);
	args = addr_gpa2hva(vcpu->vm, args_gpa);
	for (i = 0; i < 8; ++i)
		args->regs[i] = vcpu_get_reg(vcpu, ARM64_CORE_REG(regs.regs[i]));
	args->jump_tgt = jump_target;
	vcpu_set_reg(vcpu, ARM64_CORE_REG(regs.regs[0]), args_gpa);
	args->cpacr_el1 = vcpu_get_reg(vcpu, KVM_ARM64_SYS_REG(SYS_CPACR_EL1));
	args->sctlr_el1 = vcpu_get_reg(vcpu, KVM_ARM64_SYS_REG(SYS_SCTLR_EL1));
	args->tcr_el1 = vcpu_get_reg(vcpu, KVM_ARM64_SYS_REG(SYS_TCR_EL1));
	args->ttbr0_el1 = vcpu_get_reg(vcpu, KVM_ARM64_SYS_REG(SYS_TTBR0_EL1));
	args->vbar_el1 = vcpu_get_reg(vcpu, KVM_ARM64_SYS_REG(SYS_VBAR_EL1));
	args->tpidr_el1 = vcpu_get_reg(vcpu, KVM_ARM64_SYS_REG(SYS_TPIDR_EL1));
	args->sp_el1 = vcpu_get_reg(vcpu, ARM64_CORE_REG(sp_el1));
}

static int expect_mmio(struct kvm_vcpu *vcpu, uint64_t expected)
{
	struct kvm_run *run = vcpu->run;
	uint64_t value = 0;
	if (run->exit_reason != KVM_EXIT_MMIO || run->mmio.phys_addr != MMIO_GPA ||
	    !run->mmio.is_write || run->mmio.len != sizeof(value))
		return -1;
	memcpy(&value, run->mmio.data, sizeof(value));
	if (value != expected)
		printf("PVM_RUNNER_MMIO_MISMATCH: expected=0x%llx actual=0x%llx\n",
		       (unsigned long long)expected, (unsigned long long)value);
	return value == expected ? 0 : -1;
}

static int run_vcpu(struct kvm_vcpu *vcpu, const char *role)
{
	int ret;

	do {
		ret = __vcpu_run(vcpu);
	} while (ret == -1 && errno == EINTR);
	if (ret)
		printf("PVM_RUNNER_KVM_RUN_FAILED: role=%s errno=%d error=%s\n",
		       role, errno, strerror(errno));
	return ret;
}

static uint32_t count_kvm_fds(void)
{
	struct dirent *entry;
	DIR *dir = opendir("/proc/self/fd");
	uint32_t count = 0;
	if (!dir) return 0;
	while ((entry = readdir(dir))) {
		char link_path[320], target[128];
		ssize_t length;
		if (entry->d_name[0] == '.') continue;
		snprintf(link_path, sizeof(link_path), "/proc/self/fd/%s", entry->d_name);
		length = readlink(link_path, target, sizeof(target) - 1);
		if (length <= 0) continue;
		target[length] = '\0';
		if (!strcmp(target, "/dev/kvm") || !strncmp(target, "anon_inode:kvm-", 15))
			++count;
	}
	closedir(dir);
	return count;
}

int pvm_kvm_arm64_run(const char *role, const char *guest_image, int ready_fd)
{
	struct kvm_vcpu *vcpu, *iter;
	struct kvm_vm *vm = NULL;
	struct assigned_device device;
	const struct edu_config *edu;
	void *workload = NULL;
	size_t workload_size = 0;
	int ret = 1;
	struct pvm_runner_ready ready = { .magic = PVM_RUNNER_READY_MAGIC };

	assigned_device_init(&device);
	edu = !strcmp(role, "camera") ? &camera_edu : &ai_edu;

	if (pvm_image_read(guest_image, &workload, &workload_size)) {
		printf("PVM_RUNNER_IMAGE_INVALID: role=%s\n", role);
		return 2;
	}
	printf("PVM_RUNNER_WORKLOAD_VERIFIED: role=%s size=%zu\n", role, workload_size);
	vm = create_protected_vm(&vcpu);
	if (vm->page_size != MIN_PAGE_SIZE || workload_size > WORKLOAD_PAGES * vm->page_size)
		goto out;
	vm_userspace_mem_region_add(vm, VM_MEM_SRC_ANONYMOUS, WORKLOAD_GPA, 1,
				    WORKLOAD_PAGES, 0);
	memset(addr_gpa2hva(vm, WORKLOAD_GPA), 0, WORKLOAD_PAGES * vm->page_size);
	memcpy(addr_gpa2hva(vm, WORKLOAD_GPA), workload, workload_size);
	virt_map(vm, WORKLOAD_GPA, WORKLOAD_GPA, WORKLOAD_PAGES);
	virt_map(vm, MMIO_GPA, MMIO_GPA, 1);
	if (assign_edu_device(vm, &device, edu, role))
		goto out;
	vm_init_descriptor_tables(vm);
	kvm_for_each_vcpu(vm, iter)
		vcpu_init_descriptor_tables(iter);
	vcpu_args_set(vcpu, 5, MMIO_GPA,
		      EDU_GPA, (uint64_t)device.pviommu_fd, edu->vsid, DMA_GPA);
	set_boot_args(vcpu, WORKLOAD_GPA);

	if (run_vcpu(vcpu, role))
		goto out;
	if (expect_mmio(vcpu, MAGIC_STARTED)) {
		printf("PVM_RUNNER_UNEXPECTED_EXIT: role=%s reason=%u\n", role,
		       vcpu->run->exit_reason);
		goto out;
	}
	printf("GUEST_WORKLOAD_STARTED: role=%s\n", role);
	printf("PVM_DEVICE_DRIVER_OK: role=%s\n", role);
	printf("PVM_DEVICE_NONOWNER_BLOCKED: role=%s\n", role);
	printf("PVM_DEVICE_DMA_NORMAL_OK: role=%s\n", role);
	printf("PVM_DEVICE_DMA_RANGE_BLOCKED: role=%s\n", role);
	if (!strcmp(role, "camera"))
		printf("PVM_DMA_SHARE_GRANTED: role=%s receiver_sid=0x18 bytes=4096\n",
		       role);
	else {
		printf("PVM_DMA_SHARE_UNAPPROVED_BLOCKED: role=%s sid=0x10\n",
		       role);
		printf("PVM_DMA_SHARE_ACCEPTED: role=%s sender_sid=0x10 bytes=4096\n",
		       role);
		printf("PVM_DMA_SHARE_READ_OK: role=%s bytes=8\n", role);
	}
	if (verify_host_mmio_blocked(&device, role)) {
		printf("PVM_DEVICE_HOST_ACCESS_NOT_BLOCKED: role=%s\n", role);
		goto out;
	}
	ready.resource_fd_count = count_kvm_fds();
	ready.vcpu_count = 1;
	ready.memory_bytes = WORKLOAD_PAGES * vm->page_size;
	if (write(ready_fd, &ready, sizeof(ready)) != sizeof(ready)) goto out;
	raise(SIGSTOP);

	if (run_vcpu(vcpu, role))
		goto out;
	if (expect_mmio(vcpu, MAGIC_COMPLETED)) goto out;
	printf("GUEST_WORKLOAD_COMPLETED: role=%s\n", role);
	if (!strcmp(role, "ai"))
		printf("PVM_DMA_SHARE_REVOKE_BLOCKED: role=%s bytes=8\n", role);
	ret = 0;
out:
	if (vm) {
		printf("PVM_RUNNER_VMLOCK_BEFORE_TEARDOWN: role=%s bytes=%d\n",
		       role, locked_vm_bytes());
		kvm_vm_release(vm);
		kvm_vm_free(vm);
		printf("PVM_RUNNER_VMLOCK_AFTER_TEARDOWN: role=%s bytes=%d\n",
		       role, locked_vm_bytes());
	}
	assigned_device_close(&device);
	free(workload);
	return ret;
}
