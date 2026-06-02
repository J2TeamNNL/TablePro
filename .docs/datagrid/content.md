# datagrid — content (case-studies)

## 1. Cmd+C copy cell value (#1344 → #1337, #1338)

### Symptom

Click vào 1 cell có focus border, bấm Cmd+C → clipboard chứa **cả row TSV** thay vì
chỉ value của cell. Foreign key cell tệ nhất: double-click mở FK popover thay vì
inline edit, nên user không có keyboard path nào để copy mỗi cell value.

### Root cause

`KeyHandlingTableView.copy(_:)` ignore `focusedRow`/`focusedColumn` của grid và
luôn dispatch row-TSV. Grid render focus border nhưng action không consult state đó.

### Fix approach (PR #1337)

Native AppKit responder chain:

- `KeyHandlingTableView.copy(_:)` quyết định cell vs row qua `focusedDataCell()`
  (mirror pattern của `paste(_:)` sẵn có)
- Mới: `KeyHandlingTableView.copyRowsAsTSV(_:)` selector cho explicit-row
- `PasteboardCommands` menu button dispatch `NSApp.sendAction(_, to: nil, from: nil)`
  để responder chain deliver `copy:` cho đúng NSTextView hoặc NSTableView
- `PasteboardCommands` nhận `CommandActionsRegistry` fallback cho `@FocusedValue`
  (match `AppMenuCommands`) — không có thì `.disabled(!hasRowSelection)` luôn true
  khi NSTableView là first responder

```swift
// KeyHandlingTableView
override func copy(_ sender: Any?) {
    if let cell = focusedDataCell() {       // single-cell focus → cell value
        copyCellValue(cell)
    } else {
        copySelectedRows()                  // fallback: row TSV
    }
}
@objc func copyRowsAsTSV(_ sender: Any?) {  // Cmd+Shift+C — explicit rows
    copySelectedRows()
}
```

### Follow-up (PR #1338)

Responder-chain regression khi focus rời grid: `NSApp.sendAction` trả `false`,
action silently lost. Fix: cả nhánh "Copy" (.copyRows) và menu "Copy Rows" fallback
gọi `actions?.copySelectedRows()` khi `NSApp.sendAction` returns `false`.
Cũng fix `CreateTableView` mirror `selectedRows` → `GridSelectionState.indices`
giống pattern `TableStructureView` đã làm.

### Pattern thay đổi convention

- Apple HIG / DataGrip / DBeaver / Postico / Sequel Ace: shortcut target selection
  **cụ thể nhất** đang visible
- TablePlus: Cmd+Shift+C cho explicit-rows → match

---

## 2. JSON cell truncated + detail view missing data (#1345 → #1341, #1373, #1412)

### Symptom

- Cell JSON dài hiển thị bị cắt
- Bấm vào "xem chi tiết" vẫn thiếu data (truncated tại SQL layer)
- Format JSON button mark row là dirty dù chỉ view
- Key bị reorder (sortedKeys), bigint round qua NSNumber → mất precision

### Root cause — 4 lỗi cộng dồn

1. **PR #1373** phát hiện: `ColumnExclusionPolicy` truncate text columns server-side
   bằng `SUBSTRING(col, 1, 256) AS col` rồi alias lại tên gốc. Grid không biết value
   partial → edit + save **ghi 256-char value đè giá trị thật** (data corruption).
   BLOB đã có guard cho case này, text thì không.
2. **PR #1341** phát hiện: read-only cell có code path riêng, editable mode bind raw
   compact value → cách duy nhất để indent là button overwrite cell.
3. **PR #1412** phát hiện: change detection compare raw strings → whitespace =
   real edit; formatter `JSONSerialization` với `.sortedKeys` reorder + round number;
   save re-compact với `.sortedKeys` → reorder on every save.

### Fix approach

**PR #1373** — bỏ SUBSTRING truncation, theo pattern của BLOB:

- `TableQueryBuilder` là source duy nhất; `QueryTab.buildBaseTableQuery` delegate
- Xoá: `ColumnExclusionPolicy`, `LazyLoadColumnsService`, `MultiRowEditState.isTruncated`,
  6 files, ~180 LOC net removed
