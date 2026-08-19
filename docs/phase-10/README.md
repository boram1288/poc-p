# Phase 10: 공개 객체 탐지 데이터 기반 Reference Scenario 통합

- 상태: 완료
- 목적: 실물 카메라와 GPU 없이 공개 동영상의 frame과 객체 탐지 결과를 fixture로 고정하고,
  Camera pVM → AI pVM → Host Application 전체 Reference Scenario를 재현한다.
- 환경: fixture 준비 Host와 E-3 QEMU
- 관련 목표: G-11
- 관련 결정: D-9, D-10, D-11
- 실측 결과: [VERIFICATION.md](VERIFICATION.md)

## 1. 대체 범위

Phase 10은 USB 카메라 capture와 NVIDIA GPU inference를 다음 두 simulator로 대체한다.

| 실물 구성 | Phase 10 대체 구현 |
|---|---|
| USB 카메라 | 웹에서 받은 고정 MP4를 준비 단계에서 decode하고 Camera pVM이 canonical raw frame을 순서대로 재생 |
| NVIDIA GPU | 공식 객체 탐지 demo가 미리 생성한 detection oracle을 AI pVM이 frame SHA-256으로 조회 |

따라서 E-3 실행 중에는 웹 접속, 실물 camera API, GPU driver, MP4 decoder와 실제 inference
runtime이 필요하지 않다. 대신 Phase 09-b의 실제 통신·격리 경로를 그대로 사용해 frame과
결과가 end-to-end로 상관되는지를 검증한다.

공개 동영상과 oracle은 기능 fixture이므로 그 내용의 비밀성을 주장하지 않는다. Host 비노출
판정은 runtime Camera↔AI DMA-BUF에 raw frame을 relay/copy하지 않고 Host-facing protocol에
frame, hash, descriptor와 transfer token을 싣지 않는다는 경로 특성에 한정한다. 실제 모델
가중치·중간 tensor의 pVM 내 보호와 추론 정확도는 이 Phase의 판정 대상이 아니다.

## 선행 조건

- Phase 08의 Camera/AI 역할 에뮬레이션 장치 할당·회수와 DMA 격리 검증 완료
- Phase 09의 Camera↔AI EL2 DMA-BUF export/import와 Host runtime 접근 차단 완료
- Phase 09-b의 AF_VSOCK command/result, 별도 metadata channel과 장애 복구 검증 완료
- fixture 준비 Host에서 HTTPS download와 OpenVINO CPU demo를 실행할 수 있음
- E-3 runtime 검증은 공개 Host/guest interface만 사용하며 Trusted Access를 요구하지 않음

## 2. 기준 demo와 데이터

공식 Open Model Zoo의 다음 조합을 baseline으로 고정한다.

| 항목 | 고정 값 |
|---|---|
| 저장소 revision | `openvinotoolkit/open_model_zoo` commit `7cc29a91472b4cb1289a11e655ba3e188e1d4a31` |
| demo | `demos/object_detection_demo/python/object_detection_demo.py` |
| 입력 동영상 | `https://storage.openvinotoolkit.org/data/test_data/videos/person-bicycle-car-detection.mp4` |
| 동영상 크기 / SHA-256 | 6,031,199 bytes / `452b11b7e0efbd019f1d9570d0c790e90416ad4ad29eec6003872d08443140ef` |
| detector | `person-vehicle-bike-detection-2000`, FP32 |
| FP32 model XML | 185,222 bytes, SHA-384 `8c4f1a14c1e00709391c2bded1157d4497cf56be6a1d919b09747cecef183380dbae659a5c555dedbc81b9e4da579096` |
| FP32 model BIN | 7,285,140 bytes, SHA-384 `2217e4a07f0fe94a2e13bb80c359c4d6125454956e08e806eacc81176a888060f573a7f7352c5a4f4fa0288f2c53bb78` |
| model input | BGR, NCHW `1×3×256×256` |
| model output | 최대 200개의 `[image_id, class_id, confidence, xmin, ymin, xmax, ymax]` |
| class ID | `0=vehicle`, `1=person`, `2=bike` |
| demo 실행 | OpenVINO CPU, SSD adapter, confidence threshold `0.50`, raw output, no GUI |
| demo/model license | Open Model Zoo Apache-2.0. 동영상은 외부 URL에서만 받고 저장소에 재배포하지 않음 |

