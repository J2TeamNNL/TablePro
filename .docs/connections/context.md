# connections — content (case-study)

## Safe Mode reset khi mở table (#1351 → #1376)

### Symptom

1. Connect tới DB → Safe Mode default từ saved connection (e.g. "Off")
2. Toolbar dropdown → đổi sang "Read-only with confirm"
3. Click 1 table khác từ sidebar → mở table mới
4. **Toolbar dropdown reset về "Off"** (saved default)

Tương tự sau bất kỳ `reconfigure(from connection:)` nào.

### Root cause

3 chỗ cùng đọc/ghi safe mode, nhưng tất cả point về **saved connection**, không
có nơi nào lưu live value:

```swift
// ConnectionToolbarState.update(from:) (cũ)
func update(from connection: Connection) {
    self.name = connection.name
    self.safeModeLevel = connection.safeModeLevel  // ⟵ overwrite mỗi lần
    // ...
}

// MainContentCommandActions.safeModeLevel (cũ)
var safeModeLevel: SafeModeLevel {
    coordinator.activeConnection?.safeModeLevel ?? .off  // ⟵ đọc saved
}
```

Khi mở table → `MainContentCoordinator` reconfigure → `ConnectionToolbarState.update`
chạy → overwrite. Toolbar badge revert. Action menu cũng đọc saved → mọi nơi
inconsistent với live UI nếu có cache.

### Fix approach (PR #1376) — session là source-of-live-state

```swift
// ConnectionSession (mới có safeModeLevel)
final class ConnectionSession {
    let connection: Connection
    var safeModeLevel: SafeModeLevel  // seed từ connection.safeModeLevel on connect
    // ...
}

// ConnectionToolbarState.update(from:) (mới)
func update(from connection: Connection) {
    self.name = connection.name
    // KHÔNG còn overwrite safeModeLevel
}
func syncFromSession(_ session: ConnectionSession) {
    self.safeModeLevel = session.safeModeLevel  // resolve từ session
    // (fallback session?.safeModeLevel ?? connection.safeModeLevel handled trong session init)
}

// MainContentCoordinator
func setSafeModeLevel(_ level: SafeModeLevel) {
    toolbarState.safeModeLevel = level         // write-through 1
    databaseManager.setSafeModeLevel(level)    // write-through 2 → session
}

// MainContentCommandActions.safeModeLevel (mới)
var safeModeLevel: SafeModeLevel {
    coordinator.toolbarState.safeModeLevel  // ⟵ đọc live
}
```

### Lifecycle

```
connect → session seeded từ connection.safeModeLevel
       ↓
user changes badge → setSafeModeLevel
       ↓
write-through: toolbarState ← session
       ↓
reconfigure (open table) → update(from:) skip safeModeLevel
                         → syncFromSession resolve lại từ session (live giữ)
       ↓
disconnect → session destroyed → next connect re-seed từ saved
```

### Tests

- `ConnectionSessionTests` — session seed từ connection default ban đầu
- `ConnectionToolbarStateTests` — live level survives `update(from:)` và track session

---

## Safe Mode auto-save về connection default (OPEN — 2026-05-27)

### Symptom

1. Connect DB → Safe Mode = "Off" (saved default)
2. Toolbar → đổi sang "Read-only with confirm"
3. Disconnect + reconnect
4. **Safe Mode về "Off" lại** (session destroyed, re-seed từ saved default cũ)

User muốn: đổi safe mode → tự save lại làm connection default.

### Root cause

```swift
// DatabaseManager+Sessions.setSafeModeLevel (hiện tại)
func setSafeModeLevel(_ level: SafeModeLevel, for connectionId: UUID) {
    sessions[connectionId]?.safeModeLevel = level   // chỉ update session
    // ConnectionStorage.save() không được gọi → default không đổi
}
```

Session lifecycle:

```
connect → session seeded từ connection.safeModeLevel (saved default)
user đổi → session.safeModeLevel update
disconnect → session destroyed
reconnect → session re-seed từ connection.safeModeLevel (KHÔNG đổi) → revert
```

### Fix approach

Khi `setSafeModeLevel` được gọi, persist luôn vào `DatabaseConnection`:

```swift
func setSafeModeLevel(_ level: SafeModeLevel, for connectionId: UUID) {
    guard let session = sessions[connectionId] else { return }
    session.safeModeLevel = level
    connectionStorage.updateSafeModeLevel(level, for: connectionId)
}
```

`ConnectionStorage.updateSafeModeLevel(_:for:)` cần thêm:

```swift
func updateSafeModeLevel(_ level: SafeModeLevel, for id: UUID) {
    guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
    connections[idx].safeModeLevel = level
    saveConnections()    // existing save path
}
```

### Note

User preference: auto-save ngay lập tức, không cần "Save as default" button riêng.
Nếu sau này có yêu cầu "temporary session override", cần bổ sung UX riêng — nhưng
hiện tại không cần.

### Tests

- Sau `setSafeModeLevel`, `ConnectionStorage` có connection với level mới
- Disconnect + reconnect → session được seed từ level đã persist
- Không ảnh hưởng các session khác dùng cùng connection

---

## Open fork PR #1461 — code review & conflict resolution

> Handoff cho agent fix PR đang mở. Branch fork → upstream `TableProApp/TablePro`.
> Implement "auto-save về connection default" ở phần trên. **VERIFIED 2026-05-30 against main.**

### Trạng thái

| Field | Value |
|---|---|
| PR | [#1461](https://github.com/TableProApp/TablePro/pull/1461) |
| Mergeable | CONFLICTING — nhưng chỉ noise hunks, code tốt |
| Blocker | noise `.gitignore` + `CLAUDE.md` (đã có trên main), cần rebase |

### Files changed (production)

| File | Thay đổi |
|---|---|
| `Core/Storage/ConnectionStorage.swift` | mới `updateSafeModeLevel(_:for:)`: load → find by ID → mutate `safeModeLevel` → `saveConnections()` FIRST → `syncTracker.markDirty` chỉ khi save thành công và `!localOnly && !isSample` |
| `Core/Database/DatabaseManager+Sessions.swift` | `setSafeModeLevel(_:for:)` gọi `connectionStorage.updateSafeModeLevel` sau khi update session in-memory |
| `ConnectionStoragePersistenceTests.swift` | mới `updateSafeModeLevelWritesThrough` — verify level ghi xuống disk + survive fresh load |

### Findings (verified)

**Đúng / tốt**

- Invariant giữ đúng: `saveConnections()` chạy **TRƯỚC** `syncTracker.markDirty()` trong `ConnectionStorage.updateSafeModeLevel`. Đúng với invariant "persist first, then notify" (CLAUDE.md sync delete ordering) — markDirty fire `postChangeNotification` có thể trigger sync; nếu file chưa persist thì sync sai.
- Filter `!localOnly && !isSample` trước `markDirty` → không sync sample/local-only connection.
- Test cover write-through + reload.

### Conflict analysis — chỉ noise

PR đang CONFLICTING nhưng nguyên nhân **không phải code logic**, chỉ là 2 hunk môi trường lỡ commit, đã có sẵn trên main:

- `.gitignore` — `Local.xcconfig`, `/plans/reports`, `.docs/` đã có trên main (`.gitignore:128,158-160`, VERIFIED 2026-05-30).
- `CLAUDE.md:171` "Favorite tables" row đã có trên main (VERIFIED 2026-05-30).

### Fix approach

Bỏ 2 hunk noise → rebase trên `upstream/main` → conflict tự hết → verify test → merge. Không sửa code logic. Chi tiết checklist xem `tasks.md` § "Open PR #1461 — agent checklist".
