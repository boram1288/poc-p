#!/bin/bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
SOURCE_DIR=${SOURCE_DIR:-${PROJECT_ROOT}/work/src/optee-pkvm}
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
"${REPO}" sync -c -j"${JOBS:-4}" --no-tags --no-clone-bundle

# source.denx.de is occasionally unavailable while the GitHub mirror carries
# the same signed tag pinned by qemu_v8.xml.
if [ ! -d "${SOURCE_DIR}/u-boot" ]; then
	git clone --depth 1 --branch v2025.07-rc1 \
		https://github.com/u-boot/u-boot.git "${SOURCE_DIR}/u-boot"
fi

echo "OPTEE_SOURCE_READY: tag=${OPTEE_TAG} source=${SOURCE_DIR}"
