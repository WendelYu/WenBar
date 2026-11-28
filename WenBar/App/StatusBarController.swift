import Cocoa
import SwiftUI
import WenBarCore

private final class FloatingMenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController: NSObject {
    private let panel: FloatingMenuBarPanel
    private let hostingController: NSHostingController<AnyView>
    private let panelSize: NSSize
    private weak var anchorButton: NSStatusBarButton?

    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var lastOpenedAt: Date = .distantPast
    private let onWillShow: (() -> Void)?

    private let horizontalEdgeMargin: CGFloat = 14
    private let verticalBarGap: CGFloat = 8

    var isShown: Bool { panel.isVisible }

    init<Content: View>(panelSize: NSSize, onWillShow: (() -> Void)? = nil, rootView: Content) {
        self.panelSize = panelSize
        self.onWillShow = onWillShow
        let wrapped = AnyView(
            rootView
                .frame(width: panelSize.width, height: panelSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
        )
        let hc = NSHostingController(rootView: wrapped)
        hc.sizingOptions = []
        self.hostingController = hc

        let p = FloatingMenuBarPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.isMovable = false
        p.contentViewController = hc
        self.panel = p

        super.init()
    }

    func show(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        lastOpenedAt = Date()
        onWillShow?()
        positionPanel(relativeTo: button)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitors()
    }

    func close() {
        removeDismissMonitors()
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonRectInWindow)

        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let panelWidth = panelSize.width
        let panelHeight = min(panelSize.height, visibleFrame.height - 28)

        var x = buttonScreenRect.midX - panelWidth / 2
        let minX = visibleFrame.minX + horizontalEdgeMargin
        let maxX = visibleFrame.maxX - panelWidth - horizontalEdgeMargin
        x = min(max(x, minX), max(minX, maxX))

        var y = buttonScreenRect.minY - panelHeight - verticalBarGap
        let minY = visibleFrame.minY + horizontalEdgeMargin
        y = max(y, minY)

        panel.setFrame(NSRect(x: round(x), y: round(y), width: panelWidth, height: panelHeight), display: true)
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible, self.panel.attachedSheet == nil else { return }
                if Date().timeIntervalSince(self.lastOpenedAt) < 0.15 {
                    return
                }
                let mouseLoc = NSEvent.mouseLocation
                if let btn = self.anchorButton, let btnWin = btn.window {
                    let btnScreenRect = btnWin.convertToScreen(btn.convert(btn.bounds, to: nil))
                    if btnScreenRect.contains(mouseLoc) {
                        return
                    }
                }
                if !self.panel.frame.contains(mouseLoc) {
                    self.close()
                }
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, self.panel.isKeyWindow, self.panel.attachedSheet == nil else {
                return event
            }
            if event.keyCode == 53 { // Escape
                self.close()
                return nil
            }
            return event
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible, self.panel.attachedSheet == nil else { return }
                if Date().timeIntervalSince(self.lastOpenedAt) < 0.25 {
                    return
                }
                self.close()
            }
        }
    }

    private func removeDismissMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    private var clockStatusItem: NSStatusItem?
    private var diskStatusItem: NSStatusItem?

    private var mainPanel: FloatingPanelController!
    private var diskPanel: FloatingPanelController!

    private let clockVM: ClockViewModel
    private let calendarVM: CalendarViewModel
    private let diskManager: ExternalDriveManager
    private let archiveManager: ArchiveTaskManager
    private let settingsStore: SettingsStore
    private let updateService: UpdateService

    private let onOpenSettings: () -> Void
    private let onOpenOnboarding: () -> Void
    private let onQuit: () -> Void

    private var displayLinkTimer: Timer?
    private var lastClockRenderSignature: String = ""
    private var lastDiskBadgeCount: Int?

    init(
        clockVM: ClockViewModel,
        calendarVM: CalendarViewModel,
        diskManager: ExternalDriveManager,
        archiveManager: ArchiveTaskManager,
        settingsStore: SettingsStore,
        updateService: UpdateService,
        onOpenSettings: @escaping () -> Void,
        onOpenOnboarding: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.clockVM = clockVM
        self.calendarVM = calendarVM
        self.diskManager = diskManager
        self.archiveManager = archiveManager
        self.settingsStore = settingsStore
        self.updateService = updateService
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
        self.onQuit = onQuit
        super.init()

        configurePanels()
        rebuildStatusItems()
        startTitleSyncTimer()
    }

    func rebuildStatusItems() {
        if clockStatusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.target = self
                button.action = #selector(handleClockButtonClick(_:))
                button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            }
            clockStatusItem = item
        }

        lastClockRenderSignature = ""
        updateClockButtonTitle()
        updateStandaloneDiskItem()
    }

    func updateStandaloneDiskItem() {
        let shouldShow = settingsStore.settings.enableDiskManager
            && settingsStore.settings.showStandaloneDiskIcon
            && !diskManager.externalVolumes.isEmpty

        if shouldShow {
            let count = diskManager.externalVolumes.count
            if diskStatusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.image = NSImage(
                        systemSymbolName: "externaldrive.fill.badge.minus",
                        accessibilityDescription: "外接磁盘"
                    )
                    button.target = self
                    button.action = #selector(handleDiskButtonClick(_:))
                    button.sendAction(on: [.leftMouseDown, .rightMouseDown])
                }
                diskStatusItem = item
                lastDiskBadgeCount = nil
            }
            if lastDiskBadgeCount != count {
                lastDiskBadgeCount = count
                diskStatusItem?.button?.title = " \(count)"
            }
        } else {
            lastDiskBadgeCount = nil
            if let existing = diskStatusItem {
                NSStatusBar.system.removeStatusItem(existing)
                diskStatusItem = nil
            }
            if diskPanel.isShown {
                diskPanel.close()
            }
        }
    }

    func toggleMainPopover() {
        if mainPanel.isShown {
            mainPanel.close()
        } else if let button = clockStatusItem?.button {
            if diskPanel.isShown { diskPanel.close() }
            mainPanel.show(relativeTo: button)
        }
    }

    private func configurePanels() {
        mainPanel = FloatingPanelController(
            panelSize: NSSize(width: 420, height: 640),
            onWillShow: { [weak self] in
                self?.calendarVM.refreshForPanelOpen()
                self?.clockVM.refreshScheduling()
            },
            rootView: MainPopoverView(
                clockVM: clockVM,
                calendarVM: calendarVM,
                diskManager: diskManager,
                archiveManager: archiveManager,
                settingsStore: settingsStore,
                updateService: updateService,
                onOpenSettings: { [weak self] in
                    self?.mainPanel.close()
                    self?.onOpenSettings()
                },
                onOpenOnboarding: { [weak self] in
                    self?.mainPanel.close()
                    self?.onOpenOnboarding()
                }
            )
        )

        diskPanel = FloatingPanelController(
            panelSize: NSSize(width: 370, height: 380),
            rootView: DiskPopoverView(diskManager: diskManager, settingsStore: settingsStore)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(.regularMaterial)
        )
    }

    private func startTitleSyncTimer() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateClockButtonTitle()
                self?.updateStandaloneDiskItem()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayLinkTimer = timer
    }

    private func updateClockButtonTitle() {
        guard let button = clockStatusItem?.button else { return }
        let settings = settingsStore.settings
        var text = clockVM.menuBarTitle

        if let task = archiveManager.activeTask, settings.showArchiveProgressInMenuBar {
            let pct = task.isIndeterminate ? "…" : "\(Int(task.fraction * 100))%"
            text += " 📦\(pct)"
        }

        let signature = "\(text)|\(settings.clockShowCalendarIcon)|\(settings.clockFontSize)|\(settings.clockFontWeight.rawValue)|\(settings.clockUseMonospacedDigits)"
        guard signature != lastClockRenderSignature else { return }
        lastClockRenderSignature = signature

        if settings.clockShowCalendarIcon {
            let icon = NSImage(systemSymbolName: "calendar", accessibilityDescription: "WenBar")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
        }

        let isTwoLine = text.contains("\n")
        let baseSize = CGFloat(settings.clockFontSize)
        let effectiveSize = isTwoLine ? max(9.5, baseSize - 3.5) : baseSize
        let nsWeight = mapFontWeight(settings.clockFontWeight)
        let font = settings.clockUseMonospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: effectiveSize, weight: nsWeight)
            : NSFont.systemFont(ofSize: effectiveSize, weight: nsWeight)

        let paragraph = NSMutableParagraphStyle()
        if isTwoLine {
            paragraph.alignment = .center
            paragraph.lineSpacing = -1.5
            paragraph.maximumLineHeight = effectiveSize + 1.5
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    private func mapFontWeight(_ option: ClockFontWeightOption) -> NSFont.Weight {
        switch option {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    @objc private func handleClockButtonClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseDown {
            showContextMenu(from: sender)
        } else {
            toggleMainPopover()
        }
    }

    @objc private func handleDiskButtonClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseDown {
            showContextMenu(from: sender)
        } else if diskPanel.isShown {
            diskPanel.close()
        } else {
            if mainPanel.isShown { mainPanel.close() }
            diskPanel.show(relativeTo: sender)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开日历面板", action: #selector(menuOpenPopover), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "权限检查与引导…", action: #selector(menuOpenOnboarding), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 WenBar", action: #selector(menuQuit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func menuOpenPopover() { toggleMainPopover() }
    @objc private func menuOpenSettings() { onOpenSettings() }
    @objc private func menuOpenOnboarding() { onOpenOnboarding() }
    @objc private func menuQuit() { onQuit() }
}
