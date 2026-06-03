# sidebar — decisions

> **2 issue trong scope này không có PR linked.** D1-D5 là hypothesis trước khi
> implement. D6-D8 là decision thực tế của current branch.

## D1. Why close #1352 without an explicit feature PR?

**Hypothesis.** Maintainer judge use-case "find table fast" đã được cover bởi:

- Quick switcher (`Cmd+Shift+O` → `QuickSwitcherSheet`) tìm table theo name
- Sidebar Tables filter (input search ở top sidebar)

Hai cái này đủ ergonomic cho phần lớn schema → table favorites + recents là
nice-to-have, không gate use-case.

**Alternative interpretation.** Có một sequence commit không reference number
issue cover một phần của #1352 trước khi close. Cần `git log` chi tiết hơn để
confirm.

---

## D2. Why close #1353 without split?

**Hypothesis.** Combined `sidebarToggle` item (Tables + Favorites buttons trong 1
NSStackView) là intentional design vì:

- Tiết kiệm horizontal space trên toolbar
- Mode switch giữa Tables/Favorites trực quan hơn split 2 toolbar item

Maintainer có thể judge UX đỡ confusing sau khi:
- Active Connections đổi từ modal → popover (#1386 — same day, 2026-05-22)
- Update icon / spacing nhỏ nào đó

→ Close as "good enough, ship it".

---

## D3. Đề xuất cho favorite/recent tables — vẫn TODO

### Storage layer đề xuất

| Decision | Choice | Lý do |
|---|---|---|
| Recent persistence | In-memory (per-session) | Match D1 ở scope `connections/`: live state thuộc session |
| Favorite persistence | On-disk (UserDefaults JSON) | Persistent across restart |
| Cap recent | LRU, N=10 per (connection, db) | Sidebar không scroll dài; nhiều hơn dùng quick switcher |
| Key recent/favorite | `(connectionID, database, schema?, table)` | Match pattern PR #1387 (filter persistence) |

**Status:** chưa implement. Source review 2026-05-25 không thấy table favorite
storage, star badge, hoặc recent table store.

### View layer

Extend `FavoritesTabView` thêm section thay vì view mới:

```
┌─ Recent ─────────────┐
│ • posts             │
│ • users             │
│ • events            │
├─ Favorite Tables ────┤
│ ★ orders            │
│ ★ products          │
├─ Favorite Schemas ───┤
│ ★ public            │
└──────────────────────┘
```

---

## D4. Nếu fork split sidebar toggle (#1353)

**Chosen approach.** 2 toolbar item riêng:

- `sidebarToggle` — system `.toggleSidebar` action, 1 chevron-like icon
- `sidebarMode` — Tables/Favorites segmented control

**Risk.** Tốn thêm toolbar slot (default đã đông). Có thể overflow trên window nhỏ.

**Mitigation.** Đặt `sidebarMode` vào `toolbarAllowedItemIdentifiers` nhưng không
trong `default` → user customize toolbar add nếu cần.

---

## D6. Favorite tables — scope decision (STALE PROPOSAL, not implemented)

**Old proposal:** Global `Set<String>` — favorite theo tên table, không per-connection.

**Rationale:** Per-connection thêm complexity (composite key, migration) không tương xứng với use case. Nếu table "users" được favorite, hợp lý để highlight ở tất cả connections có table tên đó. Nếu connection không có table đó → silently ignored.

**Current source (2026-06-02):** favorites ĐÃ implement trên main (#1422) dùng **composite key** (connection + database + schema, theo `docs/features/favorites.mdx`), KHÔNG phải global `Set<String>` như proposal này. Proposal D6 lỗi thời.

---

## D7. Favorite tables — storage proposal (STALE PROPOSAL, not implemented)

**Old proposal:** Singleton class (không phải actor) lưu `Set<String>` JSON vào
UserDefaults key `"com.TablePro.favoriteTables"`. Notification
`favoriteTablesDidChange` khi mutation.

**Files expected if implemented:**
| File | Thay đổi |
|------|---------|
| `Core/Storage/FavoriteTablesStorage.swift` | Mới — storage singleton |
| `Views/Sidebar/SidebarContextMenu.swift` | Thêm "Add/Remove from Favorites" sau "Copy Name" |
| `Views/Sidebar/TableRowView.swift` | Thêm `isFavorite: Bool = false` + star badge vàng |
| `Views/Sidebar/SidebarView.swift` | `@State favoriteTables`, `onReceive`, `sortedByFavorite()` |
| `Views/Sidebar/FavoritesTabView.swift` | Section "Tables" + Section "Queries" khi có cả hai |
| `docs/features/sql-favorites.mdx` | Đổi title → "Favorites", thêm section Table Favorites |

**Current source (2026-06-02):** favorites ĐÃ trên main (#1422) — `FavoriteTablesStorage.swift`, `TableRowView` star button, `SidebarView` wiring. Proposal D7 (UserDefaults `Set<String>`) lỗi thời; actual storage khác.

---

## D8. Favorite tables — iCloud Sync record (STALE PROPOSAL, not implemented)

**Old proposal:** New `SyncRecordType.tableFavorite = "FavoriteTable"` with deterministic
record name `FavoriteTable_<sha256(tableName)>`.

**Rationale:** Favorite is a set-membership record. Deterministic ID makes add/remove
idempotent across devices and allows tombstone deletes without storing extra local
UUIDs.

**Trade-off:** Table names sync when iCloud Sync is enabled; there is no separate
per-category toggle. This matches docs/UI wording added in this branch. If table
names are considered sensitive later, add `syncTableFavorites` to `SyncSettings`.

**Current source (2026-06-02):** favorites iCloud sync ĐÃ trên main (#1422) — `docs/features/favorites.mdx` xác nhận "sync through iCloud". Chi tiết record-type xem code sync; proposal D8 chỉ là phác thảo ban đầu.

---

## D9. Top-level Create Table action — preferred placement (TODO)

**Context.** User wants create/insert new table visible near the top, not hidden in
right-click table context menu.

**Options.**

- (a) Add SwiftUI button above `SidebarView.tableList`
- (b) Add native AppKit action next to sidebar search in `SidebarContainerViewController`
- (c) Add toolbar item only

**Recommended.** (b) if the action belongs to sidebar browsing, because the current
top chrome (`NSSearchField`) already lives in `SidebarContainerViewController` and
keeps search/action layout independent from list state. Reuse
`MainContentCoordinator.createNewTable()`.

**Guard.** Disable when `safeModeLevel.blocksAllWrites`.

---

## D10. Context menu group disabled rule (TODO)

**Context.** A parent menu/group should not look enabled when every actionable child
inside it is disabled.

**Recommended.** Add pure helpers to `SidebarContextMenuLogic` and cover them in
`SidebarContextMenuLogicTests` before changing SwiftUI body. Keep conditions local:
selection, object type, safe mode, plugin capability.

**Why.** This file already uses extracted logic for read-only kind and visibility.
Extending the same helper avoids scattering `.disabled(...)` formulas in the view.

---

## D11. Sidebar min-size / overflow mitigation (TODO-investigate)

**Context.** Current minimum widths can exceed the window minimum when sidebar and
inspector are both visible.

**Options.**

- (a) Increase `window.minSize` based on visible pane set
- (b) Lower sidebar/inspector min widths
- (c) Auto-collapse inspector before opening sidebar when window is too narrow
- (d) Let detail pane become smaller

**Recommended next step.** Reproduce with screenshots first. If the bug is true
layout overflow, prefer (a) plus targeted (b); avoid (d) because data grid/editor
need a usable minimum width.

---

## D12. Recent tables: ở đâu — Tables sidebar (not Favorites tab)

**Context.** Issue #1352 ám chỉ Favorites tab có thể host cả Tables + Recent + Queries. Initial implementation (FavoritesTabView trên commit `408d1589`) đã đặt Recent trong Favorites tab.

**Chosen 2026-05-25 (session sidebar-recents-star).** Move Recent ra **đầu Tables sidebar**. Favorites tab gọn lại còn 2 group: Tables + Queries.

**Why.**

- Recent là điều user vừa làm trên Tables tab — đặt cùng nơi giảm context switch.
- Favorites tab thiên về "things I bookmarked"; Recent là history, ngữ nghĩa khác.
- Match TablePlus / Sequel Ace pattern.

**Implementation note.** `recentSection` đứng trước `ForEach(SidebarObjectKind.allCases)`. Tag rows bằng `TableInfo` để selection chung; search filter qua `viewModel.searchText`.

**Trade-off.** Tables sidebar dài thêm khi user mới mở vài bảng. Mitigation: `viewModel.isRecentsExpanded` cho phép collapse; section ẩn khi `filteredRecents.isEmpty`.

---

## D13. Favorite toggle: trailing star **button**, không context menu

**Context.** User explicit (2026-05-25): "tiện đánh dấu Favorites thay vì phải ghi vào context menu". Trước đó vào Favorites cần right-click → Add to Favorites.

**Chosen.** `TableRow` luôn render trailing star button. Filled yellow khi favorite, outlined `.secondary.opacity(0.55)` khi không. Click toggle qua `FavoriteTablesStorage.shared.toggle(name)`. Context-menu entry "Add/Remove from Favorites" bỏ.

**Why outline luôn-luôn-visible thay vì hover-only.**

- Discoverability cao hơn: user không phải biết hover để mark favorite.
- Sidebar list không có hover-state native consistent trên macOS (`List(.sidebar)` không expose row-hover hook); làm hover-only sẽ phải bridge AppKit tracking area, không xứng tradeoff.

**Trade-off.** Mỗi row có thêm 1 element luôn render. Outline star màu nhạt nên visual noise thấp.

**Accessibility.** Button có `.help(...)` và `.accessibilityLabel(...)` đổi theo trạng thái favorite. Vẫn giữ `TableRowLogic.accessibilityLabel(...)` cho row label tổng hợp.

---

## D14. Recent tables — `(connectionID, database)` key, not include schema

**Context.** D3 (proposal) gợi key `(connectionID, database, schema?, table)`.

**Chosen.** `RecentTablesStore.Key = (connectionID: UUID, database: String)`. Schema lưu **trong Entry**, không trong key.

**Why.** User thường switch database (Postgres / MySQL multi-db), không switch schema. Key per-database đủ phân biệt. Schema trong entry để phục hồi đúng `TableInfo` khi reopen.

**Cap = 10** theo D3.

---

## D5. Document trạng thái current-best-guess

**Chosen.** Vì không có PR linked, document file `context.md` rõ ràng đây là
reverse-engineer + hypothesis, không phải authoritative source. Người đọc kiểm
chứng với `git blame` hoặc hỏi maintainer trước khi build feature dựa trên doc
này.

## 2026-05-29 — Tách recent tables sang PR riêng (opt-in, default off)

**Quyết định.** Gỡ recent tables khỏi #1422 (commit `4b764520`), tách sang #1484 với setting `Show recent tables` default **OFF**.

**Lý do.** #1422 gộp 3 feature (favorites + recent + sidebar UX) làm review nặng; review yêu cầu tách. Recent tables là in-memory, ít rủi ro data, hợp để review riêng. Default off để không đổi hành vi sidebar mặc định cho user hiện tại.

**Trade-off.** #1484 stack lên #1422 → phải đợi #1422 merge rồi rebase. Đổi lại mỗi PR review gọn, blocker favorites tách bạch khỏi recent.

## 2026-05-29 — Hoãn fix CLA blocker (force-push)

**Quyết định.** Chưa re-author commit `c5d72f64` (đứng tên `Claude <noreply@anthropic.com>`) trong session này. User trả lời "không sao".

**Lý do.** Fix CLA cần rewrite history + force-push branch `sidebar` — branch dùng chung, có 19 commit của datlechin. Force-push ảnh hưởng local của maintainer khác → cần phối hợp, không tự ý làm.

**Mở.** Khi muốn merge #1422: re-author `c5d72f64` → `Nguyễn Nam Long <j2teamnnl@gmail.com>` (đã ký CLA), `git push --force-with-lease`, hoặc dùng cơ chế allowlist bot nếu repo hỗ trợ.

---

## 2026-05-30 — Reconcile: #1422 là nguồn favorites trên main, không phải #1352

**Context.** Note cũ (2026-05-25/05-29) trong folder ghi `FavoriteTablesStorage`/`RecentTablesStore` đã tồn tại trên branch `sidebar` (#1352). Verified 2026-05-30 vs current main.

**Sự thật.** `TablePro/Core/Storage/FavoriteTablesStorage.swift` vào main qua **PR #1422** (merge commit `4fad0b83` — "feat(sidebar): add favorite tables with iCloud sync"). Recent tables CHƯA vào main, vẫn ở PR #1484 OPEN.

**Quyết định.** Các note cũ giữ lại làm history nhưng được supersede bằng date-stamp 2026-05-30. Mọi trạng thái authoritative tính theo current main.

---

## D-1460. PR #1460 — reuse `generations` sẵn có, không thêm dict thứ 2

**Context.** PR #1460 (branch `debug/sidebar`, CONFLICTING) fix stuck spinner bằng cách thêm `loadGenerations`/`nextLoadGeneration: [UUID:Int]`. Nhưng main đã có `generations` (`SchemaService.swift:21`), `generationToken(for:)` (`:23-24`), `bumpGeneration()` (`:27-28`, 13 callsite).

**Chosen.** Xoá dict thứ 2 khỏi diff; hook generation guard vào `generationToken(for:)`/`bumpGeneration()` sẵn có.

**Why.** Dict thứ 2 = 2 nguồn sự thật, vi phạm DRY. `bumpGeneration` đã gọi đúng chỗ → không có rủi ro regression.

**Bắt buộc giữ.** (1) Catch-block reset state `.idle` khi load fail — đây là fix cốt lõi chống spinner kẹt. (2) Test deterministic `AsyncGate` + `BlockingAuxiliaryDriver` — không flaky, đừng thay bằng poll.

**Trade-off.** ~10-20 dòng refactor; đổi lại 1 cơ chế generation duy nhất.

---

## D-1484. PR #1484 — rebase-rescue vs rewrite-clean (mở cho owner)

**Context.** Branch `recent-tables` base cũ `d8adcedf` (trước #1422/#1473/#1483). Sau khi gỡ duplicate favorites (#1422) và resolve conflict với #1473/#1483, delta thực chỉ còn ~5-6 file (~200 dòng). `SidebarView.swift` bị #1473 (database tree) thay đổi rất nhiều.

**Option A — Rebase-rescue.** Giữ branch, `git rebase upstream/main`, resolve conflict từng file (THEIRS cho tree/perf; manual cho `SidebarView`/Navigation).
- Lợi: giữ commit history + context review, cùng PR number #1484.
- Rủi: `SidebarView` conflict phức tạp (PR xoá `usesDatabaseTree`, main thêm database tree branch logic).

**Option B — Rewrite-clean.** Checkout main, branch mới, cherry-pick chỉ `RecentTablesStore.swift` + tests + `GeneralSettings` delta + setting toggle + 1 dòng `push()` trong Navigation. Viết lại recent section trong `SidebarView` từ main (~200 dòng).
- Lợi: diff sạch, review dễ, không kéo theo conflict ngược.
- Rủi: mất commit history gốc, PR number mới.

**Khuyến nghị.** Nếu rebase tạo > 3 file cần merge thủ công phức tạp (đặc biệt `SidebarView`), chọn Option B — delta nhỏ, rewrite nhanh hơn resolve conflict dây chuyền. **Owner quyết định trước khi bắt đầu tasks.md mục 1.**

---

## D-1484b. Merge order — #1489 trước #1484

**Context.** #1489 (keyboard function keys) sửa `Localizable.xcstrings` + `CHANGELOG.md` — đúng 2 file #1484 cũng cần.

**Chosen.** Merge #1489 trước, rồi #1484.

**Why.** Tránh tạo conflict thừa cho #1489 nếu #1484 chạm 2 file đó trước.

**Trade-off.** #1484 delay thêm, đổi lại mỗi PR review/merge gọn.

---

## D-1484c. CLA bắt buộc, không bypass

**Context.** Check `cla` của #1484 đang FAIL.

**Chosen.** Ký CLA bằng tài khoản GitHub của author trước khi push. Không bypass.

**Why.** Upstream yêu cầu CLA cho mọi contributor; code đúng cũng không merge được nếu CLA fail.
