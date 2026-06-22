import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState = AppState()
    private let eventKitManager: EventKitManager
    private let mappingManager: MappingManager
    private let syncEngine: SyncEngine
    private let recurringEngine: RecurringEngine

    var currentStatus: SyncStatus = .idle {
        didSet {
            appState.syncStatus = currentStatus
            updateIcon()
        }
    }

    var onOpenSettings: () -> Void
    var onViewSyncLog: () -> Void
    var onOpenRecurringManager: () -> Void
    var onOpenRecurringLog: () -> Void

    init(
        eventKitManager: EventKitManager,
        mappingManager: MappingManager,
        syncEngine: SyncEngine,
        recurringEngine: RecurringEngine,
        onOpenSettings: @escaping () -> Void,
        onViewSyncLog: @escaping () -> Void,
        onOpenRecurringManager: @escaping () -> Void,
        onOpenRecurringLog: @escaping () -> Void
    ) {
        self.eventKitManager = eventKitManager
        self.mappingManager = mappingManager
        self.syncEngine = syncEngine
        self.recurringEngine = recurringEngine
        self.onOpenSettings = onOpenSettings
        self.onViewSyncLog = onViewSyncLog
        self.onOpenRecurringManager = onOpenRecurringManager
        self.onOpenRecurringLog = onOpenRecurringLog
        super.init()
        setupStatusItem()
        setupPopover()
        updateIcon()
        setupRemindersMonitoring()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let rootView = MenuPopoverView(
            appState: appState,
            eventKitManager: eventKitManager,
            mappingManager: mappingManager,
            syncEngine: syncEngine,
            recurringEngine: recurringEngine,
            onSyncNow: { [weak self] in
                self?.handleSyncNow()
            },
            onViewSyncLog: { [weak self] in
                self?.onViewSyncLog()
            },
            onOpenRecurringManager: { [weak self] in
                self?.onOpenRecurringManager()
            },
            onOpenRecurringLog: { [weak self] in
                self?.onOpenRecurringLog()
            },
            onOpenSettings: { [weak self] in
                self?.onOpenSettings()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        popover.contentViewController = NSHostingController(rootView: rootView)
        self.popover = popover
    }

    private func setupRemindersMonitoring() {
        eventKitManager.startMonitoringChanges { [weak self] in
            Task { @MainActor [weak self] in
                self?.mappingManager.loadAvailableLists()
            }
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func handleSyncNow() {
        let popoverToClose = self.popover
        popoverToClose?.performClose(nil)
        Task { @MainActor in
            await syncEngine.syncAll()
        }
    }

    func updateIcon() {
        guard let button = statusItem?.button else { return }

        stopRotationAnimation()

        let symbolName: String
        let tintColor: NSColor

        switch currentStatus {
        case .idle:
            symbolName = "hexagon"
            tintColor = .secondaryLabelColor
        case .syncing:
            symbolName = "hexagon.fill"
            tintColor = .controlAccentColor
        case .failed:
            symbolName = "exclamationmark.triangle.fill"
            tintColor = .systemYellow
        case .conflict:
            symbolName = "circle.badge.plus"
            tintColor = .controlAccentColor
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "InkSync")?
            .withSymbolConfiguration(configuration)

        button.image = image
        button.image?.isTemplate = true
        button.contentTintColor = tintColor

        if currentStatus == .syncing {
            startRotationAnimation(on: button)
        }
    }

    private func startRotationAnimation(on button: NSStatusBarButton) {
        button.wantsLayer = true

        guard let layer = button.layer else { return }

        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = -Double.pi * 2
        animation.duration = 1.0
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "rotation")
    }

    private func stopRotationAnimation() {
        statusItem?.button?.layer?.removeAnimation(forKey: "rotation")
    }

    func popoverDidClose(_ notification: Notification) {
        stopRotationAnimation()
        if currentStatus == .syncing {
            updateIcon()
        }
    }
}