- Large text fetch full, truncate ở render layer, full value available trong cell viewer

**PR #1341** — read-only cell viewer overlay thống nhất:

- Mới `CellInteractionResolver` (pure value-type): map cell context → `CellInteractionMode`
- Mới `CellOverlayBase`: shared base cho `CellOverlayEditor` + `CellOverlayViewer`
  (positioning, dismiss observer, raise-to-front)
- `JSONViewerView(isEditable: false)` reuse qua wrapper `JSONViewerContentView`
- `HexEditorContentView` thêm `isEditable` — viewer hide editable hex section + Save

**PR #1412** — JSON pretty-print mặc định, non-destructive:

- Mới `JsonSyntaxParser` + `JsonReindenter`: parse + format ở **scalar level**, copy
  keys/number tokens/string contents byte-for-byte; preserve key order + exact numbers;
  top-level primitives; invalid JSON passthrough; 500 KB cap
- `JSONViewerView` holds `displayText` buffer pretty cả 2 mode; bỏ button "{}" Format
- `MultiRowEditState.updateField` semantic compare cho JSON: `normalize(new) == normalize(original)`;
  cached `isJson` flag, true cho cả text column trông giống JSON

```swift
// MultiRowEditState (concept)
func updateField(_ new: String, original: String, isJson: Bool) {
    let isChanged = isJson
        ? JsonReindenter.normalize(new) != JsonReindenter.normalize(original)
        : new != original
    // ...
}
```

---

## 3. Raw SQL filter chỉ gợi ý cột đầu tiên (#1346 → #1384)

### Symptom

Trong raw SQL filter, autocomplete chỉ suggest column cho token đầu. Sau khi gõ
`AND`/`OR`, không có suggestion cho condition tiếp theo.

### Root cause

Raw SQL field render bởi `FilterValueTextField`, dùng **whole-string matcher** —
đúng cho per-column value field (lúc đầu được thiết kế cho), nhưng sai cho multi-token
WHERE clause. Replace cả field on accept → chỉ token đầu work được.

### Fix approach (PR #1384)

Drive raw SQL field qua `CompletionEngine` sẵn có. Raw filter execute là
`SELECT ... FROM <table> WHERE (<rawSQL>)`, nên fix complete đúng query mà filter
denotes.

**Engine (additive):**

- `CompletionEngine.filterCompletions(fragment:cursorPosition:tableName:)` → fragment-relative
  items + replacement range, columns scoped tới table hiện tại
- Optional `forcedTableReferences` trên `getCompletions`
- `SQLContext.replacingTableReferences(_:)`

**Filter:**

- Mới `RawSQLFilterCompletionProvider` wrap engine cho connection + table hiện tại
- `FilterValueTextField` thêm `FilterCompletionSource`:
  - `.staticValues` cho value field (unchanged)
  - `.sqlTokens` cho raw SQL (chạy engine async, generation-guarded, splice vào
    range của current token, caret intact)
- `FilterRowView` / `FilterPanelView` wire provider cho raw field, gated by SQL
  dialect, rebuild khi table change
- Mới `MainContentCoordinator.currentTableName`

Custom suggestion dropdown vẫn giữ (consistent với per-column value field).

---

## 4. Luôn hiển thị filter + persist filter on reopen (#1347 → #1339, #1360, #1387, #1395)

Issue gốc đề xuất "always show filter bar". Scope sau cùng (settled trong issue):
**persist filter on reopen**, kèm restructure Cmd+F → context-aware filter toggle.

### Symptom

- Cmd+Shift+F không match HIG (mọi tool dùng Cmd+F cho filter/find)
- Reopen table → filter cũ biến mất; restoration default "Always Hide"
- Same table name ở 2 connections → filter collide nếu enable restoration

### Root cause

