import Cocoa

class MenuBarController {
    private var statusItem: NSStatusItem?
    private let switcher: SwitcherWindowController
    private var layoutMenuItem: NSMenuItem?

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

        let menu = NSMenu()
        menu.addItem(layoutItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AltTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        self.statusItem = item
    }

    @objc private func toggleLayout() {
        switcher.toggleOrientation()
        layoutMenuItem?.title = layoutMenuTitle()
    }

    private func layoutMenuTitle() -> String {
        switcher.isVertical ? "Switch to Horizontal View" : "Switch to Vertical View"
    }
}
