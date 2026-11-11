# PRD - Hush Dashboard and Settings Redesign

**Status:** Draft for design approval  
**Date:** 2026-07-31  
**Platform:** macOS 15+  
**Scope:** New Hush activity dashboard, dictation history, and complete Settings redesign

## 1. Product summary

Turn the current Settings window into the Hush control center: an immersive macOS window with a valuable activity dashboard, private dictation history, persistent sidebar, and focused settings pages.

The new interface should feel native to macOS, unmistakably Hush, excellent in light and dark appearance, and calm even when it presents complex features such as transcription models and local AI personas.

This is an information architecture and interaction redesign, not only a visual reskin. Every existing setting remains available, but controls are regrouped around user goals and given enough space to explain status, consequences, and next actions. The new Dashboard gives users a reason to return by showing how much they dictated, how much time they saved, where Hush helped, and the text they may need again.

## 2. Why this redesign is needed

The current Settings window is a 600 pt wide scrolling document containing:

- Hotkey and recording mode
- Language and decoding quality
- Transcription model selection
- Paste and clipboard behavior
- HUD behavior
- AI provider selection
- Persona management
- Permissions

This layout was effective when Hush had few settings. It now creates four problems:

1. Important controls compete in one long hierarchy.
2. Users must remember where a setting lives and scroll to find it.
3. Complex model and persona workflows are compressed into cards and popovers.
4. The window is forced to light appearance, so it does not feel integrated with a dark macOS environment.

It also leaves customer value invisible. Hush completes work and disappears, but users cannot see their accumulated output, understand the time they saved, recover a recent dictation, or confirm which apps and persona are benefiting from Hush.

## 3. Reference analysis

The supplied reference succeeds because of its structure, not because of any single color or icon.

### 3.1 Patterns to adopt

- Full-height sidebar that begins beneath the traffic lights and remains visible.
- Unified titlebar and content surface with no detached toolbar chrome.
- Search at the top of the sidebar.
- Icon-led navigation with a clear selected state.
- One focused subject per detail page.
- Large content canvas with generous outer padding.
- Rounded, low-contrast cards for related information.
- Strong left labels and right-aligned values or controls.
- Thin separators inside cards instead of repeated floating boxes.
- Status is visible inline through concise text, dots, switches, and progress.
- Native macOS density: compact enough to scan, spacious enough to feel intentional.

### 3.2 Patterns not to copy literally

- Provider-specific language or branding.
- Bright blue as the dominant identity color.
- Usage and billing concepts that do not exist in Hush.
- Disabled navigation items that lead nowhere.
- Decorative complexity without a Hush workflow behind it.

## 4. Goals

### 4.1 Primary goals

- Make any setting reachable within one navigation action and one local interaction.
- Give transcription models and AI personas dedicated, understandable spaces.
- Make system and model readiness obvious without technical interpretation.
- Support light and dark appearance with equal visual quality.
- Preserve the privacy-first, local-first character of Hush.
- Use native macOS behaviors for keyboard navigation, focus, scrolling, popovers, sheets, and accessibility.
- Scale cleanly as future settings are added.
- Make Hush's accumulated value visible through useful local activity insights.
- Let users recover, search, and copy their own recent Hush output.

### 4.2 Success criteria

- A new user can configure a hotkey, select a model, and verify permissions without scrolling through unrelated settings.
- A user can understand whether AI is off, unavailable, downloading, ready, or active from the Personas page.
- Persona Off in the menu panel opens Settings directly on the Personas page with Enable AI visible and focused.
- Permissions in the menu panel opens Settings directly on the Permissions page.
- No content is clipped at 1280 x 800 display resolution.
- Light and dark mode pass the same visual and contrast review.
- Existing stored settings and models require no migration.
- A returning user can understand today's Hush activity in under five seconds.
- A user can recover and copy a missed dictation without leaving Hush.
- Activity and history remain entirely local and can be disabled or cleared.

## 5. Non-goals

- Adding accounts, cloud sync, billing, or telemetry.
- Reading or storing the system-wide clipboard history.
- Tracking text, apps, documents, or typing that did not originate from Hush.
- Changing transcription, insertion, model, or AI runtime behavior.
- Adding settings only to make a page appear fuller.
- Rebuilding onboarding in this project.
- Copying the reference application pixel for pixel.
- Replacing native macOS controls when the native control already solves the interaction well.

