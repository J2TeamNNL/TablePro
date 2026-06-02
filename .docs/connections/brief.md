# connections — brief

## Scope

Safe Mode toolbar setting và lifecycle khi reconfigure connection (open table,
switch database, …).

## Vấn đề

User đổi Safe Mode level từ toolbar (ví dụ "Read-only" → "Read-only with confirm")
→ mở table khác → level **reset về saved default** của connection. Mọi reconfigure
xoá choice.

## Root cause (1 sentence)

`ConnectionToolbarState.update(from:)` hard-set `safeModeLevel = connection.safeModeLevel`
mỗi lần, và `MainContentCommandActions.safeModeLevel` đọc saved default → live choice
mất sau bất kỳ reconfigure nào.

## Mục tiêu

- Live level lưu trên **session** (per-connect, in-memory) thay vì chỉ saved connection
- Reconfigure không overwrite live value
- Toolbar badge write-through cả toolbar state + session

## Kết quả

Per-session safe mode persistent qua lifecycle reconfigure (#1376, merged).

**Open fork PR #1461** (còn mở, CONFLICTING do noise — VERIFIED 2026-05-30): thay đổi
safe mode trong toolbar tự persist về connection default — disconnect-then-reconnect
giữ nguyên level đã chọn. Blocker duy nhất: noise hunks `.gitignore`/`CLAUDE.md`,
cần rebase. Xem `tasks.md` § agent checklist.
