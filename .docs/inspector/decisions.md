# inspector — decisions

## ADR-001: Dynamic window.minSize vs fixed larger minSize

**Date**: 2026-05-25

**Context**: Ba pane (sidebar+detail+inspector) cộng lại ~954pt, vượt `window.minSize.width = 720`. Cần fix overflow khi inspector toggle.

**Options considered**:

1. **Raise `window.minSize` lên 954pt cố định** — đơn giản, một dòng code. Nhược: ép user không được thu nhỏ window khi inspector tắt; không phù hợp khi sidebar cũng collapsed.

2. **Giảm `minimumThickness` của các pane** — giảm sidebar/inspector xuống để tổng ≤ 720. Nhược: pane quá hẹp không dùng được; phá vỡ usability của từng pane.

3. **Dynamic `window.minSize` theo pane visibility** — recompute mỗi khi visibility thay đổi. Ưu: minSize luôn đúng với trạng thái hiện tại; user có thể thu nhỏ window khi pane ẩn.

**Decision**: Option 3.

**Rationale**: Giữ nguyên `minimumThickness` hợp lý cho từng pane. Window chỉ bị ép lớn khi user thực sự bật pane đó. Co lại khi pane ẩn.

---

## ADR-002: Call sites cho recomputeWindowMinSize

**Date**: 2026-05-25

**Context**: Cần đảm bảo `recomputeWindowMinSize()` chạy tại mọi thời điểm pane visibility có thể thay đổi.

**Decision**: 4 call sites:

| Call site | Lý do |
|---|---|
| `showInspector()` | Explicit toggle on |
| `hideInspector()` | Explicit toggle off |
| `splitViewDidResizeSubviews(_:)` | AppKit trigger khi user drag divider đến 0 (collapse auto) |
| `viewWillAppear()` | Initial state từ UserDefaults khi window load |

`splitViewWillResizeSubviews` không dùng vì muốn giá trị sau khi resize hoàn tất.

---

## ADR-003: Không dùng `NSWindow.contentMinSize`

**Date**: 2026-05-25

**Context**: AppKit có cả `minSize` và `contentMinSize`.

**Decision**: Dùng `minSize` (bao gồm title bar). `TabWindowController` đã set `minSize` từ trước, consistent.

---

## ADR-004: Không cần unit test

**Date**: 2026-05-25

**Context**: Logic là geometry arithmetic — cộng số cố định.

**Decision**: Manual verify đủ. Unit test cho geometry layout AppKit phức tạp, dễ flaky, lợi ích thấp.

> Superseded 2026-05-30 bởi ADR-007: PR #1463 thêm 5 unit test thuần geometry
> (`MainSplitViewControllerWindowMinimumSizeTests`) — testable không cần live window,
> nên giữ test.

---

# Open fork PR #1463 — decisions (2026-05-30)

## ADR-005: Drop noise `.gitignore` / `CLAUDE.md`
**Context**: upstream/main đã có entries; PR add lại = conflict giả.
**Decision**: reset 2 file về upstream khi rebase.
**Trade-off**: không có.

## ADR-006: GỘP vào `recomputeWindowMinSize()` `:516`, không tạo method mới
**Context**: main đã có `recomputeWindowMinSize()` `:516` + 4 call site (`:185,:217,:478,:484`).
PR thêm `recomputeWindowMinimumSize()` (tên khác) với logic tốt hơn (`PaneMinimum` /
`resolvedContentMinSize` / `originalContentMinSize`).
**Decision**: gộp logic PR vào method cũ, giữ tên cũ; không thêm override
`splitViewDidResizeSubviews()` (main đã có `:183`).
**Lý do**: DRY — 2 method trùng chức năng vi phạm nguyên tắc; tên cũ đã rõ nghĩa, 4 call
site không cần đổi.
**Trade-off**: mất tên `recomputeWindowMinimumSize` — không đáng kể.

## ADR-007: Giữ unit test geometry (supersede ADR-004)
**Context**: PR đóng gói sizing math thành pure function `resolvedContentMinSize()`,
test được không cần live window/animation.
**Decision**: giữ 5 test (`MainSplitViewControllerWindowMinimumSizeTests`).
**Trade-off**: không — test deterministic, không flaky.

## ADR-008: Commit atomic (gộp method + call site cùng 1 commit)
**Context**: tách "gộp method" và "cập nhật call site" → commit giữa broken (build fail / git bisect).
**Decision**: 1 commit duy nhất bao gồm toàn bộ consolidation (rule "Atomic API changes").
**Trade-off**: commit lớn hơn, chấp nhận được.

## ADR-009: Giữ `setCollapsed` pre-hook
**Context**: pre-hook resize trước animation tránh visual jank/clip — không có trên main.
**Decision**: giữ từ PR, tích hợp vào `showInspector()` / `hideInspector()`.
**Trade-off**: không — logic rõ, test cover.

## ADR-010: Base min-size phải lấy từ baseline immutable, không từ `window.minSize` mutate
**Date**: 2026-05-30
**Context**: Codex bot review (P2, inline `MainSplitViewController.swift:197`) chỉ ra bug
diff-review trước bỏ sót: nếu base được suy ra từ `window.minSize`/`contentMinSize` (đã bị
các lần gọi trước gán giá trị widen), floor **chỉ tăng**. Show inspector widen lên tổng pane;
khi hide, `window.minSize` vẫn giữ giá trị widen → base không giảm → window editor hẹp kẹt
oversized, không relax về 720pt.
**Decision**: base **luôn** đến từ baseline cố định (`originalContentMinSize`, capture 1 lần,
không bị overwrite bởi giá trị widen). Body `recomputeWindowMinSize()` sau khi gộp **KHÔNG**
đọc base từ `window.minSize` hiện tại.
**Verify khi fix**: confirm `originalContentMinSize` của PR capture đúng base gốc; test cycle
show → hide phải relax về 720pt (fail nếu base đọc từ minSize mutate).
**Trade-off**: không — đây là điều kiện đúng đắn của tính năng, không phải optional.
