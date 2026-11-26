import Cocoa
import SwiftUI
import WenBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let updateService = UpdateService()
    let hotkeyManager = GlobalHotkeyManager()

    private(set) var clockVM: ClockViewModel!
    private(set) var calendarVM: CalendarViewModel!
    private(set) var diskManager: ExternalDriveManager!
    private(set) var archiveManager: ArchiveTaskManager!
    private(set) var statusBarController: StatusBarController!
    private(set) var actionRouter: ActionRouter!

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var customCompressWindow: NSWindow?
    private var passwordWindow: NSWindow?
    private var launchedForBackgroundURL = false

    func application(_ application: NSApplication, open urls: [URL]) {
        // Detect if cold launch was triggered solely by a silent background Finder action
        if actionRouter == nil {
            launchedForBackgroundURL = true
        }
        actionRouter?.handleIncomingURLs(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        calendarVM = CalendarViewModel(settingsStore: settingsStore)
        clockVM = ClockViewModel(settingsStore: settingsStore) { [weak self] in
            self?.calendarVM?.nextHoliday
        }
        diskManager = ExternalDriveManager(settingsStore: settingsStore)
        archiveManager = ArchiveTaskManager(settingsStore: settingsStore)

        actionRouter = ActionRouter(
            archiveManager: archiveManager,
            settingsStore: settingsStore,
            onRequestCustomCompress: { [weak self] urls in
                self?.openCustomCompressWindow(sources: urls)
            }
        )

        statusBarController = StatusBarController(
            clockVM: clockVM,
            calendarVM: calendarVM,
            diskManager: diskManager,
            archiveManager: archiveManager,
            settingsStore: settingsStore,
            updateService: updateService,
            onOpenSettings: { [weak self] in self?.openSettingsWindow() },
            onOpenOnboarding: { [weak self] in self?.openOnboardingWindow() },
            onQuit: { NSApp.terminate(nil) }
        )

        settingsStore.onSettingsChanged = { [weak self] in
            self?.clockVM.refreshScheduling()
            self?.statusBarController.rebuildStatusItems()
        }

        registerGlobalHotkey()
        observePasswordPrompts()

        if !settingsStore.settings.hasCompletedOnboarding && !launchedForBackgroundURL {
            openOnboardingWindow()
        }

        if settingsStore.settings.autoCheckUpdates && !launchedForBackgroundURL {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                await self?.updateService.checkForUpdates(silent: true)
            }
        }
    }

    func registerGlobalHotkey() {
        let code = settingsStore.settings.hotkeyKeyCode
        let mods = settingsStore.settings.hotkeyModifiers
        hotkeyManager.register(keyCode: code, modifiers: mods) { [weak self] in
            self?.statusBarController.toggleMainPopover()
        }
    }

    func openSettingsWindow() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            settingsStore: settingsStore,
            clockVM: clockVM,
            calendarVM: calendarVM,
            diskManager: diskManager,
            updateService: updateService,
            hotkeyManager: hotkeyManager,
            onApplyHotkey: { [weak self] in self?.registerGlobalHotkey() },
            onModulesChanged: { [weak self] in
                self?.clockVM.refreshScheduling()
                self?.statusBarController.rebuildStatusItems()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WenBar 设置"
        window.minSize = NSSize(width: 580, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        self.settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func openOnboardingWindow() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(calendarVM: calendarVM) { [weak self] in
            self?.settingsStore.settings.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 410),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WenBar 权限检测与引导"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        self.onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openCustomCompressWindow(sources: [URL]) {
        customCompressWindow?.close()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "加密 / 自定义压缩"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: CustomCompressView(
                sources: sources,
                archiveManager: archiveManager,
                settingsStore: settingsStore,
                onClose: { [weak window] in window?.close() }
            )
        )
        self.customCompressWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observePasswordPrompts() {
        Task { [weak self] in
            while let self {
                if let req = self.archiveManager.pendingPasswordRequest {
                    self.archiveManager.pendingPasswordRequest = nil
                    self.openPasswordWindow(request: req)
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func openPasswordWindow(request: PasswordPromptRequest) {
        passwordWindow?.close()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "输入解压密码"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: PasswordPromptView(
                request: request,
                onSubmit: { [weak self, weak window] pwd in
                    window?.close()
                    self?.archiveManager.enqueueExtract(
                        archives: [request.archiveURL],
                        mode: request.mode,
                        trashAfterExtract: request.trashAfterExtract,
                        password: pwd
                    )
                },
                onCancel: { [weak window] in
                    window?.close()
                }
            )
        )
        self.passwordWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
