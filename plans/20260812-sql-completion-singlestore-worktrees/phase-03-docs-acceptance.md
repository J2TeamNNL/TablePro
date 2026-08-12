# Phase 03: Docs & Acceptance

## Overview

- Wave: 3
- Branch: `codex/docs/query-completion-singlestore`
- Worktree: `/Users/hangvalong/Code/projects/worktrees/TablePro-codex-docs-query-completion-singlestore`
- Status: pending
- Priority: P2
- Gate: chỉ bắt đầu sau khi 4 PR Wave 2 đã merge vào `main`

## Scope và ownership

- README, public `docs/`, changelog, và phần driver inventory được phép sửa trong `CLAUDE.md`.
- Trang SingleStore, TLS, URL scheme, version support, compatibility limits.
- Đồng bộ README với danh sách database hiện đang thiếu.
- Sửa conflict giữa ví dụ formatter và test function casing.
- Không bulk-update `.docs/` vì đây là case-study lịch sử.
- Chạy acceptance suite và full build cuối.

## Data flow

1. Tổng hợp behavior thực tế từ foundation + 4 PR Wave 2 đã merge.
2. Đồng bộ docs public theo capability thật, version support thật, compatibility limits thật.
3. Chạy acceptance/full build trên `main`.
4. Nếu acceptance fail: trả lỗi về branch gây regression, không sửa lan sang docs ngoài scope.

## Acceptance checklist

- Hai tab khác database không gợi ý lẫn bảng/cột.
- Feature mới hơn server version không xuất hiện.
- Version không parse được dùng conservative fallback.
- SingleStore Helios và self-managed chạy metadata, query thường, parameterized query.
- `Cmd+T`, `Cmd+Enter`, `Cmd+Shift+Enter`, `Cmd+Option+Enter` không regression.
- Keyword và built-in function được viết hoa khi setting bật; identifiers giữ nguyên.

## Risks

- High: docs mô tả capability rộng hơn implementation thật.
  Mitigation: chỉ document behavior đã pass acceptance.
- Medium: chỉnh README/changelog chạm vùng project-owned ngoài scope.
  Mitigation: giới hạn đúng README, `docs/`, changelog, driver inventory section được phép.
- Medium: formatter example và casing test xung đột.
  Mitigation: fix example theo canonical behavior đã test pass.

## Backwards compatibility

- Docs phải nêu rõ SingleStore là database độc lập, chỉ tương thích MySQL protocol và một phần SQL.
- Nêu support chính thức 8.9/9.0; version khác dùng profile bảo thủ.
- Nêu rõ compatibility limits: foreign-key enforcement, trigger editing, `LIKE ... ESCAPE` không hỗ trợ.

## Verification

- Chạy acceptance suite cuối.
- Chạy full build cuối trên `main` đã chứa đủ 5 PR code.
- Đảm bảo không có regression shortcut editor và casing.

## Rollback

- Revert docs branch nếu chỉ sai tài liệu.
- Nếu acceptance phát hiện regression code: không patch chéo docs branch; mở fix riêng trên branch code tương ứng rồi rerun acceptance.

## TODO

- [ ] Chờ 4 PR Wave 2 merge
- [ ] Tạo worktree docs từ `main` mới nhất
- [ ] Cập nhật README/public docs/changelog/driver inventory được phép
- [ ] Viết trang SingleStore + TLS + URL scheme + version support + limits
- [ ] Đồng bộ ví dụ formatter với behavior function casing
- [ ] Chạy acceptance suite
- [ ] Chạy full build cuối

## Done when

- Docs phản ánh đúng behavior đã merge.
- Acceptance suite và full build pass.
- Không sửa `.docs/` hàng loạt, không vượt scope ownership.

## Notes

- Không commit nếu chưa có approval explicit.
- Không sửa repository `CLAUDE.md` ngoài phần driver inventory đã được ownership cho phép.
