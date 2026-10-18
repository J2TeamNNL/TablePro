---
paths:
  - "apple/Native/**/*"
  - "apple/Plugins/DamengDriverPlugin/**/*"
  - "apple/Plugins/HanaDriverPlugin/**/*"
  - "apple/scripts/build-dameng.sh"
  - "apple/scripts/build-hana.sh"
---

# Native bridges

- **First-party bridge code lives in `apple/Native/<X>Bridge`**, built by `apple/scripts/build-<x>.sh`, with output in a gitignored folder beside the source, never in `apple/Libs/`.
- **Rust may run in the app process; Go may not.** The Dameng staticlib is built with `panic = "unwind"`, and every export that does driver work wraps it in `catch_unwind`; a new export that does work takes the same guard. Go's `recover()` cannot catch a panic on a goroutine go-hdb starts, so HANA runs out of process as `tablepro-hana-helper`, one per driver session.
- **Toolchains and upstream code are pinned**: `rust-toolchain.toml`, `Cargo.lock` with `--locked`, the `toolchain` line of `go.mod`, `go.sum`. A protocol change for Dameng lands on the [TableProApp/rust-dameng](https://github.com/TableProApp/rust-dameng) fork first, then the pinned `rev` moves.
- **Every nested Mach-O is signed with Developer ID, the hardened runtime and a timestamp** before the main binary. The `HanaHelperEmbedding` copy phase in `apple/project.yml` signs the HANA helper with the plugin's identity; the plugins' notary submission rejects any executable signed otherwise, and `apple/scripts/release/notarize.sh` prints the log.
