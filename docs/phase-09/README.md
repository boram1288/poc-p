# Phase 09: 프레임 버퍼 zero-copy 소유권 이전

- 상태: 방식 미결
- 목적: 카메라 프레임을 Host에 노출하지 않고 Camera pVM에서 AI pVM으로 복사 없이 이전한다.
- 환경: E-1에서 경로 검증, E-3에서 실제 프레임으로 확인
- 관련 목표: G-10
- 관련 결정: D-8

## 선행 조건

- Phase 05의 다중 pVM 운용 성공
- 전달 방식 결정 (D-8)
- 실제 프레임 검증은 Phase 08의 카메라 할당 성공

## 전제

[pVM 전달 조사](../../../test-p/docs/99_pvm_dmabuf_transfer.md)의 결론은 다음과 같다.

- virtio-vsock은 Host와 guest 사이의 점대점 채널이며 guest 간 통신은 설계상 제외되어 있다.
- upstream pKVM의 게스트 메모리 하이퍼콜은 `MEM_SHARE`, `MEM_UNSHARE`, `MEM_RELINQUISH`로
  모두 대상이 Host다. 다른 pVM을 대상으로 하는 연산이 없다.
- 따라서 표준 스택만으로는 pVM 간 zero-copy 전달이 성립하지 않는다.
- EL2 벤더 모듈로 guest-to-guest share/lend 하이퍼콜을 등록하는 것이 사실상 유일한 경로다.

이 때문에 이 Phase는 대조군을 먼저 만들고 zero-copy 경로로 대체하는 2단계로 진행한다.

## 계획

1. Host 릴레이 경로로 대조군을 구성한다. 이 경로는 복사가 발생하고 Host에 노출된다.
   파이프라인 성립 확인이 목적이며 성공 조건 4를 충족하지 않는다.
2. EL2 벤더 모듈로 guest-to-guest share/lend 하이퍼콜을 설계한다. 한쪽 stage-2 unmap,
   상대 stage-2 map, 소유권 추적이 최소 구성이다.
3. Camera pVM이 캡처 버퍼의 소유권을 AI pVM으로 이전하는 경로를 구현한다.
4. 이전 전후로 Host stage-2에 해당 페이지가 매핑되지 않음을 확인한다.
5. 버퍼 핸들과 링 인덱스를 주고받는 제어 채널을 별도로 둔다. 메타데이터만 오가므로
   Host 릴레이 채널로 충분하다.
6. 대조군과 zero-copy 경로의 복사 횟수를 비교해 기록한다.

## 완료 조건

- AI pVM이 Camera pVM이 기록한 프레임 마커를 그대로 읽어야 한다.
- 전달 구간에 대한 Host 접근이 차단되어야 한다.
- 전달 과정에 데이터 복사가 없어야 한다. 대조군과의 복사 횟수 비교로 판정한다.
- 이전 후 원 소유 pVM이 해당 버퍼에 접근할 수 없어야 한다.
- 대조군 결과와 zero-copy 결과를 같은 표현으로 섞지 않아야 한다.

## 예정 산출물

- EL2 벤더 모듈 소스: `work/src/tools/pvm-buffer/`
- 대조군 릴레이 소스: `work/src/tools/pvm-buffer/relay/`
- 실행 로그: `work/build/pvm-buffer/`
- 전달 방식 결정 근거: 이 디렉터리에 추가
- 결과 문서: 이 디렉터리에 추가

## 한계

처리량과 지연은 측정하지 않는다. 복사 횟수와 Host 노출 여부만 판정한다.

EL2 벤더 모듈은 대상 SoC의 pKVM 구성에 의존한다. E-3 하드웨어가 벤더 모듈 로딩을
허용하지 않으면 이 경로 자체가 불가하며, 그 경우 대조군 결과만 남긴다.
