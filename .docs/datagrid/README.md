# datagrid — README

Case-studies trong scope `datagrid` (Conventional Commits scope chính trong upstream).

## Items

1. **Cmd+C copy cell value** (#1344 → #1337, #1338)
2. **JSON cell truncated + detail view missing** (#1345 → #1341, #1373, #1412)
3. **Raw SQL filter chỉ gợi ý cột đầu** (#1346 → #1384)
4. **Luôn hiển thị filter + persist on reopen** (#1347 → #1339, #1360, #1387, #1395)
5. **Copy chỉ visible columns** (#1354 → #1372)
6. **Save hide column + omit khỏi SELECT** (#1375 + current branch follow-up)

## Files

- [`brief.md`](brief.md) — vấn đề chung + mục tiêu + trade-off
- [`content.md`](content.md) — 6 case-studies chi tiết (symptom → root cause → fix + diff)
- [`flow.md`](flow.md) — Mermaid: Cmd+C dispatch, filter persistence, Cmd+F routing, hide → query scope
- [`tasks.md`](tasks.md) — bảng issue/PR/author/merge date/file-count
- [`decisions.md`](decisions.md) — 9 ADR-lite: target visible, fallback dispatch, render-layer truncation, hide=drop, scalar JSON parser, composite key, user-clear vs internal-reset, CompletionEngine reuse
- [`changelog.md`](changelog.md) — timeline + version mapping

## Trạng thái

Tất cả case upstream là `DONE-upstream`. **PR #1459 đã MERGED 2026-05-29** (branch
`fix/datagrid`) — gộp 4 fix: context menu copy cell, hidden columns trong new tab,
JSON popover cap 300, filter bar default ON. Đã vào upstream/main, branch xoá được,
không còn việc cần làm. Phần review/handoff dưới giữ làm lịch sử.

Current branch còn có follow-up đã verify:

- Hidden columns persist qua `ColumnVisibilityPersistence`.
- Khi switch tab, outgoing tab gọi `persistOutgoingTabHiddenColumns`.
- Khi mở/reuse table, coordinator gọi `restoreLastHiddenColumnsForTable` trước khi
  query lại.

Vì vậy checklist "mới save filter, chưa save hide column khi switch table" không còn
đúng với current branch.
