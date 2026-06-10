# datagrid — decisions

## D1. Cmd+C target selection visible cụ thể nhất

**Context.** Cmd+C cũ luôn copy row dù focus border ở cell. FK cell không có
keyboard path để copy value vì double-click mở popover.

**Options.**
- (a) Thêm modifier mới cho cell-copy
- (b) Cmd+C luôn copy cell, row qua menu
- (c) **Context-aware: cell nếu focus, row nếu không (Cmd+Shift+C = explicit row)** ✓

**Chosen.** (c) — match Apple HIG, DataGrip/DBeaver/Postico/Sequel Ace/MySQL Workbench.
TablePlus dùng `Cmd+Shift+C` cho explicit-rows → align cùng.

**Consequence.** "Copy with Headers" mất default shortcut (giữ trong menu).

---

## D2. Native AppKit responder chain + SwiftUI action fallback

**Context.** Sau #1337, action có thể silent lost nếu focus rời grid (text field
khác active trong khi row selection vẫn còn). `NSApp.sendAction` trả false → drop.

**Options.**
- (a) Bỏ responder chain, gọi action trực tiếp như pre-#1337
- (b) **Responder chain ưu tiên, SwiftUI action fallback khi sendAction == false** ✓
- (c) Refactor cả app sang DI dispatch

**Chosen.** (b) — không bỏ native pattern (AppKit `validateUserInterfaceItem` guard vẫn
hoạt động), không refactor lớn. Fallback chỉ cho `.copyRows`; `.copyCellValue` không
cần (chỉ fire khi grid là active emphasized responder).

---

## D3. Active Connections: popover thay vì add close button (#1350)

> Note: liên quan scope `toolbar/` — chi tiết đầy đủ ở `toolbar/decisions.md`. Ghi
> ở đây vì tương đồng với pattern "wrong primitive, not missing button" áp dụng
> cho filter persistence và JSON viewer.

---

## D4. Truncation ở render layer, không SQL layer

**Context.** `ColumnExclusionPolicy` truncate text columns server-side qua
`SUBSTRING(col, 1, 256) AS col`. Edit + save → ghi value 256-char đè giá trị thật.
BLOB đã refuse pattern này, text thì không (inconsistent).

**Options.**
- (a) Mark column "partial" + refuse write back (như BLOB path đã làm)
- (b) **Bỏ SUBSTRING, fetch full value, truncate ở render** ✓
- (c) Keep truncation, add validation prevent save

**Chosen.** (b) — pattern của TablePlus/DataGrip/DBeaver. Loại bỏ data corruption
risk hoàn toàn, không cần thêm guard. Xoá 6 files, ~180 LOC.

**Consequence.** Large text column transfer full → có thể chậm cho bảng có
LONGTEXT — mitigation: hide column qua #1375 → omit khỏi SELECT.

---

## D5. Hide = drop from SELECT (thay vì cosmetic)

