import Cocoa
import CoreGraphics

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let windowTitle: String  // display title (app suffix stripped)
    let rawTitle: String     // original kCGWindowName, used for AX matching
    let appName: String
    let icon: NSImage
    let pid: pid_t
    let app: NSRunningApplication
}

func fetchWindows() -> [WindowInfo] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    var results: [WindowInfo] = []

    for info in list {
        guard
            let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
            let pidNum = info[kCGWindowOwnerPID as String] as? Int32,
            let app = NSRunningApplication(processIdentifier: pidNum),
            !app.isHidden,
            app.activationPolicy == .regular
        else { continue }

        // Filter out tiny utility windows (e.g. tooltips, popups)
        if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] {
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            if w < 100 || h < 100 { continue }
        }

        // Filter out Picture-in-Picture and other known overlay windows
        let candidateTitle = info[kCGWindowName as String] as? String ?? ""
        if candidateTitle == "Picture in Picture" { continue }

        let appName = info[kCGWindowOwnerName as String] as? String ?? app.localizedName ?? "Unknown"
        // kCGWindowName requires Screen Recording permission; falls back to app name without it
        let rawTitle = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName
        // Strip trailing " - AppName" suffix that browsers/editors append (e.g. "GitHub - Google Chrome" → "GitHub")
        let winTitle = rawTitle.hasSuffix(" - \(appName)")
            ? String(rawTitle.dropLast(" - \(appName)".count))
            : rawTitle
        let winID = CGWindowID(info[kCGWindowNumber as String] as? Int ?? 0)

        let icon = app.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage()
        icon.size = NSSize(width: 48, height: 48)

        results.append(WindowInfo(
            id: winID,
            windowTitle: winTitle,
            rawTitle: rawTitle,
            appName: appName,
            icon: icon,
            pid: pid_t(pidNum),
            app: app
        ))
    }

    return results
}
