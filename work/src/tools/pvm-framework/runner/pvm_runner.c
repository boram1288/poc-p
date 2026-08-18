/* SPDX-License-Identifier: GPL-2.0-only */
#include "pvm_kvm_arm64.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	int ready_fd, ret;
	if (argc != 4) {
		fprintf(stderr, "usage: %s ROLE GUEST_IMAGE READY_FD\n", argv[0]);
		return 2;
	}
	ready_fd = atoi(argv[3]);
	if (prctl(PR_SET_PDEATHSIG, SIGTERM) || getppid() == 1)
		return 3;
	setvbuf(stdout, NULL, _IONBF, 0);
	printf("PVM_RUNNER_START: role=%s pid=%d\n", argv[1], getpid());
	ret = pvm_kvm_arm64_run(argv[1], argv[2], ready_fd);
	close(ready_fd);
	printf("PVM_RUNNER_EXIT: role=%s rc=%d\n", argv[1], ret);
	return ret;
}
