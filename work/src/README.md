# source layout

| 경로 | 내용 | Git 추적 |
|---|---|---|
| `pkvm-linux/` | Linux v6.18 + pKVM 패치 작업 트리 | submodule |
| `tools/analysis/` | 패치 집합 분석 도구 | 포함 |
| `tools/qemu/` | protected 부팅 실행 도구 | 포함 |
| `tools/pvm/` | pVM selftest 실행 도구 | 포함 |
| `tools/multi-pvm/` | 다중 pVM 오케스트레이터와 initramfs 생성 도구 | 포함 |
| `tools/optee-pkvm/` | OP-TEE QEMU v8 E-2 빌드·공존 검증 도구 | 포함 |
| `optee-pkvm/` | OP-TEE 4.7.0 qemu_v8 매니페스트 체크아웃 | 제외 |

새 구현 소스는 `work/src` 아래에 두고 빌드 결과를 소스 디렉터리에 섞지 않는다.

## pkvm-linux submodule

커널 작업 트리는 Git submodule로 관리한다. 상위 저장소는 커밋 SHA만 기록하고 소스는
별도 저장소에 둔다.

| 항목 | 값 |
|---|---|
| 경로 | `work/src/pkvm-linux` |
| URL | `https://github.com/boram1288/pkvm-linux.git` |
| 추적 브랜치 | `pkvm-6.18-full` |

저장소가 5.6GB를 넘으므로 partial clone으로 받는다.

```bash
git clone git@github.com:boram1288/poc-p.git
cd poc-p
git submodule update --init --filter=blob:none work/src/pkvm-linux
```

커널 트리를 갱신했을 때는 submodule 저장소에 먼저 push하고, 상위 저장소에서 새 SHA를
커밋한다. 순서를 바꾸면 상위 저장소가 원격에 없는 커밋을 가리키게 된다.

```bash
git -C work/src/pkvm-linux push github pkvm-6.18-full
git add work/src/pkvm-linux
git commit -m "pkvm-linux submodule 갱신"
```
