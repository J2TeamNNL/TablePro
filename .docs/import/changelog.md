# import — changelog

## Timeline

| Date | Event |
|---|---|
| 2026-05-20 05:30 | Issue [#1355](https://github.com/TableProApp/TablePro/issues/1355) opened by datlechin |
| 2026-05-21 05:33 | PR [#1366](https://github.com/TableProApp/TablePro/pull/1366) opened |
| 2026-05-21 05:51 | PR #1366 merged |

## Release

### [v0.43.2] — 2026-05-22

**Fixed**
- Importing from DBeaver no longer leaves the username empty when DBeaver stores
  it in `credentials-config.json` (#1355)

> Lưu ý: trên `CHANGELOG.md` upstream entry chính xác có thể được phrase khác —
> grep `grep -n "1355" CHANGELOG.md` để confirm.

## PR #1462 timeline (open fork)

| Date | Event |
|---|---|
| — | PR #1462 mở (branch `feat/import`), diff +652/-46 |
| 2026-05-29 | Review: CONFLICTING chỉ noise, logic đúng, test cần verify thực chất |
| 2026-05-30 | Verified vs main: vẫn open; supersede note "Merged 2026-05-28". Next: drop noise → rebase → verify test → merge (sau #1459) |

## 2026-05-28 — PR #1462 (behavior; merge status superseded → open)

**Added**
- Dedup dialog when importing connections that match an existing connection. The
  dialog offers three choices: Replace (overwrite metadata, keep existing Keychain
  entry), As Copy (rename with " (Imported)", collision-safe up to " (Imported N)"),
  and Skip.
- Dedup key is `(host, port, database, username)`, matched case-insensitively.
  Redis connections use `redisDatabase` as the database fallback when `database`
  is empty.
- Replace does not overwrite Keychain for foreign-app imports.
- Warning strings for SSH key path, SSL certificate path, and unknown database
  type are now localized. (#1462)

## Related changelog (cùng scope, ngoài 13-list user)

### [v0.44.0] — 2026-05-23

- **Added.** Import connections and passwords from DataGrip, including SSH tunnels
  and SSL settings. (#1374)
- **Fixed.** Importing connections from TablePlus brings over saved passwords
  again, after a recent release looked under the wrong keychain name.
- **Fixed.** Importing an SSH connection from TablePlus no longer fills in a fake
  private key path when no key was selected, and skips empty TLS certificate paths.
- **Fixed.** Importing from DBeaver no longer shows an unnecessary keychain
  permission warning, since DBeaver stores passwords in its own file.
