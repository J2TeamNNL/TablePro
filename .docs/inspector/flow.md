# Inspector pane overflow — flow

> **Reconcile 2026-06-09.** Các diagram bên dưới mô tả luồng `recomputeWindowMinSize` (cách CŨ) và
> "merged sizing flow" (kế hoạch GỘP). PR đã pivot sang `collapseBehavior` (commit `58cd1102`), bỏ
> hết recompute → các diagram đó **superseded**. Luồng thực tế hiện tại:
>
> ```mermaid
> flowchart TD
>     A[Setup: inspectorSplitItem.collapseBehavior<br/>= .preferResizingSplitViewWithFixedSiblings] --> B[User toggle inspector]
>     B --> C[showInspector / hideInspector]
>     C --> D[setCollapsed _:for_:<br/>animate isCollapsed CHỈ khi window.isVisible]
>     D --> E[AppKit tự nới/thu window<br/>để fit, không ép detail pane]
>     E --> F[Floor 720×480 tĩnh từ TabWindowController:75]
> ```

## Luồng toggle inspector

```mermaid
sequenceDiagram
    participant User
    participant Toolbar as MainWindowToolbar
    participant Split as MainSplitViewController
    participant Window as NSWindow

    User->>Toolbar: click Inspector button
    Toolbar->>Split: toggleInspector()
    alt inspector currently hidden
        Split->>Split: showInspector()
        Split->>Split: materializeInspectorIfNeeded()
        Split->>Split: inspectorSplitItem.isCollapsed = false
        Split->>Split: recomputeWindowMinSize()
        Split->>Window: window.minSize = NSSize(~954, 480)
        alt window.frame.width < 954
            Split->>Window: setFrame(expanded, animate: true)
        end
    else inspector currently visible
        Split->>Split: hideInspector()
        Split->>Split: inspectorSplitItem.isCollapsed = true
        Split->>Split: recomputeWindowMinSize()
        Split->>Window: window.minSize = NSSize(720, 480)
    end
```

## Luồng recompute minSize

```mermaid
flowchart TD
    A[recomputeWindowMinSize called] --> B{view.window != nil?}
    B -- no --> Z[return]
    B -- yes --> C[read sidebarSplitItem.isCollapsed]
    C --> D[read inspectorSplitItem.isCollapsed]
    D --> E[width = detailMin 400]
    E --> F{sidebarVisible?}
    F -- yes --> G[width += sidebarMin 280 + divider]
    F -- no --> H
    G --> H{inspectorVisible?}
    H -- yes --> I[width += inspectorMin 270 + divider]
    H -- no --> J
    I --> J[resolvedWidth = max 720 width]
    J --> K{newMinSize == current?}
    K -- yes --> Z
    K -- no --> L[window.minSize = newMinSize]
    L --> M{frame.width < resolvedWidth?}
    M -- yes --> N[expand frame + setFrame animate]
    M -- no --> Z
```

## 4 call sites

```mermaid
graph LR
    A[splitViewDidResizeSubviews] --> R[recomputeWindowMinSize]
    B[viewWillAppear] --> R
    C[showInspector] --> R
    D[hideInspector] --> R
```

## Key file mapping (VERIFIED-2026-05-30 vs main)

| Symbol | File | Line |
|---|---|---|
| `recomputeWindowMinSize()` (def) | `MainSplitViewController.swift` | `:516` |
| call: `splitViewDidResizeSubviews` | `MainSplitViewController.swift` | `:185` (override `:183`) |
| call: `viewWillAppear` | `MainSplitViewController.swift` | `:217` (override `:194`) |
| call: `showInspector()` | `MainSplitViewController.swift` | `:478` (func `:474`) |
| call: `hideInspector()` | `MainSplitViewController.swift` | `:484` (func `:481`) |
| `window.minSize` baseline (720×480) | `TabWindowController.swift` | ~`:54` |

> Superseded 2026-05-30: bảng cũ (~502/460/467/167/178) là ước lượng; số trên đã verify trên main.

## Open fork PR #1463 — merged sizing flow (sau khi gộp vào `recomputeWindowMinSize()`)

> PR thêm `PaneMinimum` / `resolvedContentMinSize` / `originalContentMinSize` /
> `setCollapsed` pre-hook. Logic gộp VÀO `recomputeWindowMinSize()` `:516` (không
> tạo `recomputeWindowMinimumSize()` trùng). Override `splitViewDidResizeSubviews`
> `:183` tự pick up logic mới.

```mermaid
flowchart TD
    A[User toggle inspector / sidebar] --> B[setCollapsed pre-hook]
    B --> C{Show hay Hide?}
    C -->|Show inspector| D[Lưu originalContentMinSize<br/>Pre-widen window TRƯỚC animation]
    C -->|Hide inspector| E[Pre-shrink window<br/>Restore originalContentMinSize]
    D --> F[NSSplitViewItem.animator isCollapsed]
    E --> F
    F --> G[Animation chạy<br/>không clip / jank]
    G --> H[recomputeWindowMinSize :516<br/>body đã gộp logic PR]
    H --> I[resolvedContentMinSize<br/>max base 720,<br/>sum minWidth pane visible<br/>+ dividerCount × thickness]
    I --> J{sidebar visible?}
    J -->|yes| K[+ PaneMinimum.sidebar 280 + divider]
    J -->|no| L[+0]
    K --> M{inspector visible?}
    L --> M
    M -->|yes| N[+ PaneMinimum.inspector 270 + divider]
    M -->|no| O[+0]
    N --> P[resolvedWidth = max 720, total]
    O --> P
    P --> Q{window.minSize != new?}
    Q -->|khác| R[Set window.minSize<br/>auto-expand nếu frame < min]
    Q -->|giống| S[no-op]
```

```mermaid
flowchart LR
    A[User kéo divider] --> B[splitViewDidResizeSubviews :185]
    B --> C[recomputeWindowMinSize :516<br/>body đã gộp logic PR]
    C --> D[Cập nhật window.minSize động]
```
