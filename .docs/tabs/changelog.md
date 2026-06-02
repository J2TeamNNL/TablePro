# tabs — changelog

## Timeline

| Date | Event |
|---|---|
| 2026-05-20 05:29 | Issue [#1348](https://github.com/TableProApp/TablePro/issues/1348) opened by datlechin |
| 2026-05-22 16:53 | PR [#1394](https://github.com/TableProApp/TablePro/pull/1394) opened |
| 2026-05-22 17:06 | PR #1394 merged — commit `967a1b99` |

## Release

### [v0.44.0] — 2026-05-23

**Fixed**
- Clicking a table now replaces the active tab instead of opening a new one when
  you have multiple tabs open. A new tab still opens for unsaved edits, an applied
  filter, or sorting; double-click always opens a new tab. (#1348)
