# sidebar — flow

## Combined control hiện tại (#1353 → VERIFY-current)

```mermaid
flowchart LR
  subgraph MainWindowToolbar
    A[sidebarToggle NSToolbarItem]
    A --> B[NSStackView container]
    B --> C[Tables button tag=0]
    B --> D[Favorites button tag=1]
  end
  subgraph NSSplitViewController
    E[sidebarTrackingSeparator]
    F[.toggleSidebar system action]
  end
  G[User click Tables/Favorites] --> H[Switch sidebar tab]
  I[User click chevron in split view] --> F
```

User nhìn 3 thứ trên 1 hàng → 3 control khác nhau:
1. Tables/Favorites tab switch (trong `sidebarToggle` item)
2. Collapse/expand sidebar chevron (do NSSplitViewController)
3. Tracking separator

→ Confusing.

User checklist 2026-05-25 mark item này xong, nhưng source vẫn như diagram trên.
Cần verify UI runtime trước khi đổi docs thành DONE.

## Local checklist TODO flows

```mermaid
flowchart TD
  A[SidebarContainerViewController] --> B[NSSearchField]
  A --> C[SidebarView hosted content]
  C --> D[List tables]
  D --> E[Right-click table]
  E --> F[SidebarContextMenu]
  F --> G[Create New Table...]

  H[Desired top create action] -. TODO .-> I[Call coordinator.createNewTable]
  I --> J{safeMode blocks writes?}
  J -->|yes| K[disabled]
  J -->|no| L[open create table tab]
```

```mermaid
flowchart LR
  A[window.minSize 720] --> B[Sidebar min 280]
  A --> C[Detail min 400]
  A --> D[Inspector min 270]
  B --> E{Sidebar + detail + inspector}
  C --> E
  D --> E
  E -->|~950 before dividers| F[Overflow risk on small window]
```

## Đề xuất tách (nếu fork re-implement)

```mermaid
flowchart LR
  subgraph Sau khi tách
    A1[sidebarToggle item] -->|system action| B1[NSSplitViewController.toggleSidebar:]
    A2[sidebarMode item] --> C1[NSStackView]
    C1 --> D1[Tables tag=0]
    C1 --> E1[Favorites tag=1]
  end
```

## Favorite tables — current flow (commit `408d1589` + session sidebar-recents-star)

```mermaid
sequenceDiagram
  participant U as User
  participant TR as TableRow (star button)
  participant ST as FavoriteTablesStorage
  participant NC as NotificationCenter
  participant SV as SidebarView
  participant FT as FavoritesTabView

  U->>TR: click trailing star
  TR->>ST: toggle(table.name)
  ST->>ST: persist Set<String> → UserDefaults
  ST-->>NC: post .favoriteTablesDidChange

  NC-->>SV: onReceive → reload favoriteTables Set<String>
  SV->>SV: SidebarTableOrdering.sortedByFavorite() → pin to top
  SV->>TR: rebuild with isFavorite + onToggleFavorite

  NC-->>FT: onReceive → reload favoriteTables [String]
  FT->>FT: Section("Tables") → render star rows
```

Star button trạng thái: `star.fill` (yellow) nếu favorite, `star` (secondary opacity 55%) nếu không.

Context menu **không còn** Add/Remove Favorites — star button là path duy nhất.

## Recent tables — current flow

```mermaid
sequenceDiagram
  participant U as User
  participant C as MainContentCoordinator
  participant R as RecentTablesStore
  participant NC as NotificationCenter
  participant SV as SidebarView

  U->>C: openTableTab(_ table:)
  C->>R: push(connectionID, activeDatabaseName, table)
  R->>R: LRU insert (cap 10 per (conn, db))
  R-->>NC: post .recentTablesDidChange

  NC-->>SV: onReceive → reloadRecentTables()
  SV->>R: entries(connectionID, database)
  R-->>SV: [Entry] sorted by lastAccessedAt desc
  SV->>SV: render `recentSection` at top of Tables list
```

Storage: in-memory `@MainActor` singleton (`RecentTablesStore.shared`); clears on quit. Key = `(connectionID: UUID, database: String)`. Schema stored in `Entry`, not key (xem [D14](decisions.md#d14-recent-tables--connectionid-database-key-not-include-schema)).

Render site: `SidebarView.recentSection` rendered **trước** `ForEach(SidebarObjectKind.allCases)`. Hidden khi `filteredRecents.isEmpty`. Expand state qua `SidebarViewModel.isRecentsExpanded` (default `true`, not persisted).

Recent rows tag bằng `TableInfo`. Vì `TableInfo` Equality bỏ qua `rowCount`, selection của recent row đồng nhất với row trong section chính.

## Open PR #1460 — generation-guard flow (reuse `generations` sẵn có)

> Fix dùng `generationToken(for:)`/`bumpGeneration()` đã có trên main (`SchemaService.swift:21-28`), KHÔNG thêm dict thứ 2.

```mermaid
flowchart TD
    A[Kick off load cho connectionId] --> B[bumpGeneration connectionId]
    B --> C[capturedToken = generationToken connectionId]
    C --> D[await fetchTables]
    D --> E{generationToken == capturedToken?}
    E -->|Stale: load mới đã kick off| F[Bỏ qua, không ghi state]
    E -->|Current| G[Ghi tables]
    G --> H[await fetchRoutines/Functions]
    H --> I{generationToken == capturedToken?}
    I -->|Stale| F
    I -->|Current| J[Ghi routines]
    J --> K[await fetchSchemas]
    K --> L{generationToken == capturedToken?}
    L -->|Stale| F
    L -->|Current| M[Ghi schemas, tắt spinner]
    D -->|Throw| N[catch: reset state .idle, tắt spinner — KHÔNG xoá]
    H -->|Throw| N
    K -->|Throw| N
```

Catch-block luôn reset `.idle` bất kể generation → spinner không bao giờ kẹt khi lỗi (root cause của stuck spinner).

## Open PR #1484 — rebase-deconflict flow

```mermaid
flowchart TD
    A[branch recent-tables\nbase d8adcedf] -->|git fetch upstream + rebase| B{rebase upstream/main}

    B -->|#1422 favorites đã merge 4fad0b83| C[FavoriteTablesStorage.swift diff = 0\nSync mappers/tests diff = 0\nDuplicate tự biến mất]

    B -->|#1473 database-tree 634c3cb7| D{Conflict: PR base cũ muốn xoá\nDatabaseTreeView + metadata services}
    D -->|THEIRS: giữ files #1473| E[Chỉ apply recent delta vào SidebarView]

    B -->|#1483 perf e1d88fbc| F{Conflict: SchemaService/QueryExecutor\nSQLSchemaProvider bản cũ}
    F -->|THEIRS: giữ main| G[Chỉ thêm push call\nvào MainContentCoordinator+Navigation]

    C --> H[Delta thực còn lại]
    E --> H
    G --> H

    H --> I[RecentTablesStore.swift +57\nGeneralSettings +showRecentTables OFF\nSidebarView +recent section gated\nNavigation +1 dòng push\nTests: RecentTablesStoreTests, GeneralSettingsTests]
    I --> J[Ký CLA]
    J --> K[Merge SAU #1489]

    H -.->|Nếu SidebarView conflict > 3 file phức tạp| L[Option B: rewrite-clean\nbranch mới từ main, cherry-pick delta\nxem D-1484]
```
