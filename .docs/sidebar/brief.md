# sidebar — brief

## Scope

Sidebar control bên trái: tab Tables/Favorites/etc. + nút toggle show/hide
sidebar trên toolbar + context menu trong sidebar.

## Vấn đề user nêu

### Local checklist — create table action

User muốn nút tạo table ở phía trên/sidebar top-level, không chỉ nằm trong menu
right-click table.

### Local checklist — disabled group trong context menu

Khi click chuột phải vào table, nếu toàn bộ action bên trong một group/menu bị
disabled thì parent/group cũng phải disabled hoặc không render.

### Local checklist — sidebar collapse/expand gây overflow

Khi đóng/mở sidebar, sidebar hiện ra nhưng toolbar/control không co lại như trước.
Cả window app bị tràn/che một phần UI.

### #1352 — không có favorite/recent tables

Schema lớn → tìm cùng table nhiều lần tốn thời gian. Không có:
- Mark table làm favorite
- List "recently opened tables" per connection

### #1353 — nút toggle sidebar có thêm toggle "more option"

Show/hide sidebar control include thêm 1 toggle / more-options element bên cạnh.
Không rõ phần nào toggle sidebar, phần nào toggle option khác.

## Đặc biệt với scope này

**Không có PR closing 2 issue này.** Cả 2 đều CLOSED COMPLETED nhưng:
- `closedByPullRequestsReferences == []`
- `git log --grep="1352|1353"` không tìm thấy commit

Theo `closedAt`:
- #1353 closed 2026-05-22 16:27 (trong giai đoạn datlechin merge nhiều PR sidebar/toolbar)
- #1352 closed 2026-05-25 06:46 (rất gần đây, không trùng PR nào)

Khả năng cao maintainer close vì cover bởi:
- Sidebar refactor #1308 (schema picker footer)
- Toolbar refactor #1389 (native NSSearchField switchers)
- Hoặc judge work đã đủ và "complete" theo subjective view

Issue body của #1352 tự ám chỉ: `FavoritesSidebarViewModel.swift` +
`FavoritesTabView.swift` đã có SQL favorites infrastructure; request là **extend**
tới table-level favorites + recent tables, không phải build toàn bộ favorites mới.

## Kết quả current branch

### Local checklist — create table action

- ✅ **DONE.** `SidebarView.createObjectMenu` — SwiftUI `Menu` (New Table / New View)
  với icon `plus`, gọi `coordinator?.createNewTable()` / `createView()`.
  (Không phải NSButton trong `SidebarContainerViewController` như note cũ.)
- "Create New Table..." đã rời khỏi `SidebarContextMenu` (giờ ở top-level menu).

### Local checklist — disabled group

- ✅ **DONE.** `SidebarContextMenu.maintenanceGroupEnabled(...)` (`:46`) ẩn
  `Menu("Maintenance")` khi mọi child disabled (dùng tại `:148`).

### Local checklist — sidebar overflow

- **Cần repro UI.** Source có risk rõ:
  `MainSplitViewController` đặt sidebar min 280, detail min 400, inspector min 270
  trong khi `TabWindowController.window.minSize` là 720 x 480.
- Nếu inspector + sidebar cùng mở, tổng min width vượt window min và có thể gây
  overflow/che toolbar hoặc content trên window nhỏ.

### #1352 — trạng thái authoritative (2026-05-30)

> Supersede note 2026-05-25 bên dưới.
>
> - **Favorite tables: ĐÃ trên main** qua PR #1422 (`4fad0b83`) — `FavoriteTablesStorage.swift` tồn tại. Nguồn chính thức, không phải branch `sidebar`.
> - **Recent tables: CHƯA trên main** — PR #1484 OPEN (CONFLICTING + CLA FAIL), opt-in default OFF. Xem `context.md` → "Case study PR #1484".

### #1352 — note cũ 2026-05-25 (stale, kept for history)

Trạng thái cập nhật 2026-05-25 (session sidebar-recents-star, uncommitted on branch `sidebar`):

- **Favorite tables — implemented (VERIFY-current).** `FavoriteTablesStorage` + sync mapper từ `408d1589`. `TableRow` có trailing star toggle button (filled yellow / outlined gray). `SidebarContextMenu` **không** có Add/Remove Favorite (deliberate — xem [D13](decisions.md#d13-favorite-toggle-trailing-star-button-không-context-menu)). Favorites tab có section **Tables** riêng.
- **Recent tables — implemented (VERIFY-current).** `RecentTablesStore` in-memory, cap 10 per `(connectionID, database)`. Recent render ở **đầu Tables sidebar**, không ở Favorites tab ([D12](decisions.md#d12-recent-tables-ở-đâu--tables-sidebar-not-favorites-tab)).

### #1353

- Source chưa split. `makeSidebarToggleItem` vẫn là combined Tables/Favorites toolbar
  item và show/hide đi qua `.sidebarTrackingSeparator`.
- User checklist mark item này xong; cần UI verify trước khi đổi status thành DONE.
- Nếu muốn làm tiếp: tách sidebar show/hide và sidebar mode theo D4 trong `decisions.md`.
