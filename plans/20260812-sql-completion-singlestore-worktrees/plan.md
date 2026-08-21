---
title: "SQL completion và SingleStore theo worktree"
description: "Kế hoạch 3 wave để tách foundation, các profile song song và docs/acceptance."
status: in_progress
priority: P1
effort: 5d
branch: codex/refactor/query-completion-foundation
tags: [sql, completion, singlestore, worktree, plugin-kit]
created: 2026-08-12
---

# Kế hoạch tổng

Mục tiêu: sửa SQL completion theo `DatabaseScope` từng query tab, thêm completion profile theo engine/version, tách `SingleStore` thành database type riêng nhưng tái dùng MySQL transport, mở rộng auto-uppercase cho keyword + built-in function, và chốt docs/acceptance cuối.

## Phases

1. [Phase 01 - Foundation](./phase-01-foundation.md)
   Status: implemented, đã review và bổ sung; chờ CI xanh trước khi merge. Blocker cho toàn bộ Wave 2.
2. [Phase 02 - Parallel Profiles](./phase-02-parallel-profiles.md)
   Status: pending. Chỉ bắt đầu sau khi Phase 01 merge vào `main`.
3. [Phase 03 - Docs & Acceptance](./phase-03-docs-acceptance.md)
   Status: pending. Chỉ bắt đầu sau khi cả 4 PR Wave 2 merge.

## Dependency graph

- Wave 1 branch `codex/refactor/query-completion-foundation` phải merge trước.
- Sau merge: cập nhật `main`, tạo 4 worktree Wave 2 cùng base từ `main`.
- Wave 2 có thể merge theo bất kỳ thứ tự nào nếu giữ đúng ownership file.
- Wave 3 branch `codex/docs/query-completion-singlestore` chỉ mở sau khi 4 PR Wave 2 đã vào `main`.

## Shared interfaces

- Thêm `QueryCompletionProfile`: resolved dialect, statement completions, token-casing policy.
- Thêm `resolveQueryCompletionProfile(databaseTypeId:base:) async throws` vào `PluginDatabaseDriver`; default trả profile gốc.
- Giữ nguyên public initializer hiện có.
- Không bump PluginKit nếu ABI check không phát hiện symbol bị xóa.
- Cache profile theo `DatabaseScope + DatabaseType + serverVersion`.
- Khi version/catalog không xác định: chỉ dùng baseline đã xác minh, không giả định server mới nhất.

## Test matrix

- Unit: profile resolution, conservative fallback, metadata lookup theo database type thật, token casing.
- Integration: hai query tab cùng connection khác database/schema; version gates; catalog permission fallback.
- End-to-end/acceptance: SingleStore metadata/query/parameterized query; shortcut execution không regression; uppercase chỉ tác động keyword/built-in.

## Rollback

- Wave 1 rollback độc lập bằng revert branch foundation trước khi mở Wave 2.
- Mỗi branch Wave 2 rollback độc lập vì ownership tách file; không trộn commit cross-branch.
- Wave 3 rollback chỉ ảnh hưởng docs/test harness; không rollback code tính năng trừ khi acceptance phát hiện regression.

## Success criteria

- Hai tab khác database không gợi ý lẫn bảng/cột.
- Feature mới hơn server version không xuất hiện.
- Version parse lỗi dùng conservative fallback.
- SingleStore Helios và self-managed chạy metadata, query thường, parameterized query.
- `Cmd+T`, `Cmd+Enter`, `Cmd+Shift+Enter`, `Cmd+Option+Enter` không regression.
- Setting bật thì keyword + built-in function viết hoa; identifiers giữ nguyên.

## Guardrails

- Không commit nếu chưa có approval explicit.
- Không sửa file ngoài ownership branch tương ứng.
- Mỗi PR phải rebase `main`, chạy targeted tests, `AllPlugins` build, `swiftlint lint --strict`.
- Foundation branch phải chạy thêm PluginKit ABI check nếu có chạm PluginKit.
