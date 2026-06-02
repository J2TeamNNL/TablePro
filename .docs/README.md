# `.docs` — Case-study từ upstream PRs

> **KHÔNG phải docs cho end-user.** Docs end-user nằm ở `docs/` (Mintlify `.mdx`).
> Folder này dành cho **dev/AI nội bộ** ở fork `J2TeamNNL/TablePro`, ghi lại quá trình
> reverse-engineer các PR đã merge của upstream để hiểu **vì sao** thiết kế cũ sai
> và **fix approach** được chọn.

## Bối cảnh

Sau khi fork `TableProApp/TablePro`, owner liệt kê một nhóm vấn đề UX/feature gặp phải.
Cross-check upstream (commits 2026-05-13 → 2026-05-25) cho thấy phần lớn các
case-study gốc đã được fix và merge — chủ yếu do `datlechin` báo cáo và sửa.

Review ngày 2026-05-25 mở rộng checklist lên 17 items. Một số item đã được
current branch fix sau tài liệu gốc, một số vẫn là TODO trong fork.

Thay vì re-implement, repo này dùng các PR đó làm tài liệu case-study:
- Hiểu root cause cũ (anti-pattern, source-of-truth nhân đôi, primitive sai)
- Hiểu fix approach (bao gồm trade-off, tests, scope)
- Có lịch sử rõ để AI/dev sau tham chiếu nhanh

## Tổ chức theo Conventional Commits scope

Mỗi folder ứng với một scope của upstream commit (`feat(scope):`, `fix(scope):`).
Mỗi folder có đúng 7 files:

| File | Mục đích |
|---|---|
| `README.md` | Index + navigation trong scope |
| `brief.md` | One-pager: vấn đề chung, mục tiêu, kết quả |
| `content.md` | **Case-study chi tiết**: symptom → root cause (file+function) → fix (diff snippet) |
| `flow.md` | Mermaid diagram cho case phức tạp nhất trong scope |
| `tasks.md` | Bảng issue # / PR # / author / merge date / commit SHA / status |
| `decisions.md` | ADR-lite: trade-offs, options considered, chosen approach |
| `changelog.md` | Timeline issue mở → PR merge → version released |

## 8 scope folders

| Scope | Items | Issues | PRs chính |
|---|---|---|---|
| [`datagrid/`](datagrid/README.md) | copy cell, JSON viewer, raw SQL filter, persist filter+hide col, copy visible cols | #1344, #1345, #1346, #1347, #1354, #1375 | #1337, #1338, #1339, #1341, #1360, #1372, #1373, #1375, #1384, #1387, #1395, #1411, #1412 |
| [`tabs/`](tabs/README.md) | table-click → reuse vs new tab | #1348 | #1394 |
| [`toolbar/`](toolbar/README.md) | quick switcher size, active connections popover | #1349, #1350 | #1386, #1392 |
| [`connections/`](connections/README.md) | safe mode reset | #1351 | #1376 |
| [`sidebar/`](sidebar/README.md) | create table entry, context menu disabled state, favorite/recent tables, sidebar toggle | #1352, #1353 + local checklist | _không có PR linked — partial current branch_ |
| [`inspector/`](inspector/README.md) | inspector pane overflow khi toggle | local checklist | _không có PR linked — DONE branch `sidebar`_ |
| [`import/`](import/README.md) | DBeaver username lost | #1355 | #1366 |
| [`keyboard/`](keyboard/README.md) | F5/F9/F1 function-key shortcuts + tooltip | fork PR | #1489 |

## Open fork PR triage (2026-05-30)

> Khác với các scope case-study ở trên (PR upstream ĐÃ merge). Section này là **8 PR đang MỞ** của fork `J2TeamNNL` gửi lên `TableProApp/TablePro`. Mỗi PR được map vào folder scope tương ứng làm gói handoff cho 1 agent/conversation fix.

**Root cause chung**: phần lớn PR CONFLICTING do mỗi branch lỡ commit thay đổi môi trường local (`.gitignore`: `.docs/`/`Local.xcconfig`/`/plans/reports`; `CLAUDE.md` dòng "Favorite tables") — upstream main giờ đã có sẵn → add lại = conflict rác. Gỡ các hunk này xử lý phần lớn conflict.

