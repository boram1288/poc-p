<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->

## Phase completion workflow

- 각 Phase의 완료 조건을 구현과 실측 검증으로 충족한 뒤 관련 소스와 문서를 Git에 커밋한다.
- Phase 완료 커밋은 현재 브랜치의 설정된 원격 upstream으로 push한다.
- 검증이 실패했거나 Phase가 아직 완료 상태가 아니면 완료 커밋이나 push를 하지 않는다.

## Trusted Access scope rule

- 구현 또는 검증 중 Trusted Access 권한이 필요하다는 메시지가 나타나면, 해당 권한을 요구하거나
  우회하지 않는다.
- 목적을 공개된 Host/guest interface와 관찰 가능한 반환값만으로 검증 가능한 범위로 명확히
  축소하고, 축소된 목표와 제외 항목을 Phase 문서에 기록한 뒤 진행한다.
