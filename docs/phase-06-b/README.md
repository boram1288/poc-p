# Phase 06-B: pVM 내부 OP-TEE TA 호출

- 상태: 진행 중 — FF-A 선행 경로 오류 분석 필요
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

## 1차 조사 및 실측 결과 (2026-08-18)

Phase 06-B 구현에 앞서 기존 E-2 스택의 pVM SMC/FF-A 처리 범위와 OP-TEE 전달 경로를
조사하고 최소 호출을 실측했다. 이 조사에서는 목표 경로가 아직 성립하지 않았으므로 Phase를
완료로 판정하지 않는다.

### pKVM FF-A 지원 범위

현재 pKVM 소스에는 protected guest의 FF-A 호출을 중재하는 코드가 존재한다.

- `arch/arm64/kvm/hyp/nvhe/ffa.c`에서 guest RX/TX 매핑, guest IPA에서 PA로의 변환,
  Secure World와의 메모리 share/unshare 및 VM 종료 시 정리를 처리한다.
- `kvm_handle_pvm_hvc64()`는 FF-A가 활성화된 protected VM의 FF-A 호출을 EL2에서
  전달한다.
- VMM은 `KVM_CAP_ARM_PROTECTED_VM_FLAGS_SET_FFA`를 사용해 protected VM의 FF-A
  사용을 명시적으로 활성화해야 한다.

따라서 목표 경로는 legacy OP-TEE SMC를 그대로 전달하는 방식보다 pKVM의 기존 FF-A guest
중재 경로를 사용하는 방향이 적합하다. 다만 해당 capability를 사용하는 Linux pVM VMM과
guest OP-TEE client 구성은 아직 구현하지 않았다.

### legacy OP-TEE SMC 직접 호출 대조 시험

기존 protected VM selftest guest에서 OP-TEE `CALLS_UID` SMC를 직접 호출하도록 임시
계측했다. guest heartbeat 이후 `KVM_RUN`이 `errno=22` (`EINVAL`)로 종료됐고 pVM 실행
결과는 `rc=254`였다.

이는 현재 protected guest가 legacy OP-TEE SMC를 직접 통과시킬 수 없음을 나타낸다.

- Normal World 로그: `work/build/optee-pkvm/console-phase-06-b-probe.log`
- Secure World 로그: `work/build/optee-pkvm/secure-phase-06-b-probe.log`

시험에 사용한 임시 selftest 소스 변경은 결과 확인 후 원복했다.

### OP-TEE SPMC와 Host FF-A 기준 시험

OP-TEE를 S-EL1 SPMC로 실행하도록 `SPMC_AT_EL=1`을 적용하고 Host Linux 커널에
`CONFIG_ARM_FFA_TRANSPORT=y`를 활성화해 기준 시험을 수행했다.

확인된 정상 구간은 다음과 같다.

- TF-A 및 OP-TEE 4.7.0 부팅
- OP-TEE SPMC 초기화
- Normal World의 ARM FF-A 1.2 transport 초기화
- OP-TEE logical partition 검색
- FF-A RX/TX buffer 매핑
- pKVM protected nVHE 초기화

그러나 Host OP-TEE FF-A 드라이버가 보내는 첫 direct request에서 Secure World가
`FFA_ERROR_INVALID_PARAMETER`를 반환했다. Linux에서는 이 결과가 `-EINVAL`로 변환되어
`optee arm-ffa-1` probe가 실패했고 `/dev/tee0`과 `/dev/teepriv0`이 생성되지 않았다.

`CFG_NS_VIRTUALIZATION=y` 적용 여부와 OP-TEE logical endpoint ID 변경을 각각 시험했지만
동일한 첫 direct request 오류가 발생했다. 따라서 pVM guest 경로를 추가하기 전에 TF-A
SPMD와 OP-TEE SPMC 사이의 direct-message 계약 불일치를 먼저 해결해야 한다.

주요 증거 로그는 다음과 같다.

- SPMC, NS virtualization 비활성 기준:
  `work/build/optee-pkvm/console-phase-06-b-spmc-no-virt.log`
- 해당 Secure World 로그:
  `work/build/optee-pkvm/secure-phase-06-b-spmc-no-virt.log`
- FF-A 오류 레지스터 계측 결과:
  `work/build/optee-pkvm/console-phase-06-b-spmc-diag2.log`
- 해당 Secure World 로그:
  `work/build/optee-pkvm/secure-phase-06-b-spmc-diag2.log`

오류 레지스터 계측 결과는 `a2=0xfffffffffffffffe`이며 FF-A의
`FFA_ERROR_INVALID_PARAMETER`에 해당한다. 진단을 위한 pKVM, OP-TEE 및 build script의
임시 소스 변경은 모두 원복했다. 위 로그는 재현 증거인 build 산출물로만 남겨 두었다.

### 현재 판정

다음 이유로 Phase 06-B는 아직 미완료다.

- Linux pVM 이미지와 pVM용 OP-TEE client가 아직 구성되지 않았다.
- pVM에서 `TEEC_OpenSession()` 및 `TEEC_InvokeCommand()`를 실행하지 못했다.
- 4 KiB 입력의 TA 암호화·복호화 시험을 수행하지 못했다.
- Host 비노출, 다른 pVM 접근 차단, 오류 주입 및 자원 회수를 검증하지 못했다.
- 선행 조건인 Host FF-A OP-TEE probe부터 `FFA_ERROR_INVALID_PARAMETER`로 실패한다.

Phase 완료 조건을 충족하지 않았으므로 이 조사 결과에 대해 Phase 완료 커밋이나 push를
수행하지 않았다.

### 다음 확인 순서

후속 작업은 한 항목씩 다음 순서로 확인한다.

1. TF-A SPMD가 OP-TEE logical partition의 첫 direct request를 거부하는 정확한 조건을
   레지스터와 양쪽 handler 로그로 확정한다.
2. Host Linux의 `optee arm-ffa-1` probe와 기존 Phase 06 TA 호출을 SPMC 구성에서 먼저
   복구한다.
3. VMM에 `KVM_CAP_ARM_PROTECTED_VM_FLAGS_SET_FFA`를 적용하고 pVM에서
   `FFA_VERSION`, `FFA_ID_GET` 최소 호출을 확인한다.
4. Linux가 부팅되는 pVM과 guest OP-TEE driver/client를 구성한다.
5. 정상 TA 호출 후 공유 범위, Host 및 다른 pVM 접근 차단, 오류 거부와 자원 회수를 차례로
   검증한다.

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
