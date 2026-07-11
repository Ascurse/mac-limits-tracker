import Foundation
import MacLimitsTrackerCore

@main
struct Verify {
    static func main() async {
        let claude = await ClaudeLimitsProvider().fetch()
        let codex = await CodexLimitsProvider().fetch()
        print("=== Claude ===")
        print(claude)
        print("menuTitle: \(claude.menuTitle)")
        print("=== Codex ===")
        print(codex)
        print("menuTitle: \(codex.menuTitle)")
    }
}