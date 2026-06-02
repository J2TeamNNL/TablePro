# connections — tasks

Review 2026-05-27: thêm PR #1435 (iCloud sync) + item mới safe mode auto-save.

| Item | Issue | PR | Author | Merged | Status |
|---|---|---|---|---|---|
| Safe Mode reset khi mở table | [#1351](https://github.com/TableProApp/TablePro/issues/1351) | [#1376](https://github.com/TableProApp/TablePro/pull/1376) | datlechin | 2026-05-21 | DONE |
| Safe Mode reset qua iCloud sync | — | [#1435](https://github.com/TableProApp/TablePro/pull/1435) | — | 2026-05-26 | DONE |
| Safe Mode changes tự save lại làm connection default | — | [#1461](https://github.com/TableProApp/TablePro/pull/1461) | — | open | OPEN-PR (CONFLICTING, chỉ noise) |

## Safe Mode auto-save (DONE-fork — PR #1461)

**User confirmed 2026-05-27.** Khi thay đổi safe mode trong toolbar (vd. OFF → Read-only),
muốn thay đổi đó tự persist lại làm default của connection, không chỉ sống trong session.
Hiện tại session lưu live value nhưng disconnect → next connect re-seed từ saved connection
default (cũ).

**Root cause**: `DatabaseManager+Sessions.setSafeModeLevel(_:for:)` chỉ update `ConnectionSession.safeModeLevel`.
`ConnectionStorage.save()` không được gọi, nên connection default không đổi.

**Implemented (PR #1461 — open, branch fork)**:

- Added `ConnectionStorage.updateSafeModeLevel(_ level: SafeModeLevel, for connectionId: UUID)`: loads connections, finds by ID, mutates `safeModeLevel`, calls `saveConnections` first, then `syncTracker.markDirty` only if save succeeded and `!localOnly && !isSample`.
- `DatabaseManager+Sessions.setSafeModeLevel(_:for:)` now calls `connectionStorage.updateSafeModeLevel` after updating the in-memory session.
- Added write-through test `updateSafeModeLevelWritesThrough` in `ConnectionStoragePersistenceTests.swift`.

Note: this reverses decision D1 in `decisions.md` (session-only, no write-through). User preference is auto-save; D1 should be updated to reflect the new approach.

**Trade-off**: Auto-persist nghĩa là thay đổi temporary trong session sẽ đổi luôn
connection default. Nếu cần "session override không persist", cần thêm explicit
"Save as default" UX thay vì auto-save.

User preference: auto-save (không cần thêm button).

## Open PR #1461 — trạng thái (VERIFIED 2026-05-30)

PR #1461 còn **mở**, **CONFLICTING** — nhưng conflict chỉ do noise hunks
(`.gitignore` + `CLAUDE.md`), không phải code logic. Code tốt, invariant
`saveConnections()` BEFORE `markDirty()` giữ đúng.

> Note: claim cũ "merged 2026-05-28 / DONE-fork" bị **superseded 2026-05-30** — PR vẫn đang mở, đang CONFLICTING.

### Agent checklist

**Setup**
- [ ] Worktree từ branch PR #1461
- [ ] `git fetch upstream`

**Gỡ noise (root cause conflict)**
- [ ] Reset `.gitignore` về main: `git checkout upstream/main -- .gitignore` (lines 128,158-160 đã có trên main)
- [ ] Nếu diff đụng `CLAUDE.md:171` "Favorite tables" → bỏ (đã có trên main)
- [ ] `git rebase upstream/main` → conflict tự hết

**Build / test / lint**
- [ ] `xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation`
- [ ] Test: `-only-testing:TableProTests/ConnectionStoragePersistenceTests` (suite `updateSafeModeLevelWritesThrough`)
- [ ] `swiftlint lint --strict`

**Ship**
- [ ] Push branch, confirm hết conflict → merge

**Không cần làm**
- Không sửa code logic (review xác nhận invariant đúng, không bug chặn merge).

## File changes

- `TablePro/.../ConnectionSession.swift` — thêm `safeModeLevel`, seed từ `connection.safeModeLevel` on connect
- `TablePro/.../ConnectionToolbarState.swift` — bỏ overwrite `safeModeLevel` trong `update(from:)`; `syncFromSession` resolve từ session
- `TablePro/.../MainContentCoordinator.swift` — `setSafeModeLevel(_:)` update both toolbar state + session (qua `DatabaseManager.setSafeModeLevel`)
- `TablePro/.../MainContentCommandActions.swift` — `safeModeLevel` đọc live toolbar state thay vì saved connection
- Tests: `ConnectionSessionTests`, `ConnectionToolbarStateTests`

## Note

Scope `connections/` ở đây CHỈ chứa #1351 vì user list chỉ có 1 item connections.
Upstream còn nhiều PR khác cùng scope (#1366 DBeaver — đặt ở `import/`; #1367 cancel
race; #1370 SSH tunnel; v.v.) — không nằm trong 13 items user flag.
