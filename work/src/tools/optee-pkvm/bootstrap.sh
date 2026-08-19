#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
SOURCE_DIR=${SOURCE_DIR:-${PROJECT_ROOT}/work/src/optee-pkvm}
DEFAULT_SOURCE_DIR=${PROJECT_ROOT}/work/src/optee-pkvm
REPO=${REPO:-${PROJECT_ROOT}/work/build/host-tools/repo}
OPTEE_TAG=${OPTEE_TAG:-4.7.0}

mkdir -p "${SOURCE_DIR}" "$(dirname -- "${REPO}")"
if [ ! -x "${REPO}" ]; then
	curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "${REPO}"
	chmod 755 "${REPO}"
fi

cd "${SOURCE_DIR}"
"${REPO}" init -u https://github.com/OP-TEE/manifest.git \
	-m qemu_v8.xml -b "refs/tags/${OPTEE_TAG}" --depth=1
if [ "${SOURCE_DIR}" = "${DEFAULT_SOURCE_DIR}" ]; then
	# U-Boot is owned by the root Git submodule, not by Repo's project checkout.
	mapfile -t OPTEE_PROJECTS < <("${REPO}" list -p | sed '/^u-boot$/d')
	"${REPO}" sync -c -j"${JOBS:-4}" --no-tags --no-clone-bundle \
		"${OPTEE_PROJECTS[@]}"
	git -C "${PROJECT_ROOT}" submodule update --init --filter=blob:none -- \
		work/src/optee-pkvm/u-boot
else
	"${REPO}" sync -c -j"${JOBS:-4}" --no-tags --no-clone-bundle
fi

echo "OPTEE_SOURCE_READY: tag=${OPTEE_TAG} source=${SOURCE_DIR}"
