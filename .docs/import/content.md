# import — content (case-study)

## DBeaver import mất username (#1355 → #1366)

### Symptom

Import connection từ DBeaver. UI cho phép chọn "Include passwords" yes/no. Sau
import:
- Host, port, database, SSH config: ✅ đúng
- Password: ✅ đúng (nếu chọn include) hoặc rỗng (intentional)
- **Username: rỗng** (mọi lúc, dù include password)

→ User phải edit từng connection, fill username thủ công.

### Root cause

DBeaver 6.1.3+ tách credentials ra file riêng có encrypt:

```
~/.local/share/DBeaverData/workspace6/General/.dbeaver/
├── data-sources.json          ← config (host, port, ssh, ssl, …)
└── credentials-config.json    ← username + password (encrypted)
```

**Format cũ** (DBeaver < 6.1.3 / admin / env-template configs):
```json
// data-sources.json
{
  "connections": {
    "abc": {
      "name": "Prod",
      "configuration": {
        "host": "...",
        "user": "alice"   // ⟵ username ở đây
      }
    }
  }
}
```

**Format mới** (6.1.3+):
```json
// data-sources.json
{
  "connections": {
    "abc": {
      "name": "Prod",
      "configuration": {
        "host": "..."
        // không có user
      }
    }
  }
}

// credentials-config.json (DECRYPTED)
{
  "abc": {
    "#connection": {
      "user": "alice",       // ⟵ username giờ ở đây
      "password": "..."
    }
  }
}
```

Importer cũ:
- Đọc `data-sources.json` lấy host/port → OK
- Đọc `configuration.user` → empty trên format mới
- Load credentials file CHỈ khi user check "include passwords" → username bị skip
  cùng với password

### Fix approach (PR #1366)

```swift
// Pseudocode importer
func importConnection(id: String, sources: SourcesFile, creds: CredentialsFile?, includePasswords: Bool) {
    let config = sources.connections[id].configuration
    
    // Username: precedence credentials > configuration
    let username = creds?[id]?["#connection"]?["user"]
                   ?? config["user"]
                   ?? ""
    
    // Password: chỉ khi user choice
    let password = includePasswords
        ? (creds?[id]?["#connection"]?["password"] ?? "")
        : ""
    
    // ...
}

// Importer entrypoint: load creds bất kể includePasswords
func runImport(includePasswords: Bool) {
    let sources = loadDataSources()
    let creds = tryLoadCredentials()  // ⟵ luôn load (không gate)
    for (id, _) in sources.connections {
        importConnection(id: id, sources: sources, creds: creds,
                         includePasswords: includePasswords)
    }
}
```

**Critical change.** Load `credentials-config.json` **regardless** of "include
passwords" choice. Field "user" là metadata, không phải secret. Gate chỉ áp dụng
cho field "password".

### Backward compat

Connection cũ chỉ có `configuration.user` → fallback chain `creds?.user ??
config.user ?? ""` vẫn match.

### Tests (4 cases)

1. **Username from credentials** — credentials có user, config không → username từ creds
2. **Username imported khi passwords excluded** — includePasswords=false, vẫn lấy
   user từ credentials
3. **Fallback to `configuration.user`** — credentials không có user (admin config),
   config có → từ config
4. **Credentials wins precedence** — cả 2 đều có user khác nhau → credentials thắng
   (vì DBeaver coi creds file là source-of-truth mới)

### Note PR

