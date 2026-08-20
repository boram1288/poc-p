# Phase 02~10 통합 검증 환경 구축 계획

- 작성일: 2026-08-20
- 목적: Phase 02~10의 모든 완료 조건을 이 저장소(`poc-reproduce`) 안에서 직접 재현하고
  판정할 수 있는 통합 검증 환경과, 개발자가 처음부터 따라할 수 있는 하우투 가이드를 만든다.
- 상위 문서: [PLAN.md](PLAN.md), [README.md](../README.md)

## 1. 원칙

1. 이 저장소에서 실제로 빌드/실행해서 나온 산출물만 검증 근거로 쓴다. `../poc-p`의 산출물을
   복사하거나 경로를 직접 참조하지 않는다.
2. 각 Phase의 완료 조건과 판정 기준은 새로 만들지 않는다. 기존 `docs/phase-{nn}/README.md`,
   `PLAN.md`가 정의한 기준을 그대로 사용한다.
3. Phase 산출물은 뒤 Phase가 재사용한다. 같은 산출물을 Phase마다 다시 만들지 않는다.
   (예: Phase 02 kernel Image를 Phase 03~10이 재사용, Phase 08 QEMU를 Phase 09/10이 재사용)
4. 빌드나 검증 중 막히는 문제가 생기면 `../poc-p`의 동일 Phase 문서/스크립트를 **읽기 전용
   참고 자료**로만 확인한다. 원인 파악 후 수정은 반드시 이 저장소의 소스/도구/문서에
   직접 작성한다. `../poc-p`의 파일을 복사, symlink, diff 적용 방식으로 가져오지 않는다.
5. 모든 신규 스크립트와 문서는 저장소 루트를 기준 디렉터리로 가정한다.

## 2. 현황 진단

| Phase | 기존 문서 | 명령 단위 하우투 유무 | 비고 |
|---|---|---|---|
| 02 | README.md | 절차는 있으나 실패 대응/기대 출력 미흡 | kernel 소스 통합·빌드 |
| 03 | README.md | 절차는 있으나 하우투 형식 아님 | protected 부팅 |
| 04 | README.md | 절차는 있으나 하우투 형식 아님 | 단일 pVM |
| 05 | README.md | 절차는 있으나 하우투 형식 아님 | 다중 pVM |
| 06 | README.md | 절차는 있으나 하우투 형식 아님 | OP-TEE 공존 |
| 06-b | VERIFICATION.md | 있음 | 참고 형식으로 사용 |
| 07 | README.md | 절차는 있으나 하우투 형식 아님 | 동적 수명주기 |
| 08 | README.md, validation-results.md | 부분적 | 장치 할당/DMA 격리 |
| 09 | VERIFICATION.md | 있음 | 참고 형식으로 사용 |
| 09-b | VERIFICATION.md | 있음 | 참고 형식으로 사용 |
| 10 | VERIFICATION.md | 있음(가장 상세) | 재현 기준 문서 |

현재 `work/build`는 비어 있다. 이 저장소에서 Phase 02부터 순서대로 직접 빌드해야 한다.
submodule 5개는 이미 README가 고정한 revision으로 초기화되어 있다(확인 완료).
Host는 12 vCPU, RAM 15GiB, 여유 디스크 49GiB로 README 권장 사양을 충족한다.

## 3. 목표 산출물

### 3.1 Phase별 VERIFICATION.md 신규 작성 (02~08 중 미비한 Phase)

06-b/09/09-b/10과 같은 형식(검증 범위, Host 준비, 절차, 완료 조건 결과, 자주 발생하는
실패와 조치, 재현 기록 양식)으로 아래 문서를 새로 만든다. 내용은 이 저장소에서 실제로
실행해 확인한 명령과 결과만 적는다.

- `docs/phase-02/VERIFICATION.md`
- `docs/phase-03/VERIFICATION.md`
- `docs/phase-04/VERIFICATION.md`
- `docs/phase-05/VERIFICATION.md`
- `docs/phase-06/VERIFICATION.md`
- `docs/phase-07/VERIFICATION.md`
- `docs/phase-08/VERIFICATION.md` (기존 `validation-results.md`를 대체하지 않고 보완)

