# Inspector pane overflow — brief

## Vấn đề

Khi user toggle inspector pane (panel bên phải) trong một cửa sổ hẹp (~720pt), nội dung và toolbar bị tràn ra ngoài viền window. AppKit cố gắng fit 954pt content vào 720pt frame.

## Nguyên nhân gốc

`window.minSize.width` được set cứng là 720pt trong `TabWindowController`, nhưng tổng `minimumThickness` của ba pane là:

| Pane | Min |
|---|---|
| sidebar | 280pt |
| detail | 400pt |
| inspector | 270pt |
| dividers (×2) | ~4pt |
| **Tổng** | **~954pt** |

`NSSplitViewController` không tự điều chỉnh `window.minSize` theo pane visibility — đó là trách nhiệm của app.

## Mục tiêu

- Window tự grow khi inspector bật (không overflow)
- Window không bị ép lớn khi inspector tắt
- minSize co lại khi pane collapse (để user có thể thu nhỏ window lại)

## Kết quả

`MainSplitViewController.recomputeWindowMinSize()` (`:516`) tính tổng dynamic dựa trên
pane visibility hiện tại. main đã có method + 4 call site: `splitViewDidResizeSubviews`
(`:185`), `viewWillAppear` (`:217`), `showInspector` (`:478`), `hideInspector` (`:484`).

## Open fork PR #1463 (status + blocker)

**OPEN-fork**, branch `fix/inspector`, diff +213/-13. PR thêm logic giàu hơn
(`PaneMinimum`, `resolvedContentMinSize`, `originalContentMinSize`, `setCollapsed`
pre-hook tránh animation clip) nhưng dưới tên method MỚI `recomputeWindowMinimumSize()`.

**Blocker (CONFLICTING logic)**: KHÔNG tạo method thứ hai — GỘP logic PR vào
`recomputeWindowMinSize()` `:516` sẵn có, giữ 4 call site; KHÔNG thêm override
`splitViewDidResizeSubviews()` (đã có `:183`). Commit atomic. Drop noise
(`.gitignore` + `CLAUDE.md:171`). Chi tiết: `context.md`, `tasks.md`.

> Verified 2026-05-30: status cũ "DONE 2026-05-25" superseded — PR vẫn open.

## Scope

- 1 file thay đổi chính: `MainSplitViewController.swift`
- Gộp logic vào method sẵn có + `setCollapsed` pre-hook trong `showInspector`/`hideInspector`
- Không thay đổi API public, không ảnh hưởng plugin system
- PR #1463 thêm 5 unit test geometry (`MainSplitViewControllerWindowMinimumSizeTests`) +
  manual UI verify (overflow ở window hẹp)
