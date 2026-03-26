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

## Data Model

### SiteRoutingRule

```swift
struct SiteRoutingRule: Codable, Identifiable {
    let id: UUID
    var domain: String           // e.g. "github.com" — stored normalized (no www., no scheme)
    var pathPrefix: String?      // e.g. "/myorg" — optional, for sub-domain routing
    var targetSpaceId: UUID
    var targetProfileId: UUID
    var isEnabled: Bool
}
```

**Storage:** JSON-encoded array in `NookSettingsService` (UserDefaults), consistent with all other app settings.

### Matching Logic

1. Extract the host from the URL, strip `www.` prefix
2. Find all enabled rules where `rule.domain` matches the host
3. Among matches, filter by `pathPrefix` — the URL path must start with the prefix (if set)
4. **Most-specific rule wins** — a rule with a `pathPrefix` beats a domain-only rule for the same domain
5. If no rules match, return nil (no routing)

## Architecture

### SiteRoutingManager

A new `@MainActor` manager class, following the existing manager pattern. Created in `NookApp` and injected as an environment object.

**Dependencies:**
- `NookSettingsService` — reads/writes rules
- `TabManager` — creates tabs, switches spaces/profiles

**Public API:**

```swift
@MainActor
class SiteRoutingManager {
    // Matching
    func resolve(url: URL) -> SiteRoutingRule?

    // Action — returns true if the URL was routed (caller should cancel original navigation)
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
4. If target space is already the current space, return false (no routing needed)
5. Switch to target profile (if different from current)
6. Switch to target space
7. Create a new tab in that space with the URL
8. Return true

## Integration Points

Three lightweight guard clauses inserted into existing navigation code:

### 1. `Tab.decidePolicyFor(navigationAction:)` — In-Browser Navigation

**When:** After existing checks (extension access, content blocker), before returning `.allow`

**Condition:** Navigation type is `.linkActivated` or form submission, AND destination domain differs from current tab's domain

**Action:**
```
if siteRoutingManager.applyRoute(url: url, from: self) {
    decisionHandler(.cancel)
    return
}
```

Same-domain navigations skip the check entirely to avoid re-routing while browsing within a site.

### 2. `AppDelegate.handleIncoming(url:)` — External URLs

**When:** Before routing to `ExternalMiniWindowManager`

**Action:**
```
if siteRoutingManager.applyRoute(url: url, from: nil) {
    return  // skip mini window
}
```

If no rule matches, falls through to existing mini window behavior.

### 3. `Tab.createWebViewWith(...)` — Popups / window.open()

**When:** Before creating a popup tab, after OAuth/peek checks

**Action:**
```
if let url = navigationAction.request.url,
   siteRoutingManager.applyRoute(url: url, from: self) {
    return nil  // no popup webview needed
}
```

If no rule matches, falls through to existing popup/OAuth/peek logic.

## Settings UI

A dedicated **"Air Traffic Control"** page in the sidebar-style Settings window.

### List View

- Table with columns: **Domain**, **Path** (if set), **Target Space**, **Enabled** toggle
- Target space displayed as space icon + name, with profile name in parentheses when multiple profiles exist
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

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Rule's target space was deleted | Rule is skipped, original navigation proceeds normally |
| Rule's target profile was deleted | Rule is skipped |
| Already on the target space | No routing — navigation proceeds in current tab as normal |
| Same-domain navigation | Not checked — only cross-domain triggers routing |
| Multiple rules for same domain | Most-specific (has path prefix) wins |
| URL has no host (e.g. `about:blank`) | Not checked |
| Incognito/ephemeral window | Rules still checked — routes to persistent space if matched |

## Out of Scope

- Reusing existing pinned tabs (route to space only, always new tab)
- Right-click / command palette quick-add (settings pane only for v1)
- Wildcard/regex URL patterns
- Per-rule "open in mini window" option
- Rule import/export
