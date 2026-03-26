# Air Traffic Control — Design Spec

**Date:** 2026-03-26
**Status:** Draft

## Overview

Air Traffic Control (ATC) automatically routes URLs to the correct space based on user-defined rules. When a navigation occurs — whether from clicking a link, opening a URL from an external app, or a popup — the system checks the destination URL against routing rules and opens it in the designated space and profile.

Inspired by Arc browser's feature of the same name.

## Behavior Summary

- Rules map a **domain** (with optional **path prefix**) to a **target space + profile**
- When a rule matches, a **new tab** opens in the target space (the source tab stays put)
- Cross-profile routing is supported — rules can route to spaces in any profile
- Same-domain navigations within a tab are **not** checked (only cross-domain triggers routing)
- External URLs that match a rule bypass the mini window and go directly to the target space
- If a rule's target space or profile has been deleted, the rule is silently skipped
- Routing is **disabled in incognito/ephemeral windows** to preserve privacy intent
- Subdomain matching is **exact** — `github.com` does not match `gist.github.com` and vice versa

## Data Model

### SiteRoutingRule

```swift
struct SiteRoutingRule: Codable, Identifiable {
    let id: UUID
    var domain: String           // e.g. "github.com" — stored normalized (no www., no scheme)
    var pathPrefix: String?      // e.g. "/myorg" — optional, for path-based routing
    var targetSpaceId: UUID
    var targetProfileId: UUID
    var isEnabled: Bool
}
```

**Storage:** JSON-encoded array in `NookSettingsService` (UserDefaults), consistent with all other app settings. All future fields added to this struct must be `Optional` or provide decoder defaults for forward compatibility.

### Matching Logic

1. Extract the host from the URL, strip `www.` prefix
2. Find all enabled rules where `rule.domain` **exactly matches** the normalized host (no subdomain suffix matching — `github.com` does not match `gist.github.com`)
3. Among matches, filter by `pathPrefix` — the URL path must start with the prefix (if set)
4. **Most-specific rule wins** — a rule with a `pathPrefix` beats a domain-only rule for the same domain
5. If no rules match, return nil (no routing)

## Architecture

### SiteRoutingManager

A new `@MainActor` manager class, following the existing manager pattern. Created in `NookApp` and injected as an environment object. Also stored as a property on `BrowserManager` so that `Tab` (a plain `NSObject`, not a SwiftUI view) can access it via `browserManager?.siteRoutingManager`.

**Dependencies:**
- `NookSettingsService` — reads/writes rules
- `TabManager` — creates tabs, switches spaces
- `BrowserManager` — switches profiles, provides window state

**Public API:**

```swift
@MainActor
class SiteRoutingManager {
    // Matching (pure, synchronous)
    func resolve(url: URL) -> SiteRoutingRule?

    // Action — returns true if a matching rule was found and routing was scheduled.
    // Caller should cancel the original navigation immediately.
    // The actual profile switch, space switch, and tab creation happen asynchronously in a Task.
    func applyRoute(url: URL, from sourceTab: Tab?) -> Bool

    // CRUD
    func addRule(_ rule: SiteRoutingRule)
    func updateRule(_ rule: SiteRoutingRule)
    func deleteRule(id: UUID)
    func rules() -> [SiteRoutingRule]
}
```

**`applyRoute` flow:**

1. Call `resolve(url:)` — if nil, return false
2. Look up target space and profile by IDs from the matched rule
3. If target space/profile no longer exists, return false (skip stale rule)
4. If source tab is in an ephemeral/incognito window, return false (preserve privacy)
5. If target space is already the current space, return false — navigation proceeds normally in the source tab (no new tab created, no routing)
6. Log the route match via `OSLog` (`Logger(subsystem: "com.baingurley.nook", category: "SiteRouting")`)
7. Return true immediately (caller cancels original navigation)
8. In a `Task`: switch to target profile (if different, `await` the async profile switch), switch to target space, create a new tab with the URL

The synchronous return of `true` + async execution via `Task` allows callers in `decidePolicyFor` to call `decisionHandler(.cancel)` without waiting for the profile switch to complete.

### Multi-Window Behavior

Routing always targets the **key window** (the frontmost active window). Specifically:

