# Brief

## Vấn đề gốc

"View ER Diagram" trong sidebar context menu không dùng `clickedTable` — nó luôn hiển thị toàn bộ schema bất kể bảng nào được chọn. UX không nhất quán: action gắn vào table nhưng kết quả không liên quan đến table.

## Quyết định thiết kế

**Option A — Focused diagram**: right-click table → hiển thị diagram chỉ gồm table đó và các bảng kết nối trực tiếp qua FK (1 hop). Menu bar vẫn giữ full diagram.

Lý do chọn Option A thay vì Option B (full diagram + scroll to table):
- Với schema lớn (50+ tables), full diagram quá nhiều nhiễu khi chỉ muốn xem relationships của một bảng
- Focused view cung cấp ngữ cảnh hữu ích mà không làm mất thông tin quan trọng
- Deduplication theo `(schemaKey, focusedTable)` cho phép mở nhiều focused tabs song song

## Trạng thái hiện tại (verified 2026-06-02)

Implement xong **trên branch `er-diagram`** (`60509a12`) + unit tests cho graph
filtering + tab state/payload. **CHƯA merge vào main**, không có PR mở. Code main
chỉ có full diagram (`showERDiagram()` no param); focused-diagram symbols absent.

Full `xcodebuild test` từng bị chặn trước compile vì SwiftLintPlugin trong
`LocalPackages/CodeEdit*` không load `sourcekitdInProc.framework` trong Xcode
package-plugin sandbox.
