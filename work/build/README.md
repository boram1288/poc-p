# build layout

| 경로 | 내용 |
|---|---|
| `analysis/` | 패치 집합 집계와 분류 결과 |
| `pkvm-full-clang/` | clang 커널 빌드 결과 |
| `pkvm-full-gcc/` | gcc 커널 빌드 결과 |
| `pkvm-qemu/` | 부팅 initramfs와 콘솔 로그 |
| `pkvm-pvm/` | selftest, pVM initramfs와 콘솔 로그 |
| `multi-pvm/` | 다중 pVM initramfs와 정상/장애 주입 로그 |
| `optee-pkvm/` | E-2 통합 initramfs, Normal/Secure World 로그 |
| `host-tools/` | `repo`, pyelftools 등 재현용 호스트 도구 |

이 디렉터리의 생성물은 Git에서 제외한다. 각 Phase 문서에 재현 명령과 성공 마커를 기록한다.
