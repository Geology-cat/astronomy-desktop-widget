import AppKit
import CoreGraphics

/// macOS 13 版の AppDelegate と同じ構成（デスクトップ上のパネルとメニューバーのアイコン）です。
final class LegacyAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: DesktopPanel?
    private var widgetView: LegacyWidgetView?
    private var settingsWindowController: LegacySettingsWindowController?
    private var statusItem: NSStatusItem?
    private var model: AstronomyViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = AstronomyViewModel()
        self.model = model
        createPanel(model: model)
        createStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openAstronomySettings,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    private func createPanel(model: AstronomyViewModel) {
        let view = LegacyWidgetView(model: model)
        let panel = DesktopPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 470),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("AstronomyDesktopWidgetFrame")
        let restoredFrame = panel.setFrameUsingName("AstronomyDesktopWidgetFrame")
        self.panel = panel
        self.widgetView = view
        resizePanelToFit(preserveTopEdge: restoredFrame)
        if !restoredFrame {
            positionAtTopRight(panel)
        }

        view.onLayoutChange = { [weak self] in
            DispatchQueue.main.async { self?.resizePanelToFit(preserveTopEdge: true) }
        }
        model.onChange = { [weak view] in view?.render() }
        panel.orderFrontRegardless()
    }

    private func resizePanelToFit(preserveTopEdge: Bool) {
        guard let panel = panel, let view = widgetView else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size.width > 100, size.height > 100 else { return }
        var frame = panel.frame
        let topEdge = frame.maxY
        frame.size = size
        if preserveTopEdge { frame.origin.y = topEdge - size.height }
        if let screen = panel.screen ?? NSScreen.main {
            frame = panel.constrainFrameRect(frame, to: screen)
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func positionAtTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 24,
            y: visible.maxY - panel.frame.height - 24
        ))
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = Icon.statusBarImage()
        image.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "天文情報ウィジェット"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "ウィジェットを隠す", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "今すぐ更新", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "天文情報ウィジェットを終了", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first?.title = panel?.isVisible == true ? "ウィジェットを隠す" : "ウィジェットを表示"
    }

    @objc private func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func refresh() {
        model?.refreshNow()
    }

    @objc private func openSettings() {
        guard let model = model else { return }
        if settingsWindowController == nil {
            settingsWindowController = LegacySettingsWindowController(model: model)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.present()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