### 3.2 검증 스크립트 체계 (`work/src/tools/verify/`)

Phase마다 이미 있는 도구(`work/src/tools/qemu`, `pvm`, `multi-pvm`, `optee-pkvm`,
`pvm-framework`, `pvm-buffer`, `vision-pipeline` 등)를 그대로 호출하는 얇은 driver
스크립트를 만든다. 새 빌드 로직을 만들지 않고 기존 도구를 순서대로 조합한다.

```text
work/src/tools/verify/
├── lib.sh          공통 함수: 로그 경로, 완료 marker 검사, 실패 시 종료
├── phase02.sh       kernel 소스 통합/빌드 (clang) 실행 및 산출물 확인
├── phase03.sh       protected 부팅 실행 및 4개 marker 확인
├── phase04.sh       단일 pVM selftest 실행 및 marker 확인
├── phase05.sh       다중 pVM 동시 실행 및 marker 확인
├── phase06.sh       OP-TEE bootstrap/build/run 및 marker 확인
├── phase07.sh       C VM 프레임워크 5개 경로 실행 및 marker 확인
├── phase08.sh       E-3 QEMU/kvmtool 빌드, 장치 할당/DMA 격리 실행
├── phase09.sh       EL2 DMA-BUF 검증 재실행
├── phase09b.sh      사용자 공간 end-to-end 회귀 재실행
├── phase10.sh       fixture 생성, vision pipeline 정상/장애/회귀 실행
└── run-all.sh        02→10 순차 실행, 이미 완료된 Phase는 건너뜀(재사용), 실패 시 중단
```

`run-all.sh`는 각 phaseNN.sh 실행 전에 선행 Phase의 완료 marker 파일 존재를 확인하고,
없으면 실행을 중단하고 어떤 Phase를 먼저 실행해야 하는지 안내한다. 이미 완료 marker가
있는 Phase는 `--force` 옵션 없이는 다시 빌드하지 않는다(산출물 재사용).

로그와 완료 marker는 `work/build/verify/phase-{nn}/`에 모은다. 각 Phase 원래 산출물
경로(`work/build/pkvm-full-clang`, `work/build/pkvm-qemu` 등)는 PLAN.md/각 Phase 문서가
정의한 기존 경로 규칙을 그대로 따른다.

### 3.3 통합 하우토 가이드

`docs/VERIFICATION-GUIDE.md`(신규, 저장소 최상위 docs)를 만든다. 이 문서는 Phase별
문서를 대체하지 않고, 처음 받은 개발자가 위에서 아래로 따라가면 Phase 02부터 10까지
막힘없이 완료 조건을 재현하도록 순서/사전조건/명령/문제 해결 링크를 하나로 묶는다.
각 절은 해당 Phase VERIFICATION.md와 `run-all.sh`/`phaseNN.sh` 실행 방법을 함께 안내한다.

README.md의 "다른 개발자 PC에서 재현하기" 절은 이 신규 가이드를 가리키도록 갱신한다.

## 4. Phase 산출물 재사용 매핑

| 생성 Phase | 산출물 | 재사용하는 Phase |
|---|---|---|
| 02 | `work/build/pkvm-full-clang` kernel Image/vmlinux | 03, 04, 05, 06, 07 |
| 03 | 최소 initramfs, protected 부팅 확인 절차 | 04, 05 (초기화 로그 판정 재사용) |
| 04 | pKVM selftest 정적 바이너리 | 05 (다중 pVM 실행에 재사용) |
| 06 | OP-TEE/TF-A/U-Boot 빌드, E-2 rootfs | 06-b, 09(E-2 회귀 시) |
| 07 | C VM 관리 프레임워크 바이너리/guest image | 08의 lifecycle 경로 |
| 08 | E-3 QEMU(`qemu-phase08` 빌드), arm64 kvmtool, PV IOMMU 커널 옵션 | 09, 09-b, 10 |
| 09 | `libpvm_buffer` EL2 DMA-BUF 경로 | 09-b, 10 |
| 09-b | `pvm_user_channel`/`pvm_message` 프로토콜, guest/host initramfs | 10 |
| 10 | fixture(`frames.bin`, `oracle.bin`), vision pipeline 바이너리 | 없음(최종 단계) |

