# Adding a Usage Provider

Headroom reports **subscription capacity** from the provider a person already
uses. It is not an AI gateway and must not proxy, mint, copy, or share provider
credentials.

## Admission criteria

Do not start implementation until every required item is answered with evidence.

| Requirement | Required evidence | Reject or defer when |
| --- | --- | --- |
| Supported product | The exact vendor product and plan whose usage is measured. | The feature mixes API billing with subscription limits, or cannot distinguish them. |
| Authorized usage source | A vendor-documented API/CLI output, or written vendor permission for the integration. | It requires reverse engineering a private endpoint, impersonating another client, or bypassing an OAuth/app boundary. |
| Local credential boundary | A local, read-only source that Headroom can access without exporting, copying, or persisting a secret. | It requires scraping a browser profile, weakening Keychain ACLs, reading another app's protected credential, or embedding a client secret. |
| Stable quota contract | A representative response plus documented fields for utilization and reset time. | Only a UI string is available, the response has no reset semantics, or the schema is guessed. |
| Failure semantics | Expected behavior for signed out, expired, forbidden, throttled, malformed, and network-failure responses. | A failure could be shown as zero usage, stale usage, or a successful connection. |
| Test material | Sanitized fixtures for every supported plan/window and each error class. | Tests need a real account/token or cannot detect schema drift. |
| UX integration | Provider name, icon licensing, help text, enable/disable persistence, settings ordering, and menu-bar behavior are defined. | The provider works only in the core module or exposes an unsupported setup as "connected." |
| Maintenance owner | Source URL, verification date, compatibility level, and a kill switch/removal plan are recorded. | No one can revalidate the integration after a CLI/vendor change. |

A **Supported** adapter may be implemented only after the first six rows pass.
If the source is not public and documented, it additionally needs explicit
vendor permission; local-only operation is not a substitute for authorization.
The only exception is a clearly marked **Guarded** experimental adapter: it may
be opt-in for local development while authorization is being resolved, but it
must never be advertised as live or relied on for release readiness.

## Implementation contract

1. Add the provider identifier, display name, icon mapping, and preferences
   migration. Unknown stored identifiers must be ignored safely.
2. Create a provider directory with a narrow credential reader, a DTO/parser,
   the `Provider` implementation, typed errors, and sanitized fixtures.
3. Write parser tests first. Cover each quota window, missing optional windows,
   malformed payloads, and reset-time parsing. Run the test once before the
   parser exists (red), then after implementation (green).
4. Make authentication read-only. `authenticate(.localApp)` may validate a
   local vendor session; it must never launch a login flow, mutate the vendor
   client, or store a bearer token in Headroom's Keychain.
5. Fetch only the usage data necessary for the snapshot. Use timeouts, map
   401/403 to actionable re-authentication errors, and never silently fall
   back to fabricated limits or resets.
6. Register the provider in `AppSession.makeDefault()`, update settings copy,
   README support status, and icon assets. Preserve existing user edits when
   integrating into files that are already dirty.
7. Verify the focused parser tests, all `swift test`, and the Debug Xcode
   build. A real-account check is separate evidence and must never print a
   credential or raw response.

## Compatibility levels

- **Supported** — vendor-documented public contract, with fixtures and a live
  non-secret smoke check.
- **Guarded** — vendor-owned local CLI exposes the data, but the endpoint or
  output is not a public third-party contract. It is disabled by default,
  explicitly marked experimental, fails closed on change, and is revalidated
  on every CLI update. It is not a release-ready provider without permission.
- **Deferred** — an authorized source exists but lacks quota/reset fields or
  testability. Do not add it to the UI yet.
- **Rejected** — requires secret extraction, client impersonation, or a
  potentially prohibited OAuth flow.

## Gemini / Antigravity: why it was removed

The previous Gemini adapter is a rejected pattern, not a template:

- It read OAuth material from Antigravity local state and attempted refreshes.
- It extracted an OAuth client secret from the installed `agy` binary.
- It called `v1internal` Cloud Code Assist endpoints rather than a documented
  Headroom-facing usage API.

Those choices fail the authorized-source and credential-boundary criteria even
if they work on a particular machine. Gemini can return only after Google
provides a documented, third-party-safe quota API or explicit written approval
for this exact local-only integration. A normal Gemini API key is not an
alternative: API billing/quotas are not a person's Gemini subscription
capacity.

## Claude Code decision record

Claude Code supports Claude App Pro/Max subscriptions and securely stores its
credentials. Its installed CLI currently contains a usage call for its own
subscription flow, but Anthropic's public Claude Code documentation does not
publish that call as a third-party integration API.

Headroom therefore treats Claude Code as **Guarded** until Anthropic documents
or explicitly approves this use. The adapter reads only Claude Code's non-secret
local `cachedUsageUtilization` record in `~/.claude.json`; it must not read the
Claude Code Keychain item, scrape browser data, extract credentials, make a
provider request, or invoke Claude with a prompt to infer usage. If no compatible
local usage cache exists, the provider stays signed out and explains how to
connect rather than guessing.

Before release, confirm the installed Claude Code version, cache schema fixture,
and one manual smoke check. Remove or disable the adapter immediately if the
compatibility check fails.

## Provider intake record

Copy this into the pull request or issue for every new provider:

```md
Provider / plan:
Compatibility level:
Vendor documentation or written permission:
Credential source (read-only, no secret copy):
Usage endpoint or CLI command:
Windows and reset semantics:
Fixture source and redactions:
Error mapping:
Last verified vendor/CLI version and date:
Kill switch / removal owner:
```
