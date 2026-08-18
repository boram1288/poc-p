/* SPDX-License-Identifier: MIT */
#include "pvm/pvm.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define VALID_IMAGE "/images/phase07-guest.img"
#define TAMPERED_IMAGE "/images/phase07-guest-tampered.img"

static void fail(const char *step, int ret)
{
	printf("PVM_FRAMEWORK_TEST_FAILED: step=%s ret=%d error=%s\n",
	       step, ret, pvm_error_name(ret));
	exit(1);
}

static void expect(const char *step, int actual, int expected)
{
	if (actual != expected) fail(step, actual);
}

static int wait_state(const char *role, enum pvm_state expected, struct pvm_info *info)
{
	int i, ret;
	for (i = 0; i < 500; ++i) {
		ret = pvm_status(NULL, role, info);
		if (!ret && info->state == expected) return 0;
		usleep(10000);
	}
	return -1;
}

static unsigned long mlocked_kb(void)
{
	char line[128];
	unsigned long value = ~0UL;
	FILE *file = fopen("/proc/meminfo", "r");
	if (!file) return value;
	while (fgets(line, sizeof(line), file))
		if (sscanf(line, "Mlocked: %lu kB", &value) == 1) break;
	fclose(file);
	return value;
}

static void test_auth_denial(void)
{
	pid_t child = fork();
	int status;
	if (child < 0) fail("auth-fork", PVM_ERR_SYSTEM);
	if (!child) {
		struct pvm_info info;
		if (setgid(65534) || setuid(65534)) _exit(2);
		_exit(pvm_create(NULL, "camera", VALID_IMAGE, &info) == PVM_ERR_AUTH ? 0 : 3);
	}
	waitpid(child, &status, 0);
	if (!WIFEXITED(status) || WEXITSTATUS(status)) fail("auth-denial", PVM_ERR_AUTH);
	puts("PVM_FRAMEWORK_AUTH_TEST_OK");
}

static void test_rejections(void)
{
	struct pvm_info info;
	expect("policy-denial", pvm_create(NULL, "invalid", VALID_IMAGE, &info), PVM_ERR_POLICY);
	puts("PVM_FRAMEWORK_POLICY_TEST_OK");
	expect("image-rejection", pvm_create(NULL, "camera", TAMPERED_IMAGE, &info),
	       PVM_ERR_IMAGE);
	expect("image-rejection-no-instance", pvm_status(NULL, "camera", &info),
	       PVM_ERR_NOT_FOUND);
	puts("PVM_FRAMEWORK_IMAGE_REJECTION_OK: kvm_fds=0");
}

static void test_normal_lifecycle(void)
{
	struct pvm_info info;
	expect("normal-create", pvm_create(NULL, "camera", VALID_IMAGE, &info), PVM_OK);
	if (info.state != PVM_STATE_CREATED) fail("normal-created-state", PVM_ERR_STATE);
	expect("normal-start", pvm_start(NULL, "camera", &info), PVM_OK);
	if (info.state != PVM_STATE_RUNNING || info.pid <= 1 || info.resource_fd_count < 3 ||
	    info.vcpu_count != 1 || !info.memory_bytes)
		fail("normal-running-state", PVM_ERR_STATE);
	expect("normal-status", pvm_status(NULL, "camera", &info), PVM_OK);
	expect("invalid-second-start", pvm_start(NULL, "camera", &info), PVM_ERR_STATE);
	printf("PVM_FRAMEWORK_NORMAL_RUNNING: pid=%d id=%llu resources=%u vcpus=%u memory=%llu\n",
	       info.pid, (unsigned long long)info.instance_id, info.resource_fd_count,
	       info.vcpu_count, (unsigned long long)info.memory_bytes);
	expect("normal-stop", pvm_stop(NULL, "camera", &info), PVM_OK);
	if (info.state != PVM_STATE_STOPPED || info.pid)
		fail("normal-stopped-state", PVM_ERR_STATE);
	expect("normal-delete", pvm_delete(NULL, "camera"), PVM_OK);
	puts("PVM_FRAMEWORK_NORMAL_LIFECYCLE_OK");
}

static int process_gone_or_zombie(pid_t pid)
{
	char path[64], line[256], state;
	int parsed_pid;
	FILE *file;
	snprintf(path, sizeof(path), "/proc/%d/stat", pid);
	file = fopen(path, "r");
	if (!file) return errno == ENOENT;
	state = '?';
	if (fgets(line, sizeof(line), file) &&
	    sscanf(line, "%d %*s %c", &parsed_pid, &state) != 2)
		state = '?';
	fclose(file);
	return state == 'Z';
}

