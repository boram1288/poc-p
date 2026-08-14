# source layout

| 경로 | 내용 | Git 추적 |
|---|---|---|
| `pkvm-linux/` | Linux v6.18 + pKVM 패치 작업 트리 | 제외 |
| `tools/analysis/` | 패치 집합 분석 도구 | 포함 |
| `tools/qemu/` | protected 부팅 실행 도구 | 포함 |
| `tools/pvm/` | pVM selftest 실행 도구 | 포함 |

새 구현 소스는 `work/src` 아래에 두고 빌드 결과를 소스 디렉터리에 섞지 않는다.
