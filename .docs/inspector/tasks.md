# inspector — tasks

> **Reconcile 2026-05-30 (verified vs main).** PR #1463 vẫn **OPEN** (branch
> `fix/inspector`), chưa merge. main ĐÃ CÓ `recomputeWindowMinSize()` `:516` + 4 call
> site (`:185,:217,:478,:484`); call site `splitViewDidResizeSubviews :185` **đã có sẵn**
> (không phải "missing call site added in PR"). PR thêm `recomputeWindowMinimumSize()`
> (tên mới) + `PaneMinimum`/`resolvedContentMinSize`/`originalContentMinSize`/`setCollapsed` —
> các symbol này **chưa có** trên main. Bảng trạng thái cũ bên dưới (DONE-2026-05-25/28)
> mô tả implementation đã có trên main + dự định, **không** phản ánh việc PR đã merge.

## Trạng thái main hiện tại (verified)

| Item | Status | Notes |
|---|---|---|
| `recomputeWindowMinSize()` def | ON-MAIN `:516` | Body geometry hiện tại (sum visible pane mins + dividers, floor 720). |
| Call site `splitViewDidResizeSubviews` | ON-MAIN `:185` | Đã có sẵn — không phải PR thêm. |
| Call site `viewWillAppear` | ON-MAIN `:217` | Initial state. |
| Call site `showInspector` | ON-MAIN `:478` | func `:474`. |
| Call site `hideInspector` | ON-MAIN `:484` | func `:481`. |

## PR #1463 deltas (OPEN — cần gộp, chưa trên main)

| Item | Status | Notes |
|---|---|---|
| `PaneMinimum` struct | OPEN-fork | sidebar 280 / detail 400 / inspector 270. Gộp vào `recomputeWindowMinSize()`. |
| `resolvedContentMinSize()` | OPEN-fork | `max(720, sum visible + dividerCount × thickness)`. |
| `originalContentMinSize` | OPEN-fork | Lưu base gốc, restore khi hide → tránh drift mở rộng vĩnh viễn. |
| `setCollapsed()` pre-hook | OPEN-fork | Pre-widen khi show / pre-shrink khi hide → tránh animation clip. |
| `recomputeWindowMinimumSize()` (tên mới) | DROP | **Không giữ** — gộp logic vào `recomputeWindowMinSize()` `:516`. |
| override `splitViewDidResizeSubviews()` từ PR | DROP | main đã có `:183`; không thêm lại. |
| Tests `MainSplitViewControllerWindowMinimumSizeTests` (+102, 5 case) | OPEN-fork | inspector 954 / hidden 720 / sidebar collapsed 720 / detail+inspector 802 / cycle relax 720. |
| Drop noise `.gitignore` + `CLAUDE.md:171` | TODO | reset về upstream khi rebase. |
| Manual UI verify | PENDING-runtime | Cần build + chạy app thực. |

> Superseded note (2026-05-30): các hàng "Fix base min size drift" / "Fix animation race"
> / tests `usesPaneSumWhenItExceedsBaseWithSidebarCollapsed` / `relaxesBackToOriginalBaseAfterInspectorCycle`
> đánh dấu DONE-2026-05-28 trước đây — thực chất là **deltas của PR #1463 đang open**, gom vào bảng trên.

## Agent checklist — merge PR #1463

**Setup**
- [ ] `git worktree add ../TablePro-pr1463 fix/inspector`.
- [ ] `git fetch upstream && git rebase upstream/main`.

**Drop noise**
- [ ] `git checkout upstream/main -- .gitignore`.
- [ ] `git checkout upstream/main -- CLAUDE.md` (dòng "Favorite tables" `:171`).

**Fix conflict chính (CRITICAL — đừng tạo method thứ hai)**
- [ ] Mở `TablePro/Core/Services/Infrastructure/MainSplitViewController.swift`.
- [ ] GỘP `PaneMinimum` + `resolvedContentMinSize()` + `originalContentMinSize` vào body `recomputeWindowMinSize()` `:516`.
- [ ] Thêm `setCollapsed(_ item:, collapsed:)` pre-hook; gọi thay `item.animator().isCollapsed = ...` trong `showInspector()` `:474` / `hideInspector()` `:481`.
- [ ] **KHÔNG** giữ `recomputeWindowMinimumSize()` từ PR.
- [ ] **KHÔNG** thêm override `splitViewDidResizeSubviews()` mới — `:183` đã gọi `recomputeWindowMinSize()`.
- [ ] Confirm 4 call site (`:185,:217,:478,:484`) vẫn gọi `recomputeWindowMinSize()`.
- [ ] Commit **atomic**: gộp method + call site trong 1 commit.

**Codex P2 (bot) — bug thật, verify + fix (inline `MainSplitViewController.swift:197`)**
- [ ] **Base min-size chỉ tăng không co**: base suy ra từ `window.minSize`/`contentMinSize` đang mutate → floor chỉ tăng, window kẹt oversized, không relax về 720pt sau khi toggle inspector.
  - [ ] Đảm bảo base lấy từ **baseline cố định** (`originalContentMinSize`), **KHÔNG** từ `window.minSize` đang mutate. Confirm `originalContentMinSize` capture đúng base gốc (chỉ set 1 lần, không bị overwrite bởi giá trị widen).
  - [ ] Test toggle inspector rồi co lại → window về đúng **720pt** (test "cycle show → hide relax về 720px" phải fail nếu base đọc từ minSize mutate).
  - [ ] Khi gộp logic PR vào `recomputeWindowMinSize()` `:516`: base trong body phải đến từ baseline immutable, không từ `window.minSize` hiện tại.

**Build / test / lint**
- [ ] `xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation`
- [ ] `-only-testing:TableProTests/MainSplitViewControllerWindowMinimumSizeTests`
- [ ] `swiftlint lint --strict`

**Ship**
- [ ] Push branch; confirm MERGEABLE sau khi fix conflict.
- [ ] Merge sau PR #1459, #1462.

## Verify commands

```bash
# Confirm recomputeWindowMinSize exists và đủ 4 call sites
grep -n "recomputeWindowMinSize" TablePro/Core/Services/Infrastructure/MainSplitViewController.swift

# Build clean để confirm không có compile error mới
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build \
  -skipPackagePluginValidation 2>&1 | grep -E "error:|Build succeeded"
```

## Manual verify steps

1. Build + run app
2. Mở connection, resize window về ~720pt
3. Click inspector button → window tự grow đến ~954pt, không overflow
4. Click inspector button lần nữa → window giữ kích thước, minSize về 720
5. Kéo window hẹp → bật inspector → window auto-expand
6. Sidebar collapsed + inspector on → minSize 720 (không ép grow)
7. Quit + reopen → inspector state restore, initial minSize đúng
