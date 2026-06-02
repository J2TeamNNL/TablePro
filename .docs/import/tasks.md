# import — tasks

Review 2026-05-27: thêm item mới từ user checklist "import từ other app: Replace / As Copy / Skip for All".

| Item | Issue | PR | Author | Merged | Commit | Status |
|---|---|---|---|---|---|---|
| DBeaver import mất username | [#1355](https://github.com/TableProApp/TablePro/issues/1355) | [#1366](https://github.com/TableProApp/TablePro/pull/1366) | datlechin | 2026-05-21 | — | DONE |
| Connection import dedup: Replace / As Copy / Skip for All dialog | — | [#1462](https://github.com/TableProApp/TablePro/pull/1462) | — | open (branch `feat/import`) | — | OPEN-fork (CONFLICTING noise) |

> Cập nhật 2026-05-30: PR #1462 vẫn **open**, branch `feat/import`, diff +652/-46,
> mergeable **CONFLICTING chỉ do noise** (`.gitignore` + `CLAUDE.md:171` đã có main).
> Note "Merged 2026-05-28" bên dưới là **superseded** — chưa merge. Cần drop noise →
> rebase → verify test → merge (sau PR #1459).

## Connection import dedup (OPEN-fork — PR #1462)

> Note dưới đây mô tả behavior; trạng thái merge **superseded** (xem hàng bảng trên: vẫn open).

Khi import connections từ TablePlus/DBeaver/DataGrip/Beekeeper
và TablePro đã có connection trùng, một dialog hiện ra với 3 lựa chọn:

- **Replace** — ghi đè metadata của connection hiện tại; giữ nguyên Keychain entry (không overwrite password). Với foreign-app imports, Keychain không bị overwrite trong mọi trường hợp.
- **As Copy** — giữ cả 2, rename connection được import thành " (Imported)"; nếu tên đó đã tồn tại thì thử " (Imported 2)", " (Imported 3)", v.v.
- **Skip** — bỏ qua connection trùng, không import.

**Dedup key**: `(host, port, database, username)`, so sánh case-insensitive. Redis dùng
`redisDatabase` làm fallback khi `database` rỗng.

**Files**: `ConnectionExportService.swift`, `ImportFromAppPreviewStep.swift`,
`ImportFromAppSheet.swift`, `ConnectionImportServiceTests.swift`.

Warning strings (SSH key, SSL cert, unknown DB type) đã được localize trong PR này.

### Agent checklist — merge PR #1462

**Setup**
- [ ] `git worktree add ../TablePro-pr1462 feat/import`.
- [ ] `git fetch upstream && git rebase upstream/main`.

**Drop noise**
- [ ] `git checkout upstream/main -- .gitignore` (entries `Local.xcconfig`, `/plans/reports` đã có main `:128,158-160`).
- [ ] `git checkout upstream/main -- CLAUDE.md` (dòng "Favorite tables" đã có main `:171`).

**Verify logic (test thực chất, không stub)**
- [ ] Đọc `ConnectionImportServiceTests.swift`, confirm cover:
  - Dedup match host/port/database/username case-insensitive (không phải name).
  - Redis named DB (`database`) vs numeric (`redisDatabase`) — không false positive.
  - `uniqueCopyName()` collision `(Imported)` → `(Imported 2)` → `(Imported 3)`.
  - 3 bước: `analyzeImport` → `prepareImport` → `performPreparedImport`.
- [ ] Test phải fail nếu bỏ `normalizedLookupKey` hoặc `effectiveDatabaseKey`.

**Codex P2 (bot) — verify + fix nếu confirmed**
- [ ] **Redis dedup key** (Codex commit `fa5b543b`, inline `ConnectionExportService.swift:890`): mâu thuẫn với note "PR xử lý Redis qua `effectiveDatabaseKey()`". Codex nói dedup key thực tế **chỉ** so sánh `database`, bỏ qua `redisDatabase`.
  - [ ] Đọc `normalizedLookupKey()` / `effectiveDatabaseKey()` thực tế trong `ConnectionExportService.swift` → xác nhận key có gồm `redisDatabase` (numeric, default 0) không.
  - [ ] Nếu Codex đúng (key bỏ qua `redisDatabase`): sửa để Redis dedup gồm `effectiveDatabaseKey()` → import Redis DB 1 KHÔNG bị coi là duplicate của DB 0 (tránh Replace ghi đè nhầm / Skip mất DB khác).
  - [ ] Thêm/confirm test "Redis DB 0 vs DB 1 không duplicate"; test phải fail nếu Redis chỉ so sánh `database`.

**Build / test / lint**
- [ ] `xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation`
- [ ] `-only-testing:TableProTests/ConnectionImportServiceTests`
- [ ] `-only-testing:TableProTests/ConnectionSharingTests` (không regression)
- [ ] `swiftlint lint --strict`

**Ship**
- [ ] Push branch; confirm chỉ còn noise conflict (không logic).
- [ ] Merge sau PR #1459.

## File changes

- `TablePro/.../DBeaverImporter.swift` — đọc thêm `credentials-config.json` `#connection.user`, fallback `data-sources.json` `configuration.user`
- Load credentials file **không phụ thuộc** "include passwords" choice (username là metadata, không phải secret)
- Password import vẫn gated by "include passwords"

## Tests (4 cases mới)

- Username from credentials
- Username imported khi passwords excluded
- Fallback to `configuration.user` (admin/env template configs cũ)
- Credentials wins precedence (cả 2 file đều có user → credentials thắng)

## Related (cùng scope `import/` trong upstream, NGOÀI 13 items)

- [#1374](https://github.com/TableProApp/TablePro/pull/1374) — `feat(import): import connections from DataGrip`
- [#1388](https://github.com/TableProApp/TablePro/pull/1388) — `fix(import): restore TablePlus password and SSH key import`
- [#1320](https://github.com/TableProApp/TablePro/pull/1320) — `feat(import): import connections from Beekeeper Studio`
- [#1318](https://github.com/TableProApp/TablePro/pull/1318) — `fix(import): detect foreign apps via LaunchServices`
