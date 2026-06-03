# toolbar — README

## Items

1. **Active Connections modal không có nút đóng** (#1350 → #1386)
2. **Quick switcher khoảng trống thừa** (#1349 → #1392)

## Files

- [`brief.md`](brief.md) — vấn đề chung "wrong primitive", mục tiêu, kết quả
- [`context.md`](context.md) — 2 case-studies: sheet→popover, fixed height→size-to-content
- [`flow.md`](flow.md) — sequence diagram dismiss flow + size compute flow + comparison
- [`tasks.md`](tasks.md) — PR file list, primitive comparison
- [`decisions.md`](decisions.md) — 6 ADR: popover vs close button, quick switcher giữ sheet, compute-from-content, header trong cap, isLoading default, pure filter type
- [`changelog.md`](changelog.md) — v0.44.0

## Bài học chung

**Wrong SwiftUI primitive là bug thật, không patch quanh.** Nhưng **judge
per-use-case**: Active Connections phù hợp popover; Quick switcher đúng sheet.

## Trạng thái

`DONE-upstream`. Release v0.44.0 (2026-05-23).