선정 근거는 다음과 같다.

- 공식 demo가 file video input, CPU device, raw detection 출력과 결과 영상 저장을 지원한다.
- detector가 사람 하나만이 아니라 vehicle/person/bike와 confidence/bounding box를 제공한다.
- 입력·출력 shape와 class mapping이 공개되어 simulator schema를 고정할 수 있다.
- demo와 model source를 commit 및 checksum으로 고정할 수 있다.

구현 전에 동영상 사용 조건을 다시 기록한다. 재배포 허가를 확인하지 못하면 현재 계획처럼
URL·digest만 추적하고 `work/build`로 내려받아 로컬 검증에만 사용한다.

## 3. Fixture 형식

fixture 준비 도구는 동영상 전체를 한 번 decode하고, 전체 frame 수를 기준으로 균등 간격의
30개 frame을 선택한다. 현재 Phase 09 DMA-BUF가 단일 4 KiB backing이므로 runtime replay용
frame은 같은 원본에서 32×32 BGR24로 축소해 page 앞 3,072 bytes에 넣고 나머지 1,024 bytes를
zero padding한다. detection oracle은 축소 frame이 아니라 공식 demo가 원본 frame에 수행한
결과를 사용한다. 선택식, resize 규칙, OpenCV/FFmpeg/OpenVINO 버전과 원본 frame index/PTS를
manifest에 기록한다. 선택된 frame에서 두 개 이상의 class가 관찰되지 않으면 fixture gate를
실패시키고, 동영상이나 선택 규칙 변경을 문서 검토 대상으로 돌린다.

각 canonical frame record는 다음 정보를 가진다.

- `fixture_version`, `video_sha256`, `frame_index`, `pts`
- BGR24 `width=32`, `height=32`, `stride=96`, active bytes 3,072, page bytes 4,096,
  zero-padded page SHA-256
- detector/model revision과 threshold
- 정렬된 detection list: `class_id`, Q16 confidence, Q16 normalized bounding box

raw frame은 `work/build/vision-pipeline/fixtures/frames.bin`, oracle은
`work/build/vision-pipeline/fixtures/oracle.bin`에 생성하고 Git에는 넣지 않는다. 전체 manifest와
각 산출물 digest만 Phase 결과 문서에 기록한다. 동일한 pinned 도구를 두 번 실행했을 때 frame
digest와 정규화된 oracle JSON이 같아야 fixture 준비를 통과한다.

결과 정규화 규칙은 다음과 같다.

1. confidence `< 0.50`은 제외한다.
2. 좌표는 `[0, 1]` 범위로 clamp한 뒤 unsigned Q16으로 변환한다.
3. detection은 confidence 내림차순, class ID와 좌표 오름차순으로 안정 정렬한다.
4. Host result 상한은 frame당 16개다. 초과 시 같은 정렬 순서의 상위 16개만 사용하고 truncation
   flag를 설정한다.

## 4. Runtime 시나리오

```text
Host Application
  │ AF_VSOCK: CONFIG / CAPTURE(frame_seq) / STOP
  ▼
Camera pVM — canonical BGR24 frame replay
  ├─ Phase 09 EL2 DMA-BUF lease ────────────────┐
  └─ /dev/pvm-msg: BGR3 descriptor ─────────────┤
                                                 ▼
AI pVM — frame SHA-256 → pinned oracle lookup → bounded detections
  │ AF_VSOCK: DETECTION_RESULT / ACK / ERROR
  ▼
Host Application — frame_seq, class, confidence, bounding box 출력
```

