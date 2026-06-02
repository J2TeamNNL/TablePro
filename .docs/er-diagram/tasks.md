# Tasks

## Done

- [x] Phân tích UX issue: context menu "View ER Diagram" không dùng `clickedTable`
- [x] Thiết kế Option A (focused diagram) vs Option B (full + scroll)
- [x] Thêm `erDiagramFocusedTable` vào `PersistedTab` và `TabDisplayState`
- [x] Propagate field qua `QueryTab`, `EditorTabPayload`, `QueryTabManager`, `SessionStateFactory`
- [x] Thêm `focusedTableName` vào `ERDiagramViewModel`
- [x] Implement `ERDiagramGraph.subgraph(focusedOn:)`
- [x] Apply filter trong `loadDiagram()` sau khi build full graph
- [x] Update `showERDiagram(tableName:)` — pass through + deduplication
- [x] Update `SidebarContextMenu` — pass `clickedTable?.name`
- [x] Update tab title "ER: tableName" cho focused tabs
- [x] Add graph unit tests: direct relationships, isolated table, missing table
- [x] Add tab/payload persistence tests for `erDiagramFocusedTable`
- [x] Changed-file SwiftLint pass
- [x] Update CHANGELOG.md

## In Progress

- [ ] Full build/test verification blocked by SwiftLintPlugin SourceKit sandbox issue

## Todo

- [ ] Kiểm tra localization: key "ER: %@" có trong strings catalog chưa
- [x] Test case: table không có FK nào → diagram chỉ có 1 node (bảng đó)
- [x] Test case: table có nhiều FK → tất cả direct neighbors đều hiển thị
- [x] Test case: persisted tab state preserves focused table
- [ ] Test case: restore focused tab sau khi restart app bằng UI/runtime
- [ ] Test case: mở 2 focused tabs khác nhau, deduplication hoạt động đúng bằng UI/runtime
