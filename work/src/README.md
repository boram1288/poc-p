# source layout

| 경로 | 내용 | Git 추적 |
|---|---|---|
| `pkvm-linux/` | Linux v6.18 + pKVM 패치 작업 트리 | submodule |
| `dtc/` | kvmtool용 Device Tree Compiler/libfdt | submodule |
| `kvmtool/` | arm64 protected VM VMM fork | submodule |
| `qemu-phase08/` | E-3 device assignment QEMU fork | submodule |
| `optee-pkvm/u-boot/` | OP-TEE qemu_v8 부팅용 U-Boot | submodule |
| `tools/analysis/` | 패치 집합 분석 도구 | 포함 |
| `tools/qemu/` | protected 부팅 실행 도구 | 포함 |
| `tools/pvm/` | pVM selftest 실행 도구 | 포함 |
| `tools/multi-pvm/` | 다중 pVM 오케스트레이터와 initramfs 생성 도구 | 포함 |
| `tools/optee-pkvm/` | OP-TEE QEMU v8 E-2 빌드·공존 검증 도구 | 포함 |
| `tools/pvm-manager/` | 요청 권한·이미지 검증과 pVM 수명주기 검증 도구 | 포함 |
| `optee-pkvm/`의 나머지 경로 | OP-TEE 4.7.0 qemu_v8 매니페스트 체크아웃 | 제외 |

새 구현 소스는 `work/src` 아래에 두고 빌드 결과를 소스 디렉터리에 섞지 않는다.

## 외부 소스 submodule

독립 Git 저장소인 외부 소스는 모두 submodule로 관리한다. 상위 저장소는 검증한 커밋 SHA만
기록하며, 빌드 캐시와 OP-TEE Repo 도구의 내부 저장소는 재생성 영역이므로 포함하지 않는다.

| 경로 | 원격 | 추적 브랜치/기준 |
|---|---|---|
| `work/src/pkvm-linux` | `boram1288/pkvm-linux` | `pkvm-6.18-full` |
| `work/src/dtc` | kernel.org `dtc` | `master` |
| `work/src/kvmtool` | `boram1288/kvmtools` | `boram1288/phase07-kvmtool` |
| `work/src/qemu-phase08` | `boram1288/qemu` | `boram1288/phase08-pkvm-edu` |
| `work/src/optee-pkvm/u-boot` | upstream `u-boot` | `v2025.07-rc1` 고정 |

커널 저장소가 5.6GB를 넘으므로 모든 submodule을 partial clone으로 초기화한다. kvmtool은
SSH URL을 사용하므로 해당 저장소에 접근 가능한 SSH key가 필요하다.

```bash
git clone git@github.com:boram1288/poc-p.git
cd poc-p
git submodule update --init --filter=blob:none
git submodule status
```

상위 저장소가 기록한 revision으로 되돌릴 때는 경로를 지정해 갱신한다. `status` 첫 글자가
공백이면 초기화와 revision 일치가 완료된 상태다. `-`, `+`, `U`는 각각 미초기화, revision
불일치, 충돌을 뜻한다.

```bash
git submodule update --init --filter=blob:none work/src/kvmtool
git submodule status
```

submodule 소스를 갱신할 때는 해당 저장소에 먼저 commit과 push를 완료한 뒤 상위 저장소에서
gitlink를 기록한다. 원격에 없는 commit을 상위 저장소가 가리키지 않도록 이 순서를 지킨다.

```bash
git -C work/src/kvmtool push origin boram1288/phase07-kvmtool
git add work/src/kvmtool
git commit -m "kvmtool submodule 갱신"
```

`git submodule update --remote`는 추적 브랜치의 최신 commit으로 이동하므로 재현 작업에는
사용하지 않는다. 검증 완료 후 의도적으로 revision을 갱신할 때만 사용한다.

QEMU 저장소 자체의 `roms/`와 test용 중첩 submodule은 이 PoC 빌드 입력이 아니므로 기본
초기화에 `--recursive`를 사용하지 않는다.
