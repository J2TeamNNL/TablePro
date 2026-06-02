# sidebar — content

> **Lưu ý.** 2 issue trong scope này CLOSED COMPLETED nhưng không có PR linked.
> Content dưới là **reverse-engineer từ code hiện tại + issue body**, không phải
> từ diff PR như các scope khác.

## 0. Local checklist review 2026-05-25

### 0.1 Top-level Create Table action

User request: hiển thị nút create/insert new table ở phía trên, không chỉ trong
menu chuột phải vào table.

Current source:

```
TablePro/Core/Services/Infrastructure/SidebarContainerViewController.swift
TablePro/Views/Sidebar/SidebarView.swift
TablePro/Views/Sidebar/SidebarContextMenu.swift
TablePro/Views/Main/Extensions/MainContentCoordinator+SidebarActions.swift
```

Findings:

- `SidebarContainerViewController.loadView()` chỉ tạo `NSSearchField` và hosted
  sidebar view. Không có top action row/button.
- `SidebarView.tablesContent` render loading/error/empty/list; không có create
  button trước list.
- `SidebarContextMenu` có `Button("Create New Table...")` ở đầu context menu.
- `MainContentCoordinator.createNewTable()` đã có action thật và respect safe mode.

Conclusion: **TODO-fork.** Action backend đã có, entry point visible/top-level chưa có.

### 0.2 Disable parent/group khi toàn bộ children disabled

User request: khi right-click table, nếu toàn bộ action bên trong bị disabled thì
disable cả nút/menu parent.

Current source:

- `SidebarContextMenuLogic` có helper cho `hasSelection`, `isReadOnlyKind`,
  `importVisible`, `truncateVisible`, `deleteLabel`.
- `SidebarContextMenu` apply `.disabled(...)` từng button.
- Không có helper kiểu `isCreateGroupEnabled`, `isWriteOperationsGroupEnabled`,
  hoặc "all actions disabled ⇒ group disabled".

Conclusion: **TODO-fork.** Cần define group-level rule trước khi sửa UI. Nếu giữ
SwiftUI `Menu`, parent phải `.disabled(children.allSatisfy(\.isDisabled))`; nếu chỉ
là flat context menu thì nên hide divider/group rỗng để tránh menu nhìn enabled
nhưng không có action.

### 0.3 Sidebar collapse/expand làm window/control bị tràn

User report: đóng/mở sidebar làm sidebar hiện ra nhưng nút/control không co lại;
cả window app tràn ra và che một phần UI.

Current source:

```swift
// TabWindowController
window.minSize = NSSize(width: 720, height: 480)

// MainSplitViewController
sidebarSplitItem.minimumThickness = 280
detailSplitItem.minimumThickness = 400
inspectorSplitItem.minimumThickness = 270
```

Risk:

- Sidebar + detail = 680, gần bằng min width 720, chưa tính divider/toolbar/content
  inset.
- Sidebar + detail + inspector = 950, vượt min width 720.
- `detailSplitItem.holdingPriority = .defaultLow`; nếu sidebar/inspector reclaim
  space ở window nhỏ, detail có thể bị squeeze hoặc window frame/layout drift.

Conclusion: **OPEN (user confirmed 2026-05-27).** Cụ thể: RIGHT inspector panel (không phải
left sidebar). Toggle inspector gây window overflow và che nút. Xem [`.docs/inspector/`](../inspector/README.md)
để implement `recomputeWindowMinSize()`. Cần verify `MainSplitViewController` inspector toggle
path có gọi đủ 4 call sites không.

Candidate fix: `recomputeWindowMinSize()` phải được gọi trong:
- `showInspector()`, `hideInspector()` — inspector toggle
- `splitViewDidResizeSubviews()` — resize
- `viewWillAppear()` — initial layout

## 0.4 Table list spinner stays after preview loads (OPEN — 2026-05-27)

### Symptom

Load tables: preview table content hiển thị đúng nhưng spinner trong sidebar table
list vẫn xoay. User muốn: khi trạng thái này xảy ra, có debug log visible trong
một toggle/dropdown để diagnose.

### Root cause (hypothesis)

Spinner state trong sidebar (`SidebarViewModel.isLoadingTables` hoặc tương tự)
được set khi bắt đầu fetch table list, nhưng không được clear khi:
- Table preview resolve trước table list
- Table list fetch bị stuck/timeout nhưng không có error state

### Fix approach

