# Headroom menu-bar mark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the running menu-bar text/gauge combination with the existing Headroom app mark while preserving status information for accessibility and startup/error fallback states.

**Architecture:** Keep `MenuBarLabel` responsible for the session-derived accessibility label and make its visible body a compact `NSApplication.shared.applicationIconImage`. Leave `QuotaApp` startup/error branches unchanged. No provider, Gemini, parser, or preference code changes are needed.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XcodeGen, macOS 26.

## Global Constraints

- Target macOS `26.0` and Swift `6.0` as configured in `project.yml`.
- Reuse the existing `AppIcon` asset; add no new image asset or dependency.
- Do not change quota calculations, Gemini authentication, provider icons, or pinned-value persistence.
- Preserve the existing accessibility wording and startup/error fallback behavior.
- Do not modify the unrelated untracked `docs/market-validation-2026-08-05.md` file.

---

### Task 1: Update the running menu-bar label

**Files:**
- Modify: `App/MenuBar/MenuBarLabel.swift`

**Interfaces:**
- Consumes: `AppSession`, `MenuBarStatusFormatter`, and `NSApplication.applicationIconImage`.
- Produces: A compact visible Headroom mark with the existing dynamic accessibility label.

- [ ] **Step 1: Replace the visible HStack body**

Import AppKit and render the application icon at a fixed `18x18` point frame:

```swift
import AppKit
import QuotaCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var session: AppSession

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .accessibilityLabel(accessibilityText)
    }
```

Keep `pinnedStatusText` and `accessibilityText` unchanged so the running
session still exposes severity and pinned quota values to assistive tools.

- [ ] **Step 2: Inspect the diff for accidental behavior changes**

Run:

```bash
git diff -- App/MenuBar/MenuBarLabel.swift
git diff --check
```

Expected: only the AppKit import and visible label body change; the two
computed status properties remain unchanged and `git diff --check` is clean.

- [ ] **Step 3: Commit the implementation**

Run:

```bash
git add App/MenuBar/MenuBarLabel.swift
git commit -m "feat: show Headroom mark in menu bar"
```

Expected: one focused local commit containing only the menu-bar label change.

### Task 2: Rebuild and verify existing Gemini/Icon fixes

**Files:**
- Generated/modified by tooling: `Quota.xcodeproj/` (do not stage if ignored or generated)

**Interfaces:**
- Consumes: `project.yml`, the Swift package, and existing Gemini/icon assets.
- Produces: A generated Xcode project, passing package tests, and a successful Debug app build.

- [ ] **Step 1: Regenerate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: project generation succeeds from the current `project.yml`.

- [ ] **Step 2: Run the complete Swift test suite**

Run:

```bash
swift test
```

Expected: all tests pass, including `GeminiQuotaParserTests` and
`GeminiOAuthClientDiscoveryTests`.

- [ ] **Step 3: Build the macOS application**

Run:

```bash
xcodebuild -scheme Quota -project Quota.xcodeproj -configuration Debug build
```

Expected: the `Quota` target builds successfully with the Gemini and icon
assets included.

- [ ] **Step 4: Inspect final repository state**

Run:

```bash
git status --short --branch
git diff --check
```

Expected: no unexpected source changes, no whitespace errors, and the
unrelated market-validation document remains untouched.
