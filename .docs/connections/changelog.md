# connections — changelog

## Timeline

| Date | Event |
|---|---|
| 2026-05-20 05:30 | Issue [#1351](https://github.com/TableProApp/TablePro/issues/1351) opened by datlechin |
| 2026-05-21 17:18 | PR [#1376](https://github.com/TableProApp/TablePro/pull/1376) opened |
| 2026-05-21 17:38 | PR #1376 merged |

## PR #1461 — open fork PR

| Date | Event |
|---|---|
| — | PR #1461 mở: auto-save safe mode về connection default + test |
| 2026-05-29 | Review: code tốt, invariant `saveConnections()` BEFORE `markDirty()` đúng |
| 2026-05-30 | Re-verify against main: CONFLICTING — nhưng chỉ do noise hunks `.gitignore`/`CLAUDE.md` (đã có trên main `.gitignore:128,158-160`, `CLAUDE.md:171`). Next: drop noise → rebase → verify test → merge |

> Note: bản ghi cũ "2026-05-28 PR #1461" hàm ý đã merge; **superseded 2026-05-30** — PR vẫn đang mở, đang CONFLICTING (noise only).

**Root cause fixed**: `DatabaseManager+Sessions.setSafeModeLevel(_:for:)` only updated the
in-memory `ConnectionSession`; `ConnectionStorage` was never written, so the next reconnect
re-seeded safe mode from the old saved default.

**Fix**: Added `ConnectionStorage.updateSafeModeLevel(_ level: SafeModeLevel, for connectionId: UUID)`.
It loads connections, finds by ID, mutates `safeModeLevel`, calls `saveConnections` (checks Bool
return), then calls `syncTracker.markDirty` only if the save succeeded and the connection is
not `localOnly` and not `isSample`. `DatabaseManager+Sessions` now calls this after updating
the in-memory session.

**Test added**: `updateSafeModeLevelWritesThrough` in `ConnectionStoragePersistenceTests.swift`
verifies the level is written to disk and survives a fresh load.

**Files changed**:
- `DatabaseManager+Sessions.swift`
- `ConnectionStorage.swift`
- `ConnectionStoragePersistenceTests.swift`

Note: this implements the behavior that D1 in `decisions.md` explicitly ruled out (write-through
to saved Connection). The user's requirement changed; D1 needs updating.

---

## Release

### [v0.43.2] — 2026-05-22

**Fixed**
- Safe mode no longer resets when you open another table; it stays set for the
  connection until you change it (#1351)
