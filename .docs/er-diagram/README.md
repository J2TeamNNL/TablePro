# ER Diagram Feature

Tính năng hiển thị sơ đồ quan hệ thực thể (ER Diagram) cho database schema trong TablePro.

## Scope

- Render toàn bộ schema dưới dạng graph: tables là nodes, foreign keys là edges
- Focused view: khi right-click table → chỉ hiển thị table đó + các bảng kết nối trực tiếp (1-hop FK)
- Full view: từ menu bar → hiển thị toàn bộ schema
- Pan/zoom, drag-to-reposition nodes, persist positions
- Export diagram
- Compact mode (chỉ hiện PK/FK columns)

## Entrypoints

| Trigger | Hành động |
|---|---|
| Sidebar right-click table → "View ER Diagram" | Focused diagram cho table đó |
| Menu bar → "View ER Diagram" | Full diagram toàn schema |

## Key Files

- `TablePro/ViewModels/ERDiagramViewModel.swift` — state, load, filter, layout, drag, zoom
- `TablePro/Models/ERDiagram/ERDiagramModels.swift` — `ERDiagramGraph`, `ERTableNode`, `EREdge`, `subgraph(focusedOn:)`
- `TablePro/Views/ERDiagram/ERDiagramView.swift` — main canvas
- `TablePro/Views/Main/Extensions/MainContentCoordinator+ERDiagram.swift` — `showERDiagram(tableName:)`
- `TablePro/Models/Query/QueryTabState.swift` — `erDiagramFocusedTable` trên `PersistedTab` và `TabDisplayState`
