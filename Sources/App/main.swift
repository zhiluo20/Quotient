import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let store = UsageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 384, height: 180),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = store.pinned ? .floating : .normal
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: ContentView().environmentObject(store))
        host.sizingOptions = .preferredContentSize
        panel.contentView = host

        restoreFrame(panel)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { _ in
            Task { @MainActor in
                UserDefaults.standard.set(
                    NSStringFromRect(panel.frame), forKey: "panelFrame")
            }
        }

        setupStatusItem()

        store.onPinChange = { [weak panel] pinned in
            panel?.level = pinned ? .floating : .normal
        }
        store.onHiddenChange = { [weak self] hidden in
            guard let self else { return }
            if hidden {
                self.panel.orderOut(nil)
            } else {
                self.panel.orderFrontRegardless()
            }
        }
        store.onLedChange = { [weak self] led in
            self?.statusItem.button?.image = Self.ledImage(led)
        }
        store.onOpenSettings = { [weak self] in
            self?.showSettings()
        }

        if !store.hidden {
            panel.orderFrontRegardless()
        }
        self.panel = panel
        store.start()
    }

    // MARK: - 菜单栏状态灯与菜单

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.ledImage(.gray)
        statusItem.button?.toolTip = "Quotient"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menu.removeAllItems()
            let lang = store.lang

            let toggle = NSMenuItem(
                title: L10n.t(store.hidden ? "show_panel" : "hide_panel", lang),
                action: #selector(togglePanel), keyEquivalent: "")
            let about = NSMenuItem(
                title: L10n.t("about", lang),
                action: #selector(showAbout), keyEquivalent: "")
            let settings = NSMenuItem(
                title: L10n.t("settings", lang),
                action: #selector(showSettingsAction), keyEquivalent: ",")
            let quit = NSMenuItem(
                title: L10n.t("quit", lang),
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

            for item in [toggle, about, settings] { item.target = self }

            menu.addItem(toggle)
            menu.addItem(.separator())
            menu.addItem(about)
            menu.addItem(settings)
            menu.addItem(.separator())
            menu.addItem(quit)
        }
    }

    @objc private func togglePanel() {
        store.hidden.toggle()
    }

    // MARK: - About / Settings

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: L10n.t("credits", store.lang),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ])
    }

    @objc private func showSettingsAction() {
        showSettings()
    }

    private func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(
                rootView: SettingsView().environmentObject(store))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.title = L10n.t("settings_title", store.lang)
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 杂项

    private static func ledImage(_ led: Led) -> NSImage {
        let color: NSColor
        switch led {
        case .green:  color = NSColor(red: 0.20, green: 0.90, blue: 0.45, alpha: 1)
        case .yellow: color = NSColor(red: 1.00, green: 0.80, blue: 0.15, alpha: 1)
        case .red:    color = NSColor(red: 1.00, green: 0.27, blue: 0.27, alpha: 1)
        case .gray:   color = NSColor.secondaryLabelColor
        }
        let size = NSSize(width: 11, height: 11)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func restoreFrame(_ panel: NSPanel) {
        if let saved = UserDefaults.standard.string(forKey: "panelFrame") {
            let frame = NSRectFromString(saved)
            if frame.width > 0 {
                panel.setFrameOrigin(frame.origin)
                return
            }
        }
        // 默认放在主屏右上角
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: v.maxX - panel.frame.width - 24,
                y: v.maxY - panel.frame.height - 24
            ))
        }
    }
}

/// 无边框面板默认不能成为 key window，按钮仍可点击但不抢编辑器焦点
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