## 6. Product principles

### 6.1 Quiet confidence

The interface should communicate state without shouting. Color is reserved for selection, success, progress, warnings, and destructive actions.

### 6.2 Progressive disclosure

Show the current choice and state first. Reveal model catalogs, persona editing, and explanations when the user enters the relevant page.

### 6.3 One page, one job

Each sidebar destination answers one coherent user question. Avoid reproducing the old long form inside every page.

### 6.4 Explain consequences next to actions

Download size, privacy, permission needs, and behavioral impact belong beside the control that causes them.

### 6.5 Native first, branded with restraint

Use AppKit conventions, system typography, system materials, semantic colors, and SF Symbols. Apply the Hush violet-blue aurora only where it carries meaning.

### 6.6 Data before copy

Dashboard hierarchy comes from numbers, labels, status, and grouping. Do not use lifestyle headlines, motivational messages, streaks, badges, celebrations, or vague productivity claims. Supporting copy appears only when it explains calculation, privacy, state, or the next action.

## 7. Information architecture

The sidebar uses two product destinations followed by a labeled Settings group.

| Destination | Icon | User question | Existing functionality |
|---|---|---|---|
| Dashboard | `chart.bar.xaxis` | How much value has Hush created for me? | New local activity metrics, app destinations, recents, AI status |
| History | `clock.arrow.circlepath` | What did I dictate and how can I reuse it? | Expands the current three-item recent store into private searchable history |
| **Settings** |  |  | Sidebar group label, not selectable |
| General | `gearshape.fill` | How do I trigger Hush and what happens after dictation? | Hotkey, mode, language, quality, auto-paste, restore clipboard |
| Transcription | `waveform` | Which speech model is active and installed? | Current model, model catalog, download, delete, refresh |
| Personas | `sparkles` | Is AI enabled and how should it rewrite my words? | AI enable, providers, downloads, active persona, editor, Try It |
| HUD & Menu | `menubar.rectangle` | How does Hush appear while I use it? | Show HUD, HUD position, and live state preview |
| Permissions | `hand.raised.fill` | Can Hush listen and paste correctly? | Microphone and Accessibility status and actions |
| About | `info.circle.fill` | What is this build and how does Hush protect my data? | App identity, version, privacy summary, local storage information |

Dashboard is selected when the Hush control center is opened normally. The `Settings...` menu action opens General directly. Later generic openings restore the last visited destination if the user has explicitly navigated away from Dashboard.

## 8. Window anatomy

```text
┌──────────────────────────────────────────────────────────────────────┐
│ traffic lights       sidebar                     centered page title │
├──────────────────────┬───────────────────────────────────────────────┤
│ Search Hush          │                                               │
│                      │       page content, max width 760 pt           │
│ Dashboard            │                                               │
│ History              │       ┌───────────────────────────────┐       │
│                      │       │ product or settings card      │       │
│ SETTINGS             │       │ label                 control │       │
│ General              │                                               │
│ Transcription        │       ┌───────────────────────────────┐       │
│ Personas             │       │ grouped settings card         │       │
│ HUD & Menu           │       │ label                 control │       │
│ Permissions          │       │ label                   value │       │
│ About                │       └───────────────────────────────┘       │
│                      │                                               │
│ Hush status footer   │       additional page-specific content        │
└──────────────────────┴───────────────────────────────────────────────┘
```

### 8.1 Window metrics

- Default content size: 1040 x 720 pt.
- Minimum content size: 820 x 560 pt.
- Sidebar width: 236 pt default, 210 pt minimum.
- Detail content maximum width: 760 pt.
- Detail outer padding: 32 pt horizontal, 28 pt vertical.
- Card corner radius: 12 pt.
- Page section gap: 24 pt.
- Card row minimum height: 54 pt.
- Window is resizable.
- The sidebar never overlays detail content.

### 8.2 Window chrome

- Use a unified, full-size content titlebar.
- Sidebar extends under the titlebar and traffic lights.
- The titlebar displays the selected page title, centered like the reference.
- No permanent toolbar buttons unless a page has a clear page-level action.
- Do not force `.aqua`; inherit the system appearance.
- Keep standard close, minimize, zoom, drag, resize, and restoration behavior.

