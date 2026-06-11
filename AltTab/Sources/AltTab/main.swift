import Cocoa
import ServiceManagement

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock icon

// Register as a login item (silently; no prompt needed on macOS 13+)
try? SMAppService.mainApp.register()

let switcher = SwitcherWindowController()
let hotkey = HotkeyMonitor(switcher: switcher)
let menuBar = MenuBarController(switcher: switcher)

hotkey.start()
menuBar.start()

app.run()
