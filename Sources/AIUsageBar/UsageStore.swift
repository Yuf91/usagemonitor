import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement

@MainActor
final class UsageStore: ObservableObject {
    @Published var states: [Provider: ProviderState] = [.claude: ProviderState(message: "準備連接 Claude…"), .codex: ProviderState(message: "準備連接 Codex…")]
    @Published var interval: Double { didSet { UserDefaults.standard.set(interval, forKey: "interval"); schedule() } }
    @Published var customPath: String { didSet { UserDefaults.standard.set(customPath, forKey: "codexPath") } }
    @Published var notifications: Bool { didSet { UserDefaults.standard.set(notifications, forKey: "notifications") } }
    @Published var appearance: AppearanceMode { didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    @Published var iconStyle: IconStyle { didSet { UserDefaults.standard.set(iconStyle.rawValue, forKey: "iconStyle") } }
    @Published var settingsMessage = ""
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private struct Pacing { var lastAttempt = Date.distantPast; var failures = 0; var nextAttempt = Date.distantPast }
    private var pacing: [Provider: Pacing] = [.claude: Pacing(), .codex: Pacing()]
    private var timer: Timer?
    private var alerts: Set<String> = []
    private var wakeObserver: NSObjectProtocol?
    let preview: Bool
    subscript(provider: Provider) -> ProviderState { states[provider] ?? ProviderState(message: "") }
    var loading: Bool { states.values.contains { $0.loading } }
    var latestCapture: Date? { states.values.compactMap { $0.snapshot?.capturedAt }.max() }
    init(preview: Bool = false) {
        self.preview = preview
        let savedInterval = UserDefaults.standard.double(forKey: "interval")
        interval = [60.0, 300.0, 900.0].contains(savedInterval) ? savedInterval : 300
        customPath = UserDefaults.standard.string(forKey: "codexPath") ?? ""
        notifications = UserDefaults.standard.bool(forKey: "notifications")
        alerts = Set(UserDefaults.standard.stringArray(forKey: "sentAlerts") ?? [])
        iconStyle = IconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .cat
        appearance = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        if preview {
            states[.claude] = ProviderState(snapshot: Snapshot(quotas: [Quota(id: "claude.five_hour", title: "本次 · 5 小時", used: 4, resetsAt: Date().addingTimeInterval(9000)), Quota(id: "claude.seven_day", title: "本週 · 7 天", used: 6, resetsAt: Date().addingTimeInterval(95000))], credits: [Credit(id: "claude.cloud", title: "雲端 credits", detail: "到期", balance: 100, currency: "USD", used: 0, limit: 100, resetsAt: Date().addingTimeInterval(3_000_000)), Credit(id: "claude.extra", title: "Usage credits", detail: "未啟用", balance: nil, currency: "USD", used: 0, limit: 20)], source: "示範資料", plan: "Claude Pro"), message: "示範資料 · 非即時用量")
            states[.codex] = ProviderState(snapshot: Snapshot(quotas: [Quota(id: "codex.primary", title: "5 小時", used: 28, resetsAt: Date().addingTimeInterval(7380)), Quota(id: "codex.secondary", title: "7 天", used: 46, resetsAt: Date().addingTimeInterval(180000))], source: "示範資料"), message: "示範資料 · 非即時用量")
            return
        }
        for provider in Provider.allCases {
            if let data = UserDefaults.standard.data(forKey: provider.snapshotKey), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                states[provider] = ProviderState(snapshot: snapshot, message: "上次紀錄 · 等待更新", failed: true)
            }
        }
        schedule()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh(force: true) } }
        refresh(force: true)
    }
    /// nil lets windows and the popover follow macOS again.
    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    func schedule() {
        guard !preview else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh(force: Bool = false) {
        for provider in Provider.allCases { refresh(provider, force: force) }
    }
    func refresh(_ provider: Provider, force: Bool = false) {
        guard !preview, var state = states[provider], var pace = pacing[provider], !state.loading, Date().timeIntervalSince(pace.lastAttempt) > 5 else { return }
        if !force {
            guard Date() >= pace.nextAttempt, Date().timeIntervalSince(pace.lastAttempt) >= interval else { return }
        }
        let fetch: @Sendable () throws -> Snapshot
        switch provider {
        case .codex:
            guard let path = CodexClient.executable(custom: customPath) else {
                state.message = "找不到 Codex CLI，請在設定中選取執行檔。"; state.failed = true; states[provider] = state
                return
            }
            fetch = { try CodexClient.fetch(path: path) }
        case .claude:
            fetch = { try ClaudeClient.fetch() }
        }
        pace.lastAttempt = Date(); pacing[provider] = pace
        state.loading = true; states[provider] = state
        Task {
            let result = await Task.detached(priority: .utility) { Result { try fetch() } }.value
            switch result {
            case .success(let snapshot):
                pacing[provider]?.failures = 0; pacing[provider]?.nextAttempt = .distantPast
                states[provider] = ProviderState(snapshot: snapshot, message: "已連接 · 自動更新")
                if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: provider.snapshotKey) }
                await notifyIfNeeded(snapshot, provider: provider)
            case .failure(let error):
                let failures = (pacing[provider]?.failures ?? 0) + 1
                pacing[provider]?.failures = failures
                pacing[provider]?.nextAttempt = Date().addingTimeInterval(min(3600, interval * pow(2, Double(min(failures, 4)))))
                states[provider]?.loading = false; states[provider]?.failed = true; states[provider]?.message = error.localizedDescription
            }
        }
    }
    func enableNotifications(_ enabled: Bool) {
        if !enabled { notifications = false; return }
        Task {
            do {
                notifications = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                if !notifications { settingsMessage = "通知尚未允許，可在 macOS 系統設定中開啟。" }
            } catch { settingsMessage = "無法啟用通知：\(error.localizedDescription)" }
        }
    }
    private func notifyIfNeeded(_ snapshot: Snapshot, provider: Provider) async {
        guard notifications else { return }
        for quota in snapshot.quotas {
            guard let remaining = quota.remaining, let reset = quota.resetsAt, reset > Date() else { continue }
            let level = remaining <= 10 ? 10 : remaining <= 20 ? 20 : nil
            guard let level else { continue }
            // quota.id already carries the provider prefix (claude.* / codex.*), so keys never collide across services.
            let key = "\(snapshot.account ?? "current")|\(quota.id)|\(Int(reset.timeIntervalSince1970))|\(level)"
            guard !alerts.contains(key) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(provider.name) 額度提醒"
            content.body = "\(quota.title)額度剩餘 \(Int(remaining))%，可從選單列查看重置時間。"
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                alerts.insert(key)
                if alerts.count > 200 { alerts = [key] }
                UserDefaults.standard.set(Array(alerts), forKey: "sentAlerts")
            } catch { settingsMessage = "額度已更新，但通知傳送失敗。" }
        }
    }
    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { settingsMessage = "請在系統設定 → 登入項目允許 AI Usage Bar。" }
        } catch { settingsMessage = "無法變更登入項目：\(error.localizedDescription)" }
    }
    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "選擇 Codex CLI 執行檔"
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { settingsMessage = "所選檔案無法執行。"; return }
            customPath = url.path; refresh(.codex, force: true)
        }
    }
}
