# toolbar — decisions

## D1. Popover thay vì add close button cho Active Connections

**Context.** Active Connections sheet không có close button. Naive fix: add button.

**Options.**
- (a) Add explicit close button vào sheet
- (b) **Đổi sheet → popover anchored toolbar (mirror `DatabaseSwitcher`)** ✓
- (c) Đổi sang full-window NSPanel

**Chosen.** (b) — sheet là **modal** by HIG, đúng cho task có save/cancel.
Connection switcher là transient view chọn nhanh → popover là primitive đúng.
Popover auto Esc + click-outside dismiss → close button thừa.

**Consequence.** Lost: modal dim không còn (UX khác). Gained: HIG conform, parity
với `DatabaseSwitcher` (Cmd+K), `Cmd+Ctrl+C` menu path đơn giản hơn.

---

## D2. QuickSwitcher giữ là sheet, KHÔNG đổi popover

**Context.** Cùng logic của D1 → có tempting đổi quick switcher sang popover.

**Chosen.** **GIỮ là sheet.** Quick switcher là **full-content command palette** —
user invoke từ keyboard (Cmd+Shift+O), không anchor cụ thể, full focus required.
Sheet (modal) chính là semantics đúng.

**Lesson.** "Wrong primitive" không universally apply — judge per use-case.
Active Connections anchor vào toolbar button cụ thể → popover. Quick switcher
là free-floating palette → sheet.

---

## D3. Sheet height = compute-from-content thay vì hard-coded

**Context.** SwiftUI `List` expand to fill, không shrink. Hard-coded height tạo
blank.

**Options.**
- (a) Hard-code height nhỏ hơn
- (b) **Pure view-model function `listHeight(rowHeight:headerHeight:maxVisibleRows:)`**
  drive frame ✓
- (c) GeometryReader đo content runtime

**Chosen.** (b) — pure function → unit-testable, deterministic. (c) gây re-layout
loop. (a) tệ cho cả use-case nhiều và ít item.

---

## D4. Header count vào cap

**Context.** Empty query → multi-section grouped view (Recents + Favorites +
Tables...). Nếu chỉ cap rows, headers ngoài cap → over-shoot.

**Chosen.** `listHeight = items*rowHeight + sectionHeaders*headerHeight`, clamp
total tới `cap = maxVisibleRows * rowHeight`. Headers count vào height ngân sách
→ dense empty-query không over-shoot.

---

## D5. `isLoading` default `true`

**Context.** Sheet open → load entries async → trong khoảng đó list rỗng → render
"No objects found" trước khi load complete → flash UX.

**Chosen.** ViewModel khởi tạo `isLoading = true`. Set `false` sau load. Render
loading state ngay khi open → không flash.

---

## D6. `ConnectionSwitcherFilter` là pure value-type tách riêng

**Context.** Filter logic ban đầu inline trong sheet view.

**Chosen.** Extract `ConnectionSwitcherFilter.matches(_:query:)` thành pure func →
unit test 4 case (empty/whitespace, name match, database match, no match) mà
không spin up view.

Pattern này áp dụng nhiều ở scope datagrid:
`ColumnFetchScope.selectColumns`, `VisibleColumnProjection`, `JsonReindenter`,
`FilterRestore.decision` — pure value-types tách logic khỏi view → testable.
