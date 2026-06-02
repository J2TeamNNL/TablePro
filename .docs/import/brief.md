# import — brief

## Scope

Import connection từ third-party app (DBeaver, TablePlus, DataGrip, Beekeeper).
Item gốc 13-list: #1355. Thêm fork PR #1462 (dedup dialog) — review 2026-05-30.

## Open fork PR #1462 (status)

**OPEN-fork**, branch `feat/import`. Dedup dialog Replace/As Copy/Skip; dedup key
host+port+database+username case-insensitive (Redis via `effectiveDatabaseKey`);
refactor `analyzeImport → prepareImport → performPreparedImport`. **Blocker**:
CONFLICTING chỉ do noise (`.gitignore` + `CLAUDE.md:171`). Chi tiết: `content.md`,
`tasks.md`.

## Vấn đề (#1355)

Import từ DBeaver → connection được tạo ra nhưng **username trống**. User phải
fill lại thủ công cho mọi connection.

## Root cause (1 sentence)

DBeaver 6.1.3+ đổi storage: username chuyển sang `credentials-config.json` ở key
`#connection.user`, nhưng importer vẫn đọc từ `data-sources.json` `configuration.user`
(format cũ) → empty.

## Mục tiêu

- Đọc `credentials-config.json` `#connection.user` (primary)
- Fallback `data-sources.json` `configuration.user` (admin / env-template configs cũ)
- Load credentials file bất kể "include passwords" choice — username là metadata

## Kết quả

Username import đúng từ DBeaver 6.1.3+. Password import vẫn gated by user choice.
Backward compat với DBeaver < 6.1.3 (rơi vào fallback).

## Pattern transferable

**Phân biệt metadata vs secret.** Username là metadata (không phải secret) →
luôn load. Password là secret → gated by explicit user choice. Pattern này
generalize tới các importer khác (TablePlus, DataGrip, Beekeeper).
