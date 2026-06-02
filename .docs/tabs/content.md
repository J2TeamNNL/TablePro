# tabs — content (case-study)

## Single-click table: reuse vs new tab (#1348 → #1394)

### Symptom

Có nhiều tab mở. Click một table khác ở sidebar → mong đợi: replace active tab.
Thực tế: mở thêm new tab. Lặp lại → mỗi click là 1 tab mới. Window panel sẽ
bloat lên rất nhanh.

### Reproduce

1. Open connection, mở table A (preview tab)
2. Open table B (preview tab — nó replace A vì A là preview) 
3. Sửa cái gì đó trong B → B promoted thành permanent
4. Click table C → mong đợi: replace B nếu không có unsaved → thực tế mở tab mới
5. Click table D → cũng mở thêm; sidebar có 3-4 tab

### Root cause

2 source of truth cho preview flag:

| Place | Field | Tracking unit |
|---|---|---|
| `QueryTab` | `isPreview: Bool` | per-tab |
| `WindowLifecycleMonitor` | `previewWindow` / `Entry.isPreview` | per-window |

`MainContentCoordinator.openPreviewTab` scan **mọi window của connection** tìm
window có `Entry.isPreview == true`, replace nó. Nhưng:

- Đó là **window-level** preview flag, drift ra khỏi `QueryTab.isPreview`
- Replace có thể steal focus sang window khác → confusing
- Với `enablePreviewTabs = false`: không có reuse path → mọi click spawn tab

### Fix (PR #1394) — single source of truth + window-local

`MainContentCoordinator+Navigation.swift` rewrite (+127 −201 ≈ −74 LOC):

```swift
// SidebarNavigationResult — contract mới
enum SidebarNavigationResult {
    case skip                    // không action (e.g. selecting current tab)
    case reuseActiveTab          // replace focused window's active tab
    case openNewTab(asPreview: Bool)
}

// Quyết định:
func navigationResult(...) -> SidebarNavigationResult {
    let active = focusedWindow.activeTab
    let reusable = active.isReusable  // preview tab HOẶC blank query, không unsaved
    if isDoubleClick { return .openNewTab(asPreview: false) }
    if reusable     { return .reuseActiveTab }
    return .openNewTab(asPreview: enablePreviewTabs)
}
```

`enablePreviewTabs` chỉ ảnh hưởng `asPreview:` của tab mới sinh ra — không còn
gate **whether reuse happens**.

### Xoá code chết

- `WindowLifecycleMonitor.previewWindow`
- `WindowLifecycleMonitor.setPreview`
- `WindowLifecycleMonitor.Entry.isPreview`
- `MainContentCoordinator.openPreviewTab` (cross-window preview lookup)

### Tests

`OpenTableTabTests.swift` mới (+170 LOC):

- Window-local reuse khi preview ON
- Window-local reuse khi active tab là blank query (preview OFF)
- Pinned tab protected (luôn `.openNewTab`)
- Promotion: preview tab có edit → biến permanent → click sau không reuse
- Double-click luôn `.openNewTab(asPreview: false)`

`SidebarNavigationResultTests.swift` rewrite (+85 −178) match contract mới
`.skip` / `.reuseActiveTab` / `.openNewTab`.

`MultiConnectionNavigationTests.swift` (+23 −17) cập nhật signature change.

### Pattern reference

- Xcode: editor tab có "preview" (italic title) → click 2 file thì replace; sửa
  thì promoted
- VS Code: "preview tabs" identical
- Single-click in-place; double-click new tab → macOS convention từ Finder
