# tabs — tasks

Review 2026-05-25: user checklist item "mặc định chọn table replace current
window, nhưng sau khi thêm new tab thì lần chọn table tiếp theo lại new tab" vẫn
được map vào #1348 và giữ trạng thái `DONE-upstream/current`.

| Item | Issue | PR | Author | Merged | Commit |
|---|---|---|---|---|---|
| Click table inconsistent: replace vs new tab | [#1348](https://github.com/TableProApp/TablePro/issues/1348) | [#1394](https://github.com/TableProApp/TablePro/pull/1394) | datlechin | 2026-05-22 | `967a1b99` |

## File changes (PR #1394)

13 files; +448 / −484 LOC (net −36; major dedup):

- `TablePro/Core/Services/Infrastructure/MainSplitViewController.swift` (+4 −11)
- `TablePro/Core/Services/Infrastructure/WindowLifecycleMonitor.swift` (+3 −21)
- `TablePro/Views/Main/Extensions/MainContentCoordinator+Navigation.swift` (+127 −201)
- `TablePro/Views/Main/Extensions/MainContentView+EventHandlers.swift` (+3 −7)
- `TablePro/Views/Main/Extensions/MainContentView+Setup.swift` (+2 −3)
- `TablePro/Views/Main/SidebarNavigationResult.swift` (+13 −32)
- `TableProTests/Views/Main/MultiConnectionNavigationTests.swift` (+23 −17)
- `TableProTests/Views/Main/OpenTableTabTests.swift` (+170 −0) ⟵ test file mới
- `TableProTests/Views/Main/SharedSidebarSyncTests.swift` (+13 −8)
- `TableProTests/Views/SidebarNavigationResultTests.swift` (+85 −178)
- `TablePro/Resources/Localizable.xcstrings` (+2 −2)
- `docs/features/tabs.mdx` (+2 −4)
- `CHANGELOG.md` (+1 −0)

## Removed code

- `WindowLifecycleMonitor.previewWindow`
- `WindowLifecycleMonitor.setPreview`
- `WindowLifecycleMonitor.Entry.isPreview`
- `MainContentCoordinator.openPreviewTab` (cross-window preview lookup)