## 9. Sidebar specification

### 9.1 Search

- Placeholder: `Search Hush`.
- Search indexes page names, row titles, common synonyms, and descriptive text.
- Results remain in the sidebar and show destination plus matching setting.
- Selecting a result opens its page, scrolls the matched card into view, and briefly highlights the matched row.
- Dictation text is searched only inside History, where the user clearly expects content search.
- Escape clears search. Command-F focuses search.

### 9.2 Navigation rows

- Row height: 40 pt.
- Horizontal inset: 12 pt.
- Icon tile: 24 x 24 pt with 7 pt radius.
- Label: 13 pt system semibold.
- Selection: Hush brand tint with clear keyboard focus treatment.
- Hover: subtle semantic fill, never a border.
- Each row exposes a descriptive accessibility label.
- Up and Down arrows move selection. Return activates.

### 9.3 Status footer

The bottom of the sidebar may show one compact Hush readiness line:

- Green dot + `Ready`
- Blue dot + `Loading model 64%`
- Red dot + `Permission needed`

Clicking a problem state opens the page where it can be fixed.

## 10. Detail page specifications

## 10.1 Dashboard

Purpose: present Hush activity, system state, and recoverable output clearly without turning a private utility into an analytics product.

The Dashboard is the default product destination. It should feel like a precise, calm instrument panel.

### Dashboard composition

```text
┌─────────────────────────────────────────────────────────────────┐
│ Dashboard                                  Today  7D  30D  All  │
├────────────────┬────────────────┬───────────────────────────────┤
│ 2,486 words    │ 18 min spoken  │ 56 min estimated time saved   │
│ 14 dictations  │                │ Based on 40 WPM typing         │
├─────────────────────────────────┬───────────────────────────────┤
│ Activity                        │ On this Mac                   │
│ small daily words chart         │ Whisper Small · Ready         │
│                                 │ Persona AI · Off              │
├─────────────────────────────────┴───────────────────────────────┤
│ Where Hush helped                                             │
│ Slack 42%      Mail 31%      Notes 18%      Other 9%           │
├─────────────────────────────────────────────────────────────────┤
│ Recent dictations                                  View all ->  │
│ Text preview...                         Slack   2 minutes ago   │
│ Text preview...                         Mail    18 minutes ago  │
└─────────────────────────────────────────────────────────────────┘
```

### Time range

- Segmented control: Today, 7 days, 30 days, All time.
- The selected range updates metrics, activity trend, app destinations, and comparison copy together.
- Range selection persists across launches.
- If there is insufficient prior-period data, omit comparisons rather than showing meaningless percentages.

### Value metric cards

Show four primary values:

1. Words transcribed.
2. Dictation time, displayed as minutes or hours.
3. Estimated time saved.
4. Dictations completed.

Use equal visual weight for the four primary metrics. Estimated time saved includes a small `Based on 40 WPM typing` explanation so its meaning is never ambiguous.

### Time-saved calculation

Time saved must be transparent and based on actual Hush sessions:

```text
estimated typing time = final word count / 40 words per minute
estimated time saved  = max(estimated typing time - recorded speech duration, 0)
speed multiplier      = estimated typing time / recorded speech duration
```

- Use 40 WPM as a clearly disclosed default typing baseline.
- Label the value `Estimated time saved`, never as an exact claim.
- A tooltip explains the calculation.
- Do not hard-code `4x faster` as a universal claim.
- The speed multiplier may appear as a factual secondary value such as `3.9x`, with no celebratory language.
- Future personalization of typing speed is allowed, but not required for this release.

### Activity trend card

- Compact daily bar chart showing words transcribed.
- Hover reveals date, words, dictations, and speech duration.
- Missing days render as zero, not as missing data.
- Use Hush violet for activity bars and semantic secondary fills for the remainder.
- Respect Reduce Motion and Increase Contrast.

### On this Mac card

Show the exact processing components currently used by Hush. This is operational status, not marketing.

Transcription row:

- Active transcription model display name.
- Source: Bundled or Downloaded.
- State: Loading, Ready, Failed, or Not installed.
- Local indicator: `On this Mac`.
- Clicking the row opens Transcription.

