import Cocoa
import CoreGraphics

// Cmd+Tab interceptor via CGEventTap.
// Requires Accessibility permission (prompted on first run).
class HotkeyMonitor {
    private var tap: CFMachPort?
    private let switcher: SwitcherWindowController

    init(switcher: SwitcherWindowController) {
        self.switcher = switcher
    }

    func start() {
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            return
        }
        installTap()
    }

    private func installTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)
                              | (1 << CGEventType.flagsChanged.rawValue)
        let s = Unmanaged.passRetained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                let me = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: s
        ) else {
            return
        }

        self.tap = port
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Cmd released while switcher is open → commit
        if type == .flagsChanged {
            let cmdDown = event.flags.contains(.maskCommand)
            if !cmdDown {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.switcher.isVisible else { return }
                    self.switcher.commit()
                }
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)  // 48 = Tab, 12 = Q
        let flags = event.flags
        let cmdDown = flags.contains(.maskCommand)
        let shiftDown = flags.contains(.maskShift)
        let isTab = keyCode == 48
        let isQ = keyCode == 12

        // Cmd+Q while switcher is open → quit selected app
        if cmdDown && isQ && type == .keyDown && switcher.isVisible {
            DispatchQueue.main.async { [weak self] in
                self?.switcher.quitSelected()
            }
            return nil  // consume
        }

        guard cmdDown && isTab else { return Unmanaged.passRetained(event) }

        if type == .keyDown {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.switcher.isVisible {
                    if shiftDown { self.switcher.selectPrev() } else { self.switcher.selectNext() }
                } else {
                    self.switcher.show(startingNext: !shiftDown)
                }
            }
        }
        return nil  // consume Cmd+Tab
    }

    private func requestAccessibility() {
        let opts: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)

        // Poll until granted, then install tap
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            if AXIsProcessTrusted() {
                t.invalidate()
                self?.installTap()
            }
        }
    }
}
