/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "pvm/pvm.h"
#include "protocol.h"
#include "runner_protocol.h"
#include "sha256.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define STATE_DIR "/run/pvm-framework"
#define MANIFEST_DEFAULT "/images/SHA256SUMS"
#define RUNNER_DEFAULT "/bin/pvm-runner"
#define ROLE_COUNT 2

struct instance {
	int used;
	struct pvm_info info;
	char image[PVM_PATH_MAX];
};

static struct instance instances[ROLE_COUNT];
static uint64_t next_instance_id = 1;
static const char *manifest_path = MANIFEST_DEFAULT;
static const char *runner_path = RUNNER_DEFAULT;
static uint64_t last_root_request_id;

static void marker(const char *name, const char *role, const char *detail)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	printf("PVM_FRAMEWORK_%s: ts_ms=%llu role=%s%s%s\n", name,
	       (unsigned long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000,
	       role ? role : "-",
	       detail ? " " : "", detail ? detail : "");
}

static int role_index(const char *role)
{
	if (!strcmp(role, "camera")) return 0;
	if (!strcmp(role, "ai")) return 1;
	return -1;
}

static struct instance *find_role(const char *role)
{
	int index = role_index(role);
	return index >= 0 && instances[index].used ? &instances[index] : NULL;
}

static int valid_image_path(const char *path)
{
	const char *name;
	size_t len;
	if (strncmp(path, "/images/", 8) || strstr(path, "..")) return 0;
	name = path + 8;
	len = strlen(name);
	return len > 4 && !strchr(name, '/') && !strcmp(name + len - 4, ".img");
}

static int manifest_digest(const char *image, uint8_t digest[PVM_SHA256_SIZE])
{
	char line[512], hex[PVM_SHA256_HEX_SIZE], name[PVM_PATH_MAX];
	const char *base = strrchr(image, '/');
	FILE *file = fopen(manifest_path, "r");
	if (!file) return -1;
	base = base ? base + 1 : image;
	while (fgets(line, sizeof(line), file)) {
		if (sscanf(line, "%64s %255s", hex, name) == 2 && !strcmp(name, base)) {
			fclose(file);
			return pvm_sha256_parse(hex, digest);
		}
	}
	fclose(file);
	return -1;
}

static int verify_image(const char *role, const char *path)
{
	uint8_t expected[PVM_SHA256_SIZE], actual[PVM_SHA256_SIZE];
	char hex[PVM_SHA256_HEX_SIZE], detail[96];
	if (!valid_image_path(path)) return PVM_ERR_POLICY;
	if (manifest_digest(path, expected) || pvm_sha256_file(path, actual) ||
	    memcmp(expected, actual, sizeof(actual)))
		return PVM_ERR_IMAGE;
	pvm_sha256_hex(actual, hex);
	snprintf(detail, sizeof(detail), "sha256=%s", hex);
	marker("IMAGE_VERIFIED", role, detail);
	return PVM_OK;
}

static void pidfile_path(const char *role, char path[128])
{
	snprintf(path, 128, "%s/%s.pid", STATE_DIR, role);
}

static void write_pidfile(const char *role, pid_t pid)
{
	char path[128];
	FILE *file;
	pidfile_path(role, path);
	file = fopen(path, "w");
	if (file) {
		fprintf(file, "%d\n", pid);
		fclose(file);
	}
}

static void remove_pidfile(const char *role)
{
	char path[128];
	pidfile_path(role, path);
	unlink(path);
}

static void cleanup_stale_runner(const char *role)
{
	char path[128];
	long pid;
	FILE *file;
	pidfile_path(role, path);
	file = fopen(path, "r");
	if (!file) return;
	if (fscanf(file, "%ld", &pid) == 1 && pid > 1) {
		kill((pid_t)pid, SIGCONT);
		kill((pid_t)pid, SIGTERM);
	}
	fclose(file);
	unlink(path);
}

static void reap_runners(void)
{
	int status, i;
	pid_t pid;
	while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
		for (i = 0; i < ROLE_COUNT; ++i) {
			struct instance *instance = &instances[i];
			char detail[128];
			if (!instance->used || instance->info.pid != pid) continue;
			instance->info.exit_status = WIFEXITED(status) ? WEXITSTATUS(status) :
						     128 + WTERMSIG(status);
			if (instance->info.state == PVM_STATE_STOPPING ||
			    (WIFEXITED(status) && WEXITSTATUS(status) == 0))
				instance->info.state = PVM_STATE_STOPPED;
			else
				instance->info.state = PVM_STATE_FAILED;
			instance->info.pid = 0;
			instance->info.resource_fd_count = 0;
			remove_pidfile(instance->info.role);
			snprintf(detail, sizeof(detail), "id=%llu state=%s exit=%d",
				 (unsigned long long)instance->info.instance_id,
				 pvm_state_name(instance->info.state), instance->info.exit_status);
			marker("RUNNER_REAPED", instance->info.role, detail);
		}
	}
}

