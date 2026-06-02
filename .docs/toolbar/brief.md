# toolbar — brief

## Scope

Hai control trên toolbar: **Quick Switcher** (Cmd+Shift+O command palette) và
**Active Connections** (connection switcher).

## Vấn đề chung

Cả 2 dùng **wrong SwiftUI primitive**:

- Active Connections: `.sheet` → modal dim background, không light-dismiss,
  không có close button → user kẹt
- Quick switcher: `.frame(width: 460, height: 500)` cố định → `List` không
  shrink to content → list ngắn để lại 80% khoảng trống

## Mục tiêu

Không patch primitive sai bằng workaround (thêm nút đóng, ép height) — đổi sang
primitive đúng:

- Active Connections: `.popover` anchored to toolbar (giống `DatabaseSwitcher`
  đã có sẵn)
- Quick switcher: `.frame(width:)` only + size-to-content cap 9 rows

## Kết quả

| Aspect | Active Connections | Quick switcher |
|---|---|---|
| Open | Click toolbar button hoặc Cmd+Ctrl+C | Cmd+Shift+O |
| Dismiss | Esc, click outside, click toolbar lần nữa | Esc, click outside |
| Search | NSSearchField inline | Inline text |
| Keyboard nav | ↑↓ Enter | ↑↓ Enter |
| Size | Content-sized | Content-sized, cap 9 rows |
| HIG conform | Popover = transient source-anchored | Sheet = command palette modal |

## Pattern reference

- TablePlus: connection switcher = searchable toolbar popover
- macOS HIG: popover cho transient source-anchored view; sheet cho task có
  save/cancel
