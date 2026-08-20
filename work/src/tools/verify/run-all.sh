#!/bin/bash
# Phase 02~10 통합 검증 오케스트레이터.
# 각 phaseNN.sh는 이미 완료 marker(work/build/verify/phase-*/DONE)가 있으면 건너뛰어
# 앞 단계 산출물을 재사용한다. 다시 실행하려면 FORCE=1을 지정한다.
#
# 사용법:
#   work/src/tools/verify/run-all.sh                 # 02~10 전체
#   work/src/tools/verify/run-all.sh --from 06        # 06부터 10까지
#   work/src/tools/verify/run-all.sh --only 08         # 08만
#   FORCE=1 work/src/tools/verify/run-all.sh --only 02 # 02를 강제로 다시 실행
set -eu
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

ALL_PHASES=(02 03 04 05 06 06b 07 08 09 09b 10)

FROM=""
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM=$2; shift 2 ;;
    --only) ONLY=$2; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--from PHASE] [--only PHASE]"
      exit 0
      ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

RUN_PHASES=()
if [ -n "${ONLY}" ]; then
  RUN_PHASES=("${ONLY}")
else
  started=0
  for p in "${ALL_PHASES[@]}"; do
    if [ -z "${FROM}" ] || [ "${started}" -eq 1 ] || [ "${p}" = "${FROM}" ]; then
      started=1
      RUN_PHASES+=("${p}")
    fi
  done
fi

echo "[run-all] 실행 순서: ${RUN_PHASES[*]}"

for p in "${RUN_PHASES[@]}"; do
  script="${SCRIPT_DIR}/phase${p}.sh"
  if [ ! -x "${script}" ]; then
    echo "[run-all][FAIL] 스크립트가 없습니다: ${script}" >&2
    exit 1
  fi
  echo
  echo "==================== Phase ${p} 시작 ===================="
  "${script}"
  echo "==================== Phase ${p} 완료 ===================="
done

echo
echo "[run-all] 지정한 모든 Phase 실행 완료: ${RUN_PHASES[*]}"