| PR | Scope folder | Branch | Conflict / CLA | Hành động chính |
|---|---|---|---|---|
| [#1459](https://github.com/TableProApp/TablePro/pull/1459) | [`datagrid/`](datagrid/README.md) | `fix/datagrid` | ✅ **MERGED 2026-05-29** | Xong — branch xoá được, không cần handoff |
| [#1460](https://github.com/TableProApp/TablePro/pull/1460) | [`sidebar/`](sidebar/README.md) | `debug/sidebar` | ✅ **MERGED 2026-05-29** | Xong — branch xoá được, không cần handoff |
| [#1461](https://github.com/TableProApp/TablePro/pull/1461) | [`connections/`](connections/README.md) | `fix/connections` | ⚠️ rác / ok | Bỏ noise, giữ invariant |
| [#1462](https://github.com/TableProApp/TablePro/pull/1462) | [`import/`](import/README.md) | `feat/import` | ⚠️ rác / ok | Bỏ noise, verify test |
| [#1463](https://github.com/TableProApp/TablePro/pull/1463) | [`inspector/`](inspector/README.md) | `fix/inspector` | ⚠️ logic / ok | Gộp vào `recomputeWindowMinSize()` |
| [#1484](https://github.com/TableProApp/TablePro/pull/1484) | [`sidebar/`](sidebar/README.md) | `recent-tables` | ⚠️ nặng / ❌ fail | Rebase bỏ favorites trùng, ký CLA |
| [#1489](https://github.com/TableProApp/TablePro/pull/1489) | [`keyboard/`](keyboard/README.md) | `feat/function-key-shortcuts` | ✅ **FIXED 2026-05-31 → MERGEABLE** | Rebuild sạch trên main (bỏ noise), gộp CHANGELOG, **fix Codex P2** (bare F-key primary "ghost"). Chờ CI |
| [#1465](https://github.com/TableProApp/TablePro/pull/1465) | meta (ghi chú dưới) | `docs/update-testing-rules` | ⚠️ rác / ❌ CLA | **THEO ĐUỔI** (owner quyết 2026-05-30): sửa CLA + làm rõ wording + xử lý sau #1484 |

**Đã MERGED**: #1459, #1460 (2026-05-29), #1422 (favorites, squash `4fad0b83`). **#1489 đã fix conflict + Codex P2 (2026-05-31), đang `MERGEABLE` chờ CI**. Còn mở cần xử lý: #1461, #1462, #1463, #1484, #1465.

**Thứ tự merge khuyến nghị (PR còn mở)**: #1461 / #1462 / #1463 → #1489 → #1484 → #1465. #1465 (owner quyết THEO ĐUỔI) xử lý cuối vì lệnh UI test cần target `TableProUITests` do #1484 thêm.

### Meta — #1465 `docs(claude-md)` strengthen testing rules

PR này **không phải product feature** nên không có folder scope riêng. Nó sửa `CLAUDE.md` (+4/-2) + `.gitignore`, siết quy tắc testing và thêm lệnh UI test (`-only-testing:TableProUITests`). Trạng thái: CONFLICTING + CLA FAILING.

> **Đính chính (2026-05-30)**: Ghi chú trước đây khuyến nghị **đóng** PR với giả định "upstream sở hữu `CLAUDE.md` nên sẽ reject fork edit". Giả định đó là **suy đoán, không có comment maintainer nào hỗ trợ** — kiểm tra comment thực tế trên PR cho thấy **không maintainer nào phản đối**, chỉ có bot tự động comment. Rút lại khuyến nghị đóng.

**Blocker thật (từ comment thực tế trên PR):**

1. **CLA fail** — lý do "1 out of 2 committers have signed the CLA": một commit do identity chưa ký CLA author (khả năng cao `Claude <noreply@anthropic.com>`). **Fix**: re-author commit đó về owner + ký CLA. Đây KHÔNG phải governance rejection.
2. **Codex P2** (inline trên `CLAUDE.md:55`): lệnh mới chọn `TableProUITests`, nhưng target test duy nhất trong `project.pbxproj` / `TablePro.xcscheme` là `TableProTests`. `-only-testing` identifier root từ test target → lệnh này **không chạy được, sẽ fail** cho tới khi có target `TableProUITests`. Target đó được **PR #1484 thêm vào** (kèm `TableProUITests/TableProLaunchUITests.swift` + sửa scheme). → Lệnh của #1465 **phụ thuộc #1484 land trước**. Fix: land #1484 trước, hoặc bỏ/điều chỉnh lệnh.
3. **Noise hunk** `.gitignore` / `CLAUDE.md` — đã có trên main, gỡ như các PR khác.

- **Quyết định của owner (2026-05-30): THEO ĐUỔI.** Kế hoạch fix (xử lý sau khi #1484 land):
  1. Re-author commit đứng tên `Claude <noreply@anthropic.com>` về owner + ký CLA (đạt 2/2 committer).
  2. Chờ #1484 land để có target `TableProUITests`, rồi giữ lệnh `-only-testing:TableProUITests`. Nếu #1484 chưa land lúc cần merge #1465 → tạm bỏ dòng lệnh UI test, thêm lại sau.
  3. Gỡ noise hunk `.gitignore` / `CLAUDE.md`, rebase lên upstream/main.
  4. Làm rõ wording mơ hồ "when deterministic" (định nghĩa rõ: flow nào tính là deterministic; network/animation/timing được loại trừ).

## Review 2026-05-25 — current branch

| Scope | Item từ checklist | Current status |
|---|---|---|
| `sidebar` | Hiển thị nút create/insert new table ở phía trên thay vì chỉ trong right-click menu | TODO-fork. Hiện chỉ có `Create New Table...` trong `SidebarContextMenu`. |
| `sidebar` | Disable parent/button khi toàn bộ action con bị disabled trong context menu | TODO-fork. Chưa có helper tổng hợp disabled-state cho menu group. |
| `inspector` | Toggle sidebar làm window/trailing controls bị tràn/che | DONE-current. Xem [`inspector/`](inspector/README.md). Pending manual UI verify. |
| `datagrid` | Save hidden columns + filter theo table; giữ hidden khi switch table | DONE-current. Có `ColumnVisibilityPersistence` + save outgoing tab khi switch. |
| `datagrid` | Cmd+C mặc định copy value cell; copy row là action riêng | DONE-current. `KeyHandlingTableView.copy(_:)` ưu tiên focused cell. |
| `datagrid` | Luôn hiển thị/restore filter | DONE-upstream/current theo #1347, #1387, #1395. |
| `sidebar` | Favorite table / recent table | TODO-current. Source không có `FavoriteTablesStorage`, table star badge, hoặc `RecentTable*`. Favorites tab hiện là SQL favorites. |
| `import` | DBeaver import mất username | DONE-upstream. |
| `datagrid` | Copy sau khi hide column chỉ copy cột đang show | DONE-upstream/current. |
| `sidebar` | Sidebar toggle có thêm toggle/more option gây rối | VERIFY-current. User checklist mark done, nhưng source vẫn gộp Tables/Favorites trong toolbar item. |
| `connections` | Safe Mode reset khi mở table mới | DONE-upstream. |
| `toolbar` | Active Connections là modal dim background, cần nút đóng | DONE-upstream. Đã đổi sang popover. |
| `toolbar` | Quick switcher thừa khoảng trống bên dưới | DONE-upstream. |
| `tabs` | Chọn table sau khi mở new tab luôn mở tab mới | DONE-upstream. |
| `datagrid` | Raw SQL filter chỉ suggest token đầu, sau `AND` cần suggest cột tiếp | DONE-upstream/current. |
| `datagrid` | JSON bị cắt, detail view vẫn thiếu data | DONE-upstream/current. |

## Convention

- Mọi link issue/PR dùng URL đầy đủ `https://github.com/TableProApp/TablePro/...`
- Mọi file path trong content.md dùng path tương đối từ repo root
- Diff snippet ngắn, trích chỗ cốt lõi — đầy đủ xem `gh pr diff <num>`
- Mermaid block dùng cú pháp chuẩn, paste vào https://mermaid.live để verify

## Status

Case-study upstream phần lớn là `DONE-upstream`. Current branch hiện là
`PARTIAL-current` do các item sidebar mới/chưa rõ trạng thái:

- TODO rõ: top-level create table action, favorite/recent tables, context-menu
  disabled grouping.
- TODO cần repro UI: sidebar collapse/expand gây overflow hoặc che toolbar/control.
- Cần verify thực tế: sidebar toggle "more option" user đánh dấu xong nhưng source
  vẫn còn combined Tables/Favorites toolbar item.

Nếu owner muốn implement tiếp, bắt đầu từ `sidebar/tasks.md`; các scope còn lại chủ
yếu là tài liệu tham chiếu cho behavior đã có.
