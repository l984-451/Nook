# Settings View Redesign: Sidebar Navigation

## Summary

Refactor the Settings view from Safari-style top TabView to macOS 26-style sidebar navigation using `NavigationSplitView`. Replace all checkmarks/ticks with toggles. Extract SponsorBlock and Ad Blocker into standalone sections.

## Window

- Separate settings window opened via Cmd+, (same as current)
- Replace native `Settings { }` + `TabView` with a custom `Window` + `NavigationSplitView`
- Fixed size, not resizable
- Sidebar column uses native `.sidebar` style (Liquid Glass on macOS 26)

## Sidebar Structure

Grouped by visual spacing (no explicit headers), matching macOS 26 System Settings pattern:

| Group | Items | SF Symbol |
|-------|-------|-----------|
| Core | General | gearshape |
| Core | Appearance | paintbrush |
| AI | AI | sparkles |
| Protection | Privacy | lock.shield |
| Protection | Ad Blocker | shield.lefthalf.filled |
| Protection | SponsorBlock | forward.end.alt |
| Customization | Profiles | person.crop.circle |
| Customization | Shortcuts | keyboard |
| Customization | Extensions | puzzlepiece.extension |
| Debug | Advanced | wrench.and.screwdriver |

Each sidebar row: colored rounded-rect icon badge + label. Selected row uses system accent highlight. Groups separated by spacing, not headers.

Extensions row only visible on macOS 15.5+. Advanced row only visible in DEBUG builds.

## Content Pane

- All sections use `Form` with `.formStyle(.grouped)` — picks up Liquid Glass automatically
- Content scrolls within fixed-height pane
- Navigation title set per section

## Content Migration

| Section | Source | Changes |
|---------|--------|---------|
| General | `SettingsGeneralTab` | Remove SponsorBlock section. Keep performance, search, site search. |
| Appearance | `SettingsAppearanceTab` | No content changes. |
| AI | `SettingsAITab` | No content changes. |
| Privacy | `PrivacySettingsView` | Remove Ad Blocker section. Keep cookies, cache, tracking, browsing data. |
| Ad Blocker | New (from `PrivacySettingsView`) | Ad blocker toggle, filter list management, whitelist, update filters. |
| SponsorBlock | New (from `SettingsGeneralTab`) | Enable toggle, auto-skip toggle, category selection with toggles. |
| Profiles | `ProfilesSettingsView` (in SettingsView.swift) | Convert from custom cards to Form+grouped. |
| Shortcuts | `ShortcutsSettingsView` (in SettingsView.swift) | Convert from custom cards to Form+grouped. |
| Extensions | `ExtensionsSettingsView` (in SettingsView.swift) | Convert from custom cards to Form+grouped. |
| Advanced | `AdvancedSettingsView` (in SettingsView.swift) | No content changes. |

## Toggle Conversion

All checkmarks and tick marks become `Toggle` controls:

- Filter list checkboxes in Ad Blocker (currently `.toggleStyle(.checkbox)`) → standard Toggle
- SponsorBlock category checkboxes (currently colored circles with checkmarks) → Toggle with colored label
- Shortcut enable/disable checkboxes → Toggle
- Any `Image(systemName: "checkmark")` used as on/off indicator → Toggle
- "Active" checkmark indicators on models/items remain as-is (these are selection indicators, not toggles)

## Files to Create

| File | Purpose |
|------|---------|
| `Nook/Components/Settings/SettingsWindow.swift` | `NavigationSplitView` container with sidebar and content routing |
| `Nook/Components/Settings/Tabs/AdBlocker.swift` | Ad Blocker settings tab |
| `Nook/Components/Settings/Tabs/SponsorBlock.swift` | SponsorBlock settings tab |

## Files to Modify

| File | Changes |
|------|---------|
| `App/NookApp.swift` | Replace `Settings { SettingsView() }` with `Window` using `SettingsWindow` |
| `Nook/Components/Settings/SettingsUtils.swift` | Add `.adBlocker`, `.sponsorBlock` to `SettingsTabs` enum |
| `Nook/Components/Settings/Tabs/General.swift` | Remove SponsorBlock section |
| `Nook/Components/Settings/PrivacySettingsView.swift` | Remove Ad Blocker section, convert to Form+grouped |
| `Nook/Components/Settings/SettingsView.swift` | Remove `SettingsPane`, `SettingsSectionCard`. Convert Profiles/Shortcuts/Extensions to Form+grouped. May extract into separate tab files. |
| `Settings/NookSettingsService.swift` | Update `SettingsTabs` if the enum lives here |

## Files to Remove

None — `SettingsView.swift` still contains Profiles/Shortcuts/Extensions views. `SettingsSectionCard` and `SettingsPane` become unused but can be cleaned up as part of implementation.

## Implementation Notes

- `NavigationSplitView` requires a binding for selection — reuse `nookSettings.currentSettingsTab`
- Sidebar group spacing achieved with `Section` views or manual padding between items
- Icon badges: overlay SF Symbol on a colored `RoundedRectangle` (similar to System Settings)
- The `Window` scene needs an ID and should be openable via `openWindow(id:)` or `NSApp.sendAction(Selector("showSettingsWindow:"))` — verify Cmd+, still works
- Environment objects must be injected into the new Window scene same as current Settings scene