Persona row:

- Off: `AI personas are off` with `Enable`.
- Setup needed: selected engine plus `Finish setup`.
- Downloading: engine, progress, and percentage.
- Ready: active persona, active engine, `On this Mac`, and `Manage`.
- Error: concise explanation and `Review`.

Storage row:

- Total local disk space used by downloaded transcription and persona models.
- `Manage models` deep-links to Transcription.

Footer status:

- `Audio and text processing are local on this Mac.` when every active component is verified local.
- The sentence must be derived from the active runtime configuration, not hard-coded.
- If a future non-local provider is introduced, show the actual processing location per row and remove the all-local summary.

Persona actions deep-link to Personas and never toggle AI silently.

### Where Hush helped

- Aggregate destinations by application display name and bundle identifier.
- Show the top four applications using simple horizontal share bars.
- Display app name, dictation count, and percentage of selected-range dictations.
- Use application icons only when they can be resolved locally and safely.
- Do not store window titles, document titles, URLs, recipients, or workspace names.
- Clipboard-only outcomes are grouped as `Clipboard`.

### Recent dictations

- Show the five newest stored Hush dictations.
- Each row contains a two-line text preview, destination, timestamp, Copy action, and overflow menu.
- Clicking the text opens its History detail rather than copying unexpectedly.
- Copy gives immediate `Copied` feedback without changing the row layout.
- `View all` opens History.
- Empty state: `Your recent dictations will appear here.`

### Dashboard writing rules

- Page title: `Dashboard`.
- Metric labels: `Words`, `Speech time`, `Estimated time saved`, `Dictations`.
- Section labels: `Activity`, `On this Mac`, `Destinations`, `Recent dictations`.
- Status labels use direct facts: `Ready`, `Loading 64%`, `Not installed`, `AI off`.
- Avoid copy such as `Your voice, at a glance`, `You are on fire`, `Productivity boost`, or `You crushed it`.
- Avoid decorative percentages unless a prior-period comparison is statistically and contextually meaningful.
- Privacy appears where relevant as `Stored locally` or `On this Mac`, not as repeated marketing copy.

## 10.2 History

Purpose: provide a reliable private recovery surface for text created by Hush.

Call this `Dictation History`, not `Clipboard History`. Hush records only text it produced. It never monitors the general macOS clipboard.

### History toolbar

- Search field for final text and destination app name.
- Filter menu: All apps or a specific locally observed destination.
- Date filter: Today, 7 days, 30 days, All.
- Sort: Newest first by default, Oldest first optional.

### History list

- Group rows by Today, Yesterday, and calendar date.
- Each row includes full text preview, destination, time, duration, word count, persona if used, Copy, and overflow actions.
- Text expands inline or opens a detail pane when it exceeds the preview limit.
- Copy preserves the exact final Hush output.
- Overflow actions: Copy, Copy as Plain Text, Delete.
- Multi-select supports Copy and Delete where AppKit behavior remains predictable.

### History detail

- Full final text with selectable text behavior.
- Created date and time.
- Destination app.
- Recording duration and word count.
- Persona and AI engine only if AI was used.
- Copy button is primary. Delete is secondary and destructive.
- Raw audio is never retained by this feature.
- Raw pre-persona transcription is not stored unless separately approved in a future privacy review.

### Retention and privacy

- Default text retention: 30 days.
- Options: Off, 1 day, 7 days, 30 days, 90 days, Forever.
- `Off` keeps aggregate counters but stores no future dictation text.
- `Clear History...` permanently removes stored text after confirmation.
- `Reset Activity...` separately removes aggregate usage metrics.
- History is stored only in the app's local Application Support container.
- No iCloud sync, network upload, analytics export, or hidden remote backup is added.
- Existing three recent items are imported once when the new store is created.

### History empty states

- No history yet: explain that completed Hush dictations appear here.
- History disabled: explain retention is Off and provide `Enable History`.
- No search results: preserve filters and offer Clear Search.

## 10.3 General

Purpose: configure the core dictation loop without model-management detail.

### Shortcut card

Rows:

- Dictation shortcut: current `HotkeyRecorderControl`.
- Recording mode: Hold or Toggle segmented control.
- Spoken language: popup selector.
- Recognition quality: Fast, Balanced, Best quality popup.

