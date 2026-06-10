# inspector — changelog

## 2026-06-09 — PR pivot sang collapseBehavior + conflict resolved

| Date | Event |
|---|---|
| ~2026-06 | PR pivot: commit `58cd1102` ("refactor(inspector): grow the window via NSSplitViewItem.collapseBehavior instead of custom min-size code") **xóa hẳn** `recomputeWindowMinSize()`, override `splitViewDidResizeSubviews`, `PaneMinimum`/`resolvedContentMinSize`/`originalContentMinSize`, và test `MainSplitViewControllerWindowMinimumSizeTests`. Thay bằng `inspectorSplitItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings` + helper `setCollapsed(_:for:)`. |
| 2026-06-09 | Resolve conflict: merge `upstream/main` vào `fix/inspector` (commit local `69e3555e`). Hết conflict. 3 conflict file: `SQLContextAnalyzer.swift` + `PasswordSourceResolver.swift` lấy bản main (bị #1581/#1587/#1601 thay), `CHANGELOG.md` giữ wording main + chèn lại dòng inspector. Net diff vs main = `MainSplitViewController.swift` (collapseBehavior) + 1 dòng CHANGELOG. |
| 2026-06-09 | Cập nhật PR description cho khớp collapseBehavior (bỏ mô tả recomputeWindowMinimumSize + test cũ). |
| 2026-06-09 | Push **chưa xong**: GitHub chặn vì commit mang email `longnn@senprints.com` (account bật block push lộ email). Build/lint chưa verify cục bộ (không có Xcode/swiftlint) → CI là cổng. |

> Supersede note: toàn bộ timeline 2026-05-25/28/30 bên dưới dựa trên cách `recomputeWindowMinSize`
> (recompute `window.minSize` thủ công). PR đã pivot sang collapseBehavior nên các fix đó **moot**.
> Giữ lại để tham chiếu lịch sử.

## 2026-05-30 — Reconcile vs main (verified)

| Date | Event |
|---|---|
| — | PR #1463 mở (branch `fix/inspector`), diff +213/-13 |
| 2026-05-29 | Review: CONFLICTING thật (duplicate method name `recomputeWindowMinimumSize` vs `recomputeWindowMinSize` `:516`), logic đúng |
| 2026-05-30 | Verified vs main: PR vẫn **open**, chưa merge. main đã có `recomputeWindowMinSize()` `:516` + 4 call site (`:185,:217,:478,:484`); call site `splitViewDidResizeSubviews :185` đã có sẵn (không phải PR thêm). Next: drop noise → gộp method (ADR-006) → verify test + manual UI → merge (sau #1459, #1462) |

> Supersede note: phần "## 2026-05-28 — PR #1463" bên dưới mô tả các fix như đã landed —
> thực chất là **deltas của PR đang open** (`originalContentMinSize`, animation pre-hook,
> 2 test). Giữ nội dung để tham chiếu; trạng thái merge = open.

## 2026-05-28 — PR #1463 (deltas; merge status superseded → open)

### Code review fixes

- Added missing `splitViewDidResizeSubviews` call site for `recomputeWindowMinimumSize()`. Without it, dragging a divider while the inspector was visible could leave `window.minSize` stale.
- Fixed base min size drift: `originalContentMinSize` is now captured once at `viewWillAppear` (after toolbar install) and used as the floor in every `recomputeWindowMinimumSize()` call. Previously, the function re-derived the base from the mutable `window.minSize`, so each show/hide cycle could ratchet the minimum upward.
- Fixed animation race in `hideInspector`: min size is now narrowed before the collapse animation begins, matching the pre-widening pattern already in `showInspector`.
- Added tests `usesPaneSumWhenItExceedsBaseWithSidebarCollapsed` and `relaxesBackToOriginalBaseAfterInspectorCycle` in `MainSplitViewControllerWindowMinimumSizeTests.swift`.

### Files

- `TablePro/Core/Services/Infrastructure/MainSplitViewController.swift`
- `TableProTests/MainSplitViewControllerWindowMinimumSizeTests.swift`

### Pending

- Manual UI verify still pending (lint passes; no xcodebuild run in worktree).

## 2026-05-25 — DONE (branch `sidebar`, uncommitted)

### Phát hiện

- Session phân tích `.docs/sidebar/tasks.md`: "Sidebar collapse/expand overflow" — pane min widths cộng lại có thể vượt `window.minSize`.
- Root cause confirm: `sidebarSplitItem.minimumThickness=280` + `detailSplitItem.minimumThickness=400` + `inspectorSplitItem.minimumThickness=270` + dividers ≈ 954pt > `window.minSize.width=720pt`.

### Implement

- Thêm `recomputeWindowMinSize()` vào `MainSplitViewController`.
- 4 call sites: `showInspector`, `hideInspector`, `splitViewDidResizeSubviews`, `viewWillAppear`.
- CHANGELOG.md (app): thêm entry `Fixed: Inspector pane toggle no longer causes content overflow in narrow windows`.

### Tách docs

- User yêu cầu tách thành folder riêng `.docs/inspector/` thay vì note trong `.docs/sidebar/`.
- File `.docs/sidebar/inspector-overflow.md` (tạm thời) đã remove, nội dung chuyển vào folder này.
- `.docs/README.md` cập nhật thêm scope `inspector/`.
- `.docs/sidebar/tasks.md` cập nhật pointer sang folder này.

### Pending

- Manual UI verify chưa thực hiện (cần build + chạy app thực).
