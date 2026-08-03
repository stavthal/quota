# Quota

Native macOS menu-bar app for glancing at AI subscription limits (Cursor, Codex, and more on the roadmap).

**Local-only.** Secrets stay in Keychain. Usage history stays in on-device SQLite. No Quota cloud account.

> Some future provider integrations will use unofficial or undocumented APIs. They can break when vendors change backends. Credentials never leave your Mac except to the vendor you bind.

## Requirements

- macOS 26+
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), or any `xcodegen` on `PATH`

## Build

```bash
xcodegen generate
open Quota.xcodeproj
```

Or from the CLI:

```bash
xcodegen generate
xcodebuild -scheme Quota -project Quota.xcodeproj -configuration Debug build
swift test
```

## Status (v0.1)

| Provider | Status |
|----------|--------|
| Cursor | Mock (real adapter next) |
| Codex | Mock (real adapter next) |

See [design spec](docs/superpowers/specs/2026-08-03-ai-usage-menubar-design.md) and [v0.1 plan](docs/superpowers/plans/2026-08-03-quota-v0.1-app-shell.md).