**Persist** (PR #1387):

1. Restoration gated bởi panel-state setting default = "Always Hide"
2. Path mở table vào window đã có tab restore hidden columns nhưng không filter
3. App restart không restore filter
4. Latent: `FilterSettingsStorage` key by raw `tableName` → collision cross-connection

**Cmd+F routing** (PR #1339 → #1360 bug fix):

- PR #1339 gated bởi `firstResponder is KeyHandlingTableView` — nhưng nothing focus
  grid khi tab mở → Cmd+F thường fall qua editor Find path
- 2 menu item cùng `Cmd+F` → SwiftUI dedupe drop hint của 1 item; AppKit bind
  `Cmd+F` tới Edit > Find dù disabled → mở Edit menu 1 lần xong Cmd+F chết hẳn
  ở table tab

### Fix approach

**PR #1339** — Cmd+F context-aware:

- Data grid focused: toggle filter panel
- SQL editor focused: open standard Find
- Inspector: toggle inspector filter (existing)
- Cmd+Shift+F removed làm default; user có thể rebind

**PR #1360** — `CommandFRoute` drive cả 2 menu item:

| Route | Cmd+F owner | Menu flash |
|---|---|---|
| table tab | View > Toggle Filters | View |
| query tab | Edit > Find | Edit |
| inspector | Edit > Find | Edit |

Shortcut apply tới đúng 1 item per route → không duplicate dedupe nữa.

**PR #1387** — restore filter on reopen:

- `FilterSettingsStorage`: key per `(connection + database + schema + table)`;
  default panel state đổi sang "Restore Last Filter"; migration cleanup file cũ
- `FilterCoordinator`: restore unless "Always Hide"; show filter bar populated khi
  restore; restore decision là pure function (unit testable)
- Wire vào mọi table-open path; bake filter vào query trước khi run; FK-navigation
  filter giữ precedence

**PR #1395** — persist cleared filters (follow-up):

- Bug: apply → clear (Unset) → close → reopen → filter cũ trở lại
- Cause: `applyFiltersAndReload()` save; `clearFiltersAndReload()` không xoá file
- Fix: `clearFiltersAndReload()` gọi mới `clearLastFilters(for:)` → `FilterSettingsStorage.clearLastFilters`
- Note: đặt ở `clearFiltersAndReload()` (user-initiated), KHÔNG ở `clearFilterState()`
  (internal reset khi tab switch — phải save state outgoing trước)

### Scope giới hạn (PR #1387 nêu)

- Cross-database reopen không cover (path qua `switchDatabase` clear filter state)
- Schema validation on restore không có (columns load async sau restore)

---

## 5. Copy chỉ những column đang visible (#1354 → #1372)

### Symptom

Copy row từ data grid emit mọi column từ underlying result, ignore column đã
hide và thứ tự user arrange. Clipboard không match những gì on-screen.

### Fix approach (PR #1372)

Mới `VisibleColumnProjection` value type — map columns + types + values xuống
**visible set theo display order**:

- `indices == nil` = identity (all columns)
- Out-of-range indices → drop (cho columns) / NULL (cho values) → safe với stale layout
- `TableViewCoordinator.visibleColumnDataIndices()` trả data indices của visible
  columns (exclude hidden + row-number col) on-screen order

Mọi copy path chạy qua projection:

- TSV (with/without headers)
- CSV, Markdown, JSON
- SQL `INSERT` / `UPDATE`
- Single-cell drag/copy (TSV + HTML)

Tests: `VisibleColumnProjectionTests` (identity, reorder, drop hidden, out-of-range);
`RowOperationsManagerCopyTests` thêm case visible-subset.

---

## 6. Save hide column + omit khỏi browse query (#1375 + current branch)

### Feature

Yêu cầu cũ: "chọn per-table cột nào load **trước** fetch" → một table có 1 column
nặng (e.g. BLOB, large text) mở nhanh.

### Approach (PR #1375)

Reuse **column visibility** sẵn có. Hide column = không fetch.

- Mới `ColumnFetchScope.selectColumns(schema:hidden:primaryKeys:)`: pure, tested
  → schema minus hidden, PK always kept, `nil` khi không có gì omit
- `TableQueryBuilder` nhận `selectColumns:` projection (`nil` ⇒ `SELECT *`)
- Mới `MainContentCoordinator+ColumnFetchScope`: per-table schema-column cache
  (từ async `SQLSchemaProvider.getColumns`), `selectColumns(for:)`,
  `requeryWithColumnScope`, full-schema list cho picker
- Wire qua `FilterCoordinator` (rebuild/apply/clear), open path, visibility toggles

**Behavior:**

- Hidden = không fetch; PK luôn fetch (row identity, UPDATE)
- Toggle re-run query (debounced); show column re-fetch
- Scoped at open: table có persisted hidden → first query đã scoped (column list
  từ cached `getColumns`) — không có `SELECT *` round-trip trước
- Visibility popover list **full schema** (không phải fetched result) → omitted
  column vẫn toggle back được

**Trade-off (called out trong PR):** hide/show không còn là instant cosmetic toggle
— phải re-run query.

Liên hệ: PR #1373 (cùng author) trước đó xoá `ColumnExclusionPolicy` chính vì pattern
truncate-server-side là anti-pattern; PR #1375 build cleanly trên column-visibility
thay vì restore lại anti-pattern.

### Current branch persistence verify

Current branch đã có phần persistence cụ thể, không chỉ filter persistence:

```swift
enum ColumnVisibilityPersistence {
    static func key(tableName: String, connectionId: UUID) -> String {
        "com.TablePro.columns.hiddenColumns.\(connectionId.uuidString).\(tableName)"
    }
}
```

Switch tab path:

- `MainContentCoordinator+TabSwitch.handleTabChange(...)` save filter của tab cũ,
  rồi gọi `persistOutgoingTabHiddenColumns(oldIndex:)`.
- `MainContentCoordinator+ColumnVisibility.persistTabHiddenColumns(_:)` chỉ persist
  tab `.table` có `tableName`.
- Open/reuse/restore table path gọi `restoreLastHiddenColumnsForTable(_:)`.

Kết luận review 2026-05-25: checklist "chỉ save filter, chưa save hidden column khi
switch table" là trạng thái cũ; source hiện tại đã lưu hidden columns theo
`connectionId + tableName` và restore khi quay lại table.

---

## 7. Context menu "Copy" nên copy cell value (OPEN — 2026-05-27)

### Symptom

Right-click lên cell → "Copy" → clipboard chứa cả row (TSV). User muốn "Copy" trong
context menu copy chỉ value của cell đang hover, không phải row. "Copy as Row" nên
là option phụ bên trong.

**Khác với #1344 (Cmd+C)**: Cmd+C đã fix copy cell khi có focus. Nhưng context menu
"Copy" vẫn copy row, không consult cell focus hay hover position.

### Root cause

`DataGridView+RowActions.swift` context menu item "Copy" dispatch `copySelectedRows()`
thay vì `copyCellValue(at:columnIndex:)`.

### Fix approach

Context menu phải biết cell hiện tại. Trong `NSTableView`, khi build context menu
(`menuForEvent:` hoặc `menu(_:willHighlightItem:)`), có thể lấy row + column từ
`clickedRow` / `clickedColumn` của `NSTableView`.

```swift
// DataGridView+RowActions.swift — context menu
let cellValueItem = NSMenuItem(title: "Copy", action: #selector(copyClickedCellValue), ...)
let copyRowItem   = NSMenuItem(title: "Copy Row", ...)
```

```swift
@objc func copyClickedCellValue(_ sender: Any?) {
    guard tableView.clickedRow >= 0, tableView.clickedColumn >= 0 else {
        copySelectedRows(); return
    }
    coordinator?.copyCellValue(at: tableView.clickedRow,
                               columnIndex: tableView.clickedColumn)
}
```

### Tests

- Right-click cell → Copy → clipboard = cell value only
- Right-click cell → "Copy Row" → clipboard = full row TSV
- Right-click header (row=-1) → Copy → fallback to row copy

---

## 8. Hidden columns không load khi mở NEW TAB (OPEN — 2026-05-27)

### Symptom

1. Mở table A, hide column X → được persist (tab switch path hoạt động đúng)
2. Cmd+T → New Tab → click table A → column X **hiện lại** (persisted hidden columns không load)

Tab switch (same tab) hoạt động đúng. New tab không áp dụng persisted hidden columns.

### Root cause

`ColumnVisibilityPersistence` restore được gọi qua `restoreLastHiddenColumnsForTable(_:)` trong
`MainContentCoordinator+Navigation`. Cần verify xem path tạo new tab có đi qua đúng code path
hay không.

Khả năng: new tab creation gọi `openTableTab` nhưng skip restore bước khởi tạo `DataGridConfiguration`
với hidden columns, hoặc restore được gọi trước khi `tableName` được set đúng.

### Fix approach

Trace full path của "open table in new tab":

```
Cmd+T → new TabWindowController → openTableTab(_:in:) 
     → DataGridViewModel init
     → restoreLastHiddenColumnsForTable(_:)?  ← verify call site
```

Đảm bảo `restoreLastHiddenColumnsForTable` được gọi SAU khi `tableName` available
và TRƯỚC khi `buildBaseTableQuery` chạy lần đầu.

### Tests

- Hide column X tại table A → open new tab → open table A → column X vẫn hidden
- New connection (no persisted state) → open table A in new tab → all columns visible

---

## 9. JSON expand/detail popover truncate string tại 80 ký tự (OPEN — 2026-05-27)

### Symptom

Cell JSON: click expand / xem chi tiết → popover hiển thị string values bị cắt tại
~80 ký tự (thêm `...`). Data thật vẫn đầy đủ trong DB nhưng UI không cho xem hết.

PR #1412 đã fix truncation ở SQL layer và JSON pretty-print. Nhưng `JSONTreeNode`
vẫn có truncation riêng trong tree display.

### Root cause

`JSONTreeNode.swift` có 2 đường dữ liệu:

```swift
// display: truncated tại 80 chars (dùng cho label trong tree row)
if nsLen > 80 {
    display = "\"\((escaped as NSString).substring(to: 80))...\""
}

// rawValue: full string (dùng để copy, search)
let rawValue: String = escapedFull
```

Nếu `JSONTreeNodeView` (row trong tree) render `node.display` thay vì `node.rawValue`,
user thấy truncated value dù data đầy đủ.

Expand/detail sheet mở `JSONTreeView` → `JSONTreeNodeView` → render `node.display`.
Cần render `node.rawValue` thay thế (hoặc nếu muốn giữ compact trong tree, thêm
"expand inline" cho long string values).

### Fix approach

Option A (đơn giản): `JSONTreeNodeView` render `rawValue` cho value label, không `display`.
Tree row sẽ dài hơn nhưng đúng.

Option B (UX tốt hơn): Giữ truncated `display` trong tree, nhưng click vào node → expand
inline hoặc tooltip/popover hiện `rawValue`. Pattern giống Xcode's Quick Look.

User cần thấy đủ data trong expand view → Option A đủ cho MVP.

### Tests

- JSON với string value > 80 chars → expand popover hiển thị full value
- Node count > 5000 → truncation node "(X more)" vẫn hiển thị đúng

---

## 10. Filter bar luôn hiển thị mặc định (OPEN — 2026-05-27)

### Symptom

Mở table → filter bar ẩn. Phải bấm Cmd+F để hiện. User muốn filter bar luôn ở đó
mặc định, không cần toggle.

PR #1387 đổi default sang "Restore Last Filter" — nên nếu user chưa từng show filter,
vẫn ẩn. Nếu đã show 1 lần thì restore. Nhưng first-time experience vẫn không có filter.

### Root cause

`TabFilterState.isVisible` default = `false`. "Restore Last Filter" chỉ help nếu
user đã từng show filter ở table đó trước đó.

### Fix approach

Đổi default `isVisible` = `true`:

```swift
// TabFilterState.swift (hoặc nơi khởi tạo TabFilterState)
var isVisible: Bool = true   // was false
```

Hoặc nếu default được drive bởi `FilterSettingsStorage.panelState`:

```swift
// FilterSettingsStorage
static let defaultPanelState: FilterPanelState = .alwaysShow   // was .restoreLastFilter
```

**Lưu ý**: Filter bar hiện với 1 empty row mặc định (behavior hiện tại khi toggle on).
Cần đảm bảo empty filter row không trigger query rerun.

### Tests

- Mở table lần đầu tiên → filter bar visible
- Close tab, reopen → filter bar vẫn visible
- Nếu user hide filter (Cmd+F toggle off) → persist state hidden cho table đó (behavior #1387 vẫn giữ)

---

## Open fork PR #1459 — code review & conflict resolution

> Handoff cho agent fix PR đang mở. Branch `fix/datagrid` (fork → upstream `TableProApp/TablePro`).
> Gộp 4 fix datagrid ở phần 7–10 trên thành 1 PR. **VERIFIED 2026-05-30 against main.**

### Trạng thái

| Field | Value |
|---|---|
| PR | [#1459](https://github.com/TableProApp/TablePro/pull/1459) |
| Branch | `fix/datagrid` |
| Mergeable | MERGEABLE (sạch, không conflict) |
| Blocker | Chỉ noise hunks — không có bug logic |

### Files changed (production)

| File | Thay đổi |
|---|---|
| `Core/Coordinators/FilterCoordinator.swift` | `restoreLastFilters()` / `resolvedRestoredState()`: default `isVisible = true` khi `.restoreLast` không có filter lưu; `.alwaysHide` clear + hide |
| `Models/Database/TableFilter.swift` | `TabFilterState.init(isVisible:)` default `false` |
| `Models/Query/QueryTab.swift`, `TabSession.swift` | set `filterState = TabFilterState(isVisible: tabType == .table)` |
| `Models/Query/QueryTabManager.swift` | `clearFilterState()` reset `isVisible = true` cho table op |
| `Models/UI/JSONTreeNode.swift` | `maxDisplayLength = 300` (cũ 80) |
| `Views/Main/Extensions/MainContentCoordinator+ColumnFetchScope.swift` | `executeSelectedTableTabQuery()` route qua `requeryWithColumnScope()` nếu có cột ẩn |
| `+ColumnVisibility.swift` | `rebuildSelectedTableQueryForHiddenColumnsIfNeeded()` (async) |
| `+Navigation.swift`, `+WindowLifecycle.swift` | gọi `executeSelectedTableTabQuery()` thay `runQuery()` |
| `MainContentView+Setup.swift` | gọi rebuild post-navigation |
| `Views/Results/DataGridRowView.swift` | enum `CopyContextTarget`, `copyFromContextMenu(_:)`, `focusedDataColumnIndex()` |

Tests (mới/cập nhật): `PreviewTabTests`, `JSONTreeParserTests` (cap 300 + reject 100K), `CoordinatorColumnVisibilityTests`, `FilterRestoreTests`, `MainContentCoordinatorTabSwitchTests`, `OpenTableTabTests`, `DataGridRowViewCopyTests` (cell/row/unresolved).
Docs: `CHANGELOG.md` (4 entry), `docs/features/filtering.mdx`.

### Findings (verified)

**Đúng / tốt**

- Cell copy resolve `dataColumnIndex` → `focusedDataColumnIndex()` → row. Có `guard let tableView = coordinator.tableView as? KeyHandlingTableView` (không crash).
- Hidden column restore qua `requeryWithColumnScope()` rebuild SELECT khớp visibility.
- Filter visibility: `.alwaysHide` override cả khi `current.isVisible == true` (đúng, test cover).

**Minor (không chặn merge)**

- `TabFilterState.init(isVisible:)` default `false` nhưng mọi call site truyền `tabType == .table` → default không khớp use-case phổ biến. Để nguyên (đổi default rủi ro regression không đáng).
- `JSONTreeNode.maxDisplayLength` hardcode 300, test phụ thuộc giá trị này. OK.

### Conflict analysis — chỉ noise

PR sạch (MERGEABLE). Vướng duy nhất là 2 hunk môi trường lỡ commit, đã có sẵn trên main:

- `.gitignore` — `Local.xcconfig`, `/plans/reports`, `.docs/` đã có trên main (`.gitignore:128,158-160`, VERIFIED 2026-05-30).
- `CLAUDE.md:171` "Favorite tables" row đã có trên main (VERIFIED 2026-05-30).

### Fix approach

Bỏ 2 hunk noise → verify 4 test suite pass → merge. Đây là PR ưu tiên #1 (an toàn nhất). Không sửa logic. Chi tiết checklist xem `tasks.md` § "Open PR #1459 — agent checklist".
