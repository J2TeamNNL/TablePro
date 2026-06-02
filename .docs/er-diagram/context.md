# Context

## Runtime Findings

### Tab lifecycle

`EditorTabPayload` → `SessionStateFactory` → `QueryTabManager.addERDiagramTab` → `QueryTab` → `MainEditorContentView` khởi tạo `ERDiagramViewModel` khi tab xuất hiện lần đầu (`onAppear`).

`erDiagramFocusedTable` phải đi qua toàn bộ chuỗi này để restore đúng sau khi restart app.

### Deduplication logic

`showERDiagram(tableName:)` check: `tabType == .erDiagram && schemaKey == X && focusedTable == Y`. Nếu đã có tab với cùng (schemaKey, focusedTable) thì focus window đó thay vì mở tab mới. `nil` (full diagram) và `"users"` (focused) được coi là 2 tabs khác nhau.

### `subgraph(focusedOn:)` algorithm

```
relatedEdges = edges where fromTable == tableName || toTable == tableName
visibleNames = {tableName} ∪ {edge.fromTable, edge.toTable for each relatedEdge}
filteredNodes = nodes ∩ visibleNames
filteredEdges = relatedEdges (chỉ 1-hop, không include edges giữa các neighbors)
```

Edges giữa các neighbor tables không được include — chỉ edges liên quan trực tiếp đến focused table. Đây là quyết định có chủ ý để giữ sơ đồ gọn.

### `PersistedTab.erDiagramFocusedTable`

Field mới trên `PersistedTab` (Codable) — backward compatible vì dùng `var` với default `nil`. Tabs cũ persist không có field này sẽ decode thành `nil` (full diagram).

## Gotchas

- `ERDiagramViewModel.loadDiagram()` có guard `loadState != .loaded` — sẽ không reload nếu tab được reuse. Focused filter chỉ apply khi load lần đầu.
- Tab title "ER: tableName" dùng `String(format:)` với localized key — cần đảm bảo localization catalog có key "ER: %@" nếu app hỗ trợ đa ngôn ngữ.
