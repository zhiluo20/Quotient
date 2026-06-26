import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// 面板最小高度：保证视觉上至少完整露出第一行服务卡片（标题 + 一行窗口 + padding）
    private static let minPanelHeight: CGFloat = 120

    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let store = UsageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
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
        panel.minSize = NSSize(width: 400, height: Self.minPanelHeight)
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true

        // 不用 .preferredContentSize：那会让窗口高度被 SwiftUI 内容撑满，
        // 用户每次拖拽都被还原。让 hosting view 直接跟随窗口 frame（默认行为），
        // 高度才完全交给用户控制。
        let host = NSHostingView(rootView: ContentView().environmentObject(store))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
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
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
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
                // 恢复时同样按最小高度钳制，避免存下的尺寸过小
                let clamped = NSRect(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: max(frame.width, panel.minSize.width),
                    height: max(frame.height, Self.minPanelHeight)
                )
                panel.setFrame(clamped, display: false)
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

extension AppDelegate: NSWindowDelegate {
    /// 兜底：即便设置了 minSize，用户快速拖拽仍可能瞬时低于阈值，这里再夹紧一次，
    /// 保证面板永远不会被拖到「看不见第一行内容」的高度。
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.frame.height < Self.minPanelHeight
        else { return }
        var frame = window.frame
        // 保持顶部边沿不动，向下补足高度，视觉上更稳
        frame.origin.y -= Self.minPanelHeight - frame.height
        frame.size.height = Self.minPanelHeight
        window.setFrame(frame, display: false)
    }
}

/// 无边框面板默认不能成为 key window，按钮仍可点击但不抢编辑器焦点
/// 由于没有标题栏，系统不会提供边框缩放手柄，这里手动实现底部 + 四角热区拖拽。
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 缩放热区宽度（pt）
    private let edgeSize: CGFloat = 8
    /// 最小高度由外部通过 minSize 约束，这里读取同一个值
    private var minHeight: CGFloat { minSize.height }

    private enum ResizeEdge {
        case none, bottom, left, right, bottomLeft, bottomRight
    }
    private var resizing: ResizeEdge = .none
    private var dragStart: NSPoint = .zero
    private var startFrame: NSRect = .zero

    /// 根据当前鼠标位置（窗口坐标）判断命中的缩放边缘。
    /// 注意 AppKit 窗口坐标系原点在左下角。
    private func resizeEdge(at point: NSPoint) -> ResizeEdge {
        let bounds = frame.size
        let nearLeft = point.x <= edgeSize
        let nearRight = point.x >= bounds.width - edgeSize
        let nearBottom = point.y <= edgeSize
        switch (nearBottom, nearLeft, nearRight) {
        case (true, true, _):   return .bottomLeft
        case (true, _, true):   return .bottomRight
        case (true, _, _):      return .bottom
        case (false, true, _):  return .left
        case (false, _, true):  return .right
        default:                return .none
        }
    }

    private func cursor(for edge: ResizeEdge) -> NSCursor {
        switch edge {
        case .bottom, .none:        return .arrow
        case .left, .right:         return .resizeLeftRight
        case .bottomLeft:           return .crosshair
        case .bottomRight:          return .crosshair
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convertPoint(fromScreen: NSEvent.mouseLocation)
        let edge = resizeEdge(at: point)
        if edge != .none {
            resizing = edge
            dragStart = NSEvent.mouseLocation
            startFrame = frame
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard resizing != .none else {
            super.mouseDragged(with: event)
            return
        }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStart.x
        let dy = now.y - dragStart.y

        var f = startFrame
        // 左右调整宽度（受最小宽度约束）
        if resizing == .left || resizing == .bottomLeft {
            let newWidth = max(minSize.width, startFrame.width - dx)
            f.origin.x = startFrame.maxX - newWidth
            f.size.width = newWidth
        }
        if resizing == .right || resizing == .bottomRight {
            f.size.width = max(minSize.width, startFrame.width + dx)
        }
        // 底部调整高度：向上拖增加高度，向下拖减小高度（受最小高度约束）
        let touchesBottom = (resizing == .bottom || resizing == .bottomLeft || resizing == .bottomRight)
        if touchesBottom {
            let newHeight = max(minHeight, startFrame.height - dy)
            f.origin.y = startFrame.maxY - newHeight
            f.size.height = newHeight
        }
        setFrame(f, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        if resizing != .none { resizing = .none }
        super.mouseUp(with: event)
    }

    /// 鼠标移动时切换光标，提示可缩放区域
    override func mouseMoved(with event: NSEvent) {
        let point = convertPoint(fromScreen: NSEvent.mouseLocation)
        cursor(for: resizeEdge(at: point)).set()
        super.mouseMoved(with: event)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