Quality explanation appears beneath the selected value as one short sentence. Full technical explanation moves behind a `Learn more` disclosure. The current multi-paragraph warning must not dominate the page.

### After dictation card

Rows:

- Auto-paste into focused app: switch.
- Restore clipboard after paste: switch, disabled when auto-paste is off if the setting has no effect.

The Mac App Store limitation or Accessibility dependency appears as contextual inline help, not a page-wide note.

## 10.4 Transcription

Purpose: make the active speech model and all model lifecycle states obvious.

### Active model card

Header contains:

- Waveform symbol.
- Current model display name.
- Size and local status subtitle.
- Green, blue, gray, or red status indicator.
- Refresh action for the live catalog.

Information rows:

- Status: Bundled, Installed, Downloading, Loading, Ready, or Failed.
- Storage: bundle or local cache size.
- Quality profile: short human-readable description.

### Available models card

- Show models as full-width rows inside one card, not a popover.
- Each row contains title, size, language support, and one trailing action. Do not repeat `Downloadable` in the subtitle when the action already says `Download`.
- Actions: Use, Download, Cancel, Delete. If the catalog cannot confirm a downloadable artifact, show a disabled `Not available` action.
- The active row uses a checkmark and `Active`, not an additional primary button.
- Download progress is inline and does not reflow unrelated rows.
- Destructive deletion requires confirmation and reports reclaimed storage.

### Empty, offline, and error states

- Bundled model remains available if catalog refresh fails.
- Refresh failure appears inline with Retry.
- Technical identifiers stay hidden unless copied through a disclosure action.

## 10.5 Personas

Purpose: turn AI from a compressed settings section into a legible workflow.

Use the product term `Persona` consistently. Do not label persona behavior as generic polish.

### AI master card

Header:

- Sparkles icon.
- `AI personas` title.
- Privacy subtitle: `Optional on-device rewriting. Audio and text stay on this Mac.`
- Enable switch at the trailing edge.

When off:

- Keep the page visible.
- Show a calm disabled-state explanation.
- Present one clear `Enable AI` action through the switch.
- Do not show a persona named `Polish` as active.

When opened from Persona Off in the menu panel:

- Navigate directly to this page.
- Scroll the AI master card into view.
- Move keyboard focus to the enable switch.
- Briefly apply a soft highlight to the card.

### AI engine card

Visible when AI is enabled.

- Current engine name and readiness in the header.
- Provider choices appear as rows within the card.
- Apple Intelligence explains OS availability.
- Qwen rows show one-time download size and on-disk status.
- Progress, Cancel, Use, and Delete are inline.
- Exactly one engine can be active.

### Persona library card

Replace the current profile editor popover with a persistent workspace:

- Left column: persona list with active checkmark.
- Right column: name, creativity, system prompt, and a concise preview description.
- New, Duplicate, and Delete live in an overflow menu above the list.
- Edits autosave.
- Seeded personas can be edited. Deletion rules remain unchanged.
- Switching personas never loses an in-progress edit.

At narrow window widths, list and editor stack vertically within the page.

### Try It card

- Input field with a realistic sample sentence.
- `Try Persona` button.
- Output appears below with running, success, and error states.
- The result includes elapsed time only as secondary information.
- Running a test never changes clipboard contents or inserts text into another app.

## 10.6 HUD & Menu

Purpose: give visual behavior a dedicated, preview-led page.

### HUD card

- Show floating HUD: switch.
- Position: Top or Bottom segmented control.
- Live preview that updates with the selected state and position.
- Top and Bottom place the unchanged HUD in the upper and lower regions of the same preview scene so the selected placement is immediately clear.
- Preview states can cycle through Listening, Processing, Signing, and Inserted without recording audio.

The menu panel is constant and is not previewed on this page. The settings canvas is reserved for behavior the user can change.

## 10.7 Permissions

Purpose: replace ambiguous permission copy with a status and recovery center.

### Overall status card

- Large status: Ready or Action needed.
- One sentence explaining whether all required capabilities are available.

### Permission rows

Microphone row:

- Current state: Granted, Not determined, Denied, or Restricted.
- Action: Request Access or Open System Settings.
- Explanation: required to hear dictation.

