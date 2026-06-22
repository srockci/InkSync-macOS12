import SwiftUI
import AppKit

final class RecurringRemindersWindowController: NSWindowController {
    convenience init(engine: RecurringEngine, onOpenLog: @escaping () -> Void) {
        let window = NSWindow()
        window.title = "周期备忘管理"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 480))
        window.center()

        let view = RecurringRemindersView(engine: engine, onOpenLog: onOpenLog)
        let hosting = NSHostingController(rootView: view)
        window.contentViewController = hosting

        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class RecurringLogWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow()
        window.title = "周期备忘生成日志"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 480))
        window.center()

        let view = RecurringLogView()
        let hosting = NSHostingController(rootView: view)
        window.contentViewController = hosting

        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}