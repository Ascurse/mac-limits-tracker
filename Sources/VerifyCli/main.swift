import Foundation
import MacLimitsTrackerCore

// Запускать в release: `swift run -c release VerifyCli`.
// В debug короткоживущий CLI (fetch → выход) ловит ложный nano-malloc abort при
// сворачивании пула Swift concurrency; release и само меню-бар-приложение не задеты.
@main
struct Verify {
    static func main() async {
        for provider in ProviderRegistry.makeDefault() {
            let descriptor = provider.descriptor
            let snapshot = await provider.fetch()
            print("=== \(descriptor.displayName) ===")
            print("loggedIn: \(snapshot.loggedIn)")
            print("plan: \(snapshot.plan ?? "—")")
            print("providerError: \(snapshot.providerError ?? "—")")
            print("usageError: \(snapshot.usageError ?? "—")")
            if let windows = snapshot.windows {
                for w in windows {
                    printWindow(RateLimitWindowLabel.labels(forDurationMins: w.windowDurationMins).long, w)
                }
            } else {
                print("windows: nil")
            }
            for d in snapshot.details {
                print("\(d.key): \(d.value)")
            }
            print("credits: \(snapshot.creditsBalance ?? "—")")
            print("rateLimitReachedType: \(snapshot.rateLimitReachedType ?? "none")")
            if let days = snapshot.daysUntilRenewal { print("daysUntilRenewal: \(days)") }
            if let renewal = snapshot.renewalDate { print("renewalDate: \(renewal)") }
            print("menuTitle: \(snapshot.menuTitle(shortName: descriptor.shortName))")
        }
    }

    static func printWindow(_ label: String, _ window: SnapshotWindow) {
        guard let used = window.usedPercent else { print("\(label): unavailable"); return }
        let remaining = max(0, 100 - used)
        print("\(label) remaining: \(remaining)% (used \(used)%), resets: \(String(describing: window.resetsAt))")
    }
}