Accessibility row:

- Current state: Granted or Not granted.
- Action: Open Privacy & Security.
- Explanation: required only for automatic paste.

Behavior:

- Status refreshes while the page is visible.
- When a permission changes, animate only the status indicator and text.
- Never claim Ready if auto-paste is on and Accessibility is missing.
- The App Store build clearly explains clipboard-only behavior.

When opened from the menu panel, navigate directly here and highlight the first unresolved permission.

## 10.8 About

Purpose: provide identity and trust information without creating a marketing page.

### Identity card

- Hush app icon and wordmark.
- Version and build number.
- Platform requirement.
- Current architecture if useful for support.

### Privacy card

- Audio processing location.
- Text post-processing location for the active AI engine.
- Statement that Hush has no account requirement and no telemetry, if still accurate at implementation time.
- Local model storage location with Reveal in Finder.

### Support links

Only include links that exist and are maintained. Open external links through the system browser.

## 11. Shared component system

Build reusable AppKit components instead of styling each page independently.

### Required components

- `SettingsSidebarItemView`
- `SettingsPageHeaderView`
- `SettingsCardView`
- `SettingsCardHeaderView`
- `SettingsRowView`
- `SettingsStatusView`
- `SettingsInlineMessageView`
- `SettingsEmptyStateView`
- `SettingsProgressRowView`
- `DashboardMetricView`
- `ActivityChartView`
- `LocalComponentStatusView`
- `DictationHistoryRowView`

### Card behavior

- One continuous background and outer border.
- Internal rows are separated by single-pixel semantic separators.
- First and last rows respect card radius.
- Hover is used only for clickable rows.
- Static information rows do not pretend to be buttons.
- Card height grows with content and never clips wrapped text.

### Row hierarchy

- Primary label: 13 pt semibold or regular based on importance.
- Supporting copy: 11 to 12 pt regular, secondary label color.
- Trailing value: 12 to 13 pt medium, right aligned.
- Controls keep native intrinsic sizes.
- Long status text wraps below the primary row instead of truncating critical information.

## 12. Visual design system

### 12.1 Color

Use dynamic semantic colors as the base:

- Window: `windowBackgroundColor`.
- Sidebar: `NSVisualEffectView` with sidebar material.
- Detail content: semantic window surface.
- Cards: dynamic elevated surface derived from control background color.
- Borders and dividers: `separatorColor` with tuned alpha.
- Primary text: `labelColor`.
- Secondary text: `secondaryLabelColor`.
- Muted text: `tertiaryLabelColor`.

Hush colors:

- Cool violet: selected navigation, primary progress, focused branded actions.
- Lilac, blue, rose, and mint: restrained aurora selection, focus, and activity treatments.
- Green: ready and successful only.
- Red: error, missing critical permission, and destructive confirmation only.
- Blue: neutral information only, not the product identity.

No hard-coded light-only surface may be used. Every custom color must define light and dark variants or resolve through semantic system colors.

### 12.2 Typography

- Use the system font throughout.
- Page title: 15 pt semibold in the titlebar.
- Card title: 15 to 17 pt semibold.
- Section title outside cards: 13 pt semibold.
- Row label: 13 pt.
- Supporting copy: 11 to 12 pt.
- Avoid all-uppercase section headings except very small metadata labels.

### 12.3 Iconography

- Use SF Symbols whenever possible.
- Sidebar icons follow the current system accent when selected. Fixed colors are reserved for semantic status.
- Icons must have accessibility descriptions.
- Do not mix outline and filled symbol styles without a state reason.

### 12.4 Motion

- Page change: 140 ms crossfade with no horizontal slide.
- Status change: 140 ms color and opacity transition.
- Download progress: continuous native progress animation.
- Search result highlight: 800 ms soft fade.
- Respect Reduce Motion by removing nonessential transitions.

## 13. Interaction and state rules

- Changes save immediately unless an action is destructive or starts a download.
- No global Save or Apply button.
- Destructive actions require confirmation.
- Downloads can be canceled and retried.
- A failed optional AI operation must not prevent raw transcription or paste.
- Changing sidebar pages does not cancel downloads or model loading.
- Opening the Hush control center normally shows Dashboard or restores the last product destination.
- Command-, opens General Settings from anywhere.
- Command-F focuses sidebar search, or History search when History is active.
- Escape closes transient search or sheets before closing the window.

