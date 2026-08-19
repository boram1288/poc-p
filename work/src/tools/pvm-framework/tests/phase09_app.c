/* SPDX-License-Identifier: MIT */
#include "pvm/pvm.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define PHASE09_IMAGE "/images/phase09-guest.img"
#define PHASE09_OWNER_FAULT_IMAGE "/images/phase09-owner-fault.img"
#define PHASE09_RECEIVER_TEARDOWN_IMAGE "/images/phase09-receiver-teardown.img"
#define PHASE09_TIMEOUT_IMAGE "/images/phase09-timeout.img"

static void fail(const char *step, int ret)
{
	printf("PVM_BUFFER_TEST_FAILED: step=%s ret=%d error=%s\n",
	       step, ret, pvm_error_name(ret));
	exit(1);
}

static void expect(const char *step, int actual, int expected)
{
	if (actual != expected)
		fail(step, actual);
}

static void wait_stopped(const char *role)
{
	struct pvm_info info;
	int i, ret;

	for (i = 0; i < 1000; ++i) {
		ret = pvm_status(NULL, role, &info);
		if (!ret && info.state == PVM_STATE_STOPPED)
			return;
		if (!ret && info.state == PVM_STATE_FAILED)
			fail(role, PVM_ERR_STATE);
		usleep(10000);
	}
	fail(role, PVM_ERR_SYSTEM);
}

int main(void)
{
	struct pvm_info ai, camera;

	setvbuf(stdout, NULL, _IONBF, 0);

	/* AI must exist first: its protected VM receives pKVM endpoint ID 1. */
	expect("ai-create", pvm_create(NULL, "ai", PHASE09_IMAGE, &ai), PVM_OK);
	expect("ai-start", pvm_start(NULL, "ai", &ai), PVM_OK);
	expect("camera-create", pvm_create(NULL, "camera", PHASE09_IMAGE, &camera),
	       PVM_OK);
	expect("camera-start", pvm_start(NULL, "camera", &camera), PVM_OK);

	wait_stopped("ai");
	wait_stopped("camera");
	puts("PVM_BUFFER_GUEST_TO_GUEST_OK");

	expect("camera-delete", pvm_delete(NULL, "camera"), PVM_OK);
	expect("ai-delete", pvm_delete(NULL, "ai"), PVM_OK);
	puts("PVM_BUFFER_RESOURCE_RECOVERY_OK");

	/* Keep the receiver mapping active and force an owner-side load fault. */
	expect("owner-fault-ai-create",
	       pvm_create(NULL, "ai", PHASE09_OWNER_FAULT_IMAGE, &ai), PVM_OK);
	expect("owner-fault-ai-start", pvm_start(NULL, "ai", &ai), PVM_OK);
	expect("owner-fault-camera-create",
	       pvm_create(NULL, "camera", PHASE09_OWNER_FAULT_IMAGE, &camera), PVM_OK);
	expect("owner-fault-camera-start", pvm_start(NULL, "camera", &camera),
	       PVM_OK);
	wait_stopped("camera");
	expect("owner-fault-ai-stop", pvm_stop(NULL, "ai", &ai), PVM_OK);
	expect("owner-fault-camera-delete", pvm_delete(NULL, "camera"), PVM_OK);
	expect("owner-fault-ai-delete", pvm_delete(NULL, "ai"), PVM_OK);
	puts("PVM_BUFFER_OWNER_FAULT_RECOVERY_OK");

	/* Terminate AI while its imported mapping is active. */
	expect("receiver-teardown-ai-create",
	       pvm_create(NULL, "ai", PHASE09_RECEIVER_TEARDOWN_IMAGE, &ai), PVM_OK);
	expect("receiver-teardown-ai-start", pvm_start(NULL, "ai", &ai), PVM_OK);
	expect("receiver-teardown-camera-create",
	       pvm_create(NULL, "camera", PHASE09_RECEIVER_TEARDOWN_IMAGE, &camera),
	       PVM_OK);
	expect("receiver-teardown-camera-start", pvm_start(NULL, "camera", &camera),
	       PVM_OK);
	usleep(200000);
	expect("receiver-teardown-ai-stop", pvm_stop(NULL, "ai", &ai), PVM_OK);
	wait_stopped("camera");
	expect("receiver-teardown-camera-delete", pvm_delete(NULL, "camera"), PVM_OK);
	expect("receiver-teardown-ai-delete", pvm_delete(NULL, "ai"), PVM_OK);
	puts("PVM_BUFFER_RECEIVER_TEARDOWN_RECOVERY_OK");

	/* Ignore the event in AI and exercise the bounded owner revoke path. */
	expect("timeout-ai-create",
	       pvm_create(NULL, "ai", PHASE09_TIMEOUT_IMAGE, &ai), PVM_OK);
	expect("timeout-ai-start", pvm_start(NULL, "ai", &ai), PVM_OK);
	expect("timeout-camera-create",
	       pvm_create(NULL, "camera", PHASE09_TIMEOUT_IMAGE, &camera), PVM_OK);
	expect("timeout-camera-start", pvm_start(NULL, "camera", &camera), PVM_OK);
	wait_stopped("camera");
	expect("timeout-ai-stop", pvm_stop(NULL, "ai", &ai), PVM_OK);
	expect("timeout-camera-delete", pvm_delete(NULL, "camera"), PVM_OK);
	expect("timeout-ai-delete", pvm_delete(NULL, "ai"), PVM_OK);
	puts("PVM_BUFFER_TIMEOUT_RECOVERY_OK");
	return 0;
}
