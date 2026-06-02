# tabs — brief

## Scope

Hành vi khi click vào table ở sidebar: khi nào replace tab hiện tại, khi nào mở
tab mới.

## Vấn đề

Click đầu tiên replace current tab. Khi đã có 2+ tab, mọi click sau đều mở new
tab thay vì replace active tab. User report: "không nhất quán".

## Root cause (1 sentence)

Preview-tab tracked **2 source of truth**: `QueryTab.isPreview` + `WindowLifecycleMonitor.previewWindow` —
drift ra khỏi nhau; `openPreviewTab` scan mọi window và steal focus tới window
giữ preview flag.

## Mục tiêu

- 1 source of truth: `QueryTab.isPreview`
- Single-click = window-local: reuse focused window's active tab nếu reusable
- `enablePreviewTabs` chỉ quyết định resulting tab có preview hay không

## Convention chọn

macOS / Xcode / VS Code "one-temporary-tab" model. Pinned + working tab protected.
Double-click = permanent tab riêng.

## Kết quả

```
single-click:
  → focused window's active tab REUSABLE (preview OR blank query, no unsaved)
     ? reuse
     : new tab

double-click:
  → permanent new tab
```

## Trade-off

- Cross-window preview share gone — preview giờ là per-window. Theo PR author:
  cross-window preview tạo confusion (steal focus) hơn là feature.
