# Nook Ad Blocker Architecture

## Overview

Nook's ad blocker is a wBlock-style implementation built directly into the browser. It uses the same two core libraries as wBlock (the GPL-3.0 Safari ad blocker):

- **SafariConverterLib** (AdguardTeam, SPM) — parses AdGuard/uBlock filter rules, produces Safari-compatible JSON + advanced rules text
- **AdGuard Scriptlets corelibs** (AdguardTeam, MIT) — 99 production-quality scriptlet implementations bundled as `scriptlets.corelibs.json`

The key difference from wBlock: instead of running as a Safari Content Blocker extension, Nook injects directly into `WKWebView` via `WKUserScript`, giving us per-tab control (whitelisting, OAuth exemption, temporary disable).

## Pipeline

```
Filter Lists (EasyList, uBlock Filters, etc.)
  ↓ FilterListManager downloads, caches, validates
  ↓ loadAllFilterRulesAsLines() → [String]
  ↓
SafariConverterLib.convertArray(advancedBlocking: true)
  │
  ├─ safariRulesJSON ──→ ContentRuleListCompiler
  │                        ↓ + YouTube built-in rules
  │                        ↓ chunk into 30K batches
  │                        ↓ WKContentRuleListStore.compile()
  │                        → [WKContentRuleList]  (network blocking, simple CSS hiding)
  │
  └─ advancedRulesText ─→ AdvancedBlockingEngine
                            ↓ parse scriptlet rules (#%#//scriptlet(), ##+js())
                            ↓ parse CSS injection rules (#$#)
                            ↓ parse extended CSS rules (#?#, :has-text, :upward, etc.)
                            ↓ look up scriptlet function in corelibs JSON
                            ↓ wrap as IIFE with {name, args, engine: "corelibs"} source
                            → [WKUserScript]  (injected at document_start)
```

## Files

```
Nook/Managers/ContentBlockerManager/
├── ContentBlockerManager.swift      — Orchestrator: enable/disable, whitelist, per-tab disable, OAuth exemption
├── ContentRuleListCompiler.swift    — SafariConverterLib → WKContentRuleList compilation with chunking
├── AdvancedBlockingEngine.swift     — advancedRulesText → AdGuard corelibs → WKUserScript generation
├── FilterListManager.swift          — Download, cache, validate filter lists (ETag, conditional GET)
└── Resources/
    ├── scriptlets.corelibs.json     — AdGuard Scriptlets v2.3.0 (99 scriptlets, MIT license)
    └── nook-filters-default.txt     — Bundled fallback filter list
```

## Three Blocking Layers

### 1. Network Blocking (WKContentRuleList)
- Compiled by SafariConverterLib from filter list network rules
- Runs in WebKit's content rule list engine (native, fast)
- Blocks requests, hides elements via `css-display-none`, allows exceptions
- Includes hardcoded YouTube ad endpoint rules

### 2. Scriptlet Injection (WKUserScript, document_start)
- Advanced rules that require JavaScript execution
- Examples: `prevent-fetch` (intercepts `window.fetch`), `json-prune` (modifies JSON responses), `set-constant` (stubs properties)
- Uses AdGuard's corelibs — each scriptlet is a self-contained function that takes `(source, args)`
- Wrapped as IIFE: function definition + source object + invocation
- Domain-specific scripts injected in main frame; generic scripts injected in all frames

### 3. CSS/Extended CSS Injection (WKUserScript, document_start)
- CSS injection rules (`#$#`) — arbitrary CSS added via `<style>` element
- Extended CSS (`:has-text()`, `:upward()`, `:remove()`, etc.) — MutationObserver-based runtime
- Cosmetic hiding for domain-specific selectors

## Filter Lists

### Default (always enabled)
- EasyList, EasyPrivacy, Peter Lowe's
- uBlock Filters, Unbreak, Privacy, Badware, Quick Fixes
- Nook Filters (custom)
- URLhaus (malware)

### Optional (user-selectable)
- AdGuard: Base, Annoyances, Mobile Ads, Tracking Protection
- Fanboy's: Annoyance, Social, Cookie
- EasyList Cookie
- Regional: Chinese, Japanese, French, German, Russian, Spanish/Portuguese, Turkish, Indian, Korean

## Key Scriptlets for YouTube/Facebook

| Scriptlet | Purpose | Why it matters |
|-----------|---------|----------------|
| `prevent-fetch` | Intercepts `window.fetch` calls matching patterns | YouTube uses fetch for ad payloads; AdGuard's version preserves `Request.prototype.clone` before YouTube can overwrite it |
| `json-prune` | Removes properties from JSON responses | Strips `adPlacements` from YouTube player responses |
| `set-constant` | Stubs JavaScript properties to fixed values | Disables ad-related flags and handlers |
| `abort-on-property-read` | Throws when specific properties are accessed | Prevents ad detection scripts from running |
| `no-xhr-if` | Blocks XMLHttpRequest calls matching patterns | Blocks ad-related API calls |

## Exception Handling

- **Domain whitelist** — persisted in `NookSettingsService.adBlockerWhitelist`
- **Temporary disable** — per-tab, time-limited, auto-restores
- **OAuth exemption** — `tab.isOAuthFlow` bypasses all blocking
- **Exception rules** — filter list `@@` rules and `#@#`/`#@#+js()` exceptions

## Updating

- **Corelibs**: Update `scriptlets.corelibs.json` by running `npm install && npm run build` in the [AdGuard Scriptlets repo](https://github.com/AdguardTeam/Scriptlets) and copying `dist/scriptlets.corelibs.json`
- **SafariConverterLib**: Update version in Xcode SPM dependencies
- **Filter lists**: Auto-updated every 24 hours via conditional GET (ETag/If-Modified-Since)

## History

Originally used 97 hand-written JavaScript scriptlet templates with a custom `FilterListParser` and `ScriptletEngine`. Replaced in March 2026 with the wBlock approach (SafariConverterLib + AdGuard Scriptlets corelibs) to fix YouTube anti-adblock bypass issues — our hand-written `prevent-fetch` couldn't handle YouTube overwriting `window.fetch` after proxy installation.
