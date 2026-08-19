#!/bin/bash
# SPDX-License-Identifier: MIT

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)
BUILD_DIR=${VISION_BUILD_DIR:-${PROJECT_ROOT}/work/build/vision-pipeline}
OMZ_DIR="${BUILD_DIR}/open_model_zoo"
VENV_DIR="${BUILD_DIR}/venv"
SOURCE_DIR="${BUILD_DIR}/source"
MODEL_DIR="${BUILD_DIR}/model"
FINAL_DIR="${BUILD_DIR}/fixtures"
OMZ_COMMIT=7cc29a91472b4cb1289a11e655ba3e188e1d4a31
VIDEO_URL=https://storage.openvinotoolkit.org/data/test_data/videos/person-bicycle-car-detection.mp4
VIDEO_SHA256=452b11b7e0efbd019f1d9570d0c790e90416ad4ad29eec6003872d08443140ef
MODEL_BASE=https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/person-vehicle-bike-detection-2000/FP32
MODEL_XML_SHA384=8c4f1a14c1e00709391c2bded1157d4497cf56be6a1d919b09747cecef183380dbae659a5c555dedbc81b9e4da579096
MODEL_BIN_SHA384=2217e4a07f0fe94a2e13bb80c359c4d6125454956e08e806eacc81176a888060f573a7f7352c5a4f4fa0288f2c53bb78

mkdir -p "${BUILD_DIR}" "${SOURCE_DIR}" "${MODEL_DIR}" "${FINAL_DIR}"

if [ ! -d "${OMZ_DIR}/.git" ]; then
	git clone --filter=blob:none https://github.com/openvinotoolkit/open_model_zoo.git "${OMZ_DIR}"
fi
git -C "${OMZ_DIR}" fetch origin "${OMZ_COMMIT}"
git -C "${OMZ_DIR}" checkout --detach "${OMZ_COMMIT}"
test "$(git -C "${OMZ_DIR}" rev-parse HEAD)" = "${OMZ_COMMIT}"

if [ ! -x "${VENV_DIR}/bin/python" ]; then
	python3 -m venv "${VENV_DIR}"
fi
"${VENV_DIR}/bin/pip" install --disable-pip-version-check \
	openvino==2024.6.0 opencv-python-headless==4.10.0.84 \
	'numpy<2.0' scipy inflect pyyaml

download_if_missing() {
	local url=$1
	local destination=$2
	if [ ! -f "${destination}" ]; then
		local temporary
		temporary=$(mktemp "${destination}.XXXXXX")
		curl -fL --retry 3 -o "${temporary}" "${url}"
		mv "${temporary}" "${destination}"
	fi
}

VIDEO="${SOURCE_DIR}/person-bicycle-car-detection.mp4"
MODEL_XML="${MODEL_DIR}/person-vehicle-bike-detection-2000.xml"
MODEL_BIN="${MODEL_DIR}/person-vehicle-bike-detection-2000.bin"
download_if_missing "${VIDEO_URL}" "${VIDEO}"
download_if_missing "${MODEL_BASE}/person-vehicle-bike-detection-2000.xml" "${MODEL_XML}"
download_if_missing "${MODEL_BASE}/person-vehicle-bike-detection-2000.bin" "${MODEL_BIN}"
test "$(sha256sum "${VIDEO}" | cut -d' ' -f1)" = "${VIDEO_SHA256}"
test "$(sha384sum "${MODEL_XML}" | cut -d' ' -f1)" = "${MODEL_XML_SHA384}"
test "$(sha384sum "${MODEL_BIN}" | cut -d' ' -f1)" = "${MODEL_BIN_SHA384}"

temporary_dir=$(mktemp -d "${BUILD_DIR}/fixture-run.XXXXXX")
trap 'rm -rf -- "${temporary_dir}"' EXIT
DEMO="${OMZ_DIR}/demos/object_detection_demo/python/object_detection_demo.py"

run_demo() {
	local log=$1
	"${VENV_DIR}/bin/python" "${DEMO}" \
		-m "${MODEL_XML}" -at ssd -i "${VIDEO}" -d CPU -t 0.5 \
		-r --no_show -nireq 1 > "${log}" 2>&1
}

run_demo "${temporary_dir}/demo-a.log"
run_demo "${temporary_dir}/demo-b.log"
"${VENV_DIR}/bin/python" "${SCRIPT_DIR}/prepare_fixture.py" \
	--video "${VIDEO}" --model-xml "${MODEL_XML}" --model-bin "${MODEL_BIN}" \
	--demo-log "${temporary_dir}/demo-a.log" --output "${temporary_dir}/fixture-a"
"${VENV_DIR}/bin/python" "${SCRIPT_DIR}/prepare_fixture.py" \
	--video "${VIDEO}" --model-xml "${MODEL_XML}" --model-bin "${MODEL_BIN}" \
	--demo-log "${temporary_dir}/demo-b.log" --output "${temporary_dir}/fixture-b"
"${VENV_DIR}/bin/python" "${SCRIPT_DIR}/verify_fixture.py" \
	"${temporary_dir}/fixture-a" --compare "${temporary_dir}/fixture-b"

cp "${temporary_dir}/fixture-a/frames.bin" "${FINAL_DIR}/frames.bin"
cp "${temporary_dir}/fixture-a/oracle.bin" "${FINAL_DIR}/oracle.bin"
cp "${temporary_dir}/fixture-a/manifest.json" "${FINAL_DIR}/manifest.json"
cp "${temporary_dir}/demo-a.log" "${FINAL_DIR}/openvino-demo.log"
"${VENV_DIR}/bin/pip" freeze > "${FINAL_DIR}/requirements.freeze"
"${VENV_DIR}/bin/python" "${SCRIPT_DIR}/verify_fixture.py" "${FINAL_DIR}"
echo "PVM_VISION_FIXTURE_PREPARE_OK: ${FINAL_DIR}"
