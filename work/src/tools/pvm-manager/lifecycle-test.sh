#!/bin/sh

set -u

MANAGER=/bin/pvm-manager.sh
STATE_DIR=/run/pvm-manager
REQUEST_DIR=/run/pvm-requests

kvm_fd_count()
{
	pid=$1
	count=0
	for fd in /proc/"${pid}"/fd/*; do
		target=$(readlink "${fd}" 2>/dev/null || true)
		case "${target}" in /dev/kvm|anon_inode:kvm-*) count=$((count + 1));; esac
	done
	echo "${count}"
}

wait_ready()
{
	pid=$1
	attempt=0
	while [ "${attempt}" -lt 300 ]; do
		fds=$(kvm_fd_count "${pid}")
		if [ "${fds}" -ge 3 ]; then
			kill -STOP "${pid}"
			return 0
		fi
		kill -0 "${pid}" 2>/dev/null || return 1
		attempt=$((attempt + 1))
	done
	return 1
}

request()
{
	name=$1 operation=$2 role=$3 image=$4 uid=$5
	file="${REQUEST_DIR}/${name}.request"
	echo "${operation} ${role} ${image}" > "${file}"
	chown "${uid}" "${file}"
	"${MANAGER}" "${file}"
}

mkdir -p "${STATE_DIR}" "${REQUEST_DIR}"

echo "LIFECYCLE_AUTH_TEST_BEGIN"
if request unauthorized CREATE camera /images/pkvm.bin 65534; then
	echo "LIFECYCLE_AUTH_TEST_FAILED"
	exit 10
fi
echo "LIFECYCLE_AUTH_DENIAL_OK"

echo "LIFECYCLE_IMAGE_TEST_BEGIN"
if request tampered CREATE camera /images/pkvm-tampered.bin 0; then
	echo "LIFECYCLE_IMAGE_TEST_FAILED"
	exit 11
fi
echo "LIFECYCLE_IMAGE_REJECTION_OK"

echo "LIFECYCLE_CREATE_STOP_BEGIN"
request camera-create CREATE camera /images/pkvm.bin 0 || exit 12
camera_pid=$(cat "${STATE_DIR}/camera.pid")
wait_ready "${camera_pid}" || exit 13
echo "LIFECYCLE_RUNNING: role=camera pid=${camera_pid} kvm_fds=${fds}"
kill -CONT "${camera_pid}"
request camera-stop STOP camera - 0 || exit 14
echo "LIFECYCLE_NORMAL_STOP_OK"

echo "LIFECYCLE_FAULT_TEST_BEGIN"
request camera-fault-create CREATE camera /images/pkvm.bin 0 || exit 15
camera_pid=$(cat "${STATE_DIR}/camera.pid")
wait_ready "${camera_pid}" || exit 16
camera_fds=${fds}
request ai-create CREATE ai /images/pkvm.bin 0 || exit 17
ai_pid=$(cat "${STATE_DIR}/ai.pid")
wait_ready "${ai_pid}" || exit 18
ai_fds=${fds}
echo "LIFECYCLE_OVERLAP: camera_pid=${camera_pid} camera_kvm_fds=${camera_fds} ai_pid=${ai_pid} ai_kvm_fds=${ai_fds}"
kill -KILL "${camera_pid}"
: > "${STATE_DIR}/camera.pid"
kill -CONT "${ai_pid}"
while kill -0 "${ai_pid}" 2>/dev/null; do sleep 0.01; done
sed 's/^/AI_SURVIVOR: /' "${STATE_DIR}/ai.log"
if ! grep -q "All ok!" "${STATE_DIR}/ai.log"; then exit 19; fi
: > "${STATE_DIR}/ai.pid"
echo "LIFECYCLE_FAULT_ISOLATION_OK: camera=failed ai=completed manager=responsive"
grep '^Mlocked:' /proc/meminfo
echo "LIFECYCLE_ALL_OK"
