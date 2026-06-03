# `inspector/` — Inspector pane overflow fix

Scope: `fix(inspector)`

## Vấn đề

Toggling inspector pane (right panel) trong cửa sổ nhỏ gây nội dung tràn ra ngoài frame. Ba pane có tổng `minimumThickness` (~954pt) vượt `window.minSize.width` (720pt).

## Fix

`MainSplitViewController` recompute `window.minSize.width` động mỗi khi pane visibility thay đổi. Nếu cửa sổ đang nhỏ hơn min mới, cửa sổ tự expand.

## Status

**OPEN-fork — PR [#1463](https://github.com/TableProApp/TablePro/pull/1463)**, branch `fix/inspector`. Chưa merge.

> Verified 2026-05-30: "DONE — 2026-05-25" trước đây là **superseded**. PR vẫn open.

**Blocker (CONFLICTING logic thật)**: main đã có `recomputeWindowMinSize()`
(`MainSplitViewController.swift:516`, call site `:185,:217,:478,:484`); PR thêm
`recomputeWindowMinimumSize()` (tên mới) + `PaneMinimum`/`resolvedContentMinSize`/
`originalContentMinSize`/`setCollapsed`. **CRITICAL fix**: GỘP logic PR vào method cũ
`:516`, không tạo method thứ hai; không thêm override `splitViewDidResizeSubviews()`
(đã có `:183`). Commit atomic. Plus drop noise (`.gitignore` + `CLAUDE.md:171`).
Chi tiết: `context.md` mục "Open fork PR #1463", `tasks.md` agent checklist.

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
| `TablePro/Core/Services/Infrastructure/MainSplitViewController.swift` | `recomputeWindowMinSize()` (def `:516`), `showInspector()` (`:474`), `hideInspector()` (`:481`), `splitViewDidResizeSubviews` (`:183`), `viewWillAppear` (`:194`); call sites `:185,:217,:478,:484` (verified 2026-05-30) |
| `TablePro/Core/Services/Infrastructure/TabWindowController.swift` | `window.minSize` baseline (720×480) |
