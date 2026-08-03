# Headroom

Native macOS menu-bar app for glancing at remaining AI subscription capacity (Cursor, ChatGPT/Codex, Copilot, Grok).

**Local-only.** Credentials stay on your Mac (vendor apps / CLI). Usage history stays in on-device SQLite. No Headroom cloud account.

> Some provider integrations use unofficial or undocumented APIs. They can break when vendors change backends. Credentials never leave your Mac except to the vendor you bind.

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
| Cursor | Live — Cursor app (Auto + API) |
| ChatGPT / Codex | Live — `~/.codex/auth.json` (windows from API duration: 5h and/or weekly) |
| GitHub Copilot | Live — `gh api /copilot_internal/user` (AI credits) |
| Grok | Live — `~/.grok/auth.json` via Grok CLI (`grok login`) → SuperGrok weekly pool |
| OpenCode | Live — `~/.local/share/opencode` auth + local SQLite (Go caps when present; Zen spend otherwise) |

## Roadmap (auth + providers)

- Today: local vendor sessions / CLIs (Cursor, ChatGPT/Codex, Copilot, Grok, OpenCode)
- Next: optional **API keys** for all providers as an alternate bind path
- Later: Claude Desktop and more providers

See [design spec](docs/superpowers/specs/2026-08-03-ai-usage-menubar-design.md) and [v0.1 plan](docs/superpowers/plans/2026-08-03-quota-v0.1-app-shell.md).

## Brand

Display name: **Headroom**. Internal module/target remains `Quota` / `QuotaCore` for now (bundle id unchanged so local data stays put).
