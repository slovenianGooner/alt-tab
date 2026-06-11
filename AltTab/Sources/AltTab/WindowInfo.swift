import Cocoa
import CoreGraphics

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let windowTitle: String  // display title (app suffix stripped)
    let rawTitle: String     // AX title, used for AX matching
    let appName: String
    let icon: NSImage
    let pid: pid_t
    let app: NSRunningApplication
}

// Build a CGWindowID → AX title map for a given process using the Accessibility API.
private func axTitles(for pid: pid_t) -> [CGWindowID: String] {
    let axApp = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(axApp, "AXAllWindows" as CFString, &windowsRef) != .success {
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
    }
    guard let axWindows = windowsRef as? [AXUIElement] else { return [:] }

    var map: [CGWindowID: String] = [:]
    for axWindow in axWindows {
        var idRef: CFTypeRef?
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, "AXWindowID" as CFString, &idRef) == .success,
              let axID = (idRef as? NSNumber)?.uint32Value,
              AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String
        else { continue }
        map[axID] = title
    }
    return map
}

func fetchWindows() -> [WindowInfo] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    // Collect unique PIDs up front so we call axTitles once per app, not once per window.
    let pids = Set(list.compactMap { $0[kCGWindowOwnerPID as String] as? Int32 })
    var titleCache: [pid_t: [CGWindowID: String]] = [:]
    for pid in pids { titleCache[pid_t(pid)] = axTitles(for: pid_t(pid)) }

    var results: [WindowInfo] = []

    for info in list {
        guard
            let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
            let pidNum = info[kCGWindowOwnerPID as String] as? Int32,
            let app = NSRunningApplication(processIdentifier: pidNum),
            !app.isHidden,
            app.activationPolicy == .regular
        else { continue }

        if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] {
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            if w < 100 || h < 100 { continue }
        }

        let winID = CGWindowID(info[kCGWindowNumber as String] as? Int ?? 0)
        let appName = info[kCGWindowOwnerName as String] as? String ?? app.localizedName ?? "Unknown"
        let rawTitle = titleCache[pid_t(pidNum)]?[winID].flatMap { $0.isEmpty ? nil : $0 } ?? appName

        if rawTitle == "Picture in Picture" { continue }

        let winTitle = rawTitle.hasSuffix(" - \(appName)")
            ? String(rawTitle.dropLast(" - \(appName)".count))
            : rawTitle

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
