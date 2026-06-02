# sidebar — changelog

## 2026-05-30 — Reconcile trạng thái 2 open PR vs current main

Verified vs current `main` (supersede note cũ trong folder):

- **#1422 (favorites) đã merge vào main** (commit `4fad0b83`). `TablePro/Core/Storage/FavoriteTablesStorage.swift` tồn tại. Đây là nguồn favorites chính thức, KHÔNG phải branch `sidebar`/#1352.
- **#1460 đã MERGED 2026-05-29** vào upstream/main. Review trước merge từng ghi CONFLICTING + góp ý reuse `generations` thay vì thêm `loadGenerations`; maintainer/author đã giải quyết và merge. Giữ note làm lịch sử.
- **#1484 vẫn OPEN — CONFLICTING + CLA FAIL.** Branch `recent-tables` re-add `FavoriteTablesStorage.swift` (duplicate vs #1422) → rebase để drop. Conflict thêm với #1473 (database tree) + #1483 (perf schema). Delta thực ~200 dòng. Merge sau #1489.
- Merge order: #1489 → #1484. (#1460 đã merged.)
- Noise chung bỏ khỏi cả 2 PR: `.gitignore:128,158-160` + `CLAUDE.md:171` (đã có trên main).

## 2026-05-29 — PR review #1422 + recent tables split to #1484

Branch `sidebar` ([PR #1422](https://github.com/TableProApp/TablePro/pull/1422)) verify lại 2 round review của datlechin. Branch đã thêm 35 commit sau review, nên blocker đã fix hết ở HEAD hiện tại (`ee187978`):

- B1 sync gating — `syncTableFavorites` toggle thêm vào `SyncSettings` (decode backward-compatible), gate đủ ở push/clear/tombstone/apply trong `SyncCoordinator` (dòng 307/332/360/451). ✅
- B2 "View ER Diagram" — không bị gỡ, chỉ đổi tên "Show ER Diagram", vẫn còn trong `SidebarContextMenu`. ✅
- B3 stale strings — diff vs `main` chỉ còn 2 flag hợp lệ ("Create New Table...", "Syncs connections..."); 7 entry lạ đã dọn. (`%lld of %lld` stale là có sẵn trên main.) ✅
- B4 UI test/CLAUDE.md — phần sửa rule UI-test đã bỏ; CLAUDE.md chỉ còn +1 dòng storage row. ✅
- B5 merge conflict — merge `main` sạch, GitHub báo `MERGEABLE`. ✅

Recent tables **đã gỡ khỏi #1422** ở commit `4b764520`, tách sang [PR #1484](https://github.com/TableProApp/TablePro/pull/1484) "recent tables (opt-in)" (stack lên #1422, đợi merge trước). #1484 thêm setting `General > Sidebar > Show recent tables` default OFF; gate cả render (`SidebarView`) lẫn ghi (`MainContentCoordinator+Navigation`); recent rows dùng `.selectionDisabled()` (hết duplicate List tag); `RecentTablesStore.Key.database: String?` + convert `""`→`nil` (hết collision SQLite). Còn minor chưa fix: `entryId(name:schema:)` trùng logic `Entry.id`; `clearAll()` test coverage.

Chặn merge duy nhất của #1422 (lúc đó): check **`cla` FAIL** — commit `c5d72f64` ("address PR review blockers") do `Claude <noreply@anthropic.com>` đứng tên, bot CLA coi là committer thứ 2 chưa ký.

> **Resolved 2026-05-29**: PR #1422 đã **MERGED** (squash `4fad0b83`). CLA pass (`J2TeamNNL` đã comment ký). Blocker CLA không còn.

## 2026-05-28 — PR #1460

Branch `debug/sidebar`, merged via [PR #1460](https://github.com/TableProApp/TablePro/pull/1460).

Root cause of "table list spinner stays after preview loads": stale load-generation guard in `SchemaService.runLoad` catch block left `states[connectionId]` stuck at `.loading` when both the old and new loads were abandoned. The state machine never transitioned back to `.idle`, so the spinner spun indefinitely.

Changes in `TablePro/Core/Services/Query/SchemaService.swift`:

- Added `beginLoadGeneration` and `isCurrentLoadGeneration` private methods. Each load call claims a generation token; the catch block checks the token before deciding what to do with `states[connectionId]`.
- Stale-generation catch block now resets to `.idle` only when `loadGenerations[connectionId] == nil`, meaning no active newer load is in progress.
- OSLog debug tracing added to the generation check path for future diagnostics.
- Replaced racy `Task.yield()` poll in tests with a deterministic `tablesGate` + `routinesGate` gate pattern.

Task "Table list spinner stays after preview loads" updated to `DONE-fork`.

## Timeline

| Date | Event |
|---|---|
| 2026-05-25 (sidebar-recents-star) | Branch `sidebar` (uncommitted): Recent table list moved from Favorites tab → top of Tables sidebar (`SidebarView`). Favorites tab now has only **Tables** + **Queries** sections. `TableRow` gains a trailing star toggle button (filled yellow if favorite, outlined gray otherwise); Add/Remove Favorites entry removed from `SidebarContextMenu`. New `RecentTablesStore` (in-memory, cap=10 per connection+database) posts `.recentTablesDidChange`. App `CHANGELOG.md` + `docs/features/favorites.mdx` updated. |
| 2026-05-25 (plan-review) | User confirm trên branch `sidebar`: Favorite tables → VERIFY-current sau commit `408d1589`; 4 task local checklist (Create Table button, Group disabled helper, Sidebar overflow, Recent tables) chuyển TODO-fork/investigate → TODO-current; #1353 vẫn VERIFY-current chờ user tự check. |
| 2026-05-25 (correction) | Corrected stale `.docs/sidebar` claim: current source has no table favorites or recent tables; D6-D8 marked stale proposal. |
| 2026-05-25 (review 2) | Added local checklist review: top-level Create Table TODO, context-menu disabled grouping TODO, sidebar overflow TODO-investigate, #1353 moved to VERIFY-current. |
| 2026-05-25 (review) | `.docs/sidebar` refresh cũ ghi partial done, nhưng source verify sau đó không xác nhận được. |
| 2026-05-25 (stale session note) | Entry cũ nói **#1352 IMPLEMENTED** với `FavoriteTablesStorage`; current source không có các file/symbol này. Treat as stale proposal, not implementation. |
| 2026-05-20 05:30 | Issue [#1352](https://github.com/TableProApp/TablePro/issues/1352) (favorite/recent tables) opened by datlechin |
| 2026-05-20 05:30 | Issue [#1353](https://github.com/TableProApp/TablePro/issues/1353) (sidebar toggle confusing) opened by datlechin |
| 2026-05-22 16:27 | Issue #1353 closed (state=CLOSED, reason=COMPLETED) — **no PR linked** |
| 2026-05-25 06:46 | Issue #1352 closed (state=CLOSED, reason=COMPLETED) — **no PR linked** |

## Release

Không xuất hiện trong `CHANGELOG.md` của upstream (v0.43.x → v0.44.0 → Unreleased).

Verify với:
```bash
grep -iE "1352|1353|favorite.*table|recent.*table|sidebar.*toggle" CHANGELOG.md
```
→ 0 match.

## Action nếu cần root cause certainty

```bash
# Check timeline events đầy đủ (closing actor + comments)
gh issue view 1352 --repo TableProApp/TablePro --comments
gh issue view 1353 --repo TableProApp/TablePro --comments

# Search commit body (không chỉ subject)
git log upstream/main --grep="1352" --grep="1353" --all-match=false
git log upstream/main -p -S "RecentTable" -S "recentTables"
```
