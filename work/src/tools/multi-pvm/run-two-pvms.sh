#!/bin/sh

set -u

PKVM=${PKVM:-/bin/pkvm}
WORK_DIR=${WORK_DIR:-/tmp/multi-pvm}

mkdir -p "${WORK_DIR}"

kvm_fd_count()
{
	pid=$1
	count=0
	for fd in /proc/"${pid}"/fd/*; do
		target=$(readlink "${fd}" 2>/dev/null || true)
		case "${target}" in
			/dev/kvm|anon_inode:kvm-*) count=$((count + 1)) ;;
		esac
	done
	echo "${count}"
}

prefix_log()
{
	role=$1
	log=$2
	sed "s/^/${role}: /" "${log}"
}

stop_when_kvm_ready()
{
	pid=$1
	attempt=0
	while [ "${attempt}" -lt 200 ]; do
		ready_fds=$(kvm_fd_count "${pid}")
		if [ "${ready_fds}" -ge 3 ]; then
			kill -STOP "${pid}"
			return 0
		fi
		kill -0 "${pid}" 2>/dev/null || return 1
		attempt=$((attempt + 1))
	done
	return 1
}

run_normal_pair()
{
	echo "MULTI_NORMAL_BEGIN"
	"${PKVM}" > "${WORK_DIR}/camera-normal.log" 2>&1 &
	camera_pid=$!
	if ! stop_when_kvm_ready "${camera_pid}"; then
		echo "MULTI_CAMERA_READY_FAILED"
		wait "${camera_pid}"
		return 1
	fi
	camera_fds=${ready_fds}

	"${PKVM}" > "${WORK_DIR}/ai-normal.log" 2>&1 &
	ai_pid=$!
	if stop_when_kvm_ready "${ai_pid}"; then
		ai_fds=${ready_fds}
		echo "MULTI_KVM_OVERLAP: camera_pid=${camera_pid} camera_kvm_fds=${camera_fds} ai_pid=${ai_pid} ai_kvm_fds=${ai_fds}"
		kill -CONT "${camera_pid}"
		kill -CONT "${ai_pid}"
	else
		ai_fds=0
		kill -CONT "${camera_pid}" 2>/dev/null || true
		echo "MULTI_KVM_OVERLAP_FAILED: camera_kvm_fds=${camera_fds} ai_kvm_fds=${ai_fds}"
		wait "${camera_pid}"
		camera_rc=$?
		wait "${ai_pid}"
		ai_rc=$?
		prefix_log CAMERA_SETUP "${WORK_DIR}/camera-normal.log"
		prefix_log AI_SETUP "${WORK_DIR}/ai-normal.log"
		echo "MULTI_NORMAL_SETUP_RESULT: camera_rc=${camera_rc} ai_rc=${ai_rc}"
		return 1
	fi

	wait "${camera_pid}"
	camera_rc=$?
	wait "${ai_pid}"
	ai_rc=$?
	prefix_log CAMERA "${WORK_DIR}/camera-normal.log"
	prefix_log AI "${WORK_DIR}/ai-normal.log"
	echo "MULTI_NORMAL_RESULT: camera_rc=${camera_rc} ai_rc=${ai_rc}"
	[ "${camera_rc}" -eq 0 ] && [ "${ai_rc}" -eq 0 ]
}

run_fault_pair()
{
	echo "MULTI_FAULT_BEGIN"
	"${PKVM}" > "${WORK_DIR}/camera-fault.log" 2>&1 &
	camera_pid=$!
	"${PKVM}" > "${WORK_DIR}/ai-survivor.log" 2>&1 &
	ai_pid=$!
	camera_fds=0
	ai_fds=0

	echo "MULTI_FAULT_INJECT: camera_pid=${camera_pid} ai_pid=${ai_pid}"
	kill -9 "${camera_pid}"
	wait "${camera_pid}"
	camera_rc=$?
	wait "${ai_pid}"
	ai_rc=$?
	prefix_log CAMERA_FAULT "${WORK_DIR}/camera-fault.log"
	prefix_log AI_SURVIVOR "${WORK_DIR}/ai-survivor.log"
	echo "MULTI_FAULT_RESULT: camera_rc=${camera_rc} ai_rc=${ai_rc}"
	[ "${camera_rc}" -ne 0 ] && [ "${ai_rc}" -eq 0 ]
}

run_normal_pair || exit 10
run_fault_pair || exit 11
echo "MULTI_PVM_ALL_OK"
