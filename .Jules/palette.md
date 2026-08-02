## 2024-07-31 - [Keyboard Shortcuts for Icon-Only Buttons]
**Learning:** Icon-only buttons (like the refresh button) can be unapproachable if they lack keyboard shortcuts or descriptive tooltips. Users expect native-feeling shortcuts like ⌘R for refresh.
**Action:** Always verify that frequent actions not only have an `accessibilityLabel` but also a `help` tooltip and a `.keyboardShortcut` mapped to an intuitive native binding.

## 2026-07-31 - [Native Keyboard Symbols in Tooltips]
**Learning:** Using explicit command modifier syntax like `Cmd-` in tooltips feels less native and can be slightly more confusing than using the actual Apple Command symbol (`⌘`).
**Action:** When updating keyboard shortcut tooltips, use the canonical symbols (`⌘`, `⌥`, `⇧`, `⌃`) for visual consistency and a cleaner aesthetic.
## 2026-08-01 - ASCII UI and Screen Readers
**Learning:** Text-based ASCII art (like custom `[|||···]` progress bars, sparklines, or terminal UI elements like `$ ▮`) creates a terrible, noisy experience for VoiceOver users by forcing the screen reader to enumerate punctuation and symbols character-by-character.
**Action:** When building ASCII-heavy themes (like Terminal/TUI), explicitly wrap these components with `.accessibilityHidden(true)` if they are purely decorative, or use `.accessibilityElement(children: .ignore)` and apply a semantic `.accessibilityLabel` for informative UI.
## 2026-08-01 - [ASCII UI and Screen Readers]
**Learning:** Text-based ASCII art (like custom `[|||···]` progress bars, sparklines, or terminal UI elements like `$ ▮`) creates a terrible, noisy experience for VoiceOver users by forcing the screen reader to enumerate punctuation and symbols character-by-character.
**Action:** When building ASCII-heavy themes (like Terminal/TUI), explicitly wrap these components with `.accessibilityHidden(true)` if they are purely decorative, or use `.accessibilityElement(children: .ignore)` and apply a semantic `.accessibilityLabel` for informative UI.
