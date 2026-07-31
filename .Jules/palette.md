## 2024-07-31 - [Keyboard Shortcuts for Icon-Only Buttons]
**Learning:** Icon-only buttons (like the refresh button) can be unapproachable if they lack keyboard shortcuts or descriptive tooltips. Users expect native-feeling shortcuts like ⌘R for refresh.
**Action:** Always verify that frequent actions not only have an `accessibilityLabel` but also a `help` tooltip and a `.keyboardShortcut` mapped to an intuitive native binding.