1. Investigate: tìm nơi sidebar spinner được set `true` và điều kiện clear về `false`.
2. Đảm bảo spinner clear trên cả 2 path: success và error/timeout.
3. Thêm debug logging visible trong app (collapsible debug section trong sidebar khi
   `DEBUG` build): hiển thị trạng thái fetch (loading/loaded/failed) và timestamp.

### Investigate

```bash
rg "isLoadingTables|isLoading.*table|tableListState|spinnerVisible" TablePro/Views/Sidebar TablePro/ViewModels
```

---

## Open fork PR #1460 — stuck spinner sau khi table list load (CONFLICTING, 2026-05-30)

> Verified 2026-05-30 vs current `main`. **Supersede** mọi note cũ ghi #1460 là `DONE-fork`: PR vẫn OPEN, GitHub báo **CONFLICTING**.

| Field | Value |
|---|---|
| PR | [#1460](https://github.com/TableProApp/TablePro/pull/1460) |
| Branch | `debug/sidebar` |
| Mergeable | CONFLICTING (conflict logic thật, không chỉ text) |
| CLA | ok |

### Root cause

Spinner kẹt vì stale load-generation guard trong `SchemaService.runLoad` catch block: khi cả load cũ lẫn load mới đều bị abandon, `states[connectionId]` kẹt ở `.loading`, state machine không quay về `.idle` → spinner xoay mãi.

### Findings (file:line vs main)

| Vấn đề | Bằng chứng |
|---|---|
| PR thêm dict thứ 2 song song | PR thêm `loadGenerations: [UUID:Int]` + `nextLoadGeneration: [UUID:Int]` |
| Main ĐÃ có cơ chế tương đương | `SchemaService.swift:21` `generations: [UUID:Int]`, `:23-24` `generationToken(for:)`, `:27-28` `bumpGeneration()` (`&+= 1`) |
| `bumpGeneration` đã gọi 13 callsite | `SchemaService.swift:119,126,148,164,205,245,253,278,287,333,358,366` |

→ Dict thứ 2 = 2 nguồn sự thật, vi phạm DRY (verified `rg` 2026-05-30).

### Conflict analysis

PR `debug/sidebar` chưa rebase lên main mới → conflict cấu trúc tại `SchemaService.swift`. Ngoài ra dính noise chung (xem cuối file).

### Fix approach

1. Gỡ noise `.gitignore` + `CLAUDE.md` (xem mục "Noise chung").
2. Xoá `loadGenerations`/`nextLoadGeneration` khỏi diff. Hook guard vào API sẵn có:
   - Trước await: `let capturedToken = generationToken(for: connectionId)`.
   - Sau await: `guard generationToken(for: connectionId) == capturedToken else { return }`.
   - Tại kick-off load mới: dùng `bumpGeneration(connectionId)` đã có (không tự thêm callsite nếu đã đủ).
3. **GIỮ** catch-block reset `.idle` — đây là fix cốt lõi chống spinner kẹt, không được xoá.
4. **GIỮ** test deterministic `AsyncGate` + `BlockingAuxiliaryDriver` (3 gate `tablesGate`/`routinesGate`/`schemasGate`, test chính `tableStateLoadsBeforeAuxiliaryMetadata()`) trong `TableProTests/Services/SchemaServiceRoutinesTests.swift` — không flaky, đừng thay bằng poll.

Minor không chặn merge: generation check chỉ guard bỏ qua write, không cancel Task đang bay (chấp nhận được).

---

## Open fork PR #1484 — recent tables section (opt-in) (CONFLICTING + CLA FAIL, 2026-05-30)

> Verified 2026-05-30 vs current `main`. **Supersede** note cũ (2026-05-25/05-29) ghi `RecentTablesStore`/`FavoriteTablesStorage` đã tồn tại trên branch `sidebar`. Thực tế: `FavoriteTablesStorage` vào main qua **#1422** (merge commit `4fad0b83`), KHÔNG qua branch `sidebar`/#1352; recent tables vẫn nằm trong PR #1484 OPEN.

| Field | Value |
|---|---|
| PR | [#1484](https://github.com/TableProApp/TablePro/pull/1484) |
| Branch | `recent-tables` (base cũ `d8adcedf`) |
| Mergeable | CONFLICTING NẶNG |
| CLA | FAIL — cần ký |
| Diff thực vs main | 57 files, 910 ins / 1932 del (phần lớn là conflict ngược) |

### Findings (file:line)

`FavoriteTablesStorage.swift` ĐÃ trên main: `TablePro/Core/Storage/FavoriteTablesStorage.swift` (verified tồn tại 2026-05-30). Branch `recent-tables` re-add file giống 100% → **DUPLICATE**.

Delta recent-tables thật cần giữ:

| File | Trạng thái | Ghi chú |
|---|---|---|
| `TablePro/Core/Storage/RecentTablesStore.swift` | MỚI | `@MainActor` singleton, cap 10, session-only, key `(connectionID, database?)` |
| `TablePro/Models/Settings/GeneralSettings.swift` | SỬA | `showRecentTables: Bool = false` (opt-in, default OFF) + `decodeIfPresent` |
| `TablePro/Views/Settings/GeneralSettingsView.swift` | SỬA | Toggle "Show recent tables" trong General > Sidebar |
| `TablePro/Views/Sidebar/SidebarView.swift` | SỬA | `@State recentTables`, recent section, render gated bởi `showRecentTables` |
| `TablePro/Views/Main/Extensions/MainContentCoordinator+Navigation.swift` | SỬA | 1 dòng `RecentTablesStore.shared.push(...)` sau khi mở table tab |
| `TableProTests/Storage/RecentTablesStoreTests.swift` | MỚI | push front, dedup, cap 10, clear, clearAll |
| `TableProTests/Models/GeneralSettingsTests.swift` | MỚI | decode round-trip `showRecentTables` |

### Conflict analysis (3 PR merge sau base cũ)

| PR | Merge commit | Conflict với #1484 | Hành động |
|---|---|---|---|
| #1422 favorites + iCloud sync | `4fad0b83` | `FavoriteTablesStorage` + sync mappers/tests TRÙNG | Rebase → diff tự về 0, không xoá tay |
| #1473 database tree | `634c3cb7` | PR (base cũ) muốn XOÁ `DatabaseTreeView.swift`, `DatabaseTreeMetadataService.swift`, `MetadataConnectionPool.swift`, `MetadataLoadState.swift`, `DatabaseTreeSelectionTests.swift` | Giữ THEIRS (main) — không xoá |
| #1483 perf schema introspection | `e1d88fbc` | PR có bản cũ `SchemaService`/`QueryExecutor`/`SQLSchemaProvider`; PR xoá `DatabaseManager+Metadata.swift` (main giữ) | Giữ THEIRS (main) |

`MainSplitViewController.swift` trên branch = giống 100% main (window min-size fix đã vào qua #1422) → không đụng. Window overflow để `.docs/inspector/` lo.

### Fix approach (xem D-1484 trong decisions.md cho rebase vs rewrite)

1. **Merge order**: làm #1489 (keyboard function keys) TRƯỚC để ổn định `Localizable.xcstrings` + `CHANGELOG.md` rồi mới #1484.
2. Rebase `recent-tables` lên `upstream/main` → duplicate favorites drop khỏi diff.
3. Resolve conflict theo bảng trên (THEIRS cho tree/perf; manual cho `SidebarView`/Navigation).
4. Ký CLA (bắt buộc, không bypass).
5. Giữ ONLY delta recent-tables. `SidebarView.swift` bị #1473 thay đổi nhiều → cân nhắc rewrite ~200 dòng từ main thay vì resolve conflict dây chuyền (D-1484).

---

## Noise chung — bỏ khỏi CẢ #1460 lẫn #1484

| Noise | Đã có sẵn trên main |
|---|---|
| `.gitignore` hunk (`.docs/`, `Local.xcconfig`, `/plans/reports`) | `.gitignore:128,158,159,160` |
| `CLAUDE.md` "Favorite tables" row | `CLAUDE.md:171` (verified 2026-05-30) |

Reset: `git checkout upstream/main -- .gitignore CLAUDE.md`.

---

## 1. Favorite tables + Recent tables (#1352)

### Symptom (issue body)

- Schema lớn không có cách mark table thường xuyên xài làm favorite
- Không có list "tables vừa mở" để quick-jump lại

### Code current branch

```
TablePro/Views/Sidebar/SidebarContextMenu.swift
TablePro/Views/Sidebar/SidebarView.swift
TablePro/Views/Sidebar/TableRowView.swift
TablePro/Views/Sidebar/FavoritesTabView.swift
TablePro/ViewModels/FavoritesSidebarViewModel.swift
TablePro/Core/Storage/SQLFavoriteStorage.swift
```

### Current status (supersede 2026-05-30)

> Note 2026-05-30: section "not implemented" bên dưới là review 2026-05-25 và đã LẠC HẬU. Trạng thái đúng theo current `main`:
> - **Favorite tables ĐÃ vào main** qua PR #1422 (merge `4fad0b83`): `TablePro/Core/Storage/FavoriteTablesStorage.swift` tồn tại. Đây là nguồn chính thức của table favorites, KHÔNG phải branch `sidebar`/#1352.
> - **Recent tables CHƯA vào main** — vẫn nằm trong PR #1484 OPEN (CONFLICTING). Xem "Open fork PR #1484" ở trên.

### Source review 2026-05-25 (stale — kept for history)

Source review 2026-05-25:

- `rg "FavoriteTablesStorage|favoriteTablesDidChange|tableFavorite|SidebarTableOrdering|isFavorite" TablePro TableProTests` → no match.
- `TableRowView` has no star badge and no `isFavorite` parameter.
- `SidebarContextMenu` has no Add/Remove Table Favorite action.
- `FavoritesTabView` renders `FavoriteNode` values backed by SQL favorites and
  linked SQL files, not table names.
- No `RecentTable*` / `recentTable*` symbol exists.

### If fork wants full #1352

- Add table favorite storage separate from `SQLFavoriteStorage`.
- Add context menu action on table rows.
- Add star badge/pinning in `TableRowView` / `SidebarView`.
- Add section in `FavoritesTabView` for table favorites.
- Add `RecentTablesStore` and push entries from table-open path.
- Decide whether key should be global table name or `(connection, database, schema, table)`.

---

## 2. Sidebar toggle bundles confusing extra option (#1353)

### Symptom (issue body)

Show/hide sidebar control include thêm 1 toggle / more-options element. User
không rõ phần nào toggle sidebar, phần nào extra option.

### Code hiện tại

`MainWindowToolbar.swift:234` — `makeSidebarToggleItem(...)`:

```swift
fileprivate func makeSidebarToggleItem(coordinator: MainContentCoordinator) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: Self.sidebarToggle)
    item.label = String(localized: "Sidebar")
    item.paletteLabel = String(localized: "Sidebar")

    let container = NSStackView()
    container.orientation = .horizontal
    container.spacing = 2

    let tablesButton = makeSidebarNSButton(
        icon: "list.bullet",
        label: String(localized: "Tables"),
        tag: 0
    )
    let favoritesButton = makeSidebarNSButton(
        icon: "star",
        label: String(localized: "Favorites"),
        tag: 1
    )

    container.addArrangedSubview(tablesButton)
    container.addArrangedSubview(favoritesButton)

    sidebarButtons = [tablesButton, favoritesButton]
    item.view = container
    // ...
}
```

→ Đây chính là combined control mà issue mô tả. **Nó vẫn ở code hiện tại** (chưa
split).

Lưu ý: KHÔNG có button "toggle show/hide" trong `container` này. Show/hide đi qua
`.sidebarTrackingSeparator` + `MainSplitViewController` (`.toggleSidebar` system).

Có thể user nhầm:
- 2 button Tables/Favorites trong toolbar item này
- + sidebar collapse/expand chevron bên trong sidebar (do `NSSplitViewController` add)
- → 3 control gộp lại = "confusing"

### Hypothesis về "COMPLETED"

Issue close 2026-05-22 16:27. Trùng khoảng PR #1386 (`refactor(toolbar): Active
Connections popover`) merge 2026-05-22 13:41 — không touch sidebar trực tiếp,
nhưng maintainer có thể judge UX đã đỡ confusing đủ.

Hoặc close như deliberate design decision: 2 button Tables/Favorites là intentional,
không đổi.

### Nếu fork muốn split

```swift
// Tách thành 2 toolbar item
static let sidebarToggle = ...           // chỉ system .toggleSidebar
static let sidebarMode   = ...           // riêng cho Tables/Favorites tag-0/tag-1

func toolbarDefaultItemIdentifiers(...) -> [NSToolbarItem.Identifier] {
    [
        Self.sidebarToggle,
        Self.sidebarMode,
        .sidebarTrackingSeparator,
        // ...
    ]
}
```

`sidebarToggle` đổi item.view sang `NSToolbarItem` với action `#selector(toggleSidebar:)`
trên responder chain (NSSplitViewController handle).

`sidebarMode` giữ container hiện tại với Tables/Favorites button.
