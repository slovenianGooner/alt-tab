import Cocoa

private let ITEM_WIDTH: CGFloat = 90
private let ITEM_PADDING: CGFloat = 12
private let ICON_SIZE: CGFloat = 40
private let VERTICAL_ROW_HEIGHT: CGFloat = 40
private let VERTICAL_PANEL_WIDTH: CGFloat = 500

class SwitcherWindowController {
    private var panel: NSPanel?
    private var windows: [WindowInfo] = []
    private var selectedIndex: Int = 0
    private var stackView: NSStackView?
    private var itemViews: [NSView] = []
    private var labelViews: [NSTextField] = []

    var isVertical: Bool = false
    var isVisible: Bool { panel?.isVisible ?? false }

    func toggleOrientation() {
        isVertical.toggle()
        panel = nil  // force panel rebuild with new orientation
    }

    func show(startingNext: Bool = true) {
        windows = fetchWindows()
        guard !windows.isEmpty else { return }

        if let front = NSWorkspace.shared.frontmostApplication {
            let currentIdx = windows.firstIndex { $0.pid == front.processIdentifier } ?? 0
            selectedIndex = startingNext ? (currentIdx + 1) % windows.count : currentIdx
        } else {
            selectedIndex = startingNext ? min(1, windows.count - 1) : 0
        }

        if panel == nil { buildPanel() }
        rebuildItems()
        panel?.orderFrontRegardless()
    }

    func selectNext() {
        guard !windows.isEmpty else { return }
        let old = selectedIndex
        selectedIndex = (selectedIndex + 1) % windows.count
        updateHighlight(from: old)
    }

    func selectPrev() {
        guard !windows.isEmpty else { return }
        let old = selectedIndex
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        updateHighlight(from: old)
    }

    func commit() {
        guard !windows.isEmpty else { hide(); return }
        let target = windows[selectedIndex]
        hide()
        raiseWindow(target)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func quitSelected() {
        guard !windows.isEmpty else { return }
        let target = windows[selectedIndex]
        target.app.terminate()
        windows.remove(at: selectedIndex)
        if windows.isEmpty { hide(); return }
        selectedIndex = min(selectedIndex, windows.count - 1)
        rebuildItems()
    }

    // MARK: - Window raising

    private func raiseWindow(_ w: WindowInfo) {
        let axApp = AXUIElementCreateApplication(w.pid)
        var windowsRef: CFTypeRef?
        // kAXAllWindowsAttribute includes windows regardless of PiP state or space;
        // fall back to kAXWindowsAttribute for apps that don't support it.
        if AXUIElementCopyAttributeValue(axApp, "AXAllWindows" as CFString, &windowsRef) != .success {
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        }
        guard let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            w.app.activate(options: [.activateIgnoringOtherApps])
            return
        }

        // Match by CGWindowID — cast via NSNumber to handle signed CFNumber storage
        for axWindow in axWindows {
            var idRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, "AXWindowID" as CFString, &idRef) == .success,
               let axID = (idRef as? NSNumber)?.uint32Value, axID == w.id {
                focusWindow(axWindow, axApp: axApp, app: w.app)
                return
            }
        }

        // Fallback: match by title — exact, prefix match for apps that append " - AppName - Profile",
        // or reverse-prefix for apps that append dynamic indicators (e.g. Chrome's 🔊) to kCGWindowName
        // but not to the AX title.
        for axWindow in axWindows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String {
                let axPageTitle = title.components(separatedBy: " - \(w.appName)").first ?? title
                if title == w.rawTitle
                    || title.hasPrefix(w.rawTitle + " - \(w.appName)")
                    || w.rawTitle.hasPrefix(axPageTitle) {
                    focusWindow(axWindow, axApp: axApp, app: w.app)
                    return
                }
            }
        }

        // Last resort: raise first non-PiP window
        for axWindow in axWindows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""
            if title != "Picture in Picture" {
                focusWindow(axWindow, axApp: axApp, app: w.app)
                return
            }
        }
    }

    private func focusWindow(_ axWindow: AXUIElement, axApp: AXUIElement, app: NSRunningApplication) {
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, axWindow)
        app.activate(options: [.activateIgnoringOtherApps])
    }

    // MARK: - Panel

    private func buildPanel() {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovable = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        container.layer?.cornerRadius = 12

        let sv = NSStackView()
        sv.orientation = isVertical ? .vertical : .horizontal
        sv.spacing = 0
        sv.distribution = .fillEqually
        sv.edgeInsets = NSEdgeInsets(top: ITEM_PADDING, left: ITEM_PADDING, bottom: ITEM_PADDING, right: ITEM_PADDING)
        sv.alignment = isVertical ? .leading : .top
        sv.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: container.topAnchor),
            sv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        p.contentView = container
        self.stackView = sv
        self.panel = p
    }

    private func rebuildItems() {
        guard let sv = stackView, let panel = panel else { return }

        sv.arrangedSubviews.forEach { sv.removeArrangedSubview($0); $0.removeFromSuperview() }
        itemViews = []
        labelViews = []

        for (i, w) in windows.enumerated() {
            let (container, label) = makeItem(for: w, selected: i == selectedIndex)
            sv.addArrangedSubview(container)
            itemViews.append(container)
            labelViews.append(label)
        }

        let count = CGFloat(windows.count)
        let totalWidth: CGFloat
        let totalHeight: CGFloat
        if isVertical {
            totalWidth = VERTICAL_PANEL_WIDTH
            totalHeight = VERTICAL_ROW_HEIGHT * count + ITEM_PADDING * 2
        } else {
            totalWidth = ITEM_WIDTH * count + ITEM_PADDING * 2
            totalHeight = ICON_SIZE + 36 + ITEM_PADDING * 2
        }

        let screen = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = NSPoint(x: screen.midX - totalWidth / 2, y: screen.midY - totalHeight / 2)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: totalWidth, height: totalHeight)), display: false)
    }

    private func updateHighlight(from old: Int) {
        guard old < itemViews.count, selectedIndex < itemViews.count else { return }
        itemViews[old].layer?.backgroundColor = NSColor.clear.cgColor
        itemViews[selectedIndex].layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.15).cgColor
        labelViews[old].textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        labelViews[selectedIndex].textColor = .white
    }

    private func makeItem(for w: WindowInfo, selected: Bool) -> (NSView, NSTextField) {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = selected
            ? NSColor(calibratedWhite: 1, alpha: 0.15).cgColor
            : NSColor.clear.cgColor

        let img = NSImageView(image: w.icon)
        img.imageScaling = .scaleProportionallyDown
        img.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: w.windowTitle)
        label.font = .systemFont(ofSize: 11)
        label.textColor = selected ? .white : NSColor(calibratedWhite: 0.7, alpha: 1)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(img)
        container.addSubview(label)

        if isVertical {
            let iconSize: CGFloat = 24
            label.alignment = .left
            label.maximumNumberOfLines = 1
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: VERTICAL_PANEL_WIDTH - ITEM_PADDING * 2),
                container.heightAnchor.constraint(equalToConstant: VERTICAL_ROW_HEIGHT),

                img.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                img.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: iconSize),
                img.heightAnchor.constraint(equalToConstant: iconSize),

                label.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        } else {
            label.alignment = .center
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: ITEM_WIDTH),

                img.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                img.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                img.widthAnchor.constraint(equalToConstant: ICON_SIZE),
                img.heightAnchor.constraint(equalToConstant: ICON_SIZE),

                label.topAnchor.constraint(equalTo: img.bottomAnchor, constant: 5),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            ])
        }

        return (container, label)
    }
}