PR ngắn (~50 LOC change + tests). Đây là tip-of-iceberg cho nhiều bug import
khác trong same window (#1320 Beekeeper, #1374 DataGrip, #1388 TablePlus) — mỗi
app có file format / location khác, gồm credentials tách riêng pattern tương tự.

---

## 2. Connection import dedup: Replace / As Copy / Skip (verified 2026-05-30)

> Cập nhật 2026-05-30: PR #1462 đã có UI dedup picker trên main; phần "Fix approach"
> bên dưới (`detectDuplicates`/`isSameEndpoint`, viết 2026-05-27) là **superseded** —
> implementation thực dùng `ConnectionImportDuplicateKey` + `normalizedLookupKey()` +
> refactor 3 bước. Xem mục "Open fork PR #1462" ở cuối file cho code review verified.

### Symptom

Import connections từ DBeaver/TablePlus/DataGrip. TablePro đã có connection trùng
host+database+username. Không có dialog nào — import tạo thêm duplicate hoặc ghi
đè không warning.

### Root cause

`ImportDialog.swift` không kiểm tra connection hiện có trước khi add. Importers
(`DBeaverImporter`, `TablePlusImporter`, v.v.) trả `[DatabaseConnection]` raw, không
so sánh với `ConnectionStorage.connections`.

### Fix approach

**Step 1**: Sau khi importer parse xong, so sánh mỗi `importedConn` với
`ConnectionStorage.connections`:

```swift
func detectDuplicates(
    imported: [DatabaseConnection],
    existing: [DatabaseConnection]
) -> [(imported: DatabaseConnection, conflict: DatabaseConnection?)] {
    imported.map { conn in
        let conflict = existing.first { $0.isSameEndpoint(as: conn) }
        return (conn, conflict)
    }
}

extension DatabaseConnection {
    func isSameEndpoint(as other: DatabaseConnection) -> Bool {
        host == other.host &&
        port == other.port &&
        database == other.database &&
        username == other.username
    }
}
```

**Step 2**: Nếu có conflict, hiện `ImportConflictView`:

```
┌──────────────────────────────────────────┐
│ "Prod DB" already exists                 │
│                                          │
│ A connection to postgres@prod.example    │
│ already exists in TablePro.              │
│                                          │
│  [Replace]  [Import as Copy]  [Skip]     │
│                          [Apply to All]  │
└──────────────────────────────────────────┘
```

- **Replace**: dùng `ConnectionStorage.update(_:)`
- **As Copy**: rename `importedConn.name += " (imported)"`, dùng `ConnectionStorage.add(_:)`
- **Skip**: drop connection khỏi list
- **Apply to All**: áp dụng choice này cho tất cả conflict còn lại (không hiện dialog lần sau)

**Step 3**: Single-conflict case có thể inline vào `ImportSuccessView` thay vì modal riêng.

### Tests

- `ImportDuplicateDetectorTests`: `detectDuplicates` với 0/1/n conflicts
- `ImportConflictResolverTests`: replace, copy (rename), skip, apply-to-all

### Note

"Apply to All" quan trọng khi import nhiều connections (e.g. 50 connections từ
DBeaver, 10 trùng). Không có nó user phải click 10 lần.

---

## Open fork PR #1462 — code review & conflict resolution (verified 2026-05-30)

> Branch `feat/import`. Diff +652 / -46. Mergeable: **CONFLICTING (chỉ noise)**.
> Ưu tiên trung bình — merge sau PR #1459.

PR cải thiện **backend** duplicate detection (UI dedup picker Replace/As Copy/Skip
đã có sẵn trên main trong `ConnectionImportPreviewList.swift` /
`ImportFromAppPreviewStep.swift`; PR không thêm UI mới).

### Files changed

**Production**
- `TablePro/Core/Services/Export/ConnectionExportService.swift` (+201/-44)
  - Thêm `ConnectionImportDuplicateKey` struct + `normalizedLookupKey()`
    (case-insensitive host/port/database/username).
  - Thêm `effectiveDatabaseKey()` cho Redis: dùng `database` nếu có, fallback
    `redisDatabase` (numeric index, default 0) → tránh false positive.
  - Refactor `analyzeImport()` → `prepareImport(resolutions:)` → `performPreparedImport()`.
    Inject deps (`connectionStorage`, `notifyConnectionsChanged`) → test không cần live storage.
  - `uniqueCopyName()` (~`:879`): tìm suffix trống đầu tiên `(Imported)` → `(Imported 2)`…,
    normalize case-insensitive.
  - Localization warnings (SSH key / SSL cert / unknown db type) dùng
    `String(format: String(localized: ...))` — đúng pattern, không interpolation trong key.
- `TablePro/Views/Connection/ImportFromApp/ImportFromAppPreviewStep.swift`
  - Cập nhật call site theo API 3 bước.
  - Lọc `connectionIdMap` loại bỏ connection bị Replace **trước** `restoreCredentials()`
    → không ghi đè Keychain của connection được replace.

**Tests**
- `TableProTests/Core/Services/ConnectionImportServiceTests.swift` (+434 mới):
  dedup host/port/db/user case-insensitive, Redis named vs numeric, `uniqueCopyName()`
  collision, 3 bước pipeline.

**Docs**: `docs/features/connection-sharing.mdx`, `CHANGELOG.md`.

**Noise (drop khi rebase)**: `.gitignore` (entries `Local.xcconfig`, `/plans/reports`
đã có main `:128,158-160`) + `CLAUDE.md:171` (dòng "Favorite tables" đã có main).

### Findings

| Loại | Nội dung |
|---|---|
| Tốt | Dedup key mới (host/port/db/user) đúng ngữ nghĩa hơn key cũ (name/host/port/type). |
| Tốt | `effectiveDatabaseKey()` cần cho Redis (numeric `redisDatabase`). |
| Tốt | `uniqueCopyName()` case-insensitive → tránh `(Imported)` vs `(imported)` trùng. |
| Tốt | `restoreCredentials` filter replaced connections → không overwrite password hiện có. |
| Tốt | Inject deps → unit test không cần `ConnectionStorage.shared` live. |
| Verify | `ConnectionImportServiceTests` phải test thực chất (host khác hoa, `(Imported 2)`, Redis named vs numeric) — không stub happy-path; test phải fail nếu bỏ `normalizedLookupKey`/`effectiveDatabaseKey`. |
| Verify | `uniqueCopyName()` đúng khi tên gốc đã chứa suffix `(Imported)`. |

### Conflict analysis

Chỉ noise (`.gitignore` + `CLAUDE.md:171`, đã trên main). **Không có logic conflict.**
Action: drop noise hunks → rebase `upstream/main` → verify test thực chất → merge.

### Codex automated review (GitHub) — P2

> Input từ **bot tự động** (Codex), commit review `fa5b543b`. Coi là cảnh báo **cần
> verify khi fix**, chưa phải fact đã xác nhận. Diff-review trước đó (mục Findings ở trên)
> **mâu thuẫn** với finding này.

**Redis: dedup key chỉ so sánh `database`, bỏ qua `redisDatabase`**
(inline comment trên `TablePro/Core/Services/Export/ConnectionExportService.swift:890`)

Codex: với connection Redis, database đang chọn được lưu ở `redisDatabase` (và connection
setup fallback về nó khi `database` rỗng), nhưng dedup key mới **chỉ** so sánh `database`.
Import 1 Redis connection cho DB 1 trong khi đã tồn tại connection y hệt ở DB 0 → bị đánh
dấu duplicate. Chọn **Replace** có thể ghi đè nhầm connection đã lưu, hoặc DB khác bị
**Skip** mặc định.

> **Mâu thuẫn với note hiện có.** Mục Findings + "Files changed" ở trên ghi PR đã xử lý
> Redis qua `effectiveDatabaseKey()` (fallback `redisDatabase` khi `database` rỗng). Codex
> (commit `fa5b543b`) nói **KHÔNG** — dedup key thực tế chỉ gồm `database`.
>
> **Cần verify khi fix**: kiểm tra dedup key có thực sự gồm `redisDatabase` không (Codex
> review commit `fa5b543b` nói KHÔNG). Nếu Codex đúng → sửa `normalizedLookupKey()` để
> Redis dùng `effectiveDatabaseKey()` thật sự (gồm numeric `redisDatabase`), và bổ sung
> test "Redis DB 0 vs DB 1 không bị coi là duplicate".
