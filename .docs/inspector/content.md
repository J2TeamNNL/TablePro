# Inspector pane overflow — case study chi tiết

## Symptom

Toggle inspector pane khi window width ~720pt → content area bị squeeze/tràn, toolbar controls bị che.

Repro:
1. Mở app, resize window về ~720pt
2. Bấm nút inspector (toolbar phải)
3. Layout bị vỡ

## Root cause

### `TabWindowController` set cứng minSize

```swift
// TabWindowController.swift:54
window.minSize = NSSize(width: 720, height: 480)
```

Giá trị này set một lần lúc khởi tạo, không update khi pane visibility thay đổi.

### `MainSplitViewController` set minimumThickness cho từng pane

```swift
// MainSplitViewController.swift:130
sidebarSplitItem.minimumThickness = 280

// MainSplitViewController.swift:136
detailSplitItem.minimumThickness = 400

// MainSplitViewController.swift:151
inspectorSplitItem.minimumThickness = 270
```

AppKit tôn trọng `minimumThickness` mỗi pane. Khi inspector không bị collapsed, nó chiếm ít nhất 270pt. Cộng lại vượt window.minSize.

### Không có observer nào kết nối hai thứ này

Không có code nào update `window.minSize` khi inspector toggle. `NSSplitViewController` không tự làm điều này.

## Fix

### Thêm `recomputeWindowMinSize()` trong `MainSplitViewController`

```swift
// MainSplitViewController.swift — MARK: Dynamic Window Minimum Size

private static let baseWindowMinWidth: CGFloat = 720
private static let baseWindowMinHeight: CGFloat = 480

private func recomputeWindowMinSize() {
    guard let window = view.window else { return }
    let sidebarVisible = !(sidebarSplitItem?.isCollapsed ?? true)
    let inspectorVisible = !(inspectorSplitItem?.isCollapsed ?? true)

    let detailMin: CGFloat = detailSplitItem?.minimumThickness ?? 400
    let sidebarMin: CGFloat = sidebarSplitItem?.minimumThickness ?? 280
    let inspectorMin: CGFloat = inspectorSplitItem?.minimumThickness ?? 270
    let dividerThickness = splitView.dividerThickness

    var width: CGFloat = detailMin
    if sidebarVisible { width += sidebarMin + dividerThickness }
    if inspectorVisible { width += inspectorMin + dividerThickness }

    let resolvedWidth = max(Self.baseWindowMinWidth, width)
    let newMinSize = NSSize(width: resolvedWidth, height: Self.baseWindowMinHeight)

    guard window.minSize != newMinSize else { return }
    window.minSize = newMinSize

    var frame = window.frame
    var resized = false
    if frame.size.width < resolvedWidth {
        frame.size.width = resolvedWidth
        resized = true
    }
    if frame.size.height < Self.baseWindowMinHeight {
        frame.size.height = Self.baseWindowMinHeight
        resized = true
    }
    if resized {
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}
```

### 4 call sites

```swift
// (1) splitViewDidResizeSubviews — triggered bởi AppKit khi user drag divider
override func splitViewDidResizeSubviews(_ notification: Notification) {
    super.splitViewDidResizeSubviews(notification)
    recomputeWindowMinSize()
}

// (2) viewWillAppear — initial state khi window hiện ra
override func viewWillAppear() {
    super.viewWillAppear()
    // ... existing setup ...
    recomputeWindowMinSize()
}

// (3) showInspector
func showInspector() {
    materializeInspectorIfNeeded()
    inspectorSplitItem?.animator().isCollapsed = false
    UserDefaults.standard.set(true, forKey: Self.inspectorPresentedKey)
    recomputeWindowMinSize()
}

// (4) hideInspector
func hideInspector() {
    inspectorSplitItem?.animator().isCollapsed = true
    UserDefaults.standard.set(false, forKey: Self.inspectorPresentedKey)
    recomputeWindowMinSize()
}
```

## Kết quả theo scenario

| Pane visible | minSize.width |
|---|---|
| sidebar + detail + inspector | max(720, 280+400+270+4) = 954 |
| sidebar + detail | max(720, 280+400+2) = 720 |
| detail + inspector | max(720, 400+270+2) = 720 |
| detail only | max(720, 400) = 720 |

## Manual verify steps

1. Window ~720pt → toggle inspector → window auto-grow đến ~954pt
2. Toggle inspector off → minSize drop về 720, window giữ kích thước
3. Kéo window nhỏ đến ~720 → bật inspector → window expand
4. Sidebar collapsed + inspector on → minSize = 720 (floor)
5. Restart app, inspector state persist từ UserDefaults → initial minSize đúng

---

## Open fork PR #1463 — code review & conflict resolution (verified 2026-05-30)

> Branch `fix/inspector`. Diff +213 / -13. Mergeable: **CONFLICTING (logic thật)**.
> Ưu tiên trung bình — merge sau PR #1459, #1462.

### Reconcile vs main (VERIFIED-2026-05-30)

main ĐÃ CÓ `recomputeWindowMinSize()` (def `MainSplitViewController.swift:516`),
gọi tại **4 call site**: `:185` (`splitViewDidResizeSubviews`), `:217` (`viewWillAppear`),
`:478` (`showInspector`), `:484` (`hideInspector`). main **KHÔNG** có
`recomputeWindowMinimumSize()`, `PaneMinimum`, `resolvedContentMinSize`,
`originalContentMinSize`.

