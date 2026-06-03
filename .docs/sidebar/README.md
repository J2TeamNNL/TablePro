# sidebar — README

> ⚠️ **Scope đặc biệt: không có PR linked.** Đây là **reverse-engineer + hypothesis**
> từ code hiện tại và issue body, KHÔNG phải case-study từ diff PR như các scope khác.

## Items (verified vs main 2026-06-02)

1. **Top-level Create Table action** — ✅ DONE. `SidebarView.createObjectMenu` (SwiftUI `Menu`: New Table / New View, icon `plus`).
2. **Context menu disabled grouping** — ✅ DONE. `SidebarContextMenu.maintenanceGroupEnabled(...)` (`:46`, `:148`).
3. **Sidebar collapse/expand overflow** — ⏳ OPEN (RIGHT inspector pane). Xem [`../inspector/`](../inspector/README.md).
4. **Favorite tables** (#1352) — ✅ DONE trên main qua #1422 (star button + `FavoriteTablesStorage`). **Recent tables** — ⏳ PR #1484 OPEN (opt-in, chưa main).
5. **Sidebar toggle bundles confusing extra option** (#1353) — ⛔ SKIPPED (user quyết). Source vẫn combined Tables/Favorites.

## Files

- [`brief.md`](brief.md) — vấn đề + tại sao scope này đặc biệt
- [`context.md`](context.md) — bảng trạng thái verified vs main + case-study PR #1460/#1484 + runtime findings (history)
- [`flow.md`](flow.md) — Mermaid: combined control hiện tại + local TODO flows + favorite/recent proposal
- [`tasks.md`](tasks.md) — file pointers + verify commands
- [`decisions.md`](decisions.md) — ADR hypothesis-based + stale proposals clearly marked
- [`changelog.md`](changelog.md) — timeline closing + review corrections

## Trạng thái authoritative (2026-05-30, verified vs current main)

> Supersede block "Branch `sidebar` đã implement #1352" bên dưới.

| Item | Trạng thái 2026-05-30 |
|---|---|
| Favorite tables | ĐÃ trên main qua **#1422** (`4fad0b83`), không phải branch `sidebar`/#1352 |
| Recent tables (#1484) | OPEN — CONFLICTING + CLA FAIL. Rebase để drop duplicate favorites; merge sau #1489 |
| Stuck spinner (#1460) | ✅ **MERGED 2026-05-29** vào upstream/main. Branch `debug/sidebar` xoá được. Review dưới giữ làm lịch sử |

Chi tiết review 2 PR: xem `context.md` → "Case study PR #1460" + "Case study PR #1484"; checklist: `tasks.md`; quyết định: `decisions.md` (D-1460, D-1484).

## Trạng thái (note cũ — stale, kept for history)

**Branch `sidebar` đã implement #1352** (favorite + recent tables). Uncommitted thay đổi 2026-05-25 (session sidebar-recents-star):

- Recent section đã chuyển từ Favorites tab → **đầu Tables sidebar** ([D12](decisions.md#d12-recent-tables-ở-đâu--tables-sidebar-not-favorites-tab)).
- Favorites tab gọn còn 2 group: **Tables** + **Queries**.
- `TableRow` có trailing star **button** (toggle nhanh) thay cho overlay star badge ([D13](decisions.md#d13-favorite-toggle-trailing-star-button-không-context-menu)).
- "Add/Remove from Favorites" bỏ khỏi `SidebarContextMenu` — star button là path duy nhất.
- `RecentTablesStore` in-memory cap 10 per `(connection, database)` ([D14](decisions.md#d14-recent-tables--connectionid-database-key-not-include-schema)).

Cho dev/AI sau đọc folder này:

- Favorite + Recent tables: implemented, **VERIFY-current** (cần runtime smoke test + re-run unit/UI tests). D6-D8 là proposal cũ; current implementation theo D12-D14.
- Top-level Create Table: vẫn chưa implement; xem `tasks.md`.
- Context menu disabled grouping: vẫn chưa implement; xem `tasks.md`.
- Sidebar overflow khi collapse/expand: cần repro UI; xem `context.md`.
- Sidebar toggle split (#1353): source vẫn chưa split; xem D4 nếu muốn làm tiếp.
- Verify trạng thái current bằng commands trong `tasks.md` § "Verify khi cần".
