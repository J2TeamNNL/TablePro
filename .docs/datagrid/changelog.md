# datagrid — changelog

Trích từ `CHANGELOG.md` upstream (Keep a Changelog 1.1.0) + timeline issue/PR.

## Timeline

| Date | Event |
|---|---|
| 2026-05-25 (review) | Current branch verify: hidden columns persist via `ColumnVisibilityPersistence`; tab switch saves outgoing hidden set. |
| 2026-05-19 05:30 | Issue [#1344](https://github.com/TableProApp/TablePro/issues/1344) (Cmd+C copies whole row) opened by datlechin |
| 2026-05-19 05:29 | Issue [#1345](https://github.com/TableProApp/TablePro/issues/1345) (JSON cell truncated) opened |
| 2026-05-19 05:29 | Issue [#1346](https://github.com/TableProApp/TablePro/issues/1346) (raw SQL filter only first column) opened |
| 2026-05-19 05:29 | Issue [#1347](https://github.com/TableProApp/TablePro/issues/1347) (always show filter bar) opened |
| 2026-05-19 12:34 | PR [#1337](https://github.com/TableProApp/TablePro/pull/1337) merged (copy cell value) |
| 2026-05-19 12:38 | PR [#1338](https://github.com/TableProApp/TablePro/pull/1338) merged (responder-chain followup) |
| 2026-05-19 17:15 | PR [#1339](https://github.com/TableProApp/TablePro/pull/1339) merged (Cmd+F toggle filter — initial) |
| 2026-05-20 05:59 | PR [#1341](https://github.com/TableProApp/TablePro/pull/1341) merged (cell viewer + dispatcher) |
| 2026-05-20 05:28 | Issue [#1354](https://github.com/TableProApp/TablePro/issues/1354) (copy includes hidden columns) opened |
| 2026-05-20 14:50 | PR [#1360](https://github.com/TableProApp/TablePro/pull/1360) merged (Cmd+F route fix) |
| 2026-05-21 12:26 | PR [#1372](https://github.com/TableProApp/TablePro/pull/1372) merged (copy visible columns) |
| 2026-05-21 13:19 | PR [#1373](https://github.com/TableProApp/TablePro/pull/1373) merged (unify query + drop SUBSTRING) |
| 2026-05-21 17:15 | PR [#1375](https://github.com/TableProApp/TablePro/pull/1375) merged (omit hidden from SELECT) |
| 2026-05-22 13:11 | PR [#1384](https://github.com/TableProApp/TablePro/pull/1384) merged (raw SQL filter completion) |
| 2026-05-22 15:39 | PR [#1387](https://github.com/TableProApp/TablePro/pull/1387) merged (restore filter on reopen) |
| 2026-05-22 17:31 | PR [#1395](https://github.com/TableProApp/TablePro/pull/1395) merged (persist cleared filter) |
| 2026-05-24 08:23 | PR [#1411](https://github.com/TableProApp/TablePro/pull/1411) merged (pagination refactor) |
| 2026-05-25 07:35 | PR [#1412](https://github.com/TableProApp/TablePro/pull/1412) merged (JSON pretty-print) |

## Releases

### [v0.44.0] — 2026-05-23

**Changed**
- Active Connections là searchable toolbar popover thay vì modal (#1350 — xem `toolbar/`)

**Fixed** (datagrid-related)
- Filtering table cập nhật row + page count theo filtered result
- Reopening table restore filter đã apply, per connection; remove/clear remembered (#1347)
- Raw SQL filter suggest columns + keywords ở mọi position, sau AND/OR (#1346)

### [v0.43.2] — 2026-05-22

**Changed**
- Hide column = drop khỏi query, table với 1 column nặng load nhanh hơn; PK luôn fetch (#1375)

### [v0.43.x] — pre-2026-05-22

- Cmd+C copy cell value khi single cell focus; Cmd+Shift+C explicit rows (#1344 → #1337/#1338)
- Read-only cell viewer overlay với JSON/BLOB popover (#1345 → #1341)
- Copy chỉ visible columns theo display order (#1354 → #1372)

## PR #1459 — ✅ MERGED 2026-05-29 (branch `fix/datagrid`, squash `87623952`)

| Date | Event |
|---|---|
| — | PR #1459 mở: 4 fix datagrid + 7 test suite |
| 2026-05-29 | Review: code tốt, chỉ vướng noise `.gitignore`/`CLAUDE.md` |
| 2026-05-29 | Codex P2 (`DataGridRowView.swift`): "Preserve row-copy fallback from row-number menu" — khi mở context menu từ cột row-number/non-data của row đang focus, copy phải fallback về copy nguyên row thay vì copy cell |
| 2026-05-29 | datlechin push review fix (`15d0198a`, `ac29ba8b`): hidden columns + applied filters persist **on change** (reopen restore hidden set, không còn `SELECT *`; restore last applied filter); copy rectangular grid selection từ context menu |
| 2026-05-29 | **MERGED** vào main (squash `87623952`). Branch `fix/datagrid` xoá được |

**Đã land (branch `fix/datagrid`)**

- Context menu "Copy" copy focused cell value; fallback copy nguyên row khi không resolve được column (`DataGridRowView.swift`) — Codex P2 xử lý qua `731709425`/`ac29ba8b`
- Hidden columns restored khi mở table ở tab mới; tab-creation path route qua `requeryWithColumnScope()` (`MainContentCoordinator+Navigation`, `+ColumnVisibility`)
- JSON detail popover display cap 80 → 300 ký tự (`JSONTreeNode.swift`)
- Filter bar hiện mặc định khi mở table; `clearFilterState()` reset `isVisible = true` (`FilterCoordinator.swift`, `TabFilterState`)
- Persist hidden columns + filters on change (`15d0198a`); copy rectangular grid selection (`ac29ba8b`)

---

### [Unreleased] — sẽ vào v0.44.x hoặc v0.45

- JSON/JSONB cells pretty-printed mặc định, preserve key order + exact numbers, view không mark dirty (#1412)
