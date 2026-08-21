# Phase 01: Foundation

## Overview

- Wave: 1
- Branch: `codex/refactor/query-completion-foundation`
- Worktree: `/Users/hangvalong/Code/projects/worktrees/TablePro-codex-refactor-query-completion-foundation`
- Status: implemented, verification runs in CI (no Xcode toolchain on the dev machine)
- Priority: P1
- Gate: phải merge vào `main` trước khi mở Wave 2

## Scope và ownership độc quyền

- `QueryCompletionProfile` và API PluginKit additive.
- Schema-provider cache theo `DatabaseScope`.
- Completion-profile registry và conservative fallback.
- Truyền `scope`, `serverVersion`, `profileRevision` tới editor.
- Sửa lookup metadata ưu tiên database type thực trước primary plugin type.
- Test hai query tab cùng connection nhưng khác database/schema.

## Data flow

1. Query tab cung cấp `DatabaseScope` + connection context.
2. Driver resolve profile từ `databaseTypeId`, base profile, runtime server version.
3. Registry chọn profile phù hợp hoặc fallback bảo thủ.
4. Cache lưu theo `DatabaseScope + DatabaseType + serverVersion`.
5. Editor nhận `scope`, `serverVersion`, `profileRevision` để lấy completion đúng tab.
6. Metadata lookup ưu tiên database type thực, rồi mới fallback plugin type.

## Implementation steps

1. Thêm model `QueryCompletionProfile` chứa resolved dialect, statement completions, token-casing policy.
2. Mở rộng `PluginDatabaseDriver` bằng `resolveQueryCompletionProfile(databaseTypeId:base:) async throws`, có default implementation additive.
3. Thêm registry profile với conservative fallback khi thiếu version/catalog.
4. Refactor cache schema provider để khóa theo `DatabaseScope`, tránh rò completion giữa query tabs.
5. Truyền `DatabaseScope`, `serverVersion`, `profileRevision` tới editor/completion pipeline.
6. Sửa metadata lookup dùng database type thực trước, không lệ thuộc primary plugin type.
7. Viết test cho hai query tab cùng connection nhưng khác database/schema và cho fallback version không xác định.

## Dependencies

- Không phụ thuộc Wave 2.
- Là blocker cho toàn bộ 4 branch Wave 2.

## Risks

- High: cache scope sai làm rò schema giữa tabs.
  Mitigation: key cache bằng scope đầy đủ; thêm integration test 2-tab.
- High: API PluginKit additive nhưng vô tình phá ABI.
  Mitigation: giữ initializer/public symbol cũ; chạy ABI check.
- Medium: metadata lookup đổi precedence gây regression plugin cũ.
  Mitigation: fallback plugin type khi database type thật không đủ metadata.

## Backwards compatibility

- Driver chưa override API mới vẫn dùng profile gốc.
- Unknown version/catalog vẫn chạy bằng SQL baseline bảo thủ.
- Không đổi shortcut editor hay public initializer hiện có.

## Tests

- Unit: profile resolution, registry fallback, cache key by scope.
- Integration: 2 query tabs cùng connection nhưng khác database/schema.
- Verification: `AllPlugins` build, `swiftlint lint --strict`, PluginKit ABI check nếu có chạm PluginKit.

## Rollback

- Revert riêng foundation branch trước khi tạo Wave 2.
- Nếu merge rồi mới lỗi: revert commit foundation trên `main`; các branch Wave 2 phải rebase lại từ `main` đã rollback.

## TODO

- [x] Tạo `QueryCompletionProfile`
- [x] Thêm API resolve profile vào PluginKit
- [x] Dựng registry + conservative fallback
- [x] Scope cache theo query tab
- [x] Truyền `scope/serverVersion/profileRevision` tới editor
- [x] Đổi precedence metadata lookup
- [x] Viết test 2-tab và fallback version
- [ ] Chạy build/lint/ABI check (CI, không chạy được local)

## Việc đã bổ sung sau review

- Bỏ overload `getOrCreate(for connectionId:)`: mọi call site phải nói rõ scope. Filter panel dùng scope của tab đang chọn, quick switcher dùng browse scope.
- `sampleFieldPaths` trong provider đã scope-hóa; trước đó vẫn đọc browse scope nên MongoDB field path lấy sai database.
- `prepare(for:)` là đường nạp schema duy nhất và chỉ nạp một lần; editor pane gọi nó qua `.task(id: queryScope)` thay vì fire-and-forget trong getter.
- `syncAutocompleteProvider` tạo provider cho browse scope nếu chưa có, để danh sách object của sidebar không bị bỏ rơi.
- `QueryCompletionProfileRegistry.profile` lease metadata driver bên trong resolver, nên cache hit không còn chiếm session driver.
- Cập nhật `SchemaProviderRegistryTests` (đang gọi API cũ nên test target không build) và thêm test precedence metadata lookup.

## Done when

- Foundation mergeable độc lập.
- Không leak completion giữa hai tab khác database/schema.
- API mới additive, không phá ABI/public initializer.
- Có test và verification pass.

## Notes

- Không commit nếu chưa có approval explicit.
- Không mở Wave 2 trước khi foundation vào `main`.
