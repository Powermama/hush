# PRD: Activity navigation hierarchy

- Status: Accepted
- Product: Hush for macOS
- Scope: Control Center information architecture and insights navigation
- Decision: Keep Activity primary and make Time Saved a Dashboard drill-down

## 1. Executive decision

The Control Center activity group has three primary destinations:

```text
Dashboard
Activity
History
```

Configuration is grouped by user job rather than placed under one generic Settings heading:

```text
WORKFLOW
Transcription
Personas
HUD & Menu

TRUST & PRIVACY
Verified Messages
Permissions

APP
General
About
```

Time Saved is not a sidebar destination. It explains the value claim in the Dashboard hero, so `View details` opens Time Saved as a child of Dashboard in the same window.

While Time Saved is open:

- Dashboard remains selected in the sidebar.
- A leading Back control returns to Dashboard.
- Command-[ performs the same Back action.
- The selected activity range survives navigation in both directions.
- The window is not replaced, expanded, or opened as a separate tab.

## 2. Product hierarchy

The three primary destinations answer different durable user questions:

| Destination | User question | Primary content |
| --- | --- | --- |
| Dashboard | What has Hush done for me recently? | Time saved, voice activity, destinations, local setup, recent dictations |
| Activity | Where did I use Hush? | App-level rankings and supporting activity totals |
| History | What did I dictate? | Searchable retained transcript records |

Time Saved answers a narrower follow-up:

> Why does Hush say I work 2.6x faster, and how is that calculated?

It therefore belongs beneath Dashboard rather than beside it.

## 3. Rationale

Apple describes sidebars as navigation between top-level areas or collections. Time Saved is neither. Exposing it as a peer makes the sidebar feel heavier and obscures the relationship between the Dashboard multiplier and its explanation.

Apple's split-view guidance says the selected parent should remain highlighted when showing descendant content. Keeping Dashboard selected while Time Saved is visible preserves orientation.

Apple's toolbar guidance places return navigation at the leading edge. Hush follows that convention in its existing header instead of adding a second toolbar or modal flow.

References:

- [Apple Human Interface Guidelines: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple Human Interface Guidelines: Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [Apple Human Interface Guidelines: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [AppKit navigational toolbar items](https://developer.apple.com/documentation/appkit/nstoolbaritem/isnavigational)

## 4. Goals

- Reduce the number of primary navigation choices.
- Keep the Dashboard glanceable.
- Make the voice-versus-typing calculation easy to inspect.
- Preserve context and range when navigating back.
- Keep Activity directly accessible for app-level usage.
- Preserve all existing activity and typing data.

## 5. Non-goals

- Do not merge Time Saved and Activity into one oversized page.
- Do not open Time Saved in another window, tab, sheet, or expandable card.
- Do not add Time Saved to the sidebar search results as a primary destination.
- Do not duplicate the Dashboard daily voice-activity chart.
- Do not change activity storage, typing-test generation, or retention.
- Do not add another hierarchy level or collapsible sidebar group.

## 6. Navigation behavior

### 6.1 Open

1. The user selects `View details` in the Dashboard time-saved hero.
2. The current Dashboard range is passed to Time Saved.
3. Time Saved replaces the detail content in the existing Control Center window.
4. Dashboard stays highlighted in the sidebar.
5. The header title changes to `Time Saved` and reveals the leading Back control.

### 6.2 Return

The user can return by:

- Selecting the leading `Dashboard` Back control.
- Pressing Command-[.
- Selecting Dashboard in the sidebar.

Returning restores Dashboard with the range last used in Time Saved. Scroll restoration can be added later if users need it, but range preservation is required now.

### 6.3 Other navigation

- `View all` in `Where you saved time` opens Activity with the Dashboard range.
- `View all` in recent dictations opens History.
- Selecting Activity or History while Time Saved is open exits the drill-down normally.

## 7. Time Saved value hierarchy

The detail page keeps this order:

1. Voice advantage multiplier, such as `2.6x`.
2. Spoken WPM and the active typing comparison basis.
3. Estimated minutes or hours saved.
4. Pace comparison table.
5. Supporting words spoken and recorded duration.
6. Privacy and calculation explanation.

The typing-history line chart remains excluded. It adds visual weight without materially improving the user's understanding of the current multiplier.

## 8. Accessibility and interaction

- The Back control has the accessibility label `Back to Dashboard`.
- The target is at least the standard macOS control size.
- Sidebar selection remains programmatically exposed as Dashboard.
- Keyboard focus moves naturally into the new detail content.
- Back navigation must not reset the selected range.
- The detail remains usable with VoiceOver and keyboard-only navigation.

## 9. Acceptance criteria

- The sidebar lists Dashboard, Activity, and History in that order.
- Time Saved never appears as a sidebar row.
- Dashboard `View details` opens Time Saved in the same window.
- Dashboard remains selected while Time Saved is visible.
- The Back control is leading and visible only for Time Saved.
- Back and Command-[ return to Dashboard.
- Changing the range in either view is preserved after the round trip.
- Activity and History navigation continue to work.
- Debug and Release builds pass without warnings introduced by this change.
