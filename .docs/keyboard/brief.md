# Brief — `keyboard/` (PR #1489)

## PR làm gì

Thêm phím chức năng F-key và cải thiện tooltip:

1. **F5** — Refresh / reload table data
2. **F9** — Execute query
3. **F1** — Mở docs / help
4. **Tooltip improvements** — cải thiện hiển thị tooltip trên toolbar buttons + status bar hints

Diff: +364/-18, 12 files (7 production + 1 test + 1 docs + 3 noise).

## Files production

| File | Vai trò |
|---|---|
| `FunctionKeyShortcutMonitor.swift` | NSEvent monitor lifecycle, F-key detection |
| `KeyboardShortcutModels.swift` | Model cho shortcut config |
| `AppDelegate.swift` | `monitor.start()` trong app lifecycle |
| `MainWindowToolbar.swift` | Tích hợp shortcut vào toolbar |
| `MainWindowToolbar+Buttons.swift` | Button definitions + tooltip |
| `MainStatusBarView.swift` | Status bar shortcut hints |
| `KeyboardSettingsView.swift` | Settings UI cho F-key |

## Blocker hiện tại

✅ Hết blocker (2026-05-31). Conflict đã resolve: chỉ là `CHANGELOG.md` header trùng + noise `.gitignore`/`CLAUDE.md` (đã có trên main); KHÔNG có conflict `Localizable.xcstrings` (note cũ suy đoán sai). Codex P2 F1 đã fix. PR `MERGEABLE`.

## Đánh giá tổng

Code chắc chắn: monitor lifecycle đúng (`stop()` gọi `NSEvent.removeMonitor`), F-key mapping đúng US ANSI, conflict detection check cả primary lẫn alternate, menu filtering tránh double-dispatch. Bổ sung sau review: `supportsFunctionKeyPrimary` chặn gán bare F-key làm primary cho action không có path dispatch. Khuyến nghị merge **trước** #1484.
