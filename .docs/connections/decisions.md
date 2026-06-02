# connections — decisions

## D1. ~~Session là source-of-live-state, KHÔNG persist back saved Connection~~ (superseded by PR #1461)

> **Superseded 2026-05-28.** PR #1461 implemented option (a) — write-through to saved Connection. See updated decision below.

**Context.** Live value của Safe Mode cần persist qua reconfigure. 3 options:

- (a) **Persist back vào saved `Connection` (write-through tới user data)** ✓ *(chosen in PR #1461)*
- (b) Lưu sang `UserDefaults` key per-connection
- (c) ~~Lưu trên `ConnectionSession` (in-memory, per-connect)~~ *(original choice, superseded)*

**Chosen (updated).** (a). `ConnectionStorage.updateSafeModeLevel(_:for:)` writes the new level to disk whenever the user changes it in the toolbar. `DatabaseManager+Sessions.setSafeModeLevel(_:for:)` updates both the live `ConnectionSession` and persists to storage. Disconnect-then-reconnect now restores the last-used level.

**Consequence.** Toolbar safe-mode changes are permanent by default. There is no "temporary override" UX — any change sticks. This was the user-confirmed preference (auto-save, no extra button).

---

## D2. Bỏ overwrite trong `update(from:)`, dùng `syncFromSession`

**Context.** `ConnectionToolbarState.update(from connection:)` hard-set mọi field
từ saved → đè live value.

**Options.**
- (a) Conditional skip nếu live != saved
- (b) **Tách thành 2 method: `update(from:)` cho saved-only fields, `syncFromSession`
  cho live fields** ✓

**Chosen.** (b). (a) cần track "user explicitly set" flag → state machine phức tạp.
(b) làm rõ semantic mỗi field thuộc nhóm nào:

- Saved-bound: `name`, host, port, ... → `update(from: connection)`
- Live-bound: `safeModeLevel` (và sẽ là các field tương lai như selected schema) →
  `syncFromSession(_:)`

---

## D3. Write-through 2 chỗ cùng lúc

**Context.** `setSafeModeLevel(_:)` cần update cả toolbar state (UI) và session (state).

**Options.**
- (a) Single source (session); toolbar state là computed property
- (b) **Cả 2 đều có copy, sync qua single setter** ✓
- (c) Observable session, toolbar subscribe

**Chosen.** (b) đơn giản nhất. Setter là single entry → impossible to drift.
(a) gây tradition issue cho `@Published`; (c) thêm subscription overhead cho 1 enum
field.

**Pattern reuse.** `MainContentCoordinator.setSafeModeLevel` là single setter, cả 2
write-through. Action menu, toolbar badge, command actions đều đọc từ toolbar state
(now live).

---

## D4. Tests cô lập per-layer

**Context.** Có 3 layer touch safe mode: session, toolbar state, coordinator.

**Chosen.**

- `ConnectionSessionTests`: seed-from-connection-default
- `ConnectionToolbarStateTests`: live level survives `update(from:)` + tracks session

Coordinator-level integration không test riêng vì pattern setter rõ ràng. Mỗi
layer test riêng pure behavior — không integration test (chậm + brittle).

---

## D5. Persist order: `saveConnections()` TRƯỚC `markDirty()` (PR #1461)

**Context.** `ConnectionStorage.updateSafeModeLevel(_:for:)` vừa ghi file vừa
notify sync tracker. `markDirty` fire `postChangeNotification` có thể trigger sync;
nếu file trên disk chưa cập nhật khi sync chạy → sync sai/re-upload state cũ.

**Options.**
- (a) `markDirty` trước rồi save
- (b) **`saveConnections()` trước, `markDirty()` chỉ khi save thành công** ✓

**Chosen.** (b) — đúng invariant "persist first, then notify" (CLAUDE.md sync
delete ordering). Thêm guard `!localOnly && !isSample` trước `markDirty` → không
sync sample/local-only connection.

---

## D6. Bỏ noise `.gitignore`/`CLAUDE.md` khỏi PR #1461 (open PR)

**Context.** Branch PR #1461 lỡ commit hunk `.gitignore` (`Local.xcconfig`,
`/plans/reports`, `.docs/`) và `CLAUDE.md:171` "Favorite tables" — cả 2 đã có trên
main (VERIFIED 2026-05-30). Đây là nguyên nhân PR CONFLICTING (không phải code).

**Options.**
- (a) Giữ hunk → CONFLICTING vô nghĩa
- (b) **Reset 2 file về upstream + rebase** ✓

**Chosen.** (b). `git checkout upstream/main -- .gitignore`, rebase `upstream/main`.
Gỡ commit môi trường lỡ tay, không trade-off.
