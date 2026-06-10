# inspector — tasks

> **Reconcile 2026-06-09 (verified vs PR thật).** PR #1463 đã **PIVOT** sang cách native.
> Commit `58cd1102` xóa hẳn `recomputeWindowMinSize()` + override `splitViewDidResizeSubviews`
> + `PaneMinimum`/`resolvedContentMinSize`/`originalContentMinSize` + test
> `MainSplitViewControllerWindowMinimumSizeTests`. Thay bằng
> `inspectorSplitItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings` + helper
> `setCollapsed(_:for:)` (chỉ để animate khi window visible). Floor 720×480 vẫn tĩnh ở
> `TabWindowController:75`. → Toàn bộ "PR #1463 deltas", "Agent checklist — merge", và "Codex P2
> base-min-size" bên dưới là **SUPERSEDED/MOOT** (không còn code recompute để mà bug).

## Trạng thái 2026-06-09 (verified)

| Item | Status | Notes |
|---|---|---|
| Cách fix cuối | DONE-fork `58cd1102` | `collapseBehavior = .preferResizingSplitViewWithFixedSiblings`; AppKit tự nới window. |
| `recomputeWindowMinSize()` + 4 call site | REMOVED | Bị xóa khỏi `MainSplitViewController` trong PR. |
| override `splitViewDidResizeSubviews` | REMOVED | Bị xóa trong PR. |
| `setCollapsed(_:for:)` helper | DONE-fork | Animate collapse chỉ khi `window.isVisible`; dùng cho cả sidebar + inspector. |
| Floor 720×480 | ON-MAIN `TabWindowController:75` | `window.minSize` tĩnh — nguồn floor duy nhất còn lại. |
| Test geometry | REMOVED | `MainSplitViewControllerWindowMinimumSizeTests` không còn. Không có unit test mới (UI resize/animation không deterministic). |
| Conflict vs upstream/main | RESOLVED-local `69e3555e` | Merge `upstream/main` vào `fix/inspector`. Hết conflict. |
| 3 fix kèm (mcp/connections/editor) | SUPERSEDED | Bản trên main (#1587) thay hết; net diff vs main = 0 cho các file đó. |
| Net diff PR vs main | — | `MainSplitViewController.swift` (collapseBehavior) + 1 dòng `CHANGELOG.md`. |

## Còn lại

- [ ] **Push** `fix/inspector` (commit `69e3555e`) lên origin. **Blocker**: GitHub chặn vì
      commit mang email `longnn@senprints.com` (account bật "block push lộ email"). Cách:
      (A) `git config user.email "26674308+J2TeamNNL@users.noreply.github.com"` →
      `git commit --amend --reset-author --no-edit` → push; hoặc (B) tắt setting tại
      github.com/settings/emails rồi `git push origin fix/inspector`.
- [ ] **CI build + lint** (máy local không có Xcode/swiftlint — chưa verify được cục bộ).
- [ ] PR description: đã cập nhật 2026-06-09 cho khớp collapseBehavior (bỏ phần test cũ).
- [ ] Manual UI verify (xem bước dưới) khi có build chạy được.

## Manual verify steps

1. Mở connection, resize window về ~720pt.
2. Bật inspector → window tự nới để fit, không overflow.
3. Tắt inspector → nội dung nguyên vẹn, không giật.
4. Kéo divider hẹp rồi bật inspector → window nở ra fit.
5. Toggle nhanh (on/off/on) → layout vẫn đúng.

---

## (SUPERSEDED 2026-06-09) Kế hoạch merge cũ — giữ để tham chiếu

> Các phần dưới đây dựa trên giả định PR GỘP logic vào `recomputeWindowMinSize()`. PR đã
> pivot sang `collapseBehavior`, nên kế hoạch này **không còn áp dụng**. Codex P2
> "base-min-size chỉ tăng không co" cũng moot vì không còn code recompute đọc `window.minSize`.

> Reconcile 2026-05-30 (verified vs main): main từng có `recomputeWindowMinSize()` `:516` +
> 4 call site (`:185,:217,:478,:484`); PR (lúc đó) thêm `recomputeWindowMinimumSize()` tên
> mới + `PaneMinimum`/`resolvedContentMinSize`/`originalContentMinSize`/`setCollapsed`. Kế
> hoạch lúc đó: gộp vào method cũ, không tạo method thứ hai, không thêm override mới, drop
> noise `.gitignore`/`CLAUDE.md`, giữ 5 test geometry, fix bug base-min-size lấy từ baseline
> immutable. Toàn bộ đã bị thay bởi pivot collapseBehavior.
