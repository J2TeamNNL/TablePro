# datagrid — flow

## Cmd+C dispatch (sau #1337, #1338)

```mermaid
flowchart TD
  A[User bấm Cmd+C] --> B{Menu hay key trực tiếp?}
  B -->|menu| C[PasteboardCommands button]
  B -->|key| D[NSApp.sendAction copy:]
  C --> D
  D --> E{First responder?}
  E -->|NSTextView| F[Standard text copy]
  E -->|KeyHandlingTableView| G[KeyHandlingTableView.copy:]
  E -->|khác| H{sendAction trả false?}
  H -->|yes| I[Fallback: actions?.copySelectedRows]
  H -->|no| J[Silent drop — pre-PR1338 regression]
  G --> K{focusedDataCell != nil?}
  K -->|yes| L[copyCellValue: chỉ value cell]
  K -->|no| M[copySelectedRows: TSV]
```

## Filter persistence lifecycle (sau #1387, #1395)

```mermaid
sequenceDiagram
  participant U as User
  participant FC as FilterCoordinator
  participant FS as FilterSettingsStorage
  participant Disk as Disk (per conn+db+schema+table)

  Note over U,Disk: Apply
  U->>FC: applyFiltersAndReload()
  FC->>FS: saveLastFilters(for: key)
  FS->>Disk: write file (key = conn+db+schema+table)

  Note over U,Disk: Clear (user-initiated Unset)
  U->>FC: clearFiltersAndReload()
  FC->>FS: clearLastFilters(for: key)
  FS->>Disk: delete file

  Note over U,Disk: Close → Reopen
  U->>FC: openTable(name)
  FC->>FS: loadLastFilters(for: key)
  FS->>Disk: read file
  FS-->>FC: filters or empty
  FC->>FC: restoreDecision(panelState, filters)
  Note right of FC: panelState != "Always Hide"<br/>và filters non-empty<br/>→ apply + show bar populated
```

## Cmd+F context routing (sau #1360)

```mermaid
stateDiagram-v2
  [*] --> ResolveRoute
  ResolveRoute --> TableTab: tab kind == .table
  ResolveRoute --> QueryTab: tab kind == .query
  ResolveRoute --> Inspector: window kind == .inspector

  TableTab: View > Toggle Filters owns Cmd+F
  QueryTab: Edit > Find owns Cmd+F
  Inspector: Edit > Find owns Cmd+F

  TableTab --> ToggleFilterPanel
  QueryTab --> OpenEditorFind
  Inspector --> ToggleInspectorFilter
```

## Hidden column → query scope (sau #1375)

```mermaid
flowchart LR
  A[Open table] --> B[getColumns async cached]
  B --> C[ColumnFetchScope.selectColumns<br/>schema, hidden, PKs]
  C --> D{indices == nil?}
  D -->|yes| E[SELECT *]
  D -->|no| F[SELECT col_a, col_c, PK_id]
  F --> G[Query result chỉ visible + PK]

  H[Toggle hide column] --> I[Update persisted hidden set]
  I --> C
```

## Context menu Copy cell vs row (PR #1459, open)

```mermaid
flowchart TD
    A[Context menu Copy] --> B[copyFromContextMenu]
    B --> C{dataColumnIndex có?}
    C -->|Có| D[Copy cell value tại index]
    C -->|Không| E[focusedDataColumnIndex]
    E --> F{tableView as? KeyHandlingTableView<br/>và có focused cell?}
    F -->|Có| D
    F -->|Không| G[Copy cả row]
    D --> H[Clipboard]
    G --> H
```
