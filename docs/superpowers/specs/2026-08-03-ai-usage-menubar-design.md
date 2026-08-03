# AI Usage Menu Bar — Design Spec

**Date:** 2026-08-03  
**Status:** Approved  
**Platform:** macOS (native SwiftUI)  
**Distribution posture:** Open source, local-only, portfolio-grade

## 1. Problem

Power users of AI coding tools (Cursor, Codex, later Claude and API credits) cannot see remaining subscription limits at a glance. Limits live in buried settings pages, reset on opaque windows (5-hour, weekly), and surprise people mid-session.

This product is a **native macOS menu-bar utility** that binds those subscriptions locally and surfaces remaining quota, window countdowns, usage graphs, and proactive alerts — without a cloud account or telemetry backend.

## 2. Goals and non-goals

### Goals

- Native Mac feel: `MenuBarExtra` + aesthetic glass materials
- Local-only: secrets in Keychain, history in on-disk SQLite; no first-party server
- Reliable-enough subscription visibility for **Cursor** and **Codex** first
- Proactive alerts (notification + optional sound), Focus/DND-aware where the system allows
- Clean provider boundary so unofficial/undocumented integrations can break and be fixed in isolation
- Open-source honesty: document fragility of undocumented APIs

### Non-goals (v1)

- Cross-platform (Windows/Linux)
- Cloud sync, multi-device accounts, or hosted dashboards
- Shipping Claude / OpenAI API / Anthropic API / OpenCode in v1 (roadmap only)
- Acting as a proxy, router, or spend controller for model calls
- Guaranteeing unbroken adapters forever against vendor UI/API changes

## 3. Product surface

### Primary UI: menu bar popover

- Status item glyph encodes aggregate health: OK / warn / critical (worst bound provider)
- Glass popover (macOS materials / liquid-glass aesthetic) shows:
  - Per-provider remaining quota for active windows (5-hour, weekly, others the adapter reports)
  - Window countdown / reset time
  - Compact sparkline or mini chart from local history
  - Bind / refresh / open settings actions
- **No separate main dashboard window** in v1 — depth lives in the popover and a settings sheet

### Settings sheet

- Bind / unbind / re-auth providers
- Alert thresholds (defaults: warn at 80%, critical at 90% of window consumption)
- Toggle notifications, optional sound
- Launch at login
- Adapter health / last successful sync / last error (user-visible, not cryptic)

### Alerts

- Default mode: **proactive** — system notification when crossing warn/critical, optional sound
- Respect Focus / Do Not Disturb to the extent `UserNotifications` and system APIs allow
- Menu bar glyph always updates even when notifications are suppressed
- Alerts are per-window (e.g. Cursor 5-hour vs weekly fired separately) with cooldown so the same threshold does not spam

## 4. Architecture

Single native app process (Approach A): one SwiftUI target, in-process adapters, no helper daemon in v1.

```text
┌──────────────────────────────────────────┐
│ MenuBarExtra + glass popover + settings  │
└────────────────────┬─────────────────────┘
                     │
┌────────────────────▼─────────────────────┐
│ AppCore                                  │
│  RefreshScheduler                        │
│  AlertEngine                             │
│  UsageStore (SQLite)                     │
│  SecretsStore (Keychain)                 │
└────────────────────┬─────────────────────┘
                     │ Provider protocol
           ┌─────────┴─────────┐
           ▼                   ▼
    CursorProvider       CodexProvider
```

### Modules (logical)

| Module | Responsibility |
|--------|----------------|
| `AppUI` | Menu bar, popover, settings, charts presentation |
| `AppCore` | Scheduling, alert policy, orchestration |
| `UsageStore` | Persist snapshots, query history for charts |
| `SecretsStore` | Keychain read/write for tokens/cookies/API material |
| `Providers` | `Provider` protocol + Cursor/Codex implementations |
| `Support` | Logging (local only), time windows, formatting |

Providers may live as folders under `Providers/` with a hard protocol boundary. Split into separate Swift packages only when a third real provider lands (borrow plugin discipline, defer package split).

## 5. Provider protocol

Every integration implements the same surface so UI and alerts never depend on vendor JSON shapes.

```swift
protocol Provider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }

    func authStatus() async -> AuthStatus
    func authenticate(using method: AuthMethod) async throws
    func clearAuth() async throws

    /// Point-in-time usage + limit windows for this account.
    func fetchSnapshot() async throws -> UsageSnapshot

    func healthCheck() async -> ProviderHealth
}
```

### Core model types

- `UsageSnapshot`: provider id, fetched-at, list of `UsageWindow`, optional `ModelBreakdown` entries, raw opaque diagnostics blob (not shown in UI; useful for debug export)
- `UsageWindow`: kind (fiveHour / weekly / monthly / custom), used, limit, unit (requests / tokens / credits / percent), resetsAt
- `ModelBreakdown`: model id/label, usage amount, unit, period
- `AuthMethod`: cases as needed per provider (session token paste, browser cookie import, OAuth-like device flow if discovered) — adapters declare supported methods
- `AuthStatus`: signedOut / signedIn(accountHint) / expired / invalid

### Adapter rules

