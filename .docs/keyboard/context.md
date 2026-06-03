# Code review — `keyboard/` (PR #1489)

> ⚠️ **Design CŨ (superseded) — verified 2026-06-02.** Review dưới dựa trên `FunctionKeyShortcutMonitor` + `supportsFunctionKeyPrimary`, các symbol này KHÔNG còn trên feat branch `8342e510`. Impl hiện tại: `KeyCode.functionKeyIndex` + `KeyboardLayout`/`ShortcutConflictResolver`/`SystemHotkeyChecker`. Giữ làm history; re-verify trong worktree `../TablePro-pr1489`.

## Files changed

**Production**
- `TablePro/AppDelegate.swift` — gọi `monitor.start()` sớm trong app lifecycle
- `TablePro/Core/KeyboardHandling/FunctionKeyShortcutMonitor.swift` — NSEvent monitor lifecycle
- `TablePro/Core/Services/Infrastructure/MainWindowToolbar+Buttons.swift` — button definitions + tooltip
- `TablePro/Views/Main/Child/MainWindowToolbar.swift` — tích hợp shortcut vào toolbar
- `TablePro/Models/UI/KeyboardShortcutModels.swift` — model shortcut config
- `TablePro/Views/Main/Child/MainStatusBarView.swift` — status bar shortcut hints
- `TablePro/Views/Settings/KeyboardSettingsView.swift` — settings UI cho F-key

**Tests**
- `TableProTests/Core/KeyboardShortcutModelsTests.swift` — unit test models

**Docs**
- `docs/features/keyboard-shortcuts.mdx` — cập nhật F-key shortcuts

**Noise (bỏ)**
- `.gitignore` — đã có trên main (`.gitignore:128, 158-160`)
- `CLAUDE.md` — dòng "Favorite tables" đã có trên main (`CLAUDE.md:171`)
- `CHANGELOG.md` — conflict với #1484 (cả 2 thêm section `[Unreleased]`)

## Findings — Đúng / tốt (VERIFIED 2026-05-30)

### NSEvent monitor lifecycle
- `FunctionKeyShortcutMonitor.stop()` gọi `NSEvent.removeMonitor(eventMonitor)` đúng cách
- Token monitor được lưu trữ, không leak
- Double-start guarded (không register 2 lần)
- Dùng `weak self` trong closure + responder check cho recorder
- Kết luận: KHÔNG có memory leak

### F-key mapping
- Mapping đúng layout US ANSI (keyCode chuẩn cho F1/F5/F9)
- Conflict detection check cả primary shortcut lẫn alternate shortcut

### Menu / dispatch
- Menu filtering trả `nil` cho F-key → tránh double-dispatch (F-key không trigger cả menu lẫn monitor)
- Validation bare F-key (không modifier) hợp lý UX

### Integration
- `monitor.start()` được gọi sớm trong `AppDelegate` — đúng vị trí

## Conflict thật — ✅ RESOLVED 2026-05-31

| File | Lý do conflict (giả định cũ) | Thực tế |
|---|---|---|
| `Localizable.xcstrings` | PR #1489 và #1484 cùng thêm string keys mới | **Sai** — diff thực của #1489 KHÔNG touch `Localizable.xcstrings`. Note này là suy đoán, không có thật. |
| `CHANGELOG.md` | Cả 2 PR thêm section `[Unreleased]` | Đúng — branch chèn header `### Added` mới trùng với main đã có `[Unreleased] > Added`. |
| `.gitignore`, `CLAUDE.md` | noise môi trường | Đã có trên main, gỡ. |

**Cách resolve (2026-05-31)**: rebuild branch thẳng trên `origin/main` rồi `git checkout origin/feat/function-key-shortcuts -- <10 file feature thật>`; thêm 1 bullet function-key vào `[Unreleased] > Added` sẵn có (không tạo header trùng); bỏ noise. New file auto-include qua `PBXFileSystemSynchronizedRootGroup`. Force-push → PR `MERGEABLE`.

## Codex automated review (GitHub) — P2

> Input từ **bot Codex tự động** trên PR #1489 (không phải maintainer). Review diff trước đó của fork đánh giá #1489 "clean / monitor đúng" — **bỏ sót finding F1**.

### F1: Bare F-key primary mà monitor không bao giờ dispatch — ✅ FIXED 2026-05-31

- **Vị trí**: `TablePro/Views/Settings/KeyboardSettingsView.swift:186`.
- **Codex**: validation cho phép record một bare function-key làm **primary** shortcut cho bất kỳ menu-driven action nào. Nhưng `keyboardShortcut(for:)` trả `nil` cho F-key, và `FunctionKeyShortcutMonitor.matchedAction` chỉ dispatch primary `openDocumentation` cộng các alternate `refresh`/`executeQuery`. Gán F2 làm primary cho Format Query → accept + hiển thị, nhưng nhấn F2 **không bao giờ tới action**.
- **Root cause**: guard `if !combo.hasModifier, !action.allowsBareKey, !combo.isFunctionKey` — term `!combo.isFunctionKey` khiến MỌI F-key được accept làm primary.
- **Fix**: thêm `ShortcutAction.supportsFunctionKeyPrimary` (chỉ `.openDocumentation`) làm single source of truth.
  - Monitor `matchedAction` lặp `where action.supportsFunctionKeyPrimary` thay hardcode openDocumentation.
  - Validation đổi thành: `if combo.isFunctionKey { if !action.supportsFunctionKeyPrimary { needsModifierAlert } } else if !hasModifier && !allowsBareKey { needsModifierAlert }`.
  - Test `functionKeyPrimarySupport`. Xem [`decisions.md`](decisions.md) D6.

### F2: `sanitized()` có thể drop alternate shortcuts khi load — ❌ KHÔNG REPRO

- **Codex nghi**: `AppSettingsStorage.loadKeyboard()` gọi `sanitized(...)` khi load có thể xoá nhầm alternate.
- **Verify**: `sanitized()` giữ nguyên alternate; test `settingsAlternatesCodable` (round-trip Codable) + `defaultAlternates` đã cover. **Không phải bug** → không sửa.

## Optional improvements (chưa làm — không chặn merge)

1. `guard !Self.isUITesting` quanh `monitor.start()` trong `AppDelegate` — đồng bộ pattern PR #1484.
2. Ghi chú giả định layout US ANSI cho keyCode F-key.

## Kết luận

Conflict đã resolve (rebuild trên main, không có conflict `Localizable.xcstrings` như note cũ tưởng). Codex P2 F1 đã fix qua `supportsFunctionKeyPrimary`; F2 verify = không repro. Build compile pass (chỉ fail code-signing môi trường), swiftlint --strict clean. PR #1489 → `MERGEABLE`.
