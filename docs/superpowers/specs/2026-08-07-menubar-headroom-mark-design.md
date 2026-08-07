# Headroom menu-bar mark design

## Goal

Replace the normal menu-bar status text with the existing Headroom app mark so
the menu bar shows a compact icon instead of quota text. Preserve the current
status information through accessibility text and keep startup/error states
readable.

## Current state

`App/QuotaApp.swift` renders `MenuBarLabel` after the session starts. That view
currently combines a severity-dependent SF Symbol with optional pinned quota
text. The app already ships `AppIcon` assets and recent Gemini/provider icon
fixes are present on `main`.

## Design

- Add a dedicated menu-bar mark view that loads the existing `AppIcon` asset.
- Render the mark at menu-bar scale with a fixed compact frame and preserve its
  aspect ratio.
- Keep `MenuBarLabel` as the source of the dynamic accessibility label,
  including aggregate severity and pinned values.
- Use the mark-only label for a running session.
- Keep the existing SF Symbol fallback for the starting state and use the same
  existing textual error content when startup fails.
- Do not change provider icons, Gemini authentication, quota parsing, or the
  pinned-value preferences model.

## Verification

- Generate the Xcode project from `project.yml`.
- Run the Swift package test suite, including Gemini parser/auth-discovery
  tests.
- Build the macOS `Quota` target in Debug configuration.
- Inspect the final diff and confirm the unrelated market-validation file is
  not modified.

## Non-goals

- No new image asset or dependency.
- No change to quota calculations or provider behavior.
- No change to accessibility wording beyond keeping it attached to the icon.
