#!/bin/sh

set -u

REQUEST=${1:?request file is required}
STATE_DIR=${STATE_DIR:-/run/pvm-manager}
IMAGE_DIR=${IMAGE_DIR:-/images}
MANIFEST=${MANIFEST:-${IMAGE_DIR}/SHA256SUMS}

marker()
{
	printf 'PVM_MANAGER_%s\n' "$1"
}

request_uid=$(stat -c %u "${REQUEST}" 2>/dev/null || echo unknown)
if [ "${request_uid}" != 0 ]; then
	marker "AUTH_DENIED: uid=${request_uid} request=${REQUEST}"
	exit 20
fi

IFS=' ' read -r operation role image extra < "${REQUEST}"
if [ -n "${extra:-}" ]; then
	marker "REQUEST_INVALID: request=${REQUEST}"
	exit 21
fi

case "${role}" in
	camera|ai) ;;
	*) marker "POLICY_DENIED: role=${role}"; exit 22 ;;
esac

mkdir -p "${STATE_DIR}"
pid_file="${STATE_DIR}/${role}.pid"

case "${operation}" in
	CREATE)
		case "${image}" in
			"${IMAGE_DIR}"/*.bin) ;;
			*) marker "IMAGE_PATH_DENIED: role=${role} image=${image}"; exit 23 ;;
		esac
		expected=$(sed -n "s/  ${image##*/}$//p" "${MANIFEST}")
		actual=$(sha256sum "${image}" 2>/dev/null | sed 's/ .*//')
		if [ ! -x "${image}" ] || [ -z "${expected}" ] || [ "${actual}" != "${expected}" ]; then
			marker "IMAGE_REJECTED: role=${role} image=${image}"
			exit 24
		fi
		if [ -s "${pid_file}" ] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
			marker "ALREADY_RUNNING: role=${role}"
			exit 25
		fi
		"${image}" > "${STATE_DIR}/${role}.log" 2>&1 &
		pid=$!
		echo "${pid}" > "${pid_file}"
		marker "IMAGE_VERIFIED: role=${role} sha256=$(sha256sum "${image}" | sed 's/ .*//')"
		marker "CREATED: role=${role} pid=${pid}"
		;;
	STOP)
		if [ ! -s "${pid_file}" ]; then
			marker "NOT_RUNNING: role=${role}"
			exit 26
		fi
		pid=$(cat "${pid_file}")
		kill -TERM "${pid}" 2>/dev/null || true
		attempt=0
		while kill -0 "${pid}" 2>/dev/null && [ "${attempt}" -lt 200 ]; do
			sleep 0.01
			attempt=$((attempt + 1))
		done
		if kill -0 "${pid}" 2>/dev/null; then
			kill -KILL "${pid}" 2>/dev/null || true
		fi
		: > "${pid_file}"
		marker "STOPPED: role=${role} pid=${pid}"
		;;
	*) marker "OPERATION_DENIED: operation=${operation}"; exit 27 ;;
esac
