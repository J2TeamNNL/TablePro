# connections — README

## Items

1. **Safe Mode reset khi mở table** (#1351 → #1376)

## Files

- [`brief.md`](brief.md) — vấn đề + root cause 1 câu + mục tiêu
- [`content.md`](content.md) — case-study: 3 chỗ point về saved → session là live SOT
- [`flow.md`](flow.md) — Mermaid: lifecycle, write-through, reconfigure path
- [`tasks.md`](tasks.md) — file changes + note scope
- [`decisions.md`](decisions.md) — 4 ADR: session vs saved persist, tách `update(from:)` / `syncFromSession`, write-through 2 chỗ, tests cô lập
- [`changelog.md`](changelog.md) — v0.43.2

## Pattern transferable

Live-vs-persisted state separation:

| Pattern | Saved | Live (session) |
|---|---|---|
| Safe Mode level | `Connection.safeModeLevel` | `ConnectionSession.safeModeLevel` |
| (Tương tự) selected schema | persist khi user pin | session-only mặc định |

Cho fork tự build: nếu add field tương tự (kết quả query selected, last filter
ad-hoc...) → cân nhắc session vs saved, default session.

## Trạng thái

#1351 → #1376 `DONE-upstream`, release v0.43.2 (2026-05-22).

**Open fork PR #1461** (auto-save safe mode về connection default): còn mở,
**CONFLICTING** nhưng chỉ do noise hunks `.gitignore`/`CLAUDE.md` (VERIFIED 2026-05-30),
code tốt. Bỏ noise → rebase → verify test → merge. Chi tiết: `tasks.md` §
"Open PR #1461 — agent checklist".
