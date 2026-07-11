import Foundation
import MacLimitsTrackerCore

// Запускать в release: `swift run -c release VerifyCli`.
// В debug короткоживущий CLI (fetch → выход) ловит ложный nano-malloc abort при
// сворачивании пула Swift concurrency; release и само меню-бар-приложение не задеты.
@main
struct Verify {
    static func main() async {
        let claude = await ClaudeLimitsProvider().fetch()
        print("=== Claude ===")
        print("loggedIn: \(claude.loggedIn)")
        print("subscription: \(claude.subscriptionType ?? "—")")
        print("providerError: \(claude.providerError ?? "—")")
        print("usageError: \(claude.usageError ?? "—")")
        if let usage = claude.usage {
            printWindow("fiveHour", usage.fiveHour)
            printWindow("sevenDay", usage.sevenDay)
        } else {
            print("usage: nil")
        }
        print("menuTitle: \(claude.menuTitle)")

        let codex = await CodexLimitsProvider().fetch()
        print("=== Codex ===")
        print("loggedIn: \(codex.loggedIn)")
        print("email: \(codex.email ?? "—")")
        print("planType (jwt): \(codex.planType ?? "—")")
        print("providerError: \(codex.providerError ?? "—")")
        print("usageError: \(codex.usageError ?? "—")")
        if let snap = codex.usage?.snapshot {
            printCodexWindow("5h", snap.primary)
            printCodexWindow("weekly", snap.secondary)
            print("plan: \(snap.planType ?? "—")")
            print("credits: \(snap.creditsBalance ?? "—")")
            print("rateLimitReachedType: \(snap.rateLimitReachedType ?? "none")")
        } else if codex.usage != nil {
            print("usage.snapshot: nil")
        } else {
            print("usage: nil")
        }
        print("menuTitle: \(codex.menuTitle)")
    }

    static func printWindow(_ label: String, _ window: ClaudeUsageWindow?) {
        guard let window else { print("\(label): nil"); return }
        let remaining = max(0, 100 - window.utilizationPercent)
        print("\(label) remaining: \(remaining)% (used \(window.utilizationPercent)%), resets: \(String(describing: window.resetsAt))")
    }

    static func printCodexWindow(_ label: String, _ w: CodexUsageWindow?) {
        guard let w else { print("\(label): nil"); return }
        let remaining = max(0, 100 - w.usedPercent)
        print("\(label) remaining: \(remaining)% (used \(w.usedPercent)%), resetsAt: \(String(describing: w.resetsAt))")
    }
}
