# Decisions

## [2026-05-25] Focused diagram thay vì full diagram từ context menu

**Quyết định**: Khi right-click table → "View ER Diagram", chỉ hiển thị table đó + 1-hop FK neighbors, không phải full schema.

**Lý do**: Action gắn vào table cụ thể nên kết quả phải phản ánh table đó. Full diagram từ context menu là UX không nhất quán (không khác gì gọi từ menu bar).

**Thay thế đã xem xét**:
- Option B (full + scroll to table): giữ full context nhưng vẫn noise với schema lớn
- Xóa khỏi context menu: mất đi entry point tiện lợi

---

## [2026-05-25] Filter tại ViewModel, không phải tại View

**Quyết định**: `ERDiagramViewModel.loadDiagram()` filter graph trước khi assign `self.graph`, thay vì filter tại render time trong View.

**Lý do**: Layout algorithm (`ERDiagramLayout.compute`) chạy trên graph đã filter → layout tự căn chỉnh cho focused nodes. Nếu filter tại View, layout vẫn tính cho full graph và nodes bị ẩn chiếm space.

---

## [2026-05-25] `subgraph` chỉ include edges của focused table, không include edges giữa neighbors

**Quyết định**: `subgraph(focusedOn:)` chỉ lấy edges where `fromTable == tableName || toTable == tableName`.

**Lý do**: Mục tiêu là xem relationships của *một* table. Edges giữa các neighbor (ví dụ orders→products khi focus vào customers) là thông tin thừa và làm rối diagram.

---

## [2026-05-25] Deduplication theo (schemaKey, focusedTable) pair

**Quyết định**: Hai tabs với cùng schema nhưng focused table khác nhau được coi là independent tabs.

**Lý do**: User có thể muốn so sánh focused diagrams của nhiều tables song song. Merge chúng về một tab sẽ mất thông tin.

---

## [2026-05-25] Tab title "ER: tableName" cho focused tabs

**Quyết định**: Focused tabs có title "ER: orders" thay vì "ER Diagram".

**Lý do**: Phân biệt trực quan trên tab bar khi mở nhiều focused diagrams cùng lúc.
