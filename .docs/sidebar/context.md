# sidebar — context

> **Scope đặc biệt.** Phần lớn item KHÔNG có PR linked — reverse-engineer từ code + issue body, không phải case-study từ diff PR. Bảng trạng thái dưới đã **verify vs current main 2026-06-02** (branch `feat/function-key-shortcuts` ≈ origin/main + keyboard).

## Trạng thái hiện tại (verified vs main 2026-06-02)

| Feature | Trạng thái | Bằng chứng (file:line) |
|---|---|---|
| Favorite tables (storage + star button) | ✅ **DONE trên main** (#1422, `4fad0b83`) | `TablePro/Core/Storage/FavoriteTablesStorage.swift`; `TableRowView` `isFavorite`/`onToggleFavorite` (`:47-48,:81`); `SidebarView.swift:306,404-405`. End-user docs: `docs/features/favorites.mdx` (scope = connection+database+schema, iCloud sync) |
| Top-level create object | ✅ **DONE** | SwiftUI `createObjectMenu` trong `SidebarView.swift` — `Menu` (New Table / New View) icon `plus`. KHÔNG phải NSButton trong `SidebarContainerViewController` |
| Context-menu disabled group | ✅ **DONE** | `SidebarContextMenu.swift:46` `maintenanceGroupEnabled(...)`, dùng tại `:148` (`Menu("Maintenance")` ẩn khi false) |
| Stuck spinner sau preview | ✅ **DONE trên main** (#1460 merged 2026-05-29) | `SchemaService.swift` `generations` (`:21`), `generationToken(for:)` (`:23`), `bumpGeneration` (`:27`); catch-block reset `.idle` (`:276`) |
| Recent tables | ⏳ **CHƯA trên main** — PR [#1484](https://github.com/TableProApp/TablePro/pull/1484) OPEN (CONFLICTING + CLA FAIL), opt-in default OFF | `RecentTablesStore` / `showRecentTables` absent khỏi code |
| Sidebar toggle split (#1353) | ⛔ **SKIPPED** (user quyết 2026-05-25) — vẫn combined Tables/Favorites | `MainWindowToolbar.swift:233` `makeSidebarToggleItem`, `:256` `sidebarButtons` |
| Inspector overflow (RIGHT pane) | ⏳ **OPEN** — xem [`../inspector/`](../inspector/README.md) | cần `recomputeWindowMinSize()` |
| ER focused diagram (right-click table) | ⏳ **branch-only** (`er-diagram` `60509a12`), CHƯA main | entry vẫn "View ER Diagram" → `showERDiagram()` full schema (`SidebarContextMenu.swift:121`) |

> Note 2026-05-25 ("session sidebar-recents-star") mô tả favorites/recent như uncommitted-on-branch là **LẠC HẬU**: favorites đã vào main qua #1422; recent vẫn ở PR #1484. Các section runtime cũ giữ ở cuối làm history.

---

## Case study — PR #1460 stuck spinner (MERGED 2026-05-29)

| Field | Value |
|---|---|
| PR | [#1460](https://github.com/TableProApp/TablePro/pull/1460) — branch `debug/sidebar` |
| Trạng thái | ✅ MERGED vào upstream/main. Review dưới giữ làm lịch sử |

**Root cause.** Spinner kẹt vì stale load-generation guard trong `SchemaService.runLoad` catch block: khi cả load cũ lẫn mới bị abandon, `states[connectionId]` kẹt `.loading`, không quay về `.idle`.

**Fix cốt lõi (đã trên main).** (1) Catch-block reset `.idle` (`SchemaService.swift:276`). (2) Cơ chế generation đơn nhất: `generations` (`:21`) + `generationToken(for:)` (`:23`) + `bumpGeneration()` (`:27`) — KHÔNG nhân đôi thành `loadGenerations`/`nextLoadGeneration` (vi phạm DRY). (3) Test deterministic `AsyncGate` + `BlockingAuxiliaryDriver` trong `SchemaServiceRoutinesTests.swift` (không poll, không flaky).

---

## Case study — PR #1484 recent tables (OPEN, opt-in)

| Field | Value |
|---|---|
| PR | [#1484](https://github.com/TableProApp/TablePro/pull/1484) — branch `recent-tables` (base cũ `d8adcedf`) |
| Mergeable | CONFLICTING NẶNG; CLA FAIL |
| Diff vs main | 57 files, 910 ins / 1932 del (phần lớn conflict ngược) |

**Delta thật cần giữ** (sau khi rebase drop duplicate favorites của #1422):

| File | Trạng thái | Ghi chú |
|---|---|---|
| `TablePro/Core/Storage/RecentTablesStore.swift` | MỚI | `@MainActor` singleton, cap 10, session-only, key `(connectionID, database)` |
| `TablePro/Models/Settings/GeneralSettings.swift` | SỬA | `showRecentTables: Bool = false` (opt-in) + `decodeIfPresent` |
| `TablePro/Views/Settings/GeneralSettingsView.swift` | SỬA | Toggle "Show recent tables" (General > Sidebar) |
| `TablePro/Views/Sidebar/SidebarView.swift` | SỬA | `@State recentTables`, recent section trước `SidebarObjectKind` loop, gated bởi `showRecentTables` |
| `TablePro/Views/Main/Extensions/MainContentCoordinator+Navigation.swift` | SỬA | 1 dòng `RecentTablesStore.shared.push(...)` sau khi mở table tab |
| `TableProTests/Storage/RecentTablesStoreTests.swift` | MỚI | push front, dedup, cap 10, clear |
| `TableProTests/Models/GeneralSettingsTests.swift` | MỚI | decode round-trip `showRecentTables` |

**Conflict (3 PR merge sau base cũ).** #1422 favorites trùng (`FavoriteTablesStorage.swift` đã main) → rebase tự drop. #1473 database tree → giữ THEIRS (PR muốn xoá nhầm `DatabaseTreeView`/`DatabaseTreeMetadataService`/`MetadataConnectionPool`/`MetadataLoadState`). #1483 perf schema → giữ THEIRS. `SidebarView.swift` bị #1473 đổi nhiều → cân nhắc rewrite ~200 dòng từ main (xem D-1484). Merge SAU #1489.

---

## Noise chung — bỏ khỏi mọi PR fork

| Noise | Đã có sẵn trên main |
|---|---|
| `.gitignore` hunk (`.docs/`, `Local.xcconfig`, `/plans/reports`) | `.gitignore:128,158-160` |
| `CLAUDE.md` "Favorite tables" row | đã trên main |

Reset: `git checkout upstream/main -- .gitignore CLAUDE.md`.

---

## #1352 — Favorite + Recent tables

**Symptom (issue body).** Schema lớn không mark được table favorite; không có list "tables vừa mở".

**Trạng thái (verified vs main).**
- **Favorite tables ĐÃ vào main** qua PR #1422 (`4fad0b83`), KHÔNG qua branch `sidebar`/#1352. Star button trong `TableRowView` (toggle qua `FavoriteTablesStorage.shared.toggle`), Favorites tab có section Tables riêng. End-user docs `docs/features/favorites.mdx` đã mô tả.
- **Recent tables CHƯA vào main** — PR #1484 (ở trên).

---

## #1353 — Sidebar toggle combined control (SKIPPED)

**Symptom.** Show/hide sidebar control gộp thêm element gây rối.

**Code hiện tại.** `MainWindowToolbar.makeSidebarToggleItem` (`:233`) build `NSStackView` chứa 2 button Tables/Favorites (tag 0/1), `sidebarButtons = [...]` (`:256`). Show/hide sidebar đi qua `.sidebarTrackingSeparator` + `MainSplitViewController` (system `.toggleSidebar`) — KHÔNG có button toggle trong stack này. User có thể nhầm: 2 button Tables/Favorites + chevron collapse của `NSSplitViewController`.

**Quyết định: SKIPPED** (user, 2026-05-25). Nếu muốn split sau: xem D4 (tách `sidebarToggle` system + `sidebarMode` segmented).

---

## Runtime findings (2026-05-25, session sidebar-recents-star) — stale, kept for history

> Mô tả uncommitted changes trên branch `sidebar` như source-of-truth. Thực tế favorites vào main qua #1422 (không phải branch này); recent vẫn ở PR #1484. Giữ làm history.

- `Core/Storage/RecentTablesStore.swift` (new) — `@MainActor` singleton, cap 10, key `(connectionID, database)`, post `.recentTablesDidChange`. Push site `MainContentCoordinator+Navigation.openTableTab`.
- `SidebarView.swift` — `@State recentTables`, `filteredRecents`, `recentSection` trước `SidebarObjectKind` loop; `isRecentsExpanded` default true (không persist).
- `TableRowView.swift` — trailing star **button** thay overlay badge; `star.fill` vàng / `star` `secondary.opacity(0.55)`.
- `SidebarContextMenu.swift` — bỏ "Add/Remove from Favorites" (star button là path chính).
- `FavoritesTabView.swift` — bỏ Recent section, còn `(items, filteredTables)`.

## Runtime findings (2026-05-25) — local checklist (stale labels, verify lại ở bảng trên)

- **Create Table top action** — note cũ ghi "CHƯA IMPLEMENT". **Sai vs main**: đã có `createObjectMenu` trong `SidebarView.swift`.
- **Context-menu disabled group** — note cũ ghi "CHƯA IMPLEMENT". **Sai vs main**: `maintenanceGroupEnabled` đã có.
- **Sidebar overflow** — RIGHT inspector panel, OPEN; xem `../inspector/`.

## 2026-05-29 — PR review #1422 + recent split #1484 (history)

- Branch `sidebar` của #1422 từng checkout ở worktree `/Users/hangvalong/Code/TablePro-sidebar-fix` (reset `origin/sidebar` `ee187978`).
- Review datlechin trên #1422 viết từ commit cũ; branch thêm 35 commit fix sau → verify HEAD, đừng đánh giá blocker theo text review cũ.
- `gh pr diff 1484` so với main hiện CẢ favorites (base là main) — không phải duplicate. Raw diff: `rtk proxy gh pr diff <n>` (hook RTK nén output).
- `mergeStateStatus: UNSTABLE` = mergeable nhưng non-required check fail (cla), KHÔNG phải conflict.
