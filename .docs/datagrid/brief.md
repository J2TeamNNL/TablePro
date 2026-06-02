# datagrid — brief

## Scope

6 vấn đề UX trong data grid (table view) và filter bar.

## Vấn đề chung

Data grid của TablePro tích luỹ nhiều **anti-pattern legacy**:

1. **Source-of-truth nhân đôi** — `QueryTab.buildBaseTableQuery` và `TableQueryBuilder`
   build SQL khác nhau cho cùng một table; preview-tab tracked ở 2 nơi
   (`QueryTab.isPreview` + `WindowLifecycleMonitor.previewWindow`).
2. **Server-side truncation aliased về tên gốc** — `SUBSTRING(col, 1, 256) AS col`
   khiến grid không biết value bị cắt; edit + save → ghi giá trị bị cắt vào DB
   (data corruption).
3. **Shortcut bám một-prefix** — Cmd+C luôn copy cả row dù focus ở cell;
   raw SQL filter completion match cả-chuỗi nên chỉ suggest token đầu.
4. **Filter bar ephemeral** — saved theo `tableName` trần (collision cross-connection),
   restoration gated bởi setting default "Always Hide" → reopen luôn mất.
5. **JSON formatter destructive** — round-trip qua `JSONSerialization.sortedKeys`
   reorder key, round bigint qua `NSNumber`, mark row dirty chỉ vì view.
6. **Copy ignore visibility** — clipboard ra mọi column dù user đã hide / reorder.

## Mục tiêu

- Một source of truth cho query build, cho preview-flag, cho filter persistence
- Truncation ở **render layer**, không phải SQL layer
- Shortcut match macOS HIG: Cmd+C target selection cụ thể nhất đang visible
- Per-(connection+db+schema+table) key cho mọi state lưu
- Formatter idempotent + non-destructive (semantic compare, byte-exact numbers)
- Visibility là first-class cho mọi copy/query path

## Kết quả sau merge

- `TableQueryBuilder` là source duy nhất; editor query == executed query
- Cell viewer overlay đọc-only cho text/JSON/BLOB (Return / double-click), Cmd+C
  copy đúng giá trị visible
- Raw SQL filter completion gọi `CompletionEngine` ở mọi clause position
- Filter restore default ON; key per (conn+db+schema+table); user-clear nhớ là clear
- JSON `JsonReindenter` preserve key order + bigint precision; view không mark dirty
- `VisibleColumnProjection` áp lên tất cả copy path; hide column → cũng drop khỏi
  `SELECT` (PK luôn fetch)
- Current branch lưu hidden columns qua `ColumnVisibilityPersistence` và persist
  outgoing tab khi switch table.

## Trade-off chính

- Hide/show column không còn là instant cosmetic toggle — phải re-run query
  (xem `decisions.md` § "Hide = drop from SELECT")
- `Cmd+Shift+F` cũ cho "Toggle Filters" bị remove làm default → Cmd+F context-aware
  (xem `decisions.md` § "Cmd+F context routing")
