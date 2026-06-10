# `inspector/` — Inspector pane overflow fix

Scope: `fix(inspector)`

## Vấn đề

Toggling inspector pane (right panel) trong cửa sổ nhỏ gây nội dung tràn ra ngoài frame. Ba pane có tổng `minimumThickness` (~954pt) vượt `window.minSize.width` (720pt).

> **Reconcile 2026-06-09 (verified vs PR thật).** PR đã PIVOT. Commit `58cd1102`
> ("refactor(inspector): grow the window via NSSplitViewItem.collapseBehavior instead of
> custom min-size code") **bỏ hẳn** toàn bộ cơ chế recompute: xóa `recomputeWindowMinSize()`,
> xóa override `splitViewDidResizeSubviews`, không còn `PaneMinimum`/`resolvedContentMinSize`/
> `originalContentMinSize`, và **không còn** test `MainSplitViewControllerWindowMinimumSizeTests`.
> Cách cuối: set `inspectorSplitItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings`
> để AppKit tự nới window khi inspector bật. Floor 720×480 vẫn nằm tĩnh ở `TabWindowController`.
> Toàn bộ kế hoạch "GỘP vào recomputeWindowMinSize" + ADR-006/007/010 bên dưới là **moot**
> (xem `decisions.md` ADR-011).
>
> Conflict đã resolve (merge `upstream/main` vào `fix/inspector`, commit local `69e3555e`):
> hết conflict, net diff vs main = chỉ `MainSplitViewController.swift` (collapseBehavior) + 1
> dòng `CHANGELOG.md`. 3 fix kèm theo (mcp/connections/editor) bị bản trên main (#1587) thay hết.
> **Push đang chờ**: bị GitHub chặn vì commit mang email `longnn@senprints.com` (account bật
> block push lộ email). Build/lint **chưa verify cục bộ** (máy không có Xcode/swiftlint) → CI là cổng.

## Fix (cách cuối — collapseBehavior)

`inspectorSplitItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings`: khi inspector
bật, AppKit nới window thay vì ép detail pane co lại. Bỏ toàn bộ code recompute `window.minSize`
thủ công. Floor cố định 720×480 vẫn do `TabWindowController` set.

## Status

**OPEN — PR [#1463](https://github.com/TableProApp/TablePro/pull/1463)**, branch `fix/inspector`.
Conflict đã resolve cục bộ; chờ push (email-privacy block) + CI build.

> Verified 2026-05-30: "DONE — 2026-05-25" trước đây là **superseded**.
> Reconcile 2026-06-09: kế hoạch merge "GỘP vào recomputeWindowMinSize" cũng **superseded** — PR pivot sang collapseBehavior.

## Files trong folder này

| File | Nội dung |
|---|---|
| `README.md` | File này — index + navigation |
| `brief.md` | One-pager: vấn đề, mục tiêu, kết quả |
| `context.md` | Root cause chi tiết + diff snippet |
| `flow.md` | Mermaid diagram luồng recompute |
| `tasks.md` | Bảng trạng thái task |
| `decisions.md` | ADR-lite: các approach được cân nhắc |
| `changelog.md` | Timeline từ phát hiện đến implement |

## Key files trong codebase

| File | Vai trò |
|---|---|
| `TablePro/Core/Services/Infrastructure/MainSplitViewController.swift` | `inspectorSplitItem.collapseBehavior` (cách cuối), `setCollapsed(_:for:)` helper, `showInspector()`, `hideInspector()`. `recomputeWindowMinSize()` + `splitViewDidResizeSubviews` đã **bị xóa** trong commit `58cd1102`. |
| `TablePro/Core/Services/Infrastructure/TabWindowController.swift` | `window.minSize` baseline 720×480 (`:75`) — floor tĩnh duy nhất sau khi bỏ recompute |
