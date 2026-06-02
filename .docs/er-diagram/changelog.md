# Changelog

## [2026-05-25] — plan-review

User confirm giữ nguyên trạng thái. 4 task open (full build/test verify, localization `ER: %@`, restore focused tab UI/runtime, 2-tab dedup UI/runtime) ghi nhận chưa làm trong session này.

## [2026-05-25] — Focused ER Diagram từ context menu

Implement Option A: right-click table → focused diagram (table + 1-hop FK neighbors).

**Files thay đổi:**
- `Models/ERDiagram/ERDiagramModels.swift` — thêm `subgraph(focusedOn:)` vào `ERDiagramGraph`
- `ViewModels/ERDiagramViewModel.swift` — thêm `focusedTableName`, apply filter sau load
- `Views/Sidebar/SidebarContextMenu.swift` — pass `clickedTable?.name` vào `showERDiagram`
- `Views/Main/Extensions/MainContentCoordinator+ERDiagram.swift` — `showERDiagram(tableName:)`, dedup by (schemaKey, focusedTable)
- `Models/Query/QueryTabState.swift` — `erDiagramFocusedTable` trên `PersistedTab` và `TabDisplayState`
- `Models/Query/QueryTab.swift` — propagate field
- `Models/Query/EditorTabPayload.swift` — thêm field, Codable
- `Models/Query/QueryTabManager.swift` — `addERDiagramTab(focusedTable:)`, title "ER: tableName"
- `Core/Services/Infrastructure/SessionStateFactory.swift` — restore focused table khi open tab
- `Views/Main/Child/MainEditorContentView.swift` — pass `focusedTableName` vào VM init
- `TableProTests/Models/ERDiagramGraphTests.swift` — cover direct-neighbor subgraph behavior
- `TableProTests/Models/QueryTabStateTests.swift` — cover persisted focused-table state
- `TableProTests/Models/EditorTabPayloadTests.swift` — cover focused-table payload Codable
- `TableProTests/Models/Query/QueryTabManagerTests.swift` — cover focused tab title/display state
- `CHANGELOG.md` — thêm entry "Changed"

**Trạng thái**: Code complete. Changed-file SwiftLint pass. Full build/test blocked
by SwiftLintPlugin SourceKit sandbox issue before app compilation.
