import AppKit
import SwiftUI
import Combine

signal(SIGPIPE, SIG_IGN)

if CommandLine.arguments.contains("--self-test") {
    SelfTests.run()
    exit(0)
}
if CommandLine.arguments.contains("--probe") {
    // Intentionally omit account identifiers and credentials.
    var ok = true
    for provider in Provider.allCases {
        do {
            let snapshot: Snapshot
            switch provider {
            case .codex:
                guard let path = CodexClient.executable(custom: "") else { print("Codex: CLI not found"); ok = false; continue }
                snapshot = try CodexClient.fetch(path: path)
            case .claude:
                snapshot = try ClaudeClient.fetch()
            }
            for quota in snapshot.quotas { print("\(provider.name) \(quota.title): remaining=\(quota.remaining.map { String($0) } ?? "unknown"), reset=\(quota.resetsAt?.description ?? "unknown")") }
            for credit in snapshot.credits { print("\(provider.name) \(credit.title): balance=\(credit.balance.map { String($0) } ?? "-"), used=\(credit.used.map { String($0) } ?? "-"), limit=\(credit.limit.map { String($0) } ?? "-"), status=\(credit.detail)") }
        } catch { print("\(provider.name): \(error.localizedDescription)"); ok = false }
    }
    exit(ok ? 0 : 1)
}

if let flag = CommandLine.arguments.firstIndex(of: "--render-icons"), flag + 1 < CommandLine.arguments.count {
    // Contact sheet: one row per icon style, every animation frame, 4× scale.
    let scale: CGFloat = 4, cell = NSSize(width: MenuIcon.size.width * scale, height: MenuIcon.size.height * scale)
    let columns = IconStyle.allCases.map(\.frameCount).max() ?? 1
    let sheet = NSImage(size: NSSize(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(IconStyle.allCases.count)), flipped: true) { _ in
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: cell.width * CGFloat(columns), height: cell.height * CGFloat(IconStyle.allCases.count)).fill()
        for (row, style) in IconStyle.allCases.enumerated() {
            for (column, frame) in style.frames.enumerated() {
                frame.draw(in: NSRect(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height, width: cell.width, height: cell.height))
            }
        }
        return true
    }
    guard let tiff = sheet.tiffRepresentation, let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { exit(1) }
    do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1])) }
    catch { fputs("Cannot save icons\n", stderr); exit(1) }
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"), flag + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let dark = CommandLine.arguments.contains("--dark")
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let store = UsageStore(preview: true)
        // --settings renders the settings window at a short height to check that it scrolls
        let settings = CommandLine.arguments.contains("--settings")
        let size = settings ? NSSize(width: 470, height: 520) : NSSize(width: 390, height: 720)
        let panel: AnyView = settings ? AnyView(SettingsPanel(store: store)) : AnyView(UsagePanel(store: store, openSettings: {}))
        let view = panel.environment(\.colorScheme, dark ? .dark : .light).frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1])) }
        catch { fputs("Cannot save preview\n", stderr); exit(1) }
    }
    exit(0)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    var popover: NSPopover!
    var settings: NSWindow?
    var previewWindow: NSWindow?
    var store: UsageStore!
    private var iconTimer: Timer?
    private var iconFrame = 0
    private var iconInterval: TimeInterval = 0
    private var iconFrames = IconStyle.cat.frames
    private var observers: [AnyCancellable] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        store = UsageStore(preview: CommandLine.arguments.contains("--preview"))
        NSApp.setActivationPolicy(.accessory)
        store.applyAppearance()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        iconFrames = store.iconStyle.frames
        status.button?.image = iconFrames[0]
        status.button?.toolTip = "Claude 與 Codex 用量監控"
        status.button?.target = self
        status.button?.action = #selector(togglePanel)
        store.$states.receive(on: RunLoop.main).sink { [weak self] states in
            let used = states.values.flatMap { $0.snapshot?.quotas ?? [] }.compactMap(\.used).max()
            self?.runIcon(every: MenuIcon.frameInterval(usedPercent: used))
        }.store(in: &observers)
        store.$iconStyle.dropFirst().sink { [weak self] style in
            guard let self else { return }
            iconFrames = style.frames; iconFrame = 0
            status.button?.image = iconFrames[0]
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
            .sink { [weak self] _ in guard let self else { return }; let interval = iconInterval; iconInterval = 0; runIcon(every: interval) }
            .store(in: &observers)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: UsagePanel(store: store, openSettings: { [weak self] in self?.showSettings() }))
        popover.contentSize = NSSize(width: 390, height: 720)
        if CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--window") {
            let controller = NSHostingController(rootView: UsagePanel(store: store, openSettings: { [weak self] in self?.showSettings() }))
            let window = NSWindow(contentViewController: controller)
            window.title = store.preview ? "AI Usage Bar — 示範預覽" : "AI Usage Bar"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.setContentSize(NSSize(width: 390, height: 720))
            window.center(); window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
        }
    }
    /// Faster frames as the highest quota fills up; a still icon when Reduce Motion is on.
    func runIcon(every interval: TimeInterval) {
        guard abs(interval - iconInterval) > 0.005 else { return }
        iconInterval = interval
        iconTimer?.invalidate(); iconTimer = nil
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { status.button?.image = iconFrames[0]; return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.iconFrame = (self.iconFrame + 1) % self.iconFrames.count
                self.status.button?.image = self.iconFrames[self.iconFrame]
            }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        iconTimer = timer
    }
    @objc func togglePanel() {
        guard let button = status.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            store.refresh()
            // Without an explicit appearance the popover follows the menu bar, not the app setting.
            popover.appearance = NSApp.appearance
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func showSettings() {
        popover.performClose(nil)
        if settings == nil {
            let controller = NSHostingController(rootView: SettingsPanel(store: store))
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "AI Usage Bar 設定"
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            // Fit the screen; content scrolls when it is taller than this
            let available = (NSScreen.main?.visibleFrame.height ?? 800) - 60
            window.setContentSize(NSSize(width: 470, height: min(720, available)))
            window.contentMinSize = NSSize(width: 470, height: 320)
            window.contentMaxSize = NSSize(width: 470, height: CGFloat.greatestFiniteMagnitude)
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
