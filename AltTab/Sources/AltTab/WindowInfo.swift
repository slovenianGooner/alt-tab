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

// AX title lookup tables for one process: by CGWindowID (when available) and by window origin.
// AXWindowID is an undocumented attribute not supported by all apps, so we index by screen
// position as a reliable fallback — both CG and AX use the same top-left coordinate system.
private struct AXTitleCache {
    var byID:     [CGWindowID: String] = [:]
    var byOrigin: [String:     String] = [:]  // key: "\(x),\(y)"
}

private func buildAXTitleCache(for pid: pid_t) -> AXTitleCache {
    let axApp = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(axApp, "AXAllWindows" as CFString, &windowsRef) != .success {
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
    }
    guard let axWindows = windowsRef as? [AXUIElement] else { return AXTitleCache() }

    var cache = AXTitleCache()
    for axWindow in axWindows {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String, !title.isEmpty
        else { continue }

        // Primary: match by AXWindowID (same value as kCGWindowNumber, works where supported)
        var idRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, "AXWindowID" as CFString, &idRef) == .success,
           let axID = (idRef as? NSNumber)?.uint32Value {
            cache.byID[axID] = title
        }

        // Fallback: match by top-left screen origin
        var posRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
           let posVal = posRef as! AXValue? {
            var pt = CGPoint.zero
            if AXValueGetValue(posVal, .cgPoint, &pt) {
                cache.byOrigin["\(pt.x),\(pt.y)"] = title
            }
        }
    }
    return cache
}

func fetchWindows() -> [WindowInfo] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    // Build AX title caches once per app (not once per window).
    let pids = Set(list.compactMap { $0[kCGWindowOwnerPID as String] as? Int32 })
    var titleCache: [pid_t: AXTitleCache] = [:]
    for pid in pids { titleCache[pid_t(pid)] = buildAXTitleCache(for: pid_t(pid)) }

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
        let cache = titleCache[pid_t(pidNum)]

        // Try ID match first; fall back to origin match for apps that don't expose AXWindowID.
        let axTitle: String?
        if let t = cache?.byID[winID] {
            axTitle = t
        } else if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let t = cache?.byOrigin["\(x),\(y)"] {
            axTitle = t
        } else {
            axTitle = nil
        }
        let rawTitle = axTitle ?? appName

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