> Các phần phía trên file này (tên method `recomputeWindowMinSize()`, body geometry
> đơn giản) mô tả trạng thái **main hiện tại** — đúng. Nhưng note ở `tasks.md`/`changelog.md`
> ghi "splitViewDidResizeSubviews ... missing call site added in PR review" và "DONE 2026-05-25"
> là **superseded** (2026-05-30): call site `:185` đã có sẵn trên main; PR vẫn **open**, chưa merge.

### Files changed (PR)

**Production** — `TablePro/Core/Services/Infrastructure/MainSplitViewController.swift` (~+107)
- `struct PaneMinimum` (sidebar 280, detail 400, inspector 270).
- `var originalContentMinSize: NSSize?` — lưu base gốc, restore khi hide → tránh window mở rộng vĩnh viễn.
- `resolvedContentMinSize()`: `max(base 720, sum(minWidth pane visible) + dividerCount × thickness)`.
- `recomputeWindowMinimumSize()` — **CONFLICT: trùng chức năng với `recomputeWindowMinSize()` `:516`**.
- `setCollapsed(_ item:, collapsed:)`: pre-hook resize trước animation (pre-widen khi show, pre-shrink khi hide).
- override `splitViewDidResizeSubviews()` — **CONFLICT: main đã có `:183-186`**.

**Tests** — `TableProTests/Core/Services/Infrastructure/MainSplitViewControllerWindowMinimumSizeTests.swift` (+102): 5 edge case (xem bảng threshold dưới).

**Docs**: `CHANGELOG.md`.

**Noise (drop)**: `.gitignore` (đã có main `:128,158-160`) + `CLAUDE.md:171`.

### Conflict analysis

| Điểm | PR thêm | main đã có | Action |
|---|---|---|---|
| Window min-size method | `recomputeWindowMinimumSize()` | `recomputeWindowMinSize()` `:516` | **GỘP** logic PR vào `:516`, giữ tên cũ |
| `splitViewDidResizeSubviews` | override mới | override `:183-186` gọi `recomputeWindowMinSize()` | **KHÔNG thêm** — `:183` tự pick up logic mới sau khi gộp |
| Call sites | gọi tên mới | `:185,:217,:478,:484` gọi tên cũ | giữ tên cũ; cập nhật body trong cùng commit atomic |

### Fix approach (CRITICAL)

1. **KHÔNG** tạo method thứ hai. Gộp `PaneMinimum` + `resolvedContentMinSize` +
   `originalContentMinSize` vào body `recomputeWindowMinSize()` `:516`.
2. Thêm `setCollapsed()` pre-hook; gọi thay `item.animator().isCollapsed = ...` trong
   `showInspector()` `:474` / `hideInspector()` `:481`.
3. **KHÔNG** thêm override `splitViewDidResizeSubviews()` — `:183` đã gọi method cũ.
4. Confirm 4 call site (`:185,:217,:478,:484`) vẫn gọi đúng `recomputeWindowMinSize()`.
5. **Commit atomic**: gộp method + cập nhật mọi liên quan trong 1 commit (rule "Atomic API changes").

### Findings

| Loại | Nội dung |
|---|---|
| Tốt | Math `resolvedContentMinSize` đúng: `max(base, sum visible + dividers × thickness)`. |
| Tốt | `setCollapsed` pre-hook → tránh visual clip/jank trong animation. |
| Tốt | `originalContentMinSize` lưu/restore → window không stuck ở kích thước lớn sau khi đóng inspector. |
| Tốt | 5 test edge case bao phủ trường hợp thực tế. |
| Fix | DRY — gộp vào `recomputeWindowMinSize()`, không tạo method/override trùng. |

### Test thresholds (từ PR)

| Scenario | Expected minWidth |
|---|---|
| Inspector visible | 954px (400+280+270+2×divider) |
| Inspector hidden | 720px (base) |
| Sidebar collapsed | 720px (base) |
| Detail + inspector > base | 802px |
| Cycle show → hide | relax về 720px |

### Codex automated review (GitHub) — P2

> Input từ **bot tự động** (Codex). Coi là cảnh báo **cần verify khi fix**, chưa phải fact
> đã xác nhận. Đây là **bug thật** mà diff-review trước đó BỎ SÓT (mục Findings ở trên khen
> "Math `resolvedContentMinSize` đúng").

**Base min-size chỉ tăng, không co lại — window stuck oversized sau khi toggle inspector**
(inline comment trên `TablePro/Core/Services/Infrastructure/MainSplitViewController.swift:197`)

Codex: vì base được suy ra từ `window.minSize` **sau khi** các lần gọi trước đã gán
`window.contentMinSize`, floor tính ra **chỉ có thể tăng**. Show inspector → widen
contentMinSize lên tổng các pane; khi `hideInspector()` gọi
`recomputeWindowMinimumSize(inspectorCollapsed: true)`, `window.minSize` đã phản ánh giá
trị widen đó, nên base vẫn lớn và window **không bao giờ relax về 720pt** ban đầu. Window
editor hẹp bị **kẹt oversized** sau khi toggle inspector một lần. Fix: giữ một
baseline/default content minimum riêng, **KHÔNG** đọc từ `window.minSize` đang mutate.

> **Cần verify khi fix**: `originalContentMinSize` mà PR capture có thể đã (hoặc chưa) xử
> lý đúng. Đảm bảo base lấy từ **baseline cố định** (`originalContentMinSize`), **KHÔNG**
> từ `window.minSize` đang mutate. Test: toggle inspector → co lại đúng về 720pt (test
> "cycle show → hide relax về 720px" ở bảng trên phải fail nếu base đọc từ minSize mutate).
>
> Củng cố guidance "GỘP vào `recomputeWindowMinSize()` cẩn thận" ở trên: khi gộp, base
> phải đến từ baseline immutable, không phải `window.minSize` hiện tại.
