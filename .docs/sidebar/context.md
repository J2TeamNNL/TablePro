# sidebar — context

## Authoritative state (2026-05-30, verified vs current main)

> Supersede mọi runtime findings cũ bên dưới. Verified vs current `main`:
>
> | Feature | Trạng thái 2026-05-30 | Bằng chứng |
> |---|---|---|
> | Favorite tables | ĐÃ trên main qua **#1422** (`4fad0b83`) | `TablePro/Core/Storage/FavoriteTablesStorage.swift` tồn tại |
> | Recent tables | CHƯA trên main — PR #1484 OPEN, CONFLICTING + CLA FAIL | branch `recent-tables`, base cũ `d8adcedf` |
> | Stuck spinner fix | CHƯA trên main — PR #1460 OPEN, CONFLICTING | branch `debug/sidebar` |
>
> Lưu ý: note 2026-05-25 ("session sidebar-recents-star") mô tả uncommitted changes trên branch `sidebar` (#1352) như thể đã là source-of-truth. Thực tế favorites vào main qua #1422 (không phải branch `sidebar`), recent tables vẫn trong PR #1484 chưa merge. Giữ note cũ làm history.

## Runtime findings (2026-05-25, session sidebar-recents-star) — stale, kept for history

Uncommitted changes on branch `sidebar`:

- `Core/Storage/RecentTablesStore.swift` (new) — `@MainActor` singleton, `entriesByKey: [Key: [Entry]]`, cap = 10, key = `(connectionID, database)`. `push(...)` LRU-inserts and posts `.recentTablesDidChange`. Pure in-memory, cleared on quit. Push site is `MainContentCoordinator+Navigation.openTableTab(_ table:)`.
- `Views/Sidebar/SidebarView.swift` — adds `@State recentTables: [RecentTablesStore.Entry]`, `filteredRecents` honoring `viewModel.searchText`, and a `recentSection` rendered **before** the `SidebarObjectKind` loop. Uses `viewModel.isRecentsExpanded` (default `true`, not persisted) for the disclosure. Reload triggers: `onAppear`, `recentTablesDidChange`. Recents tag rows with `TableInfo`, so selection unifies with the main list (TableInfo equality ignores `rowCount`).
- `Views/Sidebar/TableRowView.swift` — `TableRow` body wraps the label in an `HStack`; the bottom-trailing star **overlay** is gone, replaced by a trailing `Button` with `Image(systemName: isFavorite ? "star.fill" : "star")` (yellow vs `secondary.opacity(0.55)`), `.buttonStyle(.plain)`. Pass `onToggleFavorite` to enable the button; recents and main rows both pass `FavoriteTablesStorage.shared.toggle(name)`.
- `Views/Sidebar/SidebarContextMenu.swift` — "Add/Remove from Favorites" entry removed (star button is now primary path). `selectedTables.count <= 1` branch deleted.
- `Views/Sidebar/FavoritesTabView.swift` — Recent section + helper methods (`reloadRecentTables`, `recentTableRow`, `recentTableContextMenu`, `recentNodeId`, `recentEntry`, `tableInfo(forRecent:)`) deleted. `favoritesList` now takes only `(items, filteredTables)`. `.recentTablesDidChange` observer removed.
- `ViewModels/SidebarViewModel.swift` — new `var isRecentsExpanded: Bool = true` (no persistence yet).
- `TableProTests/Storage/RecentTablesStoreTests.swift` (new) — covers push/cap/clear behavior.

Build status: Swift compiles clean (`xcodebuild ... -skipPackagePluginValidation`). Only SwiftLint plugin sandbox errors appear in environment, unrelated.

App-level docs updated in the same session: `CHANGELOG.md` "Added" entries reworded; `docs/features/favorites.mdx` rewritten — now describes star button toggle and Recent at top of Tables sidebar (not Favorites tab).

Verify-still-pending: runtime UI smoke test, unit + UI test re-run for the favorite star button path, sync (iCloud) round-trip still correct after star button change (storage API unchanged).

## Runtime findings (2026-05-25)

### Local checklist — Create Table top action — CHƯA IMPLEMENT

Source hiện tại chỉ expose create table trong right-click context menu:

- `SidebarContextMenu` có `Button("Create New Table...")`.
- `SidebarContainerViewController` chỉ đặt search field ở top sidebar.
- `SidebarView` không có header/top action trước `List`.
- `MainContentCoordinator.createNewTable()` đã là action thật, có safe-mode guard.

Nếu implement, dùng action sẵn có; không cần tạo service mới.

### Local checklist — Context menu disabled group — CHƯA IMPLEMENT

`SidebarContextMenuLogic` hiện cover visibility/disabled ở từng action. Chưa có
logic tổng hợp kiểu "all children disabled ⇒ parent/group disabled". Nếu bug liên
quan `Menu("Maintenance")`, thêm helper testable trước rồi mới đổi SwiftUI menu.

### Local checklist — Sidebar overflow — CẦN REPRO

Risk từ source:

- `window.minSize = 720 x 480`
- sidebar min 280
- detail min 400
- inspector min 270

Sidebar + detail + inspector có thể cần ~950px trước divider/inset. Nếu user mở
sidebar trên window nhỏ khi inspector đang mở, AppKit có thể squeeze detail hoặc
đẩy layout/window frame không như mong đợi.

### #1352 — Favorite/recent tables — CHƯA IMPLEMENT

**Kết quả verify code:**
- `FavoritesSidebarViewModel` và `FavoritesTabView` chỉ xử lý SQL query favorites (`SQLFavorite`), không có gì liên quan đến table-level favorites
- `TableInfo` struct không có field `isFavorite`
- `SidebarContextMenu` không có Add/Remove Table Favorite
- Không có `FavoriteTablesStorage`, `SidebarTableOrdering`, `favoriteTablesDidChange`, `tableFavorite`
- Không có `RecentTable*` / `recentTable*`

**Nếu implement:**
- Decide scope key: global table name vs `(connectionID, database, schema, table)`
- Add storage riêng; đừng nhét table favorites vào `SQLFavoriteStorage`
- Add context menu action and table row badge
- Add recent push in `openTableTab` path

**Gotcha nếu thêm Favorites tab section:** empty state hiện check `viewModel.nodes.isEmpty`
cho SQL favorites. Nếu thêm table favorites, empty state phải include table favorites
và recent tables.

### #1353 — Sidebar toggle — VERIFY

Trạng thái code 2026-05-25: `MainWindowToolbar.makeSidebarToggleItem` vẫn gộp chung
Tables/Favorites buttons trong một toolbar item. Show/hide sidebar vẫn đi qua
`.sidebarTrackingSeparator`.

User checklist đánh dấu item này đã xong, nhưng source chưa chứng minh. Cần verify
UI trước khi đổi status thành DONE.

## 2026-05-29 — PR review #1422 + recent split #1484

- Branch `sidebar` của #1422 checkout sẵn ở worktree `/Users/hangvalong/Code/TablePro-sidebar-fix` (reset về `origin/sidebar` HEAD `ee187978`). Local copy trước đó stale 35 commit.
- 2 review của datlechin trên #1422 viết từ commit cũ; branch đã thêm 35 commit fix sau đó → mọi blocker code đã giải quyết. Đừng đánh giá blocker dựa trên text review, phải verify HEAD hiện tại.
- #1484 stack lên #1422: `gh pr diff 1484` so với `main` nên hiện CẢ favorites (file ADDED) — không phải duplicate, chỉ vì base là main chứ không phải branch sidebar. Sau khi #1422 merge, diff hiệu dụng của #1484 chỉ còn delta recent tables.
- Gotcha: hook RTK nén `gh pr diff`. Lấy raw bằng `rtk proxy gh pr diff <n>`.
- Authors trên branch (origin/main..HEAD): datlechin 19, Nam Long 6, Claude 1 (`c5d72f64`), github-actions 1. Commit Claude làm CLA bot fail.
- `mergeStateStatus: UNSTABLE` = mergeable nhưng có non-required check fail (ở đây là `cla`), KHÔNG phải conflict.