## 14. Accessibility

- Full keyboard navigation across sidebar, cards, controls, lists, and actions.
- Logical VoiceOver order follows visual order.
- Status never relies on color alone.
- Minimum contrast meets WCAG AA for text and meaningful controls.
- Focus rings remain visible in both appearances.
- Every switch announces title, value, and consequence.
- Progress announces percentage changes without flooding VoiceOver.
- Minimum clickable target: 28 x 28 pt, with 32 x 32 pt preferred.
- Dynamic system text metrics are respected where AppKit supports them.
- Reduce Motion and Increase Contrast are tested explicitly.

## 15. Technical architecture

### 15.1 Window and navigation

Replace the monolithic `SettingsViewController` layout with:

- `HushWindowController`: control-center lifecycle, size restoration, and deep links.
- `HushSplitViewController`: sidebar and detail composition.
- `HushSidebarViewController`: navigation and search.
- `HushDetailContainerViewController`: page switching and title updates.
- One view controller per destination.

Suggested page controllers:

- `DashboardViewController`
- `DictationHistoryViewController`
- `GeneralSettingsViewController`
- `TranscriptionSettingsViewController`
- `PersonaSettingsViewController`
- `InterfaceSettingsViewController`
- `PermissionsSettingsViewController`
- `AboutSettingsViewController`

### 15.2 Deep-link API

The control center must expose an explicit destination API:

```swift
enum HushDestination {
    case dashboard
    case history(recordID: UUID?)
    case general
    case transcription
    case personas(focusEnableAI: Bool)
    case interface
    case permissions(focusFirstMissing: Bool)
    case about
}

func showHush(destination: HushDestination)
```

The menu panel uses this API for Persona, Permissions, and recent History items. `Settings...` routes to General. A generic `Open Hush` action routes to Dashboard.

### 15.3 State ownership

- `Settings.shared` remains the source of truth for persisted preferences.
- `ModelCatalogService`, `ModelManager`, and the coordinator remain responsible for transcription model state.
- `LLMRuntime` remains responsible for AI provider and model state.
- `ActivityStore` owns local dictation records, daily aggregates, retention, and migration from `RecentInsertStore`.
- Page controllers subscribe only to the state they render.
- Shared components do not own product state.
- Existing UserDefaults keys remain unchanged.

### 15.4 Local activity data

Use a versioned SwiftData store in Application Support. UserDefaults is not appropriate for searchable text history or aggregate queries.

`DictationRecord` fields:

- Stable UUID.
- Creation timestamp.
- Final text, optional when history retention is Off.
- Word count.
- Recorded speech duration.
- Destination app display name.
- Destination bundle identifier when available.
- Outcome: inserted or clipboard.
- Active transcription model identifier and display name.
- Persona identifier and display name if used.
- AI provider identifier if used.

`DailyActivitySummary` fields:

- Local calendar date.
- Dictation count.
- Total final words.
- Total recorded speech duration.
- Estimated typing duration.
- Estimated time saved.
- Per-destination counts using app name and bundle identifier only.

Rules:

- Record only successful Hush outputs.
- Never store audio in the activity database.
- Never store window titles, document names, URLs, recipients, or clipboard contents from outside Hush.
- Removing history text does not silently reset aggregate value metrics.
- `Clear History...` and `Reset Activity...` remain separate, explicit actions.
- Dashboard current-model and local-processing status are derived from live runtime state, not historical rows.
- Database writes occur off the UI path and must not delay insertion.
- A failed database write must never fail a dictation or paste.

### 15.5 Appearance

- Remove `window.appearance = NSAppearance(named: .aqua)`.
- All custom layers update colors inside `viewDidChangeEffectiveAppearance()`.
- Prefer semantic `NSColor` resolution and native materials over manually mirrored palettes.
- Snapshot every page in Aqua and Dark Aqua.

## 16. Migration and compatibility