- Map vendor payloads → `UsageSnapshot` inside the adapter only
- Store only what `SecretsStore` needs to re-auth; never write secrets into SQLite
- Treat undocumented endpoints as unstable: version the parser, fail soft with `ProviderHealth` + user-facing error
- No shared “HTTP client god object” that knows Cursor and Codex URLs; each adapter owns its client
- **Auth UX for Cursor/Codex (v0.2–v0.3):** prefer the least-friction method that works against the live vendor backend at implementation time (session token paste and/or guided cookie/session import from the user’s browser). Exact endpoint URLs and cookie names are discovered during adapter work and documented in-adapter, not hard-coded into AppCore

## 6. Data and privacy

### On device

- **Keychain:** session tokens, cookies, API keys, refresh material
- **SQLite:** usage snapshots over time (for sparklines/history), alert cooldown state, user preferences (non-secret)
- **UserDefaults / AppStorage:** only trivial UI prefs if needed; prefer SQLite for anything chart-related

### Network

- App initiates outbound HTTPS only to endpoints required by bound providers
- No analytics, crash phone-home, or update ping that sends usage data (Sparkle/Homebrew updates are fine if they do not upload provider secrets)

### Open-source disclosure

README and in-app About must state:

- Some integrations use unofficial or undocumented APIs
- They can break without notice when vendors change backends
- Credentials never leave the Mac except to the vendor the user chose to bind

## 7. Refresh and alerts

### RefreshScheduler

- While the menu-bar app is running: poll bound providers on an interval (default 5 minutes) and on popover open (debounced)
- Manual refresh control in the popover
- Back off on repeated failures (e.g. double interval up to a cap); surface last error in settings
- No LaunchAgent daemon in v1 — quitting the app stops polling (document this)

### AlertEngine

- Inputs: latest snapshots + user thresholds + cooldown state
- Emits: notification requests, optional sound, status-item severity
- Thresholds default to **80% warn** and **90% critical** of `used/limit` per window
- Cooldown: do not re-notify the same `(provider, windowKind, thresholdLevel)` until the window resets or the user clears/rebinds, except when severity escalates (warn → critical)

## 8. UI design principles

- One composition in the popover: brand/mark, providers, glance metrics — not a dense dashboard
- Glass materials as the visual identity; avoid generic “AI purple” chrome
- Typography and spacing should feel like a shipping Mac utility (think Stats / Bartender-adjacent craft, not Electron settings)
- Charts via Swift Charts, fed only from `UsageStore` history
- Motion: subtle status transitions and popover appearance — not decorative noise
- Accessibility: VoiceOver labels on status item and primary metrics; Reduce Motion respected

## 9. Error handling

| Failure | Behavior |
|---------|----------|
| Auth expired | Mark provider expired; glyph warn; prompt re-bind in popover/settings; no alert spam |
| Network / timeout | Keep last good snapshot; show stale indicator + age; back off refresh |
| Parse / schema break | `ProviderHealth.brokenParser`; clear user message to update or file issue; do not crash |
| Keychain deny | Block that provider; explain permission needed |
| Partial multi-provider | Show healthy providers normally; isolate errors per row |

## 10. Testing strategy

- **Unit:** window math, alert threshold/cooldown, snapshot merge into store
- **Adapter:** parse fixtures checked into repo (sanitized real-shaped JSON); no CI dependency on live accounts
- **UI:** smoke previews for popover states (empty, bound, warn, critical, stale)
- **Manual:** real Cursor + Codex accounts before notarized releases

Contributors add a provider by implementing `Provider`, adding fixtures, and registering in the provider catalog — documented in contributing notes at v1.0.

## 11. Roadmap

| Phase | Deliverable |
|-------|-------------|
| **v0.1** | App shell: MenuBarExtra, glass popover, settings sheet, Keychain + SQLite wiring, AlertEngine with mock providers |
| **v0.2** | Real **Cursor** adapter (subscription windows + usage) |
| **v0.3** | Real **Codex** adapter |
| **v0.4** | History charts, model breakdown polish, alert tuning |
| **v1.0** | Notarized DMG, Homebrew formula, README, About disclosure, contributor guide for adapters |
| **Post-v1** | Claude → OpenAI API + Anthropic API → OpenCode credits |

## 12. Packaging and repo shape (v1 intent)

- Xcode / SwiftPM app target; **product name chosen at implementation kickoff** (placeholder in docs until then: “AI Usage”)
- GitHub-friendly README: screenshots, install, provider status matrix, unofficial-API warning
- Release artifacts: notarized DMG; Homebrew cask when v1.0 is stable
- **Minimum macOS: 26** (Tahoe-class glass APIs). No back-port of the glass UI to older releases; keep the visual bar high for the portfolio cut

## 13. Success criteria

- From a cold start, a user can bind Cursor and Codex and see live remaining windows in the menu bar within a few minutes
- At 80%/90% consumption, they get a proactive notification (when Focus allows) and a visible glyph change
- Quitting the app leaves no background daemon and no cloud residue
- A stranger cloning the repo understands architecture and how to add a provider from the docs alone
- Portfolio bar: looks and feels like a real Mac product, not a prototype web wrap