## 5. 실행 순서

1. 이 계획 문서를 저장하고 사용자 확인을 받는다. (완료)
2. `work/src/tools/verify/lib.sh`와 `phase02.sh`~`phase10.sh`, `run-all.sh`를 작성한다.
   기존 도구 스크립트를 호출하는 wrapper로 작성하고 새 빌드 로직은 만들지 않는다.
3. Phase 02부터 순서대로 `phaseNN.sh`를 실제로 실행한다. 실패 시:
   a. 이 저장소의 로그와 소스로 먼저 원인을 분석한다.
   b. 필요하면 `../poc-p`의 동일 Phase 문서/도구를 읽고 원인/해결 방향만 참고한다.
   c. 이 저장소의 소스/도구/문서에 직접 수정 사항을 작성한다.
   d. 수정 후 재실행해 완료 marker를 다시 확인한다.
4. 각 Phase 완료가 확인되면 해당 `docs/phase-{nn}/VERIFICATION.md`를 실제 실행 결과로
   작성한다(3.1절).
5. 09, 09-b, 10은 기존 VERIFICATION.md 절차를 이 저장소 산출물로 재실행하고 결과만
   갱신 확인한다(문서 재작성은 필요한 부분만).
6. `docs/VERIFICATION-GUIDE.md`를 작성하고 README.md의 재현 절을 이 문서로 연결한다.
7. `run-all.sh` 전체를 처음부터(또는 이미 확인된 marker 재사용) 1회 더 실행해 통합
   환경 자체가 재현 가능한지 확인한다.
8. 최종 결과를 사용자에게 보고한다.

## 6. 리스크와 대응

| 리스크 | 대응 |
|---|---|
| 커널/OP-TEE 빌드가 수십 분 이상 소요 | 백그라운드 실행 + 로그 tail로 진행 보고, Phase 단위로 checkpoint |
| 디스크 49GiB 여유가 전체 빌드(약 28GiB) 중 부족해질 가능성 | Phase 진행 중 `df -h` 주기적 확인, 불필요 산출물 정리 |
| `../poc-p` 산출물을 실수로 참조/복사 | 모든 스크립트의 경로는 저장소 루트 기준 상대경로만 사용, `../poc-p` 문자열이 스크립트/빌드 설정에 들어가지 않았는지 확인 |
| 기존 Phase 문서와 새 VERIFICATION.md 간 완료 조건 불일치 | 새 문서는 README.md 완료 조건표를 인용하고 별도 기준을 만들지 않음 |
| OP-TEE bootstrap의 외부 네트워크 의존성(Repo manifest 등) | 실패 시 명확히 기록하고 재시도, 네트워크 문제는 별도로 보고 |

## 7. 이 작업 자체의 완료 조건

- Phase 02~10 각각에 대해 `work/src/tools/verify/phaseNN.sh` 실행이 성공하고, 각 Phase
  README가 정의한 완료 marker가 이 저장소의 로그에서 확인되어야 한다.
- Phase 02~08에 새 `VERIFICATION.md`가 작성되고, 09/09-b/10은 이 저장소 산출물로 재검증한
  결과가 반영되어야 한다.
- `docs/VERIFICATION-GUIDE.md`가 Phase 02부터 10까지 하나의 순서로 안내해야 한다.
- `run-all.sh` 전체 실행이 처음부터 성공하거나, 실패 지점과 원인/대응이 문서화되어야 한다.
- 모든 산출물이 이 저장소 안에서 생성되었고 `../poc-p`의 파일을 복사한 흔적이 없어야 한다.

## 8. 진행 기록

| 일자 | 내용 |
|---|---|
| 2026-08-20 | 계획 수립 및 저장 |