- No user preference migration is required.
- Active models, downloaded models, AI provider, personas, hotkey, behavior, and HUD settings remain intact.
- Import the existing `recentInserts.v1` items into Dictation History once, preserving text, destination, and date.
- Existing imported rows omit duration, word count, model, and persona values that were never recorded.
- After successful import, keep a migration marker so duplicates cannot appear.
- The old Settings view is replaced only after every existing control is mapped to a new destination.
- The minimum macOS version remains unchanged.
- App Store and direct-download behavior continue to diverge only where permissions require it.

## 17. Acceptance criteria

### Structure

- Sidebar and detail layout is present at all supported window sizes.
- All eight selectable destinations are reachable by mouse and keyboard.
- Search finds every editable setting by its visible title.
- Dashboard is the normal product landing page and Command-, opens General.
- Last destination and per-page scroll position restore correctly.

### Visual quality

- Every destination has approved light and dark snapshots.
- No forced light appearance remains.
- No clipped labels, controls, cards, or scroll content at minimum window size.
- Sidebar selection, card boundaries, separators, and focus states remain clear in both appearances.
- The interface looks intentional at default size and on a 1280 x 800 display.

### Functional parity

- Every control in the current `SettingsViewController` exists in the redesign.
- Dashboard metrics match the selected time range and local activity records.
- Estimated time saved uses the documented formula and is labeled as estimated.
- The On this Mac card shows the exact active transcription model and accurate processing locations.
- History search, filters, Copy, Delete, retention, Clear History, and Reset Activity work.
- History never includes system clipboard content or non-Hush text.
- All changes persist and update the running app immediately.
- Model download, cancel, selection, refresh, and deletion work.
- AI enable, provider selection, persona editing, duplication, deletion, and Try It work.
- Permission status updates while the page is visible.
- Menu Persona Off deep-links to Enable AI.
- Menu Permissions deep-links to the first missing permission.

### Reliability

- Settings can open and close repeatedly without duplicate subscriptions or timers.
- Switching pages during model activity does not lose state or crash.
- Offline catalog failure preserves the bundled model workflow.
- AI failure leaves raw dictation available.
- Activity-store failure never blocks dictation, transcription, clipboard, or paste.
- Retention cleanup does not freeze the UI or corrupt aggregate counters.
- No new warnings, Auto Layout conflicts, lint failures, or flaky tests are introduced.

## 18. Verification plan

### End-to-end scenarios

1. Fresh install with empty Dashboard and History.
2. Existing install with three legacy recent items imported once.
3. Multiple dictations across apps with accurate selected-range metrics.
4. History retention Off while aggregate counters continue locally.
5. Clear History without resetting activity, then Reset Activity separately.
6. Existing install with custom hotkey, downloaded model, AI off.
7. AI enabled with Apple Intelligence ready.
8. AI enabled with a Qwen model downloading.
9. Accessibility missing while auto-paste is enabled.
10. Dark appearance with Increase Contrast enabled.
11. Light appearance at 1280 x 800 resolution.
12. Keyboard-only navigation and VoiceOver traversal.
13. Offline model catalog refresh.
14. Open Personas, Permissions, and a History record through menu-panel deep links.
15. Simulated activity-store failure while dictation still inserts successfully.

### Snapshot matrix

Capture every destination in:

- Light appearance at default size.
- Dark appearance at default size.
- Minimum supported window size.
- At least one loading, empty, error, disabled, and ready state where applicable.

## 19. Delivery sequence

1. Build the versioned local activity store, legacy recent migration, retention, and failure isolation.
2. Build the split-view shell, sidebar, titlebar, routing, and shared components.
3. Build Dashboard and History with real local data, empty states, and accurate calculations.
4. Migrate General and Permissions to validate forms, status rows, and deep links.
5. Migrate Transcription with all model lifecycle states and Dashboard model status.
6. Migrate Personas and replace the editor popover with the persistent workspace.
7. Add the interactive HUD preview and About.
8. Add search, restoration, accessibility polish, and full snapshot coverage.
9. Remove the legacy monolithic Settings layout after parity verification.

## 20. Final design decision

The Hush control center will use the reference application's strongest idea: a persistent native sidebar paired with a focused, card-based detail canvas. It will not imitate the reference's product model or branding. Dashboard and History turn invisible utility into durable customer value by showing real local output, estimated time saved, active on-device components, and recoverable Hush text. Settings remain focused destinations for capture, local models, personas, visual feedback, and permissions.
