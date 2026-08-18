/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef PVM_KVM_ARM64_H
#define PVM_KVM_ARM64_H

int pvm_kvm_arm64_run(const char *role, const char *guest_image, int ready_fd);

#endif