static int create_instance(const struct pvm_request *request, struct pvm_info *info)
{
	struct instance *instance;
	char detail[96];
	int index = role_index(request->role), ret;
	if (index < 0) return PVM_ERR_POLICY;
	if (instances[index].used) return PVM_ERR_EXISTS;
	ret = verify_image(request->role, request->guest_image);
	if (ret) {
		marker(ret == PVM_ERR_IMAGE ? "IMAGE_REJECTED" : "POLICY_DENIED",
		       request->role, NULL);
		return ret;
	}
	instance = &instances[index];
	memset(instance, 0, sizeof(*instance));
	instance->used = 1;
	instance->info.state = PVM_STATE_CREATED;
	instance->info.instance_id = next_instance_id++;
	strcpy(instance->info.role, request->role);
	strcpy(instance->image, request->guest_image);
	*info = instance->info;
	snprintf(detail, sizeof(detail), "id=%llu state=%s",
		 (unsigned long long)instance->info.instance_id,
		 pvm_state_name(instance->info.state));
	marker("CREATED", request->role, detail);
	return PVM_OK;
}

static int start_instance(const char *role, struct pvm_info *info)
{
	struct instance *instance = find_role(role);
	char fd_arg[16], detail[96];
	int ready_pipe[2];
	struct pvm_runner_ready ready;
	pid_t pid;
	if (!instance) return PVM_ERR_NOT_FOUND;
	if (instance->info.state != PVM_STATE_CREATED) return PVM_ERR_STATE;
	if (pipe(ready_pipe)) return PVM_ERR_SYSTEM;
	pid = fork();
	if (pid < 0) {
		close(ready_pipe[0]); close(ready_pipe[1]);
		return PVM_ERR_SYSTEM;
	}
	if (!pid) {
		close(ready_pipe[0]);
		snprintf(fd_arg, sizeof(fd_arg), "%d", ready_pipe[1]);
		execl(runner_path, runner_path, role, instance->image, fd_arg, NULL);
		_exit(127);
	}
	close(ready_pipe[1]);
	instance->info.pid = pid;
	write_pidfile(role, pid);
	if (read(ready_pipe[0], &ready, sizeof(ready)) != sizeof(ready) ||
	    ready.magic != PVM_RUNNER_READY_MAGIC || ready.resource_fd_count < 3) {
		int status;
		close(ready_pipe[0]);
		kill(pid, SIGCONT);
		kill(pid, SIGTERM);
		waitpid(pid, &status, 0);
		instance->info.pid = 0;
		instance->info.state = PVM_STATE_FAILED;
		remove_pidfile(role);
		return PVM_ERR_SYSTEM;
	}
	close(ready_pipe[0]);
	instance->info.state = PVM_STATE_RUNNING;
	instance->info.resource_fd_count = ready.resource_fd_count;
	instance->info.vcpu_count = ready.vcpu_count;
	instance->info.memory_bytes = ready.memory_bytes;
	snprintf(detail, sizeof(detail), "pid=%d id=%llu state=%s resources=%u", pid,
		 (unsigned long long)instance->info.instance_id,
		 pvm_state_name(instance->info.state),
		 instance->info.resource_fd_count);
	marker("RUNNING", role, detail);
	*info = instance->info;
	return PVM_OK;
}

static int stop_instance(const char *role, struct pvm_info *info)
{
	struct instance *instance = find_role(role);
	char detail[128];
	int status;
	pid_t pid;
	if (!instance) return PVM_ERR_NOT_FOUND;
	if (instance->info.state != PVM_STATE_RUNNING) return PVM_ERR_STATE;
	pid = instance->info.pid;
	instance->info.state = PVM_STATE_STOPPING;
	kill(pid, SIGCONT);
	kill(pid, SIGTERM);
	if (waitpid(pid, &status, 0) != pid) return PVM_ERR_SYSTEM;
	instance->info.exit_status = WIFEXITED(status) ? WEXITSTATUS(status) :
					     128 + WTERMSIG(status);
	instance->info.pid = 0;
	instance->info.resource_fd_count = 0;
	instance->info.state = PVM_STATE_STOPPED;
	remove_pidfile(role);
	snprintf(detail, sizeof(detail), "id=%llu state=%s exit=%d",
		 (unsigned long long)instance->info.instance_id,
		 pvm_state_name(instance->info.state), instance->info.exit_status);
	marker("STOPPED", role, detail);
	*info = instance->info;
	return PVM_OK;
}

