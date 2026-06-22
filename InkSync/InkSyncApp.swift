import SwiftUI
import AppKit

@main
struct InkSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let eventKitManager = EventKitManager()
    private var _realApiClient: RealAPIClient?
    private let _mockApiClient = MockAPIClient()

    var apiClient: APIClient {
        if appConfig.apiKey.isEmpty {
            return _mockApiClient
        }
        if _realApiClient == nil {
            _realApiClient = RealAPIClient()
        }
        return _realApiClient!
    }

    let appConfig = AppConfig.shared
    lazy var mappingManager = MappingManager(eventKitManager: eventKitManager, apiClient: apiClient)
    lazy var syncEngine = SyncEngine(
        eventKitManager: eventKitManager,
        apiClient: apiClient,
        mappingManager: mappingManager
    )
    lazy var recurringEngine = RecurringEngine(
        eventKitManager: eventKitManager,
        mappingManager: mappingManager
    )

    var statusBarController: StatusBarController?
    var settingsWindowController: SettingsWindowController?
    var onboardingWindowController: OnboardingWindowController?
    var syncLogWindowController: SyncLogWindowController?
    var recurringWindowController: RecurringRemindersWindowController?
    var recurringLogWindowController: RecurringLogWindowController?

    private var visibleWindowCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindowControllers()
        setupStatusBar()
        setupSyncEngine()
        requestPermissions()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.visibleWindowCount = NSApp.windows.filter { $0.isVisible && $0.canBecomeKey }.count
            self?.updateDockVisibility()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.visibleWindowCount = NSApp.windows.filter { $0.isVisible && $0.canBecomeKey }.count
                self?.updateDockVisibility()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.eventKitManager.refreshAuthorizationStatus()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }
    }

    private func handleSystemWake() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            recurringEngine.catchUpOnLaunchOrWake()
        }
    }

    private func updateDockVisibility() {
        let shouldShowInDock = visibleWindowCount > 0
        let currentPolicy = NSApp.activationPolicy()
        let desiredPolicy: NSApplication.ActivationPolicy = shouldShowInDock ? .regular : .accessory
        if currentPolicy != desiredPolicy {
            NSApp.setActivationPolicy(desiredPolicy)
        }
    }

    private func setupWindowControllers() {
        settingsWindowController = SettingsWindowController(
            appConfig: appConfig,
            mappingManager: mappingManager,
            syncEngine: syncEngine,
            apiClient: apiClient
        )

        onboardingWindowController = OnboardingWindowController(
            appConfig: appConfig,
            mappingManager: mappingManager,
            apiClient: apiClient
        ) { [weak self] in
            self?.onboardingWindowController?.window?.close()
            self?.onboardingWindowController = nil
        }

        syncLogWindowController = SyncLogWindowController()
    }

    private func setupStatusBar() {
        statusBarController = StatusBarController(
            eventKitManager: eventKitManager,
            mappingManager: mappingManager,
            syncEngine: syncEngine,
            recurringEngine: recurringEngine,
            onOpenSettings: { [weak self] in
                self?.showSettings()
            },
            onViewSyncLog: { [weak self] in
                self?.showSyncLog()
            },
            onOpenRecurringManager: { [weak self] in
                self?.showRecurringManager()
            },
            onOpenRecurringLog: { [weak self] in
                self?.showRecurringLog()
            }
        )

        if !appConfig.hasCompletedOnboarding {
            onboardingWindowController?.showWindow()
        }
    }

    private func setupSyncEngine() {
        syncEngine.startPolling()
        recurringEngine.start()
        recurringEngine.catchUpOnLaunchOrWake()
    }

    private func requestPermissions() {
        Task {
            _ = try? await eventKitManager.requestAccess()
            mappingManager.loadAvailableLists()

            _ = await NotificationManager.shared.requestAuthorization()
        }
    }

    func showSettings() {
        settingsWindowController?.showWindow()
    }

    func showSyncLog() {
        syncLogWindowController?.showWindow()
    }

    func showOnboarding() {
        onboardingWindowController?.showWindow()
    }

    func showRecurringManager() {
        if recurringWindowController == nil {
            recurringWindowController = RecurringRemindersWindowController(
                engine: recurringEngine,
                onOpenLog: { [weak self] in
                    self?.showRecurringLog()
                }
            )
        }
        recurringWindowController?.showWindow(nil)
    }

    func showRecurringLog() {
        if recurringLogWindowController == nil {
            recurringLogWindowController = RecurringLogWindowController()
        }
        recurringLogWindowController?.showWindow(nil)
    }
}