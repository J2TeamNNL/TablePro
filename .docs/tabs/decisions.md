# tabs — decisions

## D1. `QueryTab.isPreview` là source of truth duy nhất

**Context.** 2 nơi track preview flag drift ra khỏi nhau:

- `QueryTab.isPreview` (per-tab)
- `WindowLifecycleMonitor.previewWindow` / `Entry.isPreview` (per-window)

**Options.**
- (a) Sync 2 source bằng observer
- (b) Bỏ window-level, **chỉ per-tab** ✓
- (c) Bỏ per-tab, chỉ per-window

**Chosen.** (b). Per-tab natural hơn (preview là property của tab, không phải window).
Bỏ luôn `previewWindow`, `setPreview`, `Entry.isPreview`, và `openPreviewTab`.

---

## D2. Single-click window-local thay vì cross-window

**Context.** `openPreviewTab` cross-window có thể replace tab ở window khác và
steal focus sang đó — confusing UX.

**Options.**
- (a) Keep cross-window, fix focus stealing
- (b) **Window-local: chỉ check focused window's active tab** ✓
- (c) Cross-connection preview (lớn hơn nữa)

**Chosen.** (b). Match macOS convention (Finder, Xcode, VS Code): single-click
in-place trong window đang focus. User muốn preview window khác → click vào
window đó trước.

**Consequence.** Cross-window preview gone — theo PR author đây là feature loss
NHƯNG net positive vì pattern cũ steal focus.

---

## D3. `enablePreviewTabs` chỉ quyết "asPreview", không gate reuse

**Context.** Pre-fix: với `enablePreviewTabs = false`, không có reuse path → mọi
click là tab mới. Đây là regression cho user tắt preview vì không thích italic.

**Options.**
- (a) Disable cũng disable reuse
- (b) **Disable chỉ disable preview FLAG, reuse vẫn theo "blank query, no unsaved"** ✓

**Chosen.** (b). Reuse-active-tab khi active là blank query không có unsaved edit
vẫn hợp lý với user tắt preview. Họ get reuse based on tab content, không phải
preview marker.

---

## D4. Pinned + working tab protected

**Context.** Không muốn click bừa làm mất unsaved work hoặc tab pinned.

**Chosen.** Guard chain:

1. `isPinned == true` → `.openNewTab`
2. có unsaved edit → `.openNewTab`
3. còn lại → check reusable

Match Xcode/VS Code.

---

## D5. Test coverage là contract layer

**Context.** PR rewrite logic. Tests cũ test implementation detail của
`openPreviewTab`.

**Chosen.** Rewrite test theo contract `.skip` / `.reuseActiveTab` / `.openNewTab` —
test decision function, không phải side-effect. `SidebarNavigationResultTests`
xuống từ +178 → +85 (vẫn cover scenarios nhưng gọn).
