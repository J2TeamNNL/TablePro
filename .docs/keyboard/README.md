# `keyboard/` — F-key shortcuts (F5/F9/F1) + tooltip improvements

Scope: `feat(keyboard)` — handoff cho 1 conversation/agent fix PR #1489. PR của fork `J2TeamNNL/TablePro` → upstream `TableProApp/TablePro`.

## Vấn đề

Toolbar chưa có phím chức năng nhanh cho các action chính (refresh, execute, docs). PR thêm F5/F9/F1 và cải thiện tooltip trên toolbar buttons.

## Fix

`FunctionKeyShortcutMonitor` (NSEvent local monitor) bắt F5/F9/F1, dispatch tới refresh/execute/docs. Menu filtering trả `nil` cho F-key tránh double-dispatch. Tooltip hint được thêm vào toolbar + status bar.

## Status

**✅ MERGEABLE — 2026-05-31**, branch `feat/function-key-shortcuts`. Conflict đã resolve (rebuild trên main, bỏ noise, gộp CHANGELOG; không có conflict `Localizable.xcstrings` như note cũ tưởng). Codex P2 F1 (bare F-key primary "ghost") đã fix qua `supportsFunctionKeyPrimary`; F2 verify = không repro. Chờ CI. Khuyến nghị merge **trước** #1484.

| Field | Value |
|---|---|
| PR | [#1489](https://github.com/TableProApp/TablePro/pull/1489) |
| Branch | `feat/function-key-shortcuts` |
| Mergeable | MERGEABLE (CI đang chạy) |
| CLA | ok |
| Diff | feature thật: 10 files (7 production + 1 test + CHANGELOG + docs) |
| Độ ưu tiên | Cao — merge trước #1484 để strings ổn định |

## Files trong folder này

| File | Nội dung |
|---|---|
| `README.md` | File này — index + navigation |
| `brief.md` | One-pager: PR làm gì, files, blocker, đánh giá |
| `content.md` | Code review chi tiết: findings GOOD + conflict thật + optional improvements |
| `flow.md` | Mermaid: monitor lifecycle, F-key dispatch, xcstrings conflict resolution |
| `tasks.md` | Checklist actionable cho agent |
| `decisions.md` | ADR-lite: bỏ noise, merge order, optional improvements, US ANSI |
| `changelog.md` | Timeline review → next steps |

## Key files trong codebase

| File | Vai trò |
|---|---|
| `TablePro/Core/KeyboardHandling/FunctionKeyShortcutMonitor.swift` | NSEvent monitor lifecycle, F-key detection |
| `TablePro/Models/UI/KeyboardShortcutModels.swift` | Model cho shortcut config |
| `TablePro/Views/Settings/KeyboardSettingsView.swift` | Settings UI cho F-key |
| `TablePro/Views/Main/Child/MainWindowToolbar.swift` | Tích hợp shortcut vào toolbar |
| `TablePro/Core/Services/Infrastructure/MainWindowToolbar+Buttons.swift` | Button definitions + tooltip |
| `TablePro/Views/Main/Child/MainStatusBarView.swift` | Status bar shortcut hints |
| `TablePro/AppDelegate.swift` | `monitor.start()` trong app lifecycle |
| `docs/features/keyboard-shortcuts.mdx` | End-user doc F-key shortcuts |
