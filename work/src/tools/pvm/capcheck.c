#include <errno.h>
#include <fcntl.h>
#include <linux/kvm.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(void)
{
	int kvm, vm, vcpu, cap;

	kvm = open("/dev/kvm", O_RDWR | O_CLOEXEC);
	if (kvm < 0) {
		printf("PVM_TEST_KVM_DEV: ABSENT (%s)\n", strerror(errno));
		return 1;
	}
	puts("PVM_TEST_KVM_DEV: PRESENT");

	cap = ioctl(kvm, KVM_CHECK_EXTENSION, KVM_CAP_ARM_PROTECTED_VM);
	printf("KVM_CAP_ARM_PROTECTED_VM -> %d\n", cap);
	if (cap != 1)
		return 2;

	vm = ioctl(kvm, KVM_CREATE_VM, KVM_VM_TYPE_ARM_PROTECTED);
	if (vm < 0) {
		printf("KVM_CREATE_VM(type=PROTECTED 1<<31) -> FAIL (%s)\n",
		       strerror(errno));
		return 3;
	}
	puts("KVM_CREATE_VM(type=PROTECTED 1<<31) -> OK");

	vcpu = ioctl(vm, KVM_CREATE_VCPU, 0);
	if (vcpu < 0) {
		printf("KVM_CREATE_VCPU -> FAIL (%s)\n", strerror(errno));
		return 4;
	}
	puts("KVM_CREATE_VCPU -> OK");

	close(vcpu);
	close(vm);
	close(kvm);
	puts("PVM_TEST_CAPCHECK: rc=0");
	return 0;
}
