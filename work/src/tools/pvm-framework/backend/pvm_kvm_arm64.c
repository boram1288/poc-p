/* SPDX-License-Identifier: GPL-2.0-only */
#include "pvm_kvm_arm64.h"
#include "pvm_image.h"
#include "runner_protocol.h"

#include <dirent.h>
#include <fcntl.h>
#include <kvm_util.h>
#include <processor.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

#include "pkvm.h"

#define WORKLOAD_GPA BIT_ULL(30)
#define WORKLOAD_PAGES 4
#define MMIO_GPA (WORKLOAD_GPA + WORKLOAD_PAGES * MIN_PAGE_SIZE)
#define MAGIC_STARTED 0x54524154534d5650ULL
#define MAGIC_COMPLETED 0x21454e4f444d5650ULL

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
	return value == expected ? 0 : -1;
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
	void *workload = NULL;
	size_t workload_size = 0;
	int ret = 1;
	struct pvm_runner_ready ready = { .magic = PVM_RUNNER_READY_MAGIC };

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
	vm_init_descriptor_tables(vm);
	kvm_for_each_vcpu(vm, iter)
		vcpu_init_descriptor_tables(iter);
	vcpu_args_set(vcpu, 1, MMIO_GPA);
	set_boot_args(vcpu, WORKLOAD_GPA);

	vcpu_run(vcpu);
	if (expect_mmio(vcpu, MAGIC_STARTED)) {
		printf("PVM_RUNNER_UNEXPECTED_EXIT: role=%s reason=%u\n", role,
		       vcpu->run->exit_reason);
		goto out;
	}
	printf("GUEST_WORKLOAD_STARTED: role=%s\n", role);
	ready.resource_fd_count = count_kvm_fds();
	ready.vcpu_count = 1;
	ready.memory_bytes = WORKLOAD_PAGES * vm->page_size;
	if (write(ready_fd, &ready, sizeof(ready)) != sizeof(ready)) goto out;
	raise(SIGSTOP);

	vcpu_run(vcpu);
	if (expect_mmio(vcpu, MAGIC_COMPLETED)) goto out;
	printf("GUEST_WORKLOAD_COMPLETED: role=%s\n", role);
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
	free(workload);
	return ret;
}
