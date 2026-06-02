# Flow

## Trigger Flow: Sidebar Right-Click → Focused ER Diagram

```mermaid
sequenceDiagram
    participant User
    participant SidebarContextMenu
    participant Coordinator as MainContentCoordinator+ERDiagram
    participant TabManager as QueryTabManager
    participant Factory as SessionStateFactory
    participant View as MainEditorContentView
    participant VM as ERDiagramViewModel

    User->>SidebarContextMenu: right-click "users" → View ER Diagram
    SidebarContextMenu->>Coordinator: showERDiagram(tableName: "users")
    Coordinator->>Coordinator: build schemaKey = "mydb.public"
    Coordinator->>Coordinator: dedup check: tabType==erDiagram && schemaKey=="mydb.public" && focusedTable=="users"
    alt tab đã tồn tại
        Coordinator->>User: focus existing window
    else tab chưa có
        Coordinator->>TabManager: addERDiagramTab(schemaKey:, focusedTable: "users")
        TabManager->>TabManager: title = "ER: users"
        TabManager->>TabManager: tab.display.erDiagramFocusedTable = "users"
        View->>VM: ERDiagramViewModel(focusedTableName: "users")
        VM->>VM: loadDiagram()
        VM->>VM: build fullGraph (all tables)
        VM->>VM: builtGraph = fullGraph.subgraph(focusedOn: "users")
        VM->>View: graph = {users, orders, sessions} + FK edges
    end
```

## subgraph(focusedOn:) Logic

```mermaid
flowchart TD
    A[fullGraph] --> B["filter edges: fromTable=='users' || toTable=='users'"]
    B --> C["visibleNames = {users} ∪ {orders, sessions, ...}"]
    C --> D["filteredNodes = nodes ∩ visibleNames"]
    B --> E["filteredEdges = relatedEdges (1-hop only)"]
    D --> F[ERDiagramGraph subgraph]
    E --> F
```

## Tab Lifecycle & Persistence

```mermaid
flowchart LR
    A[showERDiagram tableName] --> B[EditorTabPayload\nerDiagramFocusedTable]
    B --> C[WindowManager.openTab]
    C --> D[SessionStateFactory\naddERDiagramTab focusedTable]
    D --> E[QueryTab\ndisplay.erDiagramFocusedTable]
    E --> F[toPersistedTab\nerDiagramFocusedTable]
    F --> G[disk JSON]
    G --> H[restore: PersistedTab\nerDiagramFocusedTable]
    H --> I[QueryTab init\nTabDisplayState]
    I --> J[MainEditorContentView\nERDiagramViewModel focusedTableName]
```

## Key File Mapping

| Concern | File |
|---|---|
| Entry point (sidebar) | `Views/Sidebar/SidebarContextMenu.swift` |
| Entry point (menu bar) | `TableProApp.swift:583` |
| Coordinator / dedup | `Views/Main/Extensions/MainContentCoordinator+ERDiagram.swift` |
| Tab creation | `Models/Query/QueryTabManager.swift` |
| Tab state | `Models/Query/QueryTabState.swift` (PersistedTab, TabDisplayState) |
| Tab restore | `Core/Services/Infrastructure/SessionStateFactory.swift` |
| VM init / filter | `ViewModels/ERDiagramViewModel.swift` |
| Graph model + filter | `Models/ERDiagram/ERDiagramModels.swift` |
| View init | `Views/Main/Child/MainEditorContentView.swift` |
