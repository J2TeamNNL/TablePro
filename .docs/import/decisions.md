# import — decisions

## D1. Username là metadata, không phải secret

**Context.** UI có toggle "Include passwords" cho user privacy. Importer cũ gate
**toàn bộ credentials-config.json load** behind toggle → username (cũng nằm trong
file đó) bị skip theo.

**Options.**
- (a) Đổi UI: thêm toggle riêng "Include usernames" (over-engineered)
- (b) **Phân biệt field-level: load file luôn, chỉ field `password` gated** ✓
- (c) Force include passwords mọi lúc

**Chosen.** (b) — match mental model user: "include passwords" có nghĩa **password**,
không phải mọi thứ trong file credentials. Username = metadata visible trong UI
DBeaver, không phải secret.

**Consequence.** Một số user paranoid có thể không hiểu file vẫn được đọc dù
"include passwords = no". Document trong import wizard tooltip hoặc release notes.

---

## D2. Precedence: credentials > configuration

**Context.** Cả 2 file đều có thể có `user` (DBeaver < 6.1.3 hoặc config bị migrate
không sạch).

**Options.**
- (a) Configuration thắng (legacy compat)
- (b) **Credentials thắng (modern source-of-truth)** ✓
- (c) Báo lỗi nếu cả 2 có

**Chosen.** (b) — DBeaver 6.1.3+ treat credentials file là canonical. Config có
user chỉ là leftover từ pre-migration. Tránh dùng stale value.

---

## D3. Fallback chain rõ ràng thay vì hard branch by version

**Context.** Có thể detect version DBeaver và switch implementation.

**Options.**
- (a) `if dbeaverVersion >= 6.1.3 { reads creds } else { reads config }`
- (b) **Fallback chain: `creds?.user ?? config.user ?? ""`** ✓

**Chosen.** (b) — không phải detect version (DBeaver không expose dễ); chain
naturally handle:
- Modern: creds có → dùng
- Legacy: creds không có → fallback config
- Admin/env-template (không có credentials file): fallback config
- Edge case file corrupted: fallback hoặc empty (an toàn)

---

## D4. PR ngắn nhưng test rộng

**Context.** Fix chỉ ~50 LOC, nhưng có 4 tests.

**Chosen.** Test mỗi path của fallback chain + precedence + gating decision.
Lessons từ scope `datagrid/` D8 (user-clear vs internal-reset): import có nhiều
path subtle, không cover sẽ regression sau.

---

## D5. Pattern transferable tới importer khác

**Context.** Upstream có importer cho TablePlus, DataGrip, Beekeeper. Mỗi tool
storage khác.

**Chosen.** Pattern chung — mỗi importer split file storage:

| Tool | Metadata source | Secret source | TablePro PR |
|---|---|---|---|
| DBeaver | data-sources.json | credentials-config.json | #1366 |
| TablePlus | TablePlus.plist | macOS Keychain | #1388 |
| DataGrip | dataSources.local.xml | KeePass-encrypted vault | #1374 |
| Beekeeper | apps.config json | same file (less common) | #1320 |

→ Mọi importer "load metadata file luôn, gate secret access by user choice".
Documenting pattern này ở fork khi build importer mới (e.g. HeidiSQL, Sequel Ace).

---

# Open fork PR #1462 — decisions (2026-05-30)

## D6. Drop noise `.gitignore` / `CLAUDE.md`
- **Context.** upstream/main đã có entries; PR add lại = conflict giả.
- **Decision.** reset 2 file về upstream trong branch khi rebase.
- **Trade-off.** không có.

## D7. Đổi duplicate key sang host/port/database/username
- **Context.** key cũ (name+host+port+type) bỏ sót trùng khi tên khác nhau.
- **Decision.** giữ key mới — 2 connection cùng server/db/user là trùng dù tên hiển thị khác.
- **Trade-off.** false positive khi user cố ý có 2 connection khác tên đến cùng endpoint;
  chấp nhận được vì UI cho chọn Skip.

## D8. Giữ refactor 3 bước (analyzeImport → prepareImport → performPreparedImport)
- **Context.** main có 1 hàm monolithic gọi trực tiếp `ConnectionStorage.shared`, khó unit test.
- **Decision.** giữ refactor — inject deps, tách analyze / plan / execute.
- **Trade-off.** thêm surface API; chấp nhận được vì +434 dòng test.

## D9. Merge sau khi verify test thực chất
- **Context.** test file mới 434 dòng — cần chắc không phải stub.
- **Decision.** chạy `ConnectionImportServiceTests`, confirm test fail khi bỏ
  `normalizedLookupKey` trước khi merge.
