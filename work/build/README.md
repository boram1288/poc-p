# build layout

| 경로 | 내용 |
|---|---|
| `analysis/` | 패치 집합 집계와 분류 결과 |
| `pkvm-full-clang/` | clang 커널 빌드 결과 |
| `pkvm-full-gcc/` | gcc 커널 빌드 결과 |
| `pkvm-qemu/` | 부팅 initramfs와 콘솔 로그 |
| `pkvm-pvm/` | selftest, pVM initramfs와 콘솔 로그 |

이 디렉터리의 생성물은 Git에서 제외한다. 각 Phase 문서에 재현 명령과 성공 마커를 기록한다.