static int delete_instance(const char *role)
{
	struct instance *instance = find_role(role);
	char detail[96];
	if (!instance) return PVM_ERR_NOT_FOUND;
	if (instance->info.state == PVM_STATE_RUNNING ||
	    instance->info.state == PVM_STATE_STOPPING)
		return PVM_ERR_STATE;
	snprintf(detail, sizeof(detail), "id=%llu state=%s",
		 (unsigned long long)instance->info.instance_id,
		 pvm_state_name(instance->info.state));
	memset(instance, 0, sizeof(*instance));
	marker("DELETED", role, detail);
	return PVM_OK;
}

static int process_request(uid_t uid, const struct pvm_request *request,
			   struct pvm_info *info)
{
	struct instance *instance;
	if (request->magic != PVM_PROTOCOL_MAGIC ||
	    request->version != PVM_PROTOCOL_VERSION ||
	    !memchr(request->role, '\0', sizeof(request->role)) ||
	    !memchr(request->guest_image, '\0', sizeof(request->guest_image)))
		return PVM_ERR_INVALID;
	if (uid != 0) {
		char detail[64];
		snprintf(detail, sizeof(detail), "uid=%u", uid);
		marker("AUTH_DENIED", request->role, detail);
		return PVM_ERR_AUTH;
	}
	if (!request->request_id || request->request_id == last_root_request_id)
		return PVM_ERR_INVALID;
	last_root_request_id = request->request_id;
	switch (request->operation) {
	case PVM_OP_CREATE: return create_instance(request, info);
	case PVM_OP_START: return start_instance(request->role, info);
	case PVM_OP_STATUS:
		instance = find_role(request->role);
		if (!instance) return PVM_ERR_NOT_FOUND;
		*info = instance->info;
		return PVM_OK;
	case PVM_OP_STOP: return stop_instance(request->role, info);
	case PVM_OP_DELETE: return delete_instance(request->role);
	default: return PVM_ERR_INVALID;
	}
}

int main(int argc, char **argv)
{
	struct sockaddr_un address = { .sun_family = AF_UNIX };
	const char *socket_path = PVM_SOCKET_DEFAULT;
	int listener, opt, i;

	while ((opt = getopt(argc, argv, "s:m:r:")) != -1) {
		if (opt == 's') socket_path = optarg;
		else if (opt == 'm') manifest_path = optarg;
		else if (opt == 'r') runner_path = optarg;
		else return 2;
	}
	setvbuf(stdout, NULL, _IONBF, 0);
	if (mkdir(STATE_DIR, 0755) && errno != EEXIST) return 3;
	cleanup_stale_runner("camera");
	cleanup_stale_runner("ai");
	if (strlen(socket_path) >= sizeof(address.sun_path)) return 4;
	strcpy(address.sun_path, socket_path);
	unlink(socket_path);
	listener = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
	if (listener < 0 || bind(listener, (struct sockaddr *)&address, sizeof(address)) ||
	    chmod(socket_path, 0666) || listen(listener, 8))
		return 5;
	puts("PVM_FRAMEWORK_DAEMON_READY");
	for (;;) {
		struct pvm_response response = {
			.magic = PVM_PROTOCOL_MAGIC,
			.version = PVM_PROTOCOL_VERSION,
		};
		struct ucred cred;
		struct pvm_request request;
		socklen_t cred_len = sizeof(cred);
		int client;

		reap_runners();
		client = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
		if (client < 0) {
			if (errno == EINTR) continue;
			break;
		}
		memset(&request, 0, sizeof(request));
		if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &cred, &cred_len) ||
		    recv(client, &request, sizeof(request), MSG_WAITALL) != sizeof(request)) {
			close(client);
			continue;
		}
		response.request_id = request.request_id;
		response.result = process_request(cred.uid, &request, &response.info);
		send(client, &response, sizeof(response), 0);
		close(client);
	}
	for (i = 0; i < ROLE_COUNT; ++i) {
		if (instances[i].used && instances[i].info.pid > 0) {
			kill(instances[i].info.pid, SIGCONT);
			kill(instances[i].info.pid, SIGTERM);
		}
	}
	close(listener);
	unlink(socket_path);
	return 0;
}
