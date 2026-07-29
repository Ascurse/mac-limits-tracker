import Cocoa
import CoreGraphics

// windowlist.swift — CGWindowListCopyWindowInfo → one line per window.
// Output format: windowID|ownerPID|ownerName|layer|title|bounds
//
// Used by QA assert primitives to inspect windows of MacLimitsTracker
// (main window, Settings, desktop widget) without relying on AX APIs.

let options = CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(0)
}

for info in windowList {
    let windowID = info[kCGWindowNumber as String] as? Int ?? 0
    let ownerPID = info[kCGWindowOwnerPID as String] as? Int ?? 0
    let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
    let layer = info[kCGWindowLayer as String] as? Int ?? 0
    let title = info[kCGWindowName as String] as? String ?? ""

    let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let x = boundsDict["X"] ?? 0
    let y = boundsDict["Y"] ?? 0
    let width = boundsDict["Width"] ?? 0
    let height = boundsDict["Height"] ?? 0
    let bounds = "\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))"

    // Escape pipe characters in title so consumers can split reliably.
    let safeTitle = title.replacingOccurrences(of: "|", with: "\\|")

    print("\(windowID)|\(ownerPID)|\(ownerName)|\(layer)|\(safeTitle)|\(bounds)")
}
