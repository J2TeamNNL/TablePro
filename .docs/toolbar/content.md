# toolbar — content (case-studies)

## 1. Active Connections không có nút đóng (#1350 → #1386)

### Symptom

Mở "Active Connections" từ toolbar → modal làm mờ background. Không có visible
close button. User không biết cách dismiss (Esc / click outside không hoạt động).

### Root cause

`ConnectionSwitcherSheet.swift` present qua SwiftUI `.sheet`. Theo macOS HIG,
sheet là **modal**: dim + block parent, không light-dismiss on click-outside, nên
**cần close button** — mà nó không có.

> **Wrong primitive là bug thật, không phải missing button.** — PR author.

### Fix approach (PR #1386)

Rewrite thành **native popover anchored to toolbar's Connection button**, mirror
`DatabaseSwitcher` đã có sẵn.

SwiftUI `.popover` light-dismiss on Esc + click-outside tự động, reset binding
luôn → không cần close button (match HIG: popover là transient view, chỉ cần
close button khi có task save/cancel).

```swift
// MainContentCoordinator
@Published var isConnectionSwitcherShown = false

// MainContentCommandActions
func openConnectionSwitcher() {
    coordinator.isConnectionSwitcherShown = true
}

// MainWindowToolbar+Buttons (ConnectionToolbarButton)
.popover(isPresented: $coord.isConnectionSwitcherShown) {
    ConnectionSwitcherPopover(...)
}
```

`Cmd+Ctrl+C` menu path light up cùng popover qua flag — same pattern `Cmd+K`
cho database switcher đã có.

### `ConnectionSwitcherSheet.swift` → `ConnectionSwitcherPopover.swift`

- Drop dead `isPresented` binding (popover bind ngoài)
- Drop `.onExitCommand` (popover handle Esc tự động)
- Add NSSearchField + ↑↓ navigation + Return to switch
- Keep active/saved sections, tap to activate, Manage Connections
- Replace `Ctrl+J/K` bằng arrow keys

### Tests

`ConnectionSwitcherFilterTests`:

- Empty/whitespace query → match all
- Case-insensitive substring match cho name
- Match cho database name
- Non-matching query → false

### Note

`QuickSwitcherSheet` **giữ là sheet** (xem item 2). Nó là full-content command
palette — correctly modal.

---

## 2. Quick switcher có khoảng trống thừa (#1349 → #1392)

### Symptom

Cmd+Shift+O mở quick switcher. Vài match hoặc không có match → 80% panel blank
ở dưới. List "no results" cũng fill cả panel.

### Root cause

```swift
// Cũ
QuickSwitcherSheet
    .frame(width: 460, height: 500)
```

`List` trong SwiftUI **expand to fill height được offer, không shrink to content**.
Pin height 500pt → list ngắn để lại blank.

### Fix approach (PR #1392)

```swift
// Mới
QuickSwitcherSheet
    .frame(width: 460)  // chỉ width

// QuickSwitcherViewModel
func listHeight(rowHeight: CGFloat,
                headerHeight: CGFloat,
                maxVisibleRows: Int) -> CGFloat {
    let natural = items.count * rowHeight + sectionHeaders * headerHeight
    let cap = CGFloat(maxVisibleRows) * rowHeight  // 9 rows
    return min(natural, cap)
}
```

- Drop fixed height; sheet sizes to content
- View model compute natural content height (items + section headers)
- Clamp tới `maxVisibleRows * rowHeight` (9 rows); beyond cap → scroll
- **Header count vào cap** → empty-query dense view (multi-section) không over-shoot
- Pin row height (drop vertical padding, zero vertical row insets) → height math
  exact
- Loading & "no results" states self-size
- `isLoading` start `true` → tránh flash "No objects found" trước khi load chạy

Kept `List` (native selection, section headers, double-click, VoiceOver) và sheet
presentation. Bug là height, không phải primitive — khác với case Active Connections.

### Behavior

| Scenario | Height |
|---|---|
| 1 result | 1 row |
| Content ≤ cap (≤ ~9 rows items + headers) | exact fit |
| Beyond cap | clamp + scroll |
| Empty query (multi-section grouped) | bounded bởi cap |

### Tests

8 tests trên view model:

- `listHeight` cho 0 items, 1 filtered, at cap, over cap
- Multi-section empty-query case
- Recent group adds header (uncapped)
- Clamp engages khi sections + rows overflow
- `isLoading` default true

### Verify on device

PR author note: `rowHeight=30`, `sectionHeaderHeight=28` là constants. `List.inset`
add small outer content inset arithmetic không thấy → nếu few-px gap hoặc clip,
nudge 2 constants.
