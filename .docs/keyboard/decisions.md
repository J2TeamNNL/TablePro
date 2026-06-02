# Decisions — `keyboard/` (PR #1489)

## D1: Bỏ noise `.gitignore`/`CLAUDE.md`

- **Context**: Upstream/main đã có sẵn các entry này. PR add lại là commit môi trường lỡ tay.
- **Decision**: Reset 2 file về upstream trong branch.
- **Trade-off**: Không có.

## D2: Merge PR #1489 trước PR #1484

- **Context**: Cả #1489 và #1484 đều thêm entries vào `Localizable.xcstrings`. PR nào land sau phải rebase lại strings.
- **Decision**: Merge #1489 trước vì nhỏ hơn (+364) và không có dependency vào #1484. #1484 rebase sau sẽ dễ hơn.
- **Trade-off**: Nếu #1484 đã sẵn sàng trước thì ưu tiên có thể đảo. Quyết định dựa trên trạng thái hiện tại.

## D3: Optional improvements không chặn merge

- **Context**: 3 cải tiến nhỏ (guard isUITesting, doc comment, US ANSI note) tốt nhưng không fix bug.
- **Decision**: Không bắt buộc. Làm nếu còn thời gian trong cùng PR; nếu không, tạo follow-up task riêng.
- **Trade-off**: Làm ngay thì sạch hơn; để sau thì merge nhanh hơn.

## D5: Codex P2 (F1, F2) là pre-merge fix, KHÔNG optional — ✅ RESOLVED 2026-05-31

- **Context**: Bot Codex tự động trên PR #1489 raise finding P2 mà review diff fork bỏ sót (đã đánh giá nhầm #1489 "clean / monitor đúng"). F1: bare F-key primary cho action menu-driven không bao giờ dispatch nhưng vẫn accept + hiển thị. F2: nghi `sanitized()` trong `loadKeyboard()` drop alternate shortcuts.
- **Decision**: Coi F1 là **bắt buộc fix trước merge** (khác với D3 — 3 improvement kia thật sự optional). F1 là correctness bug (UI nói gán được nhưng phím không chạy).
- **Kết quả**: F1 fixed (xem D6). F2 verify lại = **không repro**: `sanitized()` giữ alternate, đã có test `settingsAlternatesCodable` + `defaultAlternates` cover round-trip → không phải bug, không cần fix.
- **Trade-off**: Không có. Merge mà chưa fix F1 = ship trạng thái shortcut "ghost".

## D6: `supportsFunctionKeyPrimary` làm single source of truth cho F-key primary

- **Context**: Fix F1 có 2 hướng (Codex gợi ý): (a) reject trong validation các primary F-key không có handler; (b) dispatch tất cả primary F-key. Hướng (b) sai vì phần lớn action là menu-driven, không có path dispatch ngoài menu.
- **Decision**: Chọn (a) nhưng tránh hardcode danh sách ở 2 nơi. Thêm `ShortcutAction.supportsFunctionKeyPrimary` (hiện chỉ `.openDocumentation`):
  - `FunctionKeyShortcutMonitor.matchedAction` lặp `where action.supportsFunctionKeyPrimary` thay vì hardcode block `if .openDocumentation` → monitor + validation cùng đọc 1 property.
  - `KeyboardSettingsView.handleRecord`: nếu combo là F-key mà action không `supportsFunctionKeyPrimary` → `needsModifierAlert`, không cho lưu.
- **Trade-off**: Thêm 1 property nhỏ. Đổi lại đúng theo nguyên tắc codebase "design for open-ended" (CLAUDE.md #9): thêm action Help dùng F-key primary sau này chỉ cần set property, không sửa monitor + validation rời rạc. Test `functionKeyPrimarySupport` chốt invariant.

## D4: Giữ nguyên F-key mapping US ANSI

- **Context**: keyCode hardcode theo layout US ANSI. Non-US keyboards có thể mapping khác.
- **Decision**: Giữ nguyên — consistent với cách TablePro handle shortcuts khác. Ghi chú giả định US ANSI là đủ.
- **Trade-off**: Non-US users có thể gặp vấn đề, nhưng đây là vấn đề đã tồn tại trong toàn codebase, không phải regression mới.