Camera simulator는 선택된 30개 zero-padded page를 pVM image에서 읽고 매 CAPTURE마다 새
DMA-BUF에 복사한다. Phase 09-b descriptor allowlist에 `BGR3` 단일 plane을 추가하며
`stride >= width × 3`, `stride × height <= plane size <= actual_size`, padding zero와 overflow를
검증한다. MP4 byte stream이나 fixture path는 Camera↔AI protocol에 보내지 않는다.

AI simulator는 sequence만으로 oracle을 선택하지 않는다. imported DMA-BUF의 검증된 layout으로
raw frame SHA-256을 계산하고 manifest의 `(frame_sha256, layout)`과 일치할 때만 detection을
반환한다. 일치하지 않거나 duplicate/stale frame이면 buffer를 반환하고 `FRAME_REJECTED`와
Host-facing ERROR를 보낸다.

Host-facing `DETECTION_RESULT`는 다음 필드만 허용한다.

- `session_id`, `request_id`, `frame_seq`, `status`
- `detection_count`, `truncated`
- 최대 16개의 `class_id`, Q16 `confidence`, Q16 `xmin/ymin/xmax/ymax`

raw frame, frame hash, oracle record, local FD, transfer ID, PA/IPA/IOVA, model path와 가변 문자열은
Host-facing result에 포함하지 않는다.

## 5. 구현 계획

### P10-0. Fixture 및 license gate

1. URL, Open Model Zoo commit, demo/model license와 동영상 재배포 조건을 기록한다.
2. 동영상 크기와 SHA-256을 검증하고 mismatch면 즉시 실패한다.
3. pinned OpenVINO/OpenCV/FFmpeg 버전으로 CPU demo를 실행한다.
4. canonical frame과 normalized oracle을 두 번 생성해 digest가 같은지 확인한다.

### P10-1. Fixture preparation tool

1. `work/src/tools/vision-pipeline/prepare-fixture.sh`는 다운로드·버전 확인·demo 실행만 조정한다.
2. frame 선택, decode, Q16 변환과 manifest 생성은 test 가능한 프로그램으로 구현한다.
3. network 없이 기존 fixture digest를 검증하는 `verify-fixture` 경로를 제공한다.

### P10-2. Camera simulator

1. Phase 09-b와 같은 transport/API를 사용하는 별도 Camera fixture replay adapter를 추가한다.
2. frame index/PTS를 session의 frame sequence와 결합하고 BGR3 descriptor를 별도 message
   channel로 전송한다.
3. EOF에서는 묵시적으로 loop하지 않고 Host에 명시적 EOS/ACK를 반환한다.

### P10-3. AI/GPU simulator

1. AI pVM image에 model binary 대신 bounded oracle manifest를 넣는다.
2. descriptor와 DMA-BUF를 transfer ID로 결합하고 actual size/BGR3 plane bounds를 먼저 검증한다.
3. frame hash로 oracle을 조회하고 bounded `DETECTION_RESULT`를 생성한다.
4. 한 byte 변조, 잘못된 layout, 미등록 hash, duplicate와 oracle index mismatch를 거부한다.

### P10-4. Result protocol

1. Phase 09-b versioned protocol에 고정 크기 detection result를 추가한다.
2. class allowlist, count 상한, Q16 range와 bounding box 순서를 Host decoder에서 재검증한다.
3. Host는 frame별 detection을 구조화된 text/JSON log로 출력하되 raw frame은 저장하지 않는다.

### P10-5. End-to-end 및 장애 검증

1. 30개 fixture frame에 대해 CAPTURE → DMA-BUF/descriptor → oracle lookup → RESULT를 반복한다.
2. Host 결과가 normalized oracle과 frame별로 정확히 일치하는지 별도 verifier로 비교한다.
3. Camera, AI, Host 종료 및 중간 연결 상실을 각각 주입하고 false success와 stale result가 없는지
   확인한다.
4. STOP/EOS 뒤 socket, FD, EL2 lease/message queue, VM/vCPU와 page reference를 회수한다.
5. Phase 09-b 정상·negative·fault 검증을 회귀 실행한다.

## 6. 완료 조건

