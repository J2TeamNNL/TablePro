# toolbar — tasks

Review 2026-05-25: 2 user checklist items trong scope này vẫn giữ trạng thái
`DONE-upstream/current`:

- Active Connections modal dim background → đổi sang popover.
- Quick switcher dư khoảng trống dưới → bỏ fixed height, list tự size theo content.

| Item | Issue | PR | Author | Merged | Commit |
|---|---|---|---|---|---|
| Quick switcher khoảng trống thừa | [#1349](https://github.com/TableProApp/TablePro/issues/1349) | [#1392](https://github.com/TableProApp/TablePro/pull/1392) | datlechin | 2026-05-22 16:23 | `764e00ac` |
| Active Connections modal không có nút đóng | [#1350](https://github.com/TableProApp/TablePro/issues/1350) | [#1386](https://github.com/TableProApp/TablePro/pull/1386) | datlechin | 2026-05-22 13:41 | `488e0658` |

## Trade-off: chọn primitive đúng

Cả 2 PR có chung nguyên tắc: **wrong SwiftUI primitive là bug thật**, không phải
"thiếu nút đóng" / "thiếu cap height". Sửa bằng cách đổi primitive:

| Item | Primitive cũ | Primitive mới | Lý do |
|---|---|---|---|
| Active Connections | `.sheet` (modal) | `.popover` (anchored) | Sheet là modal/dim, không light-dismiss; popover anchor toolbar + light-dismiss tự nhiên |
| Quick switcher | `.frame(width:height:)` fix | `.frame(width:)` + size-to-content cap | List trong SwiftUI expand to fill, không shrink to content |

## File changes

**#1386** (Active Connections):
- `MainContentCoordinator.swift` — add `isConnectionSwitcherShown`; remove `.connectionSwitcher` từ `ActiveSheet`
- `MainContentCommandActions.swift` — `openConnectionSwitcher()` set flag
- `MainContentView.swift` — drop `.connectionSwitcher` sheet case
- `MainWindowToolbar+Buttons.swift` — `ConnectionToolbarButton` carry `.popover` binding
- `ConnectionSwitcherSheet.swift` → `ConnectionSwitcherPopover.swift` (rename + rewrite)
- Mới `ConnectionSwitcherFilter.matches(_:query:)` (pure, testable)
- `ConnectionSwitcherFilterTests.swift` mới

**#1392** (Quick switcher):
- `QuickSwitcherSheet.swift` — drop fixed height; row pinned height; loading/no-results self-size
- `QuickSwitcherViewModel.swift` — `listHeight(rowHeight:headerHeight:maxVisibleRows:)` (pure)
- `isLoading` default `true` → tránh flash "No objects found"
- 8 unit tests trên view model
