/* SPDX-License-Identifier: MIT */
#include "pvm/pvm.h"

#include <stdio.h>
#include <string.h>

static void show(const struct pvm_info *info)
{
	printf("role=%s id=%llu state=%s pid=%d exit=%d resources=%u vcpus=%u memory=%llu\n", info->role,
	       (unsigned long long)info->instance_id, pvm_state_name(info->state),
	       info->pid, info->exit_status, info->resource_fd_count, info->vcpu_count,
	       (unsigned long long)info->memory_bytes);
}

int main(int argc, char **argv)
{
	struct pvm_info info;
	int ret;
	if (argc < 3) {
		fprintf(stderr, "usage: %s create ROLE IMAGE | start|status|stop|delete ROLE | list -\n", argv[0]);
		return 2;
	}
	if (!strcmp(argv[1], "create") && argc == 4)
		ret = pvm_create(NULL, argv[2], argv[3], &info);
	else if (!strcmp(argv[1], "start")) ret = pvm_start(NULL, argv[2], &info);
	else if (!strcmp(argv[1], "status")) ret = pvm_status(NULL, argv[2], &info);
	else if (!strcmp(argv[1], "stop")) ret = pvm_stop(NULL, argv[2], &info);
	else if (!strcmp(argv[1], "delete")) ret = pvm_delete(NULL, argv[2]);
	else if (!strcmp(argv[1], "list")) {
		struct pvm_info infos[2];
		int i;
		ret = pvm_list(NULL, infos, 2);
		if (ret >= 0) {
			for (i = 0; i < ret; ++i) show(&infos[i]);
			return 0;
		}
	} else return 2;
	if (ret) {
		fprintf(stderr, "pvmctl: %s (%d)\n", pvm_error_name(ret), ret);
		return 1;
	}
	if (strcmp(argv[1], "delete")) show(&info);
	return 0;
}
