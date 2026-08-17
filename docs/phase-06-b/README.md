# Phase 06-B: pVM 내부 OP-TEE TA 호출

- 상태: 계획
- 목적: pVM 내부 애플리케이션이 Secure World의 OP-TEE TA를 호출하고, 호출 데이터가 비신뢰 Host에 노출되지 않는 경로를 검증한다.
- 환경: E-2 확장
- 선행 Phase: Phase 06
- 관련 목표: G-6 확장

## 배경

Phase 06은 Host Linux에서 OP-TEE TA를 호출하는 동안 pVM이 함께 실행될 수 있음을 확인했다.
그러나 TA client는 Host에서 실행되며, pVM 내부에서 OP-TEE 서비스를 직접 사용하는 경로는
검증하지 않았다.

Phase 06-B에서는 Linux가 부팅되는 pVM 안에 OP-TEE client를 배치하고, pVM에서 Secure
World까지 TA 요청을 전달하는 경로를 구현한다. 기능 성공뿐 아니라 요청 데이터와 공유
메모리가 Host에 노출되지 않는지도 함께 판정한다.

## 목표 구조

```text
pVM Linux/Application
└─ libteec / tee-supplicant
   └─ 가상화된 TEE 전달 경로
      └─ pKVM EL2 중재
         └─ TF-A / OP-TEE Secure World
            └─ TA
```

## 구현 경로

### 대조군: Host 프록시

pVM의 요청을 virtio 또는 별도 RPC 채널로 Host에 전달하고, Host의 OP-TEE client가 대신 TA를
호출한다. 이 경로는 pVM 애플리케이션의 TA 사용 가능성을 빠르게 확인하는 기능 대조군으로만
사용한다.

Host가 요청 평문이나 응답을 볼 수 있으므로 이 경로의 성공만으로 pVM 데이터의 기밀성을
주장하지 않는다.

### 목표 경로: 직접 또는 FF-A 기반 전달

pKVM이 pVM의 OP-TEE 또는 FF-A 호출을 EL2에서 중재하고, Secure World 호출에 필요한
페이지만 제한적으로 공유한다. 호출이 끝나면 공유 권한과 매핑을 회수한다.

구현 전 다음 사항을 조사해 전달 방식을 확정한다.

1. pVM의 SMC 및 FF-A 호출에 대한 현재 pKVM 처리 범위
2. TF-A와 OP-TEE가 제공하는 VM별 endpoint 및 메모리 공유 모델
3. pVM private page를 Secure World와 공유하고 회수할 수 있는 경로
4. OP-TEE 세션과 호출자 identity를 pVM별로 분리하는 방법
5. 게스트 Linux OP-TEE 드라이버에 필요한 DT 또는 ACPI 인터페이스

## 계획

1. Linux가 부팅되는 최소 pVM 이미지와 콘솔을 구성한다.
2. pVM 이미지에 OP-TEE client, `libteec`, `tee-supplicant`와 최소 TA client를 포함한다.
3. Host 프록시 경로를 구현해 pVM 내부 `TEEC_OpenSession()`과
   `TEEC_InvokeCommand()`의 기능 대조군을 확보한다.
4. pKVM, TF-A, OP-TEE의 SMC/FF-A 및 메모리 공유 경로를 조사하고 목표 전달 방식을
   결정한다.
5. pVM별 TEE endpoint와 TA 세션을 분리한다.
6. TA 호출에 필요한 페이지만 Secure World와 공유하고 Host stage-2에는 매핑하지 않는
   전달 경로를 구현한다.
7. pVM 내부에서 4 KiB 카메라 프레임 모사 데이터를 TA로 암호화하고 복호화해 원본 일치를
   확인한다.
8. 호출 중 Host CPU 접근과 다른 pVM의 접근이 차단되는지 대조군과 함께 확인한다.
9. TA 세션 종료와 pVM 종료 후 공유 페이지, 세션, vCPU 및 메모리가 회수되는지 확인한다.
10. 잘못된 endpoint, 다른 pVM의 세션 핸들, 범위를 벗어난 공유 요청이 거부되는지 확인한다.

## 완료 조건

다음 결과가 같은 부팅 세션의 로그로 확인되어야 한다.

- pVM Linux가 protected VM으로 부팅된다.
- pVM 내부에서 `TEEC_OpenSession()`과 `TEEC_InvokeCommand()`가 성공한다.
- TA가 4 KiB 입력을 암호화·복호화하고 원본 일치를 확인한다.
- TA 호출 중 pVM과 Secure World가 필요한 페이지만 공유한다.
- 공유 구간에 대한 Host CPU 접근이 차단된다.
- 다른 pVM이 호출 데이터와 기존 TA 세션에 접근하지 못한다.
- 잘못된 공유 및 세션 요청이 예상된 오류로 거부된다.
- 호출 및 pVM 종료 후 공유 매핑, TA 세션, 메모리와 vCPU 자원이 회수된다.

Host 프록시 경로의 성공은 기능 대조군일 뿐이며 Phase 06-B의 완료 조건으로 인정하지 않는다.
직접 또는 FF-A 기반 목표 경로와 Host 비노출 검증까지 성공해야 완료로 판정한다.

## 예정 산출물

- pVM Linux 이미지 및 rootfs 생성 도구
- pVM용 OP-TEE client와 최소 TA 호출 프로그램
- Host 프록시 대조군 구현 및 로그
- 직접 또는 FF-A 기반 전달 구현
- 정상 호출, 접근 차단, 오류 주입 및 자원 회수 로그
- pKVM, TF-A, OP-TEE 변경 커밋과 재현 명령

산출물은 기존 규칙에 따라 `work/src`, `work/build/optee-pkvm-guest`와 이 문서 아래에
정리한다.

## 한계

- 제품 수준의 키 프로비저닝과 영구 암호화 저장소는 범위에 포함하지 않는다.
- QEMU E-2 확장 환경의 결과는 실제 하드웨어의 Secure World 격리 보증을 대신하지 않는다.
- 성능과 호출 지연은 완료 판정 대상이 아니다.
- OP-TEE 및 FF-A 구성에 VM별 격리 기능이 부족하면 관련 구성 요소의 확장이 필요할 수 있다.
