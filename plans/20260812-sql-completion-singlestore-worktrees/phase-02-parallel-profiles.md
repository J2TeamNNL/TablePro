# Phase 02: Parallel Profiles

## Overview

- Wave: 2
- Base branch cho cả 4 worktree: `main` sau khi foundation merge
- Status: pending
- Priority: P1
- Rule: file ownership tách tuyệt đối, PR vào `main`, merge theo bất kỳ thứ tự nào

## Parallel branches và ownership

1. `codex/feat/singlestore-support`
   Worktree: `/Users/hangvalong/Code/projects/worktrees/TablePro-codex-feat-singlestore-support`
   Ownership: MySQL/MariaDB/SingleStore driver, `DatabaseType.singlestore`, curated metadata/icon/`singlestore://`, probe `@@memsql_version`, Helios + self-managed, TLS Verify Identity mặc định, text protocol parameter binding + MariaDB C client escaping, disable unsupported capabilities, support chính thức 8.9/9.0, version khác dùng profile bảo thủ.
2. `codex/feat/bundled-query-profiles`
   Worktree: `/Users/hangvalong/Code/projects/worktrees/TablePro-codex-feat-bundled-query-profiles`
   Ownership: PostgreSQL, Redshift, CockroachDB, PGlite, SQLite, ClickHouse, runtime catalog khi có, curated version gates khi catalog thiếu; không sửa MySQL plugin hoặc editor casing.
3. `codex/feat/registry-query-profiles`
   Worktree: `/Users/hangvalong/Code/projects/worktrees/TablePro-codex-feat-registry-query-profiles`
   Ownership: SQL Server, Oracle, DuckDB, Cassandra/ScyllaDB, Cloudflare D1, DynamoDB PartiQL, BigQuery, libSQL/Turso, Snowflake, Beancount, SurrealQL, Teradata, Trino; version profile, permission fallback, plugin-specific tests; loại trừ MongoDB, Elasticsearch, Redis, etcd.
4. `codex/feat/sql-function-uppercase`
   Worktree: `/Users/hangvalong/Code/projects/worktrees/TablePro-codex-feat-sql-function-uppercase`
   Ownership: auto-uppercase + formatter, completion insert text cho keyword/built-in, rename setting thành `Auto-uppercase keywords and functions`, không đổi table/column/UDF/string/comment/quoted identifier, grammar case-sensitive giữ canonical casing.

## Data flows

- Foundation registry nhận `databaseType + serverVersion + scope`, rồi branch profile tương ứng bổ sung completion sets/version gates.
- Runtime catalog nếu server có sẽ augment curated profile; nếu không có hoặc permission thiếu thì fallback curated baseline.
- SingleStore branch nhận handshake/version probe, resolve database type riêng, rồi đi qua MySQL wire transport hiện có.
- Uppercase branch chỉ tác động token insert/casing policy cho keyword và built-in, không chạm identifier resolution.

## Dependencies

- Hard blocker: Phase 01 đã merge vào `main`.
- Soft coordination: mỗi branch chỉ đọc interface chung từ foundation; không sửa file ngoài ownership.
- Wave 3 blocked bởi cả 4 branch đã merge.

## Risks

- High: overlap file giữa SingleStore và profile registry/bundled profiles.
  Mitigation: giữ ownership theo plugin/dialect rõ ràng; nếu có shared registry file thì chỉ thêm entry phần mình, merge tuần tự và rebase trước test.
- High: SingleStore tự nhận MySQL/MariaDB sai path, làm metadata/query lệch.
  Mitigation: probe `@@memsql_version`; unknown result fallback profile bảo thủ, không tự nhận full MySQL feature set.
- Medium: curated version gates drift với runtime catalog.
  Mitigation: ưu tiên runtime catalog khi server cung cấp; curated chỉ bù chỗ thiếu.
- Medium: uppercase branch phá casing grammar nhạy chữ hoa thường.
  Mitigation: giữ canonical casing cho grammar case-sensitive; test quoted/string/comment/UDF.

## Branch test matrix

- Chung cho mỗi PR: targeted tests, `AllPlugins` build, `swiftlint lint --strict`, rebase `main` trước test.
- SingleStore: metadata, query thường, parameterized query, Helios/self-managed, TLS default, unsupported capabilities off, fallback cho version ngoài 8.9/9.0.
- Bundled profiles: version gates cho PostgreSQL-family, SQLite, ClickHouse; runtime catalog vs curated fallback.
- Registry profiles: permission fallback, per-plugin version profile, dialect exclusions không khai báo SQL dialect phù hợp.
- Uppercase: insert text keyword/built-in, formatter, setting label/default off, không đổi identifiers/string/comment/quoted identifiers.

## Rollback

- Revert từng PR độc lập trên `main` vì phạm vi file ownership tách.
- Nếu branch sửa shared registry entry và gây regression: revert PR đó rồi rebase các PR chưa merge.

## TODO

- [ ] Merge foundation vào `main`
- [ ] Cập nhật `main` local
- [ ] Tạo 4 worktree Wave 2 từ `main`
- [ ] Giữ ownership file không chồng lấn
- [ ] Viết test theo từng branch
- [ ] Rebase từng branch lên `main` mới nhất trước test
- [ ] Chạy build/lint/targeted tests cho từng PR

## Done when

- 4 PR mergeable độc lập, không conflict ownership.
- Không feature nào giả định server version mới nhất khi version không parse được.
- SingleStore hoạt động như database type riêng trên MySQL wire transport.
- Uppercase chỉ tác động keyword + built-in functions khi setting bật.

## Notes

- Không commit nếu chưa có approval explicit.
- Không sửa generated `.xcodeproj`, secrets, build artifacts.
