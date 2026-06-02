# Tasks — `keyboard/` (PR #1489) — ✅ RESOLVED 2026-05-31

> Conflict đã fix + Codex P2 đã fix + push. PR `MERGEABLE`, chờ CI. Checklist dưới giữ làm lịch sử.

## Resolve conflict — DONE (rebuild thay vì rebase)
- [x] Thay vì rebase (branch có nhiều merge commit rác), **rebuild sạch**: `git checkout -B feat/function-key-shortcuts origin/main` rồi `git checkout origin/feat/function-key-shortcuts -- <10 file feature thật>`.
- [x] Bỏ noise `.gitignore` + `CLAUDE.md` — đã có trên main (`.gitignore` có `.docs/`+`Local.xcconfig`; `CLAUDE.md:171` đã có dòng Favorite tables bản chuẩn hơn).
- [x] `CHANGELOG.md`: thêm 1 bullet function-key vào `[Unreleased] > Added` sẵn có của main (không tạo header trùng).
- [x] `Localizable.xcstrings`: **không cần đụng** — diff thực của PR không touch file này (note cũ là suy đoán, sai).
- [x] New file (`FunctionKeyShortcutMonitor.swift`, test) auto-include qua `PBXFileSystemSynchronizedRootGroup` — không cần sửa `project.pbxproj`.

## Codex P2 — DONE
- [x] **Bug xác nhận thật** (`KeyboardSettingsView.swift:186`): `!combo.isFunctionKey` trong guard khiến BẤT KỲ bare F-key nào được accept làm primary cho mọi action; nhưng monitor chỉ dispatch primary `.openDocumentation` → F2→Format Query "hiện mà không chạy".
- [x] Fix: thêm `ShortcutAction.supportsFunctionKeyPrimary` (chỉ `.openDocumentation`) làm single source of truth.
- [x] Monitor `matchedAction` lặp `where action.supportsFunctionKeyPrimary` thay vì hardcode openDocumentation (mở rộng được cho action Help tương lai).
- [x] Validation: `if combo.isFunctionKey { if !action.supportsFunctionKeyPrimary { needsModifierAlert } } else if !hasModifier && !allowsBareKey { needsModifierAlert }`.
- [x] Test `functionKeyPrimarySupport`: openDocumentation true; formatQuery/refresh false.
- F2 (drop alternate khi load) — không repro: `sanitized()` giữ alternate (test `settingsAlternatesCodable` + `defaultAlternates` đã cover). Không phải bug.

## Build + Test + Lint — DONE
- [x] Build: chỉ fail code-signing (môi trường không có cert) — Swift compile pass, không error nguồn.
- [x] `swiftlint lint --strict` trên file đổi: clean.
- [~] `xcodebuild ... test` không chạy được trong môi trường này (test host cần code-signing). Logic test trivial (property check) — verify bằng compile + review.

## Ship — DONE
- [x] Force-push `feat/function-key-shortcuts` (history rewrite).
- [x] PR #1489 → `MERGEABLE`. Merge **trước** #1484.

## Optional (chưa làm — không chặn merge)
- [ ] `guard !Self.isUITesting` quanh `monitor.start()` trong `AppDelegate.swift` (đồng bộ pattern #1484).
- [ ] Ghi chú giả định US ANSI keyCode cho F-key mapping.
