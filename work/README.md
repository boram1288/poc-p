# work 디렉터리

`work/`는 실제 소스와 재생성 가능한 빌드·실행 산출물을 분리한다.

```text
work/
├── src/    외부 소스와 프로젝트 실행·분석 도구
└── build/  빌드 결과, initramfs, 분석 결과와 실행 로그
```

- `src/pkvm-linux/`는 Git submodule이다. 커밋 SHA만 상위 저장소에 기록한다.
- `src/tools/`의 프로젝트 도구는 Git으로 관리한다.
- `src/` 아래 별도 Git repository를 수정하면 해당 repository의 작업 완료·검증 후 먼저
  source commit을 만들고, 이어서 상위 repository에 submodule SHA와 관련 문서를 commit한다.
- `build/`의 생성물은 README를 제외하고 Git에서 관리하지 않는다.
- 문서의 명령은 저장소 루트를 현재 디렉터리로 가정한다.

submodule 초기화와 갱신 절차는 [source layout](src/README.md)을 따른다.
