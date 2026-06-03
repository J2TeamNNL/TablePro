# sidebar — tasks

| Item | Issue | PR linked | Current status | Source note |
|---|---|---|---|---|
| Top-level Create Table button | Local checklist | — | ✅ DONE (verified 2026-06-02) | `SidebarView.createObjectMenu` — SwiftUI `Menu` (New Table / New View), icon `plus`, gọi `coordinator?.createNewTable()`/`createView()`. "Create New Table..." đã rời `SidebarContextMenu`. (KHÔNG phải NSButton trong `SidebarContainerViewController`.) |
| Disable parent/group khi mọi child disabled | Local checklist | — | DONE-2026-05-25 | `SidebarContextMenuLogic.maintenanceGroupEnabled(isReadOnly:hasSelection:supportedOperations:)` thêm. `Menu("Maintenance")` ẩn khi helper trả false. Tests: `SidebarContextMenuLogicTests`. |
| Inspector pane overflow (RIGHT panel) | Local checklist | — | OPEN — needs verify | User confirmed 2026-05-27: RIGHT inspector panel toggle vẫn gây window overflow. Xem [`.docs/inspector/`](../inspector/README.md). `recomputeWindowMinSize()` có thể chưa được gọi đúng chỗ trong inspector toggle path. |
| Favorite tables | [#1352](https://github.com/TableProApp/TablePro/issues/1352) | [#1422](https://github.com/TableProApp/TablePro/pull/1422) | ✅ MERGED 2026-05-29 | Squash-merge `4fad0b83` vào main. CLA đã ký (`J2TeamNNL`). Review `datlechin`: 3 feature trong 1 PR (favorites + iCloud sync, recent tables in-memory, sidebar UX: plus button, dynamic window min, conditional Maintenance menu), split hợp lý, test coverage trên value layer tốt. Recent tables sau đó tách ra #1484. Tất cả review blocker (B1-B5) đã fix ở HEAD `ee187978` trước merge. Branch `sidebar` xoá được. |
| Recent tables | [#1352](https://github.com/TableProApp/TablePro/issues/1352) | [#1484](https://github.com/TableProApp/TablePro/pull/1484) | OPEN — CONFLICTING + CLA FAIL (verified 2026-05-30) | **Supersede SPLIT-OUT note cũ.** PR #1484 (branch `recent-tables`, base cũ `d8adcedf`) vẫn OPEN. Setting `General > Sidebar > Show recent tables` default **OFF**; gate render (`SidebarView`) + ghi (`MainContentCoordinator+Navigation`). Conflict NẶNG: #1422 (favorites trùng → `FavoriteTablesStorage.swift` đã trên main), #1473 (database tree, PR muốn xoá nhầm), #1483 (perf schema). Diff thực vs main 57 files / 910 ins / 1932 del. CLA chưa ký. Merge sau #1489. Checklist ↓. |
| Sidebar toggle bundles confusing extra option | [#1353](https://github.com/TableProApp/TablePro/issues/1353) | **không có** | SKIPPED | User quyết định bỏ qua (2026-05-25). |
| Table list spinner stays after preview loads | — | [#1460](https://github.com/TableProApp/TablePro/pull/1460) | ✅ MERGED 2026-05-29 | Đã vào upstream/main. Branch `debug/sidebar` xoá được. Note review (loadGenerations vs `generations` sẵn có) giữ làm lịch sử — không còn task. |
| ER Diagram — context menu entry | Local checklist | — | ✅ present (verified 2026-06-02) | `SidebarContextMenu.swift:121` `Button("View ER Diagram")` → `showERDiagram()` (FULL schema, no param). Tên vẫn "View ER Diagram" (note "đổi → Show ER Diagram" là sai). Focused-diagram variant chỉ ở branch `er-diagram`, chưa main. |

## Agent checklist — PR #1460 (stuck spinner)

### Setup
- [ ] Worktree từ branch: `git worktree add ../TablePro-pr1460 debug/sidebar`.
- [ ] `git fetch upstream && git rebase upstream/main`.

### Gỡ noise
- [ ] `.gitignore`: `git checkout upstream/main -- .gitignore` (entry đã có `.gitignore:128,158-160`).
- [ ] `CLAUDE.md`: `git checkout upstream/main -- CLAUDE.md` ("Favorite tables" row đã có `CLAUDE.md:171`).

### Refactor cấu trúc (bắt buộc — gộp vào `generations` sẵn có)
- [ ] Mở `TablePro/Core/Services/Query/SchemaService.swift`.
- [ ] Xoá khai báo `loadGenerations: [UUID:Int]` + `nextLoadGeneration: [UUID:Int]` khỏi diff.
- [ ] Mỗi phase sau await: thay `loadGenerations[id] == token` → `generationToken(for: connectionId) == capturedToken`. Pattern: `let capturedToken = generationToken(for: connectionId)` trước await; `guard generationToken(for: connectionId) == capturedToken else { return }` sau await.
- [ ] Kick-off load mới: dùng `bumpGeneration(connectionId)` đã có (`:119,126,148,164,205,245,253,278,287,333,358,366`); kiểm tra PR có miss callsite nào không.
- [ ] GIỮ catch-block reset `.idle` — KHÔNG xoá.
- [ ] GIỮ test `AsyncGate` + `BlockingAuxiliaryDriver` trong `SchemaServiceRoutinesTests.swift`.

### Verify + ship
- [ ] Build: `xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation`.
- [ ] `-only-testing:TableProTests/SchemaServiceRoutinesTests`.
- [ ] `swiftlint lint --strict`.
- [ ] Push, confirm conflict resolved + CI pass.

## Agent checklist — PR #1484 (recent tables, opt-in)

> Đọc D-1484 (rebase vs rewrite) trong decisions.md trước. Merge SAU #1489.

### 0. Đánh giá trước
- [ ] `git diff HEAD origin/recent-tables --stat` (57 files / 910 ins / 1932 del).
- [ ] Confirm `FavoriteTablesStorage.swift` diff = 0 vs main (đã trên main qua #1422).
- [ ] Quyết định **rebase-rescue** hay **rewrite-clean** (D-1484). Nếu rewrite → bỏ mục 1-3, đi thẳng mục 4.

### 1. Rebase
- [ ] `git worktree add ../TablePro-pr1484 origin/recent-tables`.
- [ ] `git fetch upstream && git rebase upstream/main`.

### 2. Resolve conflict
- [ ] Sau rebase: confirm `FavoriteTablesStorage.swift` **không còn** trong diff.
- [ ] THEIRS (giữ main) cho: `DatabaseTreeView.swift`, `DatabaseTreeMetadataService.swift`, `MetadataConnectionPool.swift`, `MetadataLoadState.swift`, `DatabaseTreeSelectionTests.swift` (thuộc #1473).
- [ ] THEIRS (giữ main) cho: `SchemaService.swift`, `QueryExecutor.swift`, `SQLSchemaProvider.swift`, `DatabaseManager+Metadata.swift` (thuộc #1483).
- [ ] THEIRS cho `FavoritesTabView.swift`, `TableRowView.swift`, `SidebarContextMenu.swift` (bản mới từ #1422/#1473).
- [ ] Manual `SidebarView.swift`: base = main; thêm `@State recentTables`, recent section, render gated bởi `showRecentTables`. (SidebarView bị #1473 đổi nhiều → cân nhắc rewrite ~200 dòng.)
- [ ] Manual `MainContentCoordinator+Navigation.swift`: base = main; thêm DUY NHẤT 1 dòng `RecentTablesStore.shared.push(...)`.

### 3. Gỡ noise
- [ ] `git checkout upstream/main -- .gitignore CLAUDE.md`.
- [ ] `project.pbxproj`: chỉ giữ ref `RecentTablesStore.swift`, `RecentTablesStoreTests.swift`, `GeneralSettingsTests.swift`; bỏ ref files đã trên main.
- [ ] `Localizable.xcstrings`: giữ key "Recent"/"Recent Tables", bỏ key #1473 mà PR muốn xoá. (Merge sau #1489.)
- [ ] `CHANGELOG.md`: giữ entry recent-tables, bỏ phần PR xoá entries #1473/#1483.

### 4. CLA + build + ship
- [ ] Ký CLA bằng tài khoản GitHub của author; confirm check `cla` pass.
- [ ] Build (lệnh như #1460).
- [ ] `-only-testing:TableProTests/RecentTablesStoreTests`, `-only-testing:TableProTests/GeneralSettingsTests`, `-only-testing:TableProTests/SidebarViewModelTests`.
- [ ] `swiftlint lint --strict`.
- [ ] Push, confirm MERGEABLE. Merge SAU #1489.

### Không cần làm
- [ ] Không sửa `MainSplitViewController.swift` (window min-size fix đã trên main qua #1422).
- [ ] Không đụng `FavoriteTablesStorage.swift` (để rebase drop duplicate).
- [ ] Không đụng `DatabaseTreeView.swift` + metadata services (thuộc #1473).

## ⚠️ Đặc biệt: không có closing PR

`gh issue view ... --json closedByPullRequestsReferences` trả `[]` cho cả 2 issues.
`git log --grep="1352|1353"` không match commit nào trên `upstream/main`.

Khả năng:

1. Maintainer (datlechin) judge issue đã được cover bởi PR refactor lớn không
   reference number issue (e.g. sidebar refactor #1308 schema picker, toolbar
   #1389 NSSearchField) → close manual với stateReason=COMPLETED.
2. Một số code path đã có sẵn (`FavoritesSidebarViewModel.swift`,
   `FavoritesTabView.swift`) — issue mô tả request **extend** existing infra,
   không phải build mới.

## Code pointer (do issue body trích)

### Cho #1352

- [`TablePro/Views/Sidebar/SidebarContextMenu.swift`](../../TablePro/Views/Sidebar/SidebarContextMenu.swift) — no Add/Remove Table Favorite action.
- [`TablePro/Views/Sidebar/SidebarView.swift`](../../TablePro/Views/Sidebar/SidebarView.swift) — no favorite state / table pinning.
- [`TablePro/Views/Sidebar/TableRowView.swift`](../../TablePro/Views/Sidebar/TableRowView.swift) — no star badge / `isFavorite`.
- [`TablePro/Views/Sidebar/FavoritesTabView.swift`](../../TablePro/Views/Sidebar/FavoritesTabView.swift) — SQL favorites only.
- [`TablePro/ViewModels/FavoritesSidebarViewModel.swift`](../../TablePro/ViewModels/FavoritesSidebarViewModel.swift) — `FavoriteNode` model for SQL favorites / folders, not tables.

### Cho #1353

- [`TablePro/Core/Services/Infrastructure/MainWindowToolbar.swift`](../../TablePro/Core/Services/Infrastructure/MainWindowToolbar.swift) — `makeSidebarToggleItem` build container 2 button (Tables/Favorites tag 0/1) + sidebar show/hide flag, gộp chung làm user confused
- [`TablePro/Core/Services/Infrastructure/MainSplitViewController.swift`](../../TablePro/Core/Services/Infrastructure/MainSplitViewController.swift) — `.toggleSidebar` handler
- Issue request: split combined control → 1 sidebar toggle riêng + extra options ở control labeled rõ

### Cho local checklist mới

- [`TablePro/Core/Services/Infrastructure/SidebarContainerViewController.swift`](../../TablePro/Core/Services/Infrastructure/SidebarContainerViewController.swift) — top area hiện chỉ có `NSSearchField`; nơi hợp lý để thêm top create action nếu muốn native AppKit header.
- [`TablePro/Views/Sidebar/SidebarView.swift`](../../TablePro/Views/Sidebar/SidebarView.swift) — nếu muốn SwiftUI header/list action thay vì AppKit header.
- [`TablePro/Views/Sidebar/SidebarContextMenu.swift`](../../TablePro/Views/Sidebar/SidebarContextMenu.swift) — current right-click menu; cần group-level disabled helper.
- [`TablePro/Views/Main/Extensions/MainContentCoordinator+SidebarActions.swift`](../../TablePro/Views/Main/Extensions/MainContentCoordinator+SidebarActions.swift) — `createNewTable()` action đã có và safe-mode guard.
- [`TablePro/Core/Services/Infrastructure/MainSplitViewController.swift`](../../TablePro/Core/Services/Infrastructure/MainSplitViewController.swift) — sidebar/detail/inspector minimum widths.
- [`TablePro/Core/Services/Infrastructure/TabWindowController.swift`](../../TablePro/Core/Services/Infrastructure/TabWindowController.swift) — `window.minSize = 720 x 480`.

## Verify khi cần

Để check state hiện tại của 2 feature:

```bash
# Favorite tables: tìm code đã implement
rg "FavoriteTablesStorage|tableFavorite|SidebarTableOrdering|favoriteTablesDidChange" TablePro TableProTests

# Recent tables: xác nhận chưa implement
rg "RecentTable|recentTable" TablePro TableProTests

# Sidebar toggle UI: xác nhận đã split hay chưa
rg "makeSidebarToggleItem|sidebarButtons" TablePro/Core/Services/Infrastructure/MainWindowToolbar.swift

# Top-level Create Table: xác nhận chưa có visible button/header
rg "Create New Table|createNewTable|SidebarContainerViewController" TablePro/Views/Sidebar TablePro/Core/Services/Infrastructure

# Context menu group disabled helper
rg "SidebarContextMenuLogic|all.*disabled|is.*Group.*Enabled" TablePro/Views/Sidebar TableProTests

# Sidebar min-size risk
rg "minimumThickness|window.minSize|sidebarSplitItem|inspectorSplitItem" TablePro/Core/Services/Infrastructure
```

Lần cuối check (verified 2026-06-02 vs main):

- ✅ `FavoriteTablesStorage.swift` đã có. `TableRowView` trailing star toggle button (`isFavorite`/`onToggleFavorite` `:47-48,:81`); wire tại `SidebarView.swift:306,404-405`.
- ❌ `RecentTablesStore` **CHƯA** trên main — vẫn ở PR #1484 OPEN (note cũ ghi ✅ là sai).
- ✅ Top-level create: `SidebarView.createObjectMenu` (New Table / New View). "Create New Table..." rời khỏi `SidebarContextMenu`.
- ✅ `SidebarContextMenu.maintenanceGroupEnabled` (`:46`,`:148`) ẩn `Menu("Maintenance")` khi mọi child disabled.
- ✅ #1353 SKIPPED theo quyết định của user (vẫn combined Tables/Favorites).
- ❌ Inspector pane overflow chưa fix — xem [`../inspector/`](../inspector/README.md).
