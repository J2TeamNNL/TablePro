# Brief

## Vấn đề gốc

"View ER Diagram" trong sidebar context menu không dùng `clickedTable` — nó luôn hiển thị toàn bộ schema bất kể bảng nào được chọn. UX không nhất quán: action gắn vào table nhưng kết quả không liên quan đến table.

## Quyết định thiết kế

**Option A — Focused diagram**: right-click table → hiển thị diagram chỉ gồm table đó và các bảng kết nối trực tiếp qua FK (1 hop). Menu bar vẫn giữ full diagram.

Lý do chọn Option A thay vì Option B (full diagram + scroll to table):
- Với schema lớn (50+ tables), full diagram quá nhiều nhiễu khi chỉ muốn xem relationships của một bảng
- Focused view cung cấp ngữ cảnh hữu ích mà không làm mất thông tin quan trọng
- Deduplication theo `(schemaKey, focusedTable)` cho phép mở nhiều focused tabs song song

## Trạng thái hiện tại

Đã implement xong và đã thêm unit tests cho graph filtering + tab state/payload.
Changed-file SwiftLint pass.

Full `xcodebuild test` đã thử nhưng bị chặn trước khi compile app vì dependency
SwiftLintPlugin trong `LocalPackages/CodeEdit*` không load được
`sourcekitdInProc.framework` bên trong Xcode package-plugin sandbox.
