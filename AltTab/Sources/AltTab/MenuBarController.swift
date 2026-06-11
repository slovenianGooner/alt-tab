import Cocoa

class MenuBarController {
    private var statusItem: NSStatusItem?
    private let switcher: SwitcherWindowController
    private var layoutMenuItem: NSMenuItem?
    private var fontSizeItems: [NSMenuItem] = []
    private let fontSizes: [Double] = [9, 10, 11, 12, 13, 14, 16]

    init(switcher: SwitcherWindowController) {
        self.switcher = switcher
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            let img = NSImage(systemSymbolName: "square.2.layers.3d", accessibilityDescription: "AltTab")
            img?.isTemplate = true
            button.image = img
        }

        let layoutItem = NSMenuItem(title: layoutMenuTitle(), action: #selector(toggleLayout), keyEquivalent: "")
        layoutItem.target = self
        self.layoutMenuItem = layoutItem

        let fontMenu = NSMenu()
        for size in fontSizes {
            let sizeItem = NSMenuItem(
                title: "\(Int(size))pt",
                action: #selector(setFontSize(_:)),
                keyEquivalent: ""
            )
            sizeItem.tag = Int(size * 10)
            sizeItem.state = ConfigManager.shared.config.fontSize == size ? .on : .off
            sizeItem.target = self
            fontMenu.addItem(sizeItem)
            fontSizeItems.append(sizeItem)
        }
        let fontSizeMenuItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        fontSizeMenuItem.submenu = fontMenu

        let menu = NSMenu()
        menu.addItem(layoutItem)
        menu.addItem(fontSizeMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AltTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        self.statusItem = item
    }

    @objc private func toggleLayout() {
        switcher.toggleOrientation()
        layoutMenuItem?.title = layoutMenuTitle()
    }

    @objc private func setFontSize(_ sender: NSMenuItem) {
        let size = Double(sender.tag) / 10.0
        ConfigManager.shared.update { $0.fontSize = size }
        fontSizeItems.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        switcher.invalidatePanel()
    }

    private func layoutMenuTitle() -> String {
        switcher.isVertical ? "Switch to Horizontal View" : "Switch to Vertical View"
    }
}