- **In-browser navigation** (`decidePolicyFor`): The route applies to the window containing the source tab. That window switches profile/space and gets the new tab.
- **External URLs** (`handleIncoming`): The route applies to the key window (via `NSApp.keyWindow` / `WindowRegistry.activeWindowState`). If no window is open, one is created.
- **Popups** (`createWebViewWith`): Same as in-browser — the source tab's window receives the route.

v1 does not search other windows to find one already showing the target space. The active/source window always switches.

## Integration Points

Three lightweight guard clauses inserted into existing navigation code:

### 1. `Tab.decidePolicyFor(navigationAction:)` — In-Browser Navigation

**When:** After existing checks (extension access, content blocker), before returning `.allow`

**Condition:** Navigation is cross-domain (destination host differs from current tab's host). Checked for all navigation types — link clicks, form submissions, typed URLs, and server-side redirects — since the domain comparison itself is the meaningful filter.

**Action:**
```swift
if let url = navigationAction.request.url,
   browserManager?.siteRoutingManager.applyRoute(url: url, from: self) == true {
    decisionHandler(.cancel)
    return
}
```

Same-domain navigations skip the check to avoid re-routing while browsing within a site.

### 2. `AppDelegate.handleIncoming(url:)` — External URLs

**When:** Before routing to `ExternalMiniWindowManager`

**Action:**
```swift
if siteRoutingManager.applyRoute(url: url, from: nil) {
    return  // skip mini window
}
```

If no rule matches, falls through to existing mini window behavior.

### 3. `Tab.createWebViewWith(...)` — Popups / window.open()

**When:** Before creating a popup tab, after OAuth/peek checks

**Action:**
```swift
if let url = navigationAction.request.url,
   browserManager?.siteRoutingManager.applyRoute(url: url, from: self) == true {
    return nil  // no popup webview needed
}
```

If no rule matches, falls through to existing popup/OAuth/peek logic.

## Settings UI

A dedicated **"Air Traffic Control"** page in the sidebar-style Settings window. Added as a new case in the settings tab enum (e.g. `.airTrafficControl`), with icon `arrow.triangle.branch`.

### List View

- Table with columns: **Domain**, **Path** (if set), **Target Space**, **Enabled** toggle
- Target space displayed as space icon + name, with profile name in parentheses when multiple profiles exist
- Spaces with nil `profileId` shown under an "Unassigned" group in pickers, or hidden if no tabs use them
- **Add (+)** and **Remove (-)** buttons at the bottom of the list

### Add/Edit Sheet

- **Domain** text field — required. Auto-strips `https://`, `http://`, `www.`, and trailing slashes on save
- **Path prefix** text field — optional. e.g. `/myorg`
- **Target space** picker — grouped by profile
- **Enabled** toggle
- Save / Cancel buttons

### Validation

- Domain is required — show inline error if empty
- Warn on duplicate domain + path prefix combination
- No rule ordering UI — specificity-based matching makes order irrelevant

## Observability

All route matches and routing actions are logged via `OSLog`:

```swift
private let logger = Logger(subsystem: "com.baingurley.nook", category: "SiteRouting")
```

- `logger.info("Route matched: \(url) → space '\(space.name)' via rule \(rule.id)")` on successful route
- `logger.debug("Route skipped: target space \(rule.targetSpaceId) no longer exists")` on stale rules
- Helps users debug "why did my link open over there?" via Console.app

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Rule's target space was deleted | Rule is skipped, original navigation proceeds normally |
| Rule's target profile was deleted | Rule is skipped |
| Already on the target space | No routing — navigation proceeds in source tab as normal |
| Same-domain navigation | Not checked — only cross-domain triggers routing |
| Multiple rules for same domain | Most-specific (has path prefix) wins |
| URL has no host (e.g. `about:blank`) | Not checked |
| Incognito/ephemeral window | Routing disabled — rules are not checked, navigation proceeds normally |
| Subdomains (e.g. `gist.github.com` vs `github.com`) | Exact match only — these are treated as separate domains |
| Server-side redirect crosses domains | Checked — the redirect's destination URL is evaluated against rules |
| Multiple windows open | Route targets the source tab's window (in-browser) or key window (external URLs) |
| Spaces with nil profileId | Shown under "Unassigned" group in settings picker |

## Out of Scope

- Reusing existing pinned tabs (route to space only, always new tab)
- Right-click / command palette quick-add (settings pane only for v1)
- Wildcard/regex URL patterns
- Per-rule "open in mini window" option
- Rule import/export
- Searching other windows for one already showing the target space
