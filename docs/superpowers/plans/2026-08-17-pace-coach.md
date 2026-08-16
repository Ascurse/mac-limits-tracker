# Pace Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the menu-bar surface answer whether the current AI usage pace is safe and what to do when it is not.

**Architecture:** Reuse the existing `PaceComparisonPolicy`, `PaceComparisonContent`, and `UsagePaceView`. The Core presentation builder will expose compact pace rows on both menu-bar and desktop surfaces; the view will render compact rows as one-line status/action copy and retain the existing two-bar comparison for desktop.

**Tech Stack:** Swift 5.10+, SwiftUI, XCTest, Swift Package Manager.

**Spec:** Beads issue `mac-limits-tracker-qfc` and the approved Pace coach product direction.

## Global Constraints

- Menu bar remains a glanceable status surface; no new chart, provider routing, or cost analytics.
- No new dependency or persistence format.
- Existing pace statuses remain exhaustive: on pace, at risk, collecting history, unavailable.
- Production code follows RED → GREEN → REFACTOR with a failing XCTest first.

---

### Task 1: Expose compact pace rows on both surfaces

**Files:**
- Modify: `Sources/MacLimitsTrackerCore/Models/PopupContent.swift`
- Test: `Tests/MacLimitsTrackerTests/PopupContentBuilderTests.swift`

**Interfaces:**
- Consumes: existing `BurnRateCalculator`, `PaceComparisonPolicy`, `PaceComparisonContent`.
- Produces: `.paceComparison` rows for each valid window on `menuBar` and `desktop`; menu-bar tests assert the existing window order plus pace statuses.

- [ ] Write a failing test proving the menu-bar surface includes one pace row per valid window.
- [ ] Run the focused surface test and confirm it fails because menu-bar rows currently omit pace comparisons.
- [ ] Make `windowRows` calculate the burn rate once and append the existing pace content for both surfaces.
- [ ] Run the focused surface tests and confirm the new contract passes without restoring omitted technical rows.

### Task 2: Render compact pace copy as an action-oriented glance

**Files:**
- Modify: `Sources/MacLimitsTracker/UI/UsageTrendView.swift`
- Test: `Tests/MacLimitsTrackerTests/PaceComparisonPolicyTests.swift` if policy-edge coverage is needed

**Interfaces:**
- Consumes: `PaceComparisonContent` and existing `UsagePaceVariant.compact`.
- Produces: compact text showing status, remaining/reset or forecast information, and a recovery suggestion for `.atRisk`.

- [ ] Extend the compact-view assertions through a policy/string contract that can fail before implementation.
- [ ] Run the focused test to verify the missing action-oriented behavior.
- [ ] Render compact variants as one line with safe, risk, history, and unavailable states; keep desktop bars unchanged.
- [ ] Run focused policy and surface tests, then the complete `swift test` suite.

### Task 3: Verify the observable product contract

**Files:**
- Modify: `README.md` only if the shipped surface behavior differs from its current description.

- [ ] Run the full test suite and inspect the diff for unrelated files.
- [ ] Build and launch the bundled app or the closest available local surface, then verify one safe and one at-risk fixture visually.
- [ ] Record any manual-QA limitation honestly; do not claim the GUI gate passed without observing the app.
