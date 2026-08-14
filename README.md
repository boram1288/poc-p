# pKVM Protected VM PoC

이 저장소는 Linux v6.18에 pKVM 패치를 적용하고, QEMU와 실제 하드웨어에서
protected VM(pVM) 기반의 신뢰 실행 환경을 단계적으로 검증하는 PoC다. 최종적으로는
비신뢰 Host로부터 카메라 영상과 AI 모델·추론 데이터를 격리하면서, 두 pVM이 실제
USB 카메라와 NVIDIA GPU를 사용해 영상 추론 파이프라인을 수행하는 것을 목표로 한다.

## 프로젝트 목표

- **재현 가능한 pKVM 기반선 구축**: Linux kernel v6.18과 pKVM 패치를 통합하고,
  QEMU에서 커널 부팅, EL2 초기화, pVM 생성·실행 및 protected memory 격리를 검증한다.
- **Secure World 공존 검증**: pKVM이 동작하는 Normal World와 OP-TEE Secure OS를 함께
  구성하고, pVM 실행 중에도 OP-TEE의 암호화·복호화 서비스를 사용할 수 있음을 확인한다.
- **실제 장치의 안전한 할당**: USB 카메라 1대와 NVIDIA GPU 1대를 Camera pVM과 AI pVM에
  각각 할당하고, 장치 소유권과 DMA 접근 범위가 Host 및 다른 pVM과 분리되는지 확인한다.
- **격리된 AI 파이프라인 구현**: Camera pVM이 수집한 프레임을 Host가 읽을 수 없는
  protected memory에 저장하고, 버퍼 복사 없이 소유권을 AI pVM으로 이전해 GPU 추론을
  수행한 뒤 추론 결과만 Host Application에 반환한다.
- **동적 pVM 수명주기 검증**: Host 요청의 권한과 정책을 확인한 뒤 pVM 이미지를 검증하고,
  Camera/AI pVM의 생성, 모니터링, 장애 격리, 종료 및 자원 회수를 일관되게 수행한다.

## 목표 구성

| 구성 요소 | 역할 |
|---|---|
| QEMU | pKVM과 OP-TEE 통합 전 단계의 재현 가능한 기능 검증 환경 |
| Linux kernel v6.18 + pKVM | EL2에서 Host와 pVM, pVM 상호 간 메모리 및 실행 경계 제공 |
| OP-TEE | Secure World에서 카메라 영상의 암호화·복호화 등 보안 서비스 제공 |
| USB camera 1대 | Camera pVM에 할당되는 실제 영상 입력 장치 |
| NVIDIA GPU 1대 | AI pVM에 할당되는 실제 추론 가속 장치 |
| Camera pVM / AI pVM | 카메라 캡처와 AI 추론을 분리하여 최소 권한으로 실행하는 보호 워크로드 |

QEMU는 pKVM 부팅과 격리 동작을 먼저 확인하기 위한 기능 검증 환경이며, 실제 장치 할당과
DMA 격리의 완료 여부는 USB 카메라, NVIDIA GPU 및 SMMU/IOMMU를 갖춘 하드웨어 환경에서
별도로 판정한다.

## Reference Scenario

비신뢰 Host의 요청으로 Camera pVM과 AI pVM을 동적으로 생성한다. Camera pVM은 USB
카메라로 프레임을 캡처하고, pKVM이 보호하는 버퍼의 소유권을 AI pVM에 zero-copy 방식으로
이전한다. AI pVM은 NVIDIA GPU로 추론을 수행하며, 민감한 영상과 모델 중간 데이터 대신
추론 결과만 Host에 전달한다. 암호화·복호화가 필요한 데이터는 OP-TEE의 Crypto Manager를
통해 처리한다.

![Reference Scenario 개념도](docs/concepts/reference-scenario-concept.png)

![Reference Scenario 시퀀스](docs/concepts/reference-scenario-sequence-diagram.png)

세부 설계는 [pVM 수명주기 관리](docs/concepts/vm-management.png),
[장치 직접 할당과 소유권 전환](docs/concepts/hw-sharing-by-arbiter.png),
[프레임 버퍼 zero-copy 소유권 이전](docs/concepts/zero-copy-buffer-sharing.png)을 기준으로 한다.

### 성공 조건

1. Linux v6.18 + pKVM 커널과 OP-TEE가 동일 시스템에서 초기화되고 각각 정상 동작한다.
2. Camera pVM과 AI pVM을 동시에 생성·실행하며 Host와 각 pVM의 메모리 접근을 격리한다.
3. USB 카메라와 NVIDIA GPU의 직접 할당, 회수 및 배타적 소유권 전환을 검증한다.
4. 카메라 프레임을 Host에 노출하지 않고 Camera pVM에서 AI pVM으로 zero-copy 전달한다.
5. AI pVM이 GPU 추론을 완료하고 허용된 추론 결과만 Host Application에 반환한다.
6. pVM 종료 후 장치, 메모리 및 vCPU 자원이 안전하게 회수된다.

## 문서 구조

- [전체 수행 계획](docs/PLAN.md): 목표, Phase 순서, 완료 조건, 현재 상태와 남은 작업
- [work 디렉터리 안내](work/README.md): 소스와 빌드 산출물 관리 규칙

## 작업 디렉터리

```text
work/
├── src/
│   ├── pkvm-linux/       Linux v6.18 + pKVM 패치 소스 트리
│   └── tools/            분석 및 QEMU 실행 도구
└── build/
    ├── analysis/         커밋 집계·분류 결과
    ├── pkvm-full-clang/  clang 커널 빌드 산출물
    ├── pkvm-full-gcc/    gcc 커널 빌드 산출물
    ├── pkvm-qemu/        부팅용 initramfs와 콘솔 로그
    └── pkvm-pvm/         pVM selftest 산출물과 콘솔 로그
```

`work/src/tools`의 프로젝트 도구는 Git으로 관리한다. 외부 커널 소스와 빌드 산출물은
용량이 크거나 재생성 가능하므로 Git에서 제외한다. 모든 명령은 별도 언급이 없으면 저장소
루트에서 실행한다.