static pid_t test_daemon_recovery(pid_t old_daemon)
{
	struct pvm_info camera;
	pid_t new_daemon;
	int i, ret;

	expect("recovery-create", pvm_create(NULL, "camera", VALID_IMAGE, &camera), PVM_OK);
	expect("recovery-start", pvm_start(NULL, "camera", &camera), PVM_OK);
	if (kill(old_daemon, SIGKILL)) fail("recovery-kill-daemon", PVM_ERR_SYSTEM);
	usleep(50000);
	new_daemon = fork();
	if (new_daemon < 0) fail("recovery-fork-daemon", PVM_ERR_SYSTEM);
	if (!new_daemon) {
		execl("/bin/pvmd", "/bin/pvmd", NULL);
		_exit(127);
	}
	for (i = 0; i < 500; ++i) {
		struct pvm_info infos[2];
		ret = pvm_list(NULL, infos, 2);
		if (ret >= 0) break;
		usleep(10000);
	}
	if (i == 500) fail("recovery-new-daemon-ready", PVM_ERR_SYSTEM);
	expect("recovery-empty-state", pvm_status(NULL, "camera", &camera),
	       PVM_ERR_NOT_FOUND);
	for (i = 0; i < 500 && !process_gone_or_zombie(camera.pid); ++i)
		usleep(10000);
	if (i == 500) fail("recovery-stale-runner", PVM_ERR_SYSTEM);
	puts("PVM_FRAMEWORK_DAEMON_RECOVERY_OK");
	return new_daemon;
}

static void test_fault_isolation(void)
{
	struct pvm_info camera, ai, listed[2];
	int count;
	expect("fault-camera-create", pvm_create(NULL, "camera", VALID_IMAGE, &camera), PVM_OK);
	expect("fault-camera-start", pvm_start(NULL, "camera", &camera), PVM_OK);
	expect("fault-ai-create", pvm_create(NULL, "ai", VALID_IMAGE, &ai), PVM_OK);
	expect("fault-ai-start", pvm_start(NULL, "ai", &ai), PVM_OK);
	if (camera.resource_fd_count < 3 || ai.resource_fd_count < 3 ||
	    camera.instance_id == ai.instance_id)
		fail("overlap-resources", PVM_ERR_STATE);
	printf("PVM_FRAMEWORK_OVERLAP: camera_pid=%d camera_resources=%u ai_pid=%d ai_resources=%u\n",
	       camera.pid, camera.resource_fd_count, ai.pid, ai.resource_fd_count);
	if (kill(camera.pid, SIGKILL)) fail("camera-sigkill", PVM_ERR_SYSTEM);
	if (wait_state("camera", PVM_STATE_FAILED, &camera))
		fail("camera-failed-state", PVM_ERR_STATE);
	expect("ai-survives", pvm_status(NULL, "ai", &ai), PVM_OK);
	if (ai.state != PVM_STATE_RUNNING) fail("ai-running-after-camera-fault", PVM_ERR_STATE);
	count = pvm_list(NULL, listed, 2);
	if (count != 2) fail("controller-responsive", count);
	if (kill(ai.pid, SIGCONT)) fail("ai-continue", PVM_ERR_SYSTEM);
	if (wait_state("ai", PVM_STATE_STOPPED, &ai))
		fail("ai-completed", PVM_ERR_STATE);
	puts("PVM_DEVICE_REASSIGN_OK");
	puts("PVM_FRAMEWORK_FAULT_ISOLATION_OK");
	expect("fault-camera-delete", pvm_delete(NULL, "camera"), PVM_OK);
	expect("fault-ai-delete", pvm_delete(NULL, "ai"), PVM_OK);
}

int main(int argc, char **argv)
{
	unsigned long locked;
	pid_t daemon_pid, replacement_daemon;
	int status;
	if (argc != 2) return 2;
	daemon_pid = (pid_t)strtol(argv[1], NULL, 10);
	if (daemon_pid <= 1) return 2;
	setvbuf(stdout, NULL, _IONBF, 0);
	test_auth_denial();
	test_rejections();
	test_normal_lifecycle();
	replacement_daemon = test_daemon_recovery(daemon_pid);
	test_fault_isolation();
	locked = mlocked_kb();
	printf("Mlocked: %lu kB\n", locked);
	if (locked != 0) fail("resource-recovery", PVM_ERR_SYSTEM);
	puts("PVM_FRAMEWORK_RESOURCE_RECOVERY_OK");
	puts("PVM_FRAMEWORK_VALIDATION_OK");
	kill(replacement_daemon, SIGTERM);
	waitpid(replacement_daemon, &status, 0);
	return 0;
}
