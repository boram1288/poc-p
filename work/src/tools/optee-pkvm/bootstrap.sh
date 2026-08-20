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

if [ "${SOURCE_DIR}" = "${DEFAULT_SOURCE_DIR}" ] && \
	git -C "${PROJECT_ROOT}" submodule status -- work/src/optee-pkvm/u-boot \
		2>/dev/null | grep -qv '^-'; then
	# work/src/optee-pkvm/u-boot is already a populated Git submodule
	# checkout (e.g. after `git submodule update --init` at clone time).
	# Repo's "Checking out local projects" step processes every manifest
	# project it knows about, including u-boot, even when u-boot is
	# excluded from the explicit sync project list below. That checkout
	# fails against an existing unrelated submodule working tree. Empty
	# the path first; the submodule is restored from the pinned SHA after
	# sync completes.
	git -C "${PROJECT_ROOT}" submodule deinit -f -- work/src/optee-pkvm/u-boot
fi

cd "${SOURCE_DIR}"
"${REPO}" init -u https://github.com/OP-TEE/manifest.git \
	-m qemu_v8.xml -b "refs/tags/${OPTEE_TAG}" --depth=1
if [ "${SOURCE_DIR}" = "${DEFAULT_SOURCE_DIR}" ]; then
	# U-Boot is owned by the root Git submodule, not by Repo's project checkout.
	mapfile -t OPTEE_PROJECTS < <("${REPO}" list -p | sed '/^u-boot$/d')
	"${REPO}" sync -c -j"${JOBS:-4}" --no-tags --no-clone-bundle \
		"${OPTEE_PROJECTS[@]}"
	# Repo still creates its own (symlink-based) checkout at work/src/optee-pkvm/u-boot
	# even though it was excluded from the sync project list above, because that
	# path is registered in the manifest. `git submodule update --init` cannot
	# absorb a gitdir into .git/modules over a non-empty destination, so drop
	# Repo's checkout and let the submodule recreate the working tree from the
	# already-fetched .git/modules/.../u-boot object store (no network needed).
	rm -rf work/src/optee-pkvm/u-boot
	git -C "${PROJECT_ROOT}" submodule update --init --filter=blob:none -- \
		work/src/optee-pkvm/u-boot
else
	"${REPO}" sync -c -j"${JOBS:-4}" --no-tags --no-clone-bundle
fi

echo "OPTEE_SOURCE_READY: tag=${OPTEE_TAG} source=${SOURCE_DIR}"
