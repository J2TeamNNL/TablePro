# Changelog — `keyboard/` (PR #1489)

| Date | Event |
|---|---|
| — | PR #1489 mở (branch `feat/function-key-shortcuts`), +364/-18, 12 files |
| — | CLA ok |
| 2026-05-29 | Review: CONFLICTING (CHANGELOG chồng + noise `.gitignore`/`CLAUDE.md`) |
| 2026-05-29 | Finding: monitor lifecycle đúng, không leak, F-key mapping đúng US ANSI |
| 2026-05-30 | Verified findings; folder `keyboard/` tạo từ handoff |
| 2026-05-30 | Codex P2 trên `KeyboardSettingsView.swift:186`: primary bare F-key gán cho action menu-driven (vd F2 → Format Query) được accept + hiển thị nhưng monitor không dispatch → "hiện mà không chạy" |
| 2026-05-31 | **Conflict resolved**: rebuild branch thẳng trên `origin/main` (10 file feature thật), bỏ noise `.gitignore`/`CLAUDE.md` (đã có trên main), gộp CHANGELOG entry vào `[Unreleased] > Added` sẵn có. Xác nhận diff không đụng `Localizable.xcstrings` (note "rebase xcstrings" cũ là suy đoán) |
| 2026-05-31 | **Codex P2 fixed**: thêm `ShortcutAction.supportsFunctionKeyPrimary` (chỉ `.openDocumentation`); monitor `matchedAction` dùng property thay vì hardcode openDocumentation; validation reject bare F-key primary khi `!supportsFunctionKeyPrimary`. Thêm test `functionKeyPrimarySupport`. Build pass (chỉ fail code-signing môi trường), swiftlint --strict clean |
| 2026-05-31 | Force-push; PR #1489 → **MERGEABLE** (`mergeStateStatus: UNSTABLE` do CI đang chạy) |
| 2026-05-31 | CI **macOS Tests FAIL**: 1 test `BareKeyValidationTests.bareKeyDefaultsAreAllowed` (`TableProTests/Models/KeyboardShortcutTests.swift`) — invariant "mọi default no-modifier phải `allowsBareKey`". PR thêm `.openDocumentation` default F1 (no-modifier) nhưng F1 validate qua function-key path, không qua `allowsBareKey`. Author gốc bỏ sót test invariant này. **Fix**: update test branch theo `isFunctionKey` → assert `supportsFunctionKeyPrimary`, else `allowsBareKey` (khớp logic validation). KHÔNG set `openDocumentation.allowsBareKey=true` vì sẽ cho gán plain key → regress lại bug P2 ghost. Push lại |
| 2026-05-31 | CI **Contract Drift FAIL** — gốc do main. `SSLHandshakeError.swift` divergent giữa 2 cây PluginKit (`Packages/TableProCore/.../TableProPluginKit/` vs `Plugins/TableProPluginKit/`): bản `Plugins/` có thêm 3 case `clientKeyPassphraseRequired/Incorrect/Invalid` (superset thuần), không trong baseline. Run push main `1da50cd7` cũng FAIL. Gate trigger trên #1489 vì PR đụng `TablePro/Models/**`. |
| 2026-05-31 | macOS Tests **PASS** trên commit test-fix (watch exit 0). |
| 2026-05-31 | **Rebase #1489 lên main mới nhất** (branch trễ 20 commit). Main đã sửa `KeyboardShortcutModels.swift` + `CHANGELOG` + `keyboard-shortcuts.mdx` (#1490 thêm sidebar keyboard control). Auto-merge sạch; verify `openDocumentation` + `supportsFunctionKeyPrimary` + `ShortcutCategory.help` còn nguyên; compile pass. |
| 2026-05-31 | **Contract Drift fixed trong #1489** (owner quyết "nhét vào PR"): reconcile — copy bản `Plugins/SSLHandshakeError.swift` (superset) sang `Packages/TableProCore/.../SSLHandshakeError.swift` → 2 file identical, divergence biến mất (KHÔNG thêm baseline entry, theo policy "burn down"). Safe: 0 consumer của enum trong package nên thêm case không vỡ exhaustive switch. Commit riêng `fix(plugins): reconcile SSLHandshakeError...`. Drift audit local + CI = **success**. |
| 2026-05-31 | Branch = 2 commit trên main: `feat(keyboard)` + `fix(plugins)`. CI: Contract Drift ✅, CLA ✅, macOS/iOS Tests đang chạy lại. |

## Next

Chờ CI xanh → merge. Recommend merge **trước** #1484 để giảm vòng rebase cho #1484.
