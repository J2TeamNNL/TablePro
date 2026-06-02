# import — README

## Items

1. **DBeaver import mất username** (#1355 → #1366) — DONE, v0.43.2
2. **Connection import dedup: Replace / As Copy / Skip** (#1462) — OPEN-fork, branch `feat/import`

## Files

- [`brief.md`](brief.md) — vấn đề + root cause + pattern transferable
- [`content.md`](content.md) — case-study chi tiết: DBeaver storage layout cũ vs mới, fallback chain
- [`flow.md`](flow.md) — Mermaid: import flow, storage layout split, metadata vs secret
- [`tasks.md`](tasks.md) — file changes, 4 test cases, related PRs trong scope
- [`decisions.md`](decisions.md) — 5 ADR: metadata vs secret, precedence credentials > config, fallback chain, test coverage, pattern transferable cho importer khác
- [`changelog.md`](changelog.md) — v0.43.2

## Pattern bài học

**Phân biệt metadata vs secret khi load credentials file:**

- Metadata (username, host, ssh-user): LUÔN load
- Secret (password, private-key): gated by explicit user choice

Áp dụng pattern này cho mọi importer tương lai (HeidiSQL, Sequel Ace, …).

## Trạng thái

- #1355 → #1366: `DONE-upstream`, release v0.43.2.
- #1462 dedup dialog: **OPEN-fork** (branch `feat/import`). Blocker: CONFLICTING
  chỉ do noise (`.gitignore` + `CLAUDE.md:171`). Drop noise → rebase → verify
  `ConnectionImportServiceTests` thực chất → merge (sau #1459). Chi tiết:
  `content.md` mục "Open fork PR #1462", `tasks.md` agent checklist.
