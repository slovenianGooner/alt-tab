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

// Returns AX window titles for a process as (ordered list, id→title map).
// kAXWindowsAttribute enumerates only on-screen non-minimized windows, front-to-back —
// the same set and order that CGWindowListCopyWindowInfo returns for a given PID.
private func axWindowInfo(for pid: pid_t) -> (ordered: [String], byID: [CGWindowID: String]) {
    let axApp = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
    guard let axWindows = windowsRef as? [AXUIElement] else { return ([], [:]) }

    var ordered: [String] = []
    var byID: [CGWindowID: String] = [:]

    for axWindow in axWindows {
        var titleRef: CFTypeRef?
        let title = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success
            ? (titleRef as? String ?? "")
            : ""

        ordered.append(title)

        var idRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, "AXWindowID" as CFString, &idRef) == .success,
           let axID = (idRef as? NSNumber)?.uint32Value {
            byID[axID] = title
        }
    }
    return (ordered, byID)
}

func fetchWindows() -> [WindowInfo] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    // Build AX info once per app.
    let pids = Set(list.compactMap { $0[kCGWindowOwnerPID as String] as? Int32 }.map { pid_t($0) })
    var axCache: [pid_t: (ordered: [String], byID: [CGWindowID: String])] = [:]
    for pid in pids { axCache[pid] = axWindowInfo(for: pid) }

    // Track how many CG windows we've seen per PID for index-based fallback.
    var pidIndex: [pid_t: Int] = [:]

    var results: [WindowInfo] = []

    for info in list {
        guard
            let layer   = info[kCGWindowLayer as String]    as? Int,    layer == 0,
            let pidNum  = info[kCGWindowOwnerPID as String] as? Int32,
            let app     = NSRunningApplication(processIdentifier: pidNum),
            !app.isHidden,
            app.activationPolicy == .regular
        else { continue }

        if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] {
            if (bounds["Width"] ?? 0) < 100 || (bounds["Height"] ?? 0) < 100 { continue }
        }

        let pid    = pid_t(pidNum)
        let winID  = CGWindowID(info[kCGWindowNumber as String] as? Int ?? 0)
        let appName = info[kCGWindowOwnerName as String] as? String ?? app.localizedName ?? "Unknown"
        let ax     = axCache[pid]
        let idx    = pidIndex[pid, default: 0]
        pidIndex[pid, default: 0] += 1

        // ID match is exact; index match works because both APIs enumerate front-to-back.
        let axTitle: String
        if let t = ax?.byID[winID], !t.isEmpty {
            axTitle = t
        } else if let t = ax?.ordered[safe: idx], !t.isEmpty {
            axTitle = t
        } else {
            axTitle = appName
        }

        if axTitle == "Picture in Picture" { continue }

        let rawTitle = axTitle
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
            pid: pid,
            app: app
        ))
    }

    return results
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