| ID | 완료 조건 |
|---|---|
| CC-10-01 | demo commit, model/video URL, license, tool version과 모든 입력/fixture digest가 기록된다. |
| CC-10-02 | fixture를 두 번 생성해 선택 frame SHA-256과 normalized oracle이 동일하며 선택 frame에 두 개 이상의 class가 있다. |
| CC-10-03 | Camera pVM이 30개 32×32 BGR24/zero-padded page를 순서대로 DMA-BUF와 별도 BGR3 descriptor로 전달한다. |
| CC-10-04 | AI pVM이 actual size/format/plane bounds 검증 후 frame hash로만 oracle을 결합한다. |
| CC-10-05 | 한 byte 변조, 잘못된 layout/hash, duplicate/replay/mismatch가 결과 생성 전에 거부된다. |
| CC-10-06 | Host가 30개 frame의 bounded detection을 받고 class/score/bbox가 oracle과 정확히 일치한다. |
| CC-10-07 | Host-facing capture에서 raw frame/hash/descriptor/FD/token/address/oracle/model field가 0건이다. |
| CC-10-08 | 정상 STOP/EOS와 Camera/AI/Host 장애 뒤 false success 없이 모든 runtime 자원이 회수되고 `Mlocked: 0 kB`다. |
| CC-10-09 | Phase 09-b VSOCK, metadata, DMA-BUF, negative/fault 회귀가 모두 통과한다. |
| CC-10-10 | panic/Oops/BUG와 unexpected timeout이 없고 최종 `PVM_VISION_PIPELINE_OK` marker가 출력된다. |
| CC-10-11 | 실제 camera/GPU/inference/model 보호를 검증하지 않았다는 제한이 결과 문서와 최종 판정에 명시된다. |

demo가 Host에서 실행됐다는 사실이나 fixture 생성 성공만으로 Phase 10을 완료하지 않는다.
CC-10-01~11을 실제 E-3 end-to-end session에서 모두 통과한 뒤에만 완료로 변경한다.

## 7. 산출물

- fixture 준비/검증: `work/src/tools/vision-pipeline/`
- Camera/AI simulator와 result protocol: `work/src/tools/pvm-user-channel/`,
  `work/src/tools/pvm-buffer/`
- 비추적 fixture와 로그: `work/build/vision-pipeline/`
- 입력·oracle digest와 검증 결과: `docs/phase-10/VERIFICATION.md`

## 8. 한계

- USB camera capture, camera driver와 실시간 sensor timing을 검증하지 않는다.
- NVIDIA GPU assignment, GPU driver, GPU inference와 model/tensor 기밀성을 검증하지 않는다.
- AI pVM은 실제 model inference가 아니라 공개 demo의 사전 생성 oracle을 조회한다.
- 공개 fixture에 대해 runtime 경로 격리를 검증하므로 실제 민감 영상의 기밀성 보증이 아니다.
- 정확도, FPS, latency, backpressure와 production reconnect는 평가하지 않는다.
- 실제 camera/GPU를 확보하면 simulator adapter만 hardware adapter로 교체하고 Phase 08~10의
  격리·통신·장애 시험 전체를 다시 수행해야 한다.

## 9. 조사 출처

- [Open Model Zoo Object Detection Python Demo](https://github.com/openvinotoolkit/open_model_zoo/blob/7cc29a91472b4cb1289a11e655ba3e188e1d4a31/demos/object_detection_demo/python/README.md)
- [person-vehicle-bike-detection-2000 model](https://github.com/openvinotoolkit/open_model_zoo/blob/7cc29a91472b4cb1289a11e655ba3e188e1d4a31/models/intel/person-vehicle-bike-detection-2000/README.md)
- [Open Model Zoo demo video directory](https://storage.openvinotoolkit.org/data/test_data/videos/)
- [Open Model Zoo Apache-2.0 license](https://github.com/openvinotoolkit/open_model_zoo/blob/7cc29a91472b4cb1289a11e655ba3e188e1d4a31/LICENSE)
