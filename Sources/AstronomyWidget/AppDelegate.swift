import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: DesktopPanel?
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<AstronomyWidgetView>?
    private let model = AstronomyViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        createStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openAstronomySettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(widgetAppearanceChanged),
            name: .astronomyPreferencesChanged,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    private func createPanel() {
        let view = AstronomyWidgetView(model: model)
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]

        let panel = DesktopPanel(
            contentRect: NSRect(x: 0, y: 0, width: 452, height: 470),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        self.hostingView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("AstronomyDesktopWidgetFrame")
        let restoredFrame = panel.setFrameUsingName("AstronomyDesktopWidgetFrame")
        resizePanelToFit(panel, hostingView: hostingView, preserveTopEdge: restoredFrame)
        if !restoredFrame {
            positionAtTopRight(panel)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    @objc private func widgetAppearanceChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let hostingView = self.hostingView else { return }
            self.resizePanelToFit(panel, hostingView: hostingView, preserveTopEdge: true)
        }
    }

    private func resizePanelToFit(
        _ panel: NSPanel,
        hostingView: NSHostingView<AstronomyWidgetView>,
        preserveTopEdge: Bool
    ) {
        hostingView.layoutSubtreeIfNeeded()
        // NSHostingView は Auto Layout 制約を持たないため fittingSize が 0 になることがあり、
        // SwiftUI が算出した intrinsicContentSize を優先します。
        let intrinsic = hostingView.intrinsicContentSize
        let fittingSize = intrinsic.width > 100 && intrinsic.height > 100 ? intrinsic : hostingView.fittingSize
        guard fittingSize.width.isFinite, fittingSize.height.isFinite,
              fittingSize.width > 100, fittingSize.height > 100 else { return }
        var frame = panel.frame
        let topEdge = frame.maxY
        frame.size = fittingSize
        if preserveTopEdge { frame.origin.y = topEdge - fittingSize.height }
        if let screen = panel.screen ?? NSScreen.main {
            frame = panel.constrainFrameRect(frame, to: screen)
        }
        panel.setFrame(frame, display: true)
    }

    private func positionAtTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - panel.frame.width - 24,
            y: visible.maxY - panel.frame.height - 24
        )
        panel.setFrameOrigin(origin)
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "天文情報ウィジェット")
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
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func refresh() {
        model.refreshNow()
    }

    @objc private func openSettings() {
        if let window = settingsWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "天文情報ウィジェット設定"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
