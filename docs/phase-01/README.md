# Phase 01: 커널 및 패치 결정

- 상태: 완료
- 목적: PoC의 기준 커널과 pKVM 패치 소스를 확정한다.

## 결정

- 타깃 커널: upstream Linux v6.18 LTS
- 패치 목록 기준: `for-android/pkvm-mainline-6.18`
- 선형 패치 초안: `for-android/pkvm-master-6.18`
- 최신 개발 현황 대조: `for-android/pkvm-mainline-7.1`

`pkvm-master-6.18`은 v6.18-rc2 위의 선형 스택이라 적용하기 쉽지만 최신 기능 일부가 없다.
`pkvm-mainline-6.18`은 ACK 코드가 섞여 있으나 전체 대상과 후속 의존성을 확인하는 기준이다.

## 수치 구분

| 수치 | 의미 |
|---:|---|
| 394 | `pkvm-master-6.18`의 선형 커밋 수 |
| 658 | 경로와 파일 성격으로 재실측한 pKVM 관련 규모 |
| 721 | v6.18 위에서 실제 빌드·실행한 최종 검증 트리의 커밋 수 |

658은 규모 분석용이며 721과 같은 집합이 아니다. 실제 빌드에는 v6.18에 없는 `FROMLIST` 의존성과
로컬 빌드 수정이 추가된다.

상세 근거와 조사 방법은 [커널 버전 및 패치 소스 조사](pkvm-kernel-version.md)를 참조한다.

## 산출물

- 조사 문서: `docs/phase-01/pkvm-kernel-version.md`
- 대상 커밋: [target-commits.tsv](target-commits.tsv)
- mainline 추가 목록: [pick-mainline.txt](pick-mainline.txt)
- arm64 경계 분석: [arm64-boundary.md](arm64-boundary.md)
- defconfig 분석: [defconfig-options.md](defconfig-options.md)
- 토픽 분류: [topic-classification.md](topic-classification.md)
- 중간 분석 결과: `work/build/analysis/`
- 분석 도구: `work/src/tools/analysis/`
