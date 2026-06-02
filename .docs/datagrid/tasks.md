# datagrid — tasks

Trạng thái: tất cả case upstream `DONE-upstream`. Review current branch
2026-05-25 xác nhận thêm hidden-column persistence đã có trong fork.

| Item | Issue | PR(s) | Current status | Author | Merged | Commit |
|---|---|---|---|---|---|---|
| Cmd+C copy cell value (row → Cmd+Shift+C) | [#1344](https://github.com/TableProApp/TablePro/issues/1344) | [#1337](https://github.com/TableProApp/TablePro/pull/1337), [#1338](https://github.com/TableProApp/TablePro/pull/1338) | DONE-current | datlechin | 2026-05-19 | — |
| JSON cell truncated + detail view missing data | [#1345](https://github.com/TableProApp/TablePro/issues/1345) | [#1341](https://github.com/TableProApp/TablePro/pull/1341), [#1373](https://github.com/TableProApp/TablePro/pull/1373), [#1412](https://github.com/TableProApp/TablePro/pull/1412) | DONE-current | datlechin | 2026-05-20 → 2026-05-25 | — |
| Raw SQL filter suggest sau AND/OR | [#1346](https://github.com/TableProApp/TablePro/issues/1346) | [#1384](https://github.com/TableProApp/TablePro/pull/1384) | DONE-current | datlechin | 2026-05-22 | `6bdef581` |
| Luôn hiển thị filter + persist filter on reopen | [#1347](https://github.com/TableProApp/TablePro/issues/1347) | [#1339](https://github.com/TableProApp/TablePro/pull/1339), [#1360](https://github.com/TableProApp/TablePro/pull/1360), [#1387](https://github.com/TableProApp/TablePro/pull/1387), [#1395](https://github.com/TableProApp/TablePro/pull/1395) | DONE-current | datlechin | 2026-05-19 → 2026-05-22 | `39b47b5c`, `3b2ed6d8` |
| Copy chỉ những cột visible | [#1354](https://github.com/TableProApp/TablePro/issues/1354) | [#1372](https://github.com/TableProApp/TablePro/pull/1372) | DONE-current | datlechin | 2026-05-21 | — |
| Save hide column + omit khỏi browse query | — | [#1373](https://github.com/TableProApp/TablePro/pull/1373), [#1375](https://github.com/TableProApp/TablePro/pull/1375) | DONE-current | datlechin + fork follow-up | 2026-05-21 | — |

## File-count theo PR

- **#1337** (copy cell): 6 files modified (KeyHandlingTableView, PasteboardCommands, PasteboardActionRouter, AppCommands, menu wiring)
- **#1341** (cell viewer + dispatcher): refactor `CellInteractionResolver`, `CellOverlayBase`; CellOverlayEditor 295→120 LOC; CellOverlayViewer 235→70 LOC
- **#1372** (copy visible): new `VisibleColumnProjection` value type; touches mọi copy path (TSV/CSV/Markdown/JSON/INSERT/UPDATE/drag)
- **#1373** (unify query): xoá `ColumnExclusionPolicy`, `LazyLoadColumnsService`, `MultiRowEditState.isTruncated`, 6 files deleted, ~180 LOC net removed
- **#1375** (omit hidden from query): mới `ColumnFetchScope.selectColumns(schema:hidden:primaryKeys:)`; `MainContentCoordinator+ColumnFetchScope`
- **#1384** (raw SQL completion): mới `RawSQLFilterCompletionProvider`, `FilterCompletionSource` enum; `FilterValueTextField` chia path static-values vs sql-tokens
- **#1387** (persist filter): key `FilterSettingsStorage` đổi từ `tableName` → `(connection+database+schema+table)`; default panel state đổi sang "Restore Last Filter"; migration script
- **#1395** (persist cleared): `clearFiltersAndReload()` gọi thêm `clearLastFilters(for:)`
- **#1411** (pagination refactor): de-dup pagination helpers, guard "All rows" khi total unknown
- **#1412** (JSON pretty): mới `JsonSyntaxParser` + `JsonReindenter` (scalar-level, preserve key order + exact numbers, 500KB cap); `MultiRowEditState.updateField` compare semantically

## Current branch verify 2026-05-25

Checklist user có 2 note cũ:

- "mới save filter chứ không phải hide column"
- "chưa lưu hidden column khi switch table"

Source hiện tại đã fix tab-switch path:

- `TablePro/Core/Storage/ColumnVisibilityPersistence.swift` lưu
  `com.TablePro.columns.hiddenColumns.<connectionId>.<tableName>`.
- `MainContentCoordinator+ColumnVisibility.persistOutgoingTabHiddenColumns(oldIndex:)`
  persist hidden set của tab cũ khi switch.
- `MainContentCoordinator+TabSwitch.handleTabChange(...)` gọi persist outgoing tab.
- `MainContentCoordinator+Navigation` và `MainContentView+Setup` gọi
  `restoreLastHiddenColumnsForTable(_:)` khi mở/reuse/restore table.

Verify nhanh:

```bash
rg "ColumnVisibilityPersistence|persistOutgoingTabHiddenColumns|restoreLastHiddenColumnsForTable" TablePro TableProTests
```

---

## Open items — 2026-05-27

User confirmed 4 bugs chưa được cover bởi các PR đã merge:

| Item | Issue | PR | Status | Root |
|---|---|---|---|---|
| Context menu "Copy" nên copy cell value (không phải row) | — | [#1459](https://github.com/TableProApp/TablePro/pull/1459) | ✅ MERGED | `DataGridRowView.swift` `copyFromContextMenu(_:)` |
| Hidden columns không load khi mở table trong NEW TAB | — | [#1459](https://github.com/TableProApp/TablePro/pull/1459) | ✅ MERGED | Tab creation route qua `requeryWithColumnScope()` |
| JSON expand/detail popover truncate string tại 80 ký tự | — | [#1459](https://github.com/TableProApp/TablePro/pull/1459) | ✅ MERGED | `JSONTreeNode.maxDisplayLength` 80 → 300 |
| Filter bar luôn ON mặc định khi mở table | — | [#1459](https://github.com/TableProApp/TablePro/pull/1459) | ✅ MERGED | `TabFilterState.isVisible` default `false`, cần `true` cho `.table` |

Chi tiết xem `content.md` phần 7–10 + § "Open fork PR #1459".

---

## PR #1459 — đã MERGED 2026-05-29

PR #1459 (branch `fix/datagrid`) đã được **merge vào upstream/main** lúc 2026-05-29.
4 fix đã vào main, branch xoá được. Không còn task. Checklist dưới giữ làm lịch sử.

### Agent checklist

**Setup**
- [ ] Worktree từ branch: `git worktree add ../TablePro-pr1459 fix/datagrid`
- [ ] `git fetch upstream && git rebase upstream/main` (sạch sẵn, rebase để chắc)

**Gỡ noise (root cause conflict chung 2 PR)**
- [ ] Reset `.gitignore` về main: `git checkout upstream/main -- .gitignore` (lines 128,158-160 đã có trên main)
- [ ] Nếu diff đụng `CLAUDE.md:171` "Favorite tables" → bỏ (đã có trên main)

**Build / test / lint**
- [ ] `xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation`
- [ ] Test 5 suite của PR:
  - `-only-testing:TableProTests/DataGridRowViewCopyTests`
  - `-only-testing:TableProTests/JSONTreeParserTests`
  - `-only-testing:TableProTests/FilterRestoreTests`
  - `-only-testing:TableProTests/CoordinatorColumnVisibilityTests`
  - `-only-testing:TableProTests/OpenTableTabTests`
- [ ] `swiftlint lint --strict`

**Ship**
- [ ] Push branch, confirm PR #1459 vẫn MERGEABLE → merge (ưu tiên #1, an toàn nhất)

**Không cần làm**
- Không sửa logic (review không tìm thấy bug chặn merge).