**Context.** User feedback (#1352 và variations): table với 1 column nặng mở rất
chậm. Trước đây hide chỉ ẩn UI, query vẫn fetch.

**Options.**
- (a) Cosmetic hide only (status quo)
- (b) Separate "exclude from fetch" toggle khác với "hide"
- (c) **Hide = drop từ SELECT; PK luôn fetch** ✓ (đề xuất bởi user trong issue
  comment: "why not based on column visibility?")

**Chosen.** (c) — single concept, không thêm UI surface. PK always-fetch giữ row
identity + UPDATE work. Visibility popover list **full schema**, không phải
fetched result → omitted column vẫn toggle back được.

**Consequence (PR nêu rõ).** Hide/show không còn instant cosmetic toggle — re-run
query (debounced).

---

## D6. JSON formatter scalar-level parser (preserve key order + bigint)

**Context.** `JSONSerialization.sortedKeys` reorder key + coerce number qua
`NSNumber` (round bigint > 2^53). Cho event-store JSONB everywhere, "view" trở
thành destructive.

**Options.**
- (a) Disable reformat / readonly mode chỉ cho JSON
- (b) **Scalar-level parser + reindenter, byte-copy keys + number tokens** ✓
- (c) Wrap qua external lib (e.g. swift-syntax)

**Chosen.** (b) — `JsonSyntaxParser` + `JsonReindenter` parse + format ở scalar
level, copy keys/number tokens/string contents byte-for-byte. Cap 500 KB. Idempotent.
Invalid JSON passthrough unchanged. Top-level primitives supported.

**Consequence.** `MultiRowEditState.updateField` semantic compare:
`normalize(new) == normalize(original)` cho JSON field → reformat ≠ change.
Cached `isJson` flag (true cả cho text column trông giống JSON).

---

## D7. Filter restore key = `(connection + database + schema + table)`

**Context.** Latent bug: cùng `tableName` ở 2 connection collide. Invisible khi
restoration off (default), nhưng turning ON default sẽ lộ cross-connection leak.

**Options.**
- (a) Keep `tableName` key + connection guard ở caller
- (b) **Composite key persist** ✓ + migration script xoá file cũ
- (c) Disable cross-connection restoration

**Chosen.** (b) — fix lỗi root + cho phép default ON. Migration upgrade user
"Always Hide" → "Restore Last Filter" và xoá file key cũ.

---

## D8. User-clear vs internal-reset (clearFiltersAndReload vs clearFilterState)

**Context.** PR #1395 follow-up #1387. Symmetric: user clear cũng phải persist.
NHƯNG có 2 site clear filter — phải chọn đúng.

| Site | Khi nào | Persist? |
|---|---|---|
| `clearFiltersAndReload()` | User bấm Unset | **YES — xoá file** |
| `clearFilterState()` | Internal: tab switch / replace | **NO — outgoing tab phải save trước** |

**Chosen.** Place `clearLastFilters(for:)` ở `clearFiltersAndReload()`. Đặt nhầm
ở `clearFilterState()` sẽ wrongly xoá filter user muốn restored.

---

## D9. CompletionEngine cho raw SQL filter (không hand-rolled matcher)

**Context.** `FilterValueTextField` whole-string matcher đúng cho per-column
value field (case ban đầu) nhưng sai cho multi-token WHERE.

**Options.**
- (a) Patch matcher hỗ trợ multi-token
- (b) **Drive qua `CompletionEngine` sẵn có** (SQL editor đang dùng) ✓
- (c) New parser riêng cho filter

**Chosen.** (b) — raw filter execute là `... WHERE (<rawSQL>)` nên complete chính
xác query nó denotes. Engine cho token extraction, clause detection, string-literal
suppression, ranking, replacement range. `FilterCompletionSource` enum để value
field path không đổi.

**Consequence.** Custom dropdown kept (consistent với per-column value field) —
chỉ data source change.

---

## D10. Bỏ noise `.gitignore`/`CLAUDE.md` khỏi PR #1459 (open PR)

**Context.** Branch `fix/datagrid` lỡ commit hunk `.gitignore` (`Local.xcconfig`,
`/plans/reports`, `.docs/`) và `CLAUDE.md:171` "Favorite tables" — cả 2 đã có sẵn
trên main (VERIFIED 2026-05-30).

**Options.**
- (a) Giữ hunk → conflict/noise vô nghĩa
- (b) **Reset 2 file về upstream trong branch** ✓

**Chosen.** (b). `git checkout upstream/main -- .gitignore`. Đây là gỡ commit môi
trường lỡ tay, không trade-off.

---

## D11. Giữ 4 fix trong 1 PR #1459 (không tách)

**Context.** PR gộp 4 fix datagrid độc lập (context menu copy, hidden columns new
tab, JSON popover cap, filter bar default).

**Options.**
- (a) Tách thành 4 PR nhỏ
- (b) **Giữ gộp** ✓

**Chosen.** (b) — đều nhỏ, cùng scope datagrid, test đầy đủ, đang MERGEABLE. Tách
giờ tốn công vô ích (YAGNI).

---

## D12. Delete hành xử theo nguồn selection thống nhất (gridSelection + rows)

**Context.** `delete(_:)` và `validateUserInterfaceItem` (KeyHandlingTableView.swift:223,281)
chỉ đọc `selectedRowIndexes` (row-selection của NSTableView). Chọn bằng cell-range
(gridSelection) → `selectedRowIndexes` rỗng → Delete bị disable + no-op, phải chuột
phải. `copy()` (dòng 229) đã đọc `gridSelection` trước rồi fallback rows nên copy đúng.

**Options.**
- (a) Sync gridSelection → selectedRowIndexes mọi lúc (rủi ro side-effect UI selection)
- (b) **`delete` + validate đọc `gridSelection.affectedRows` nếu non-empty, fallback `selectedRowIndexes`** ✓ (đối xứng `copy()`)

**Chosen.** (b): tái dùng đúng mẫu `copy()` (D1/D2). Một nguồn xóa thống nhất cũng
sửa luôn case chuột phải.

**Consequence.** Chuột phải Delete: `menu(for:)` (dòng 538) đang thay selection = dòng
click trước khi mở menu → chỉ thay khi dòng click CHƯA nằm trong selection hiện có
(chuẩn NSTableView/Finder). Sửa cùng commit.

---

## D13. Filter panel: 1 Apply + Clear (un-apply) + tri-state check-all

**Context.** 3 cơ chế "dòng nào tham gia" chồng nhau (checkbox enable, Apply-all header,
Apply-solo per-row) → khó hiểu. "Unset" gọi `clearFilterState()` xóa sạch `state.filters`
(FilterCoordinator.swift:414) thay vì chỉ bỏ filter đang áp.

**Options.**
- (a) Giữ nguyên, chỉ đổi label
- (b) **1 Apply (header); solo → context menu; "Unset"→"Clear" gọi `clearAppliedFilters()` (commit=nil, giữ rows); checkbox tri-state đầu cột bật/tắt tất cả; "Remove all filters" vào menu …** ✓

**Chosen.** (b): owner chốt. `clearAppliedFilters()` (dòng 304) đã có sẵn. Tri-state theo
chuẩn macOS select-all (owner chọn thay 2 nút). Canh width picker cột/toán tử thẳng
hàng; ô value đồng nhất style; 1 nền + divider mảnh (bỏ banding).

**Consequence.** Hành vi destructive (xóa hết rows) chuyển vào menu, có chủ đích.
Không đổi semantics `clearFilterState`/`clearAppliedFilters` (D8 vẫn đúng). Cập nhật
docs/features + UI test.

---

## D14. Refresh (⌘R): re-run xác định 1 lần, giữ filter/sort/page

**Context.** ⌘R → `handleRefreshData` (MainContentCommandActions.swift:912) chạy 2 việc:
`handleRefresh()` (reload grid chỉ khi `.table`) + `refreshTables()` (luôn reload
sidebar). `handleRefresh` (+Refresh.swift:45) `currentQueryTask?.cancel()` rồi
`runQuery()` ngay; nhưng `runQuery`/`executeTableTabQueryDirectly`/`executeQueryInternal`
(780/854/1034) đều mở đầu `guard !tab.execution.isExecuting`. Cancel async, cờ chưa
reset → bail → grid không reload. `rebuildTableQuery` chỉ giữ WHERE khi `hasAppliedFilters`
→ nếu reload base-query thắng thì mất filter.

**Options.**
- (a) Bỏ guard `isExecuting` ở path refresh (rủi ro chạy chồng query)
- (b) **Reset execution state đồng bộ (hoặc await hủy task) trước re-run; rebuild theo `appliedFilters`; chạy đúng 1 reload; không để base-query đè** ✓
- (c) Gộp handleRefresh + refreshTables thành 1 pipeline có thứ tự

**Chosen.** (b), cân nhắc (c) khi implement. CẦN build + OSLog repro để chốt đúng nhánh
nào bail / reload nào thắng trước khi sửa (không kết luận khi chưa chạy thật).

**Consequence.** Query tab vẫn KHÔNG auto re-run trên Refresh (giữ chủ ý maintainer,
comment +Refresh.swift:33). Chỉ sửa table tab.

---

## D15. Port fix autocomplete EDITOR sang FilterValueTextField (phase 2)

**Context.** D9 đã đưa raw filter qua CompletionEngine. Nhưng lỗi behavior (popup luôn
hiện; Enter chèn rác do range stale) đã fix ở EDITOR (#1601 replace-whole-word qua
SQLTokenBoundary; #1611 filter-in-place) mà `FilterValueTextField` (path riêng) chưa
nhận: `presentSuggestions` gọi vô điều kiện; `spliceTokenCompletion` fail thầm khi
`latestReplacementRange` stale.

**Options.**
- (a) Viết lại logic filter riêng
- (b) **Tái dùng SQLTokenBoundary + filter-in-place của editor cho filter** ✓

**Chosen.** (b): cùng nguồn chân lý với editor, tránh phân kỳ lần 3. Phase 2 (sau 3
fix datagrid trên), vì medium và đụng async completion.
