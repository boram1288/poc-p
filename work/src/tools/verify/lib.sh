#!/bin/bash
# 통합 검증 스크립트 공통 함수.
# 이 파일은 phaseNN.sh 스크립트에서 source해서 쓴다.

set -u

VERIFY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
VERIFY_LOG_DIR="${VERIFY_ROOT}/work/build/verify"
FORCE=${FORCE:-0}

cd "${VERIFY_ROOT}" || exit 1

verify_log() {
  echo "[verify] $*"
}

verify_fail() {
  echo "[verify][FAIL] $*" >&2
  exit 1
}

# require_file <path> [설명]
require_file() {
  local path=$1
  local desc=${2:-}
  if [ ! -e "${path}" ]; then
    verify_fail "필수 산출물이 없습니다: ${path} ${desc}"
  fi
}

# require_exec <path>
require_exec() {
  local path=$1
  if [ ! -x "${path}" ]; then
    verify_fail "실행 파일이 없거나 실행 권한이 없습니다: ${path}"
  fi
}

# check_markers <logfile> <marker1> [marker2 ...]
# 로그 파일에서 각 marker 문자열을 grep -F로 확인한다. 하나라도 없으면 실패.
check_markers() {
  local log=$1
  shift
  require_file "${log}" "(marker 확인 대상 로그)"
  local missing=0
  local m
  for m in "$@"; do
    if ! grep -qF -- "${m}" "${log}"; then
      echo "[verify][MISSING MARKER] ${m}" >&2
      missing=1
    fi
  done
  if [ "${missing}" -ne 0 ]; then
    verify_fail "로그에서 필수 marker를 찾지 못했습니다: ${log}"
  fi
}

# check_mlocked_zero <logfile> - /proc/self/status의 "Mlocked:" 값이 0인지 확인한다.
# /proc/meminfo류 출력은 라벨과 값 사이 공백 수가 커널/파일마다 달라 grep -F로는
# 맞추기 어려우므로 정규식으로 확인한다.
check_mlocked_zero() {
  local log=$1
  require_file "${log}"
  if ! grep -qE 'Mlocked:[[:space:]]+0 kB' "${log}"; then
    verify_fail "Mlocked이 0이 아니거나 로그에 없습니다: ${log}"
  fi
}

# check_no_kernel_fault <logfile...>
# panic/Oops/BUG 문자열이 없어야 정상이다.
check_no_kernel_fault() {
  local hit
  hit=$(grep -E 'Kernel panic|Oops|BUG:' "$@" 2>/dev/null || true)
  if [ -n "${hit}" ]; then
    echo "${hit}" >&2
    verify_fail "커널 오류 문자열(panic/Oops/BUG)이 로그에서 발견됐습니다."
  fi
}

# phase_done_file <phase-id>
phase_done_file() {
  echo "${VERIFY_LOG_DIR}/phase-$1/DONE"
}

# skip_if_done <phase-id> - 이미 완료 marker가 있으면 스크립트를 0으로 종료한다.
# FORCE=1이면 건너뛰지 않고 다시 실행한다.
skip_if_done() {
  local phase=$1
  local done_file
  done_file=$(phase_done_file "${phase}")
  if [ "${FORCE}" != "1" ] && [ -f "${done_file}" ]; then
    verify_log "Phase ${phase}는 이미 완료 marker가 있습니다 (재사용): ${done_file}"
    verify_log "다시 실행하려면 FORCE=1을 지정하세요."
    exit 0
  fi
}

# mark_done <phase-id> <설명>
mark_done() {
  local phase=$1
  local desc=${2:-}
  local done_file
  done_file=$(phase_done_file "${phase}")
  mkdir -p "$(dirname "${done_file}")"
  {
    echo "phase=${phase}"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "desc=${desc}"
  } > "${done_file}"
  verify_log "Phase ${phase} 완료 marker 기록: ${done_file}"
}

require_prev_phase() {
  local phase=$1
  local done_file
  done_file=$(phase_done_file "${phase}")
  if [ ! -f "${done_file}" ]; then
    verify_fail "선행 Phase ${phase}가 완료되지 않았습니다. work/src/tools/verify/phase${phase}.sh를 먼저 실행하세요."
  fi
}
