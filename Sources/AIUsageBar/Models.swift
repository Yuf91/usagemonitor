import Foundation

struct Quota: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var used: Double?
    var resetText: String?
    var resetsAt: Date?
    var remaining: Double? { used.flatMap { $0.isFinite && $0 >= 0 && $0 <= 100 ? 100 - $0 : nil } }
}
struct Credit: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var balance: Double?
    var currency: String?
    var used: Double? = nil
    var limit: Double? = nil
    var resetsAt: Date? = nil
}
struct Snapshot: Codable, Equatable {
    var quotas: [Quota] = []
    var credits: [Credit] = []
    var capturedAt = Date()
    var source: String
    var account: String? = nil
    var plan: String? = nil
}
enum Provider: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var name: String { self == .claude ? "Claude" : "Codex" }
    /// Web usage page, opened only when the user clicks the provider icon.
    var usageURL: URL { URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/settings/usage?tab=overview")! }
    /// Codex keeps the original key so snapshots saved by 1.0 still load.
    var snapshotKey: String { self == .claude ? "claudeSnapshot" : "snapshot" }
}
/// App-only appearance, independent of the macOS setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: "跟隨系統"; case .light: "淺色"; case .dark: "深色" } }
}
struct ProviderState {
    var snapshot: Snapshot?
    var message: String
    var loading = false
    var failed = false
    func stale(at now: Date = Date(), maxAge: TimeInterval = 660) -> Bool {
        guard let snapshot else { return false }
        return failed || snapshot.source == "手動匯入" || now.timeIntervalSince(snapshot.capturedAt) > maxAge
    }
}
enum UsageError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

enum CodexParser {
    static func parse(_ object: [String: Any]) throws -> Snapshot {
        var result = Snapshot(source: "Codex App Server")
        let buckets: [String: Any]
        if let multiple = object["rateLimitsByLimitId"] as? [String: Any], !multiple.isEmpty { buckets = multiple }
        else if let single = object["rateLimits"] as? [String: Any] { buckets = [single["limitId"] as? String ?? "codex": single] }
        else { throw UsageError.message("此帳號尚未提供額度資料；請確認 Codex 使用訂閱帳號登入。") }
        for key in buckets.keys.sorted() {
            guard let bucket = buckets[key] as? [String: Any] else { continue }
            for (window, label) in [("primary", "短期額度"), ("secondary", "長期額度")] {
                guard let value = bucket[window] as? [String: Any] else { continue }
                let mins = value["windowDurationMins"] as? Double
                let span = mins.map { $0 >= 1440 ? String(format: "%.0f 天", $0 / 1440) : $0 >= 60 ? String(format: "%.0f 小時", $0 / 60) : String(format: "%.0f 分鐘", $0) }
                let name = key == "codex" ? "" : "\(bucket["limitName"] as? String ?? key) · "
                result.quotas.append(Quota(id: "\(key).\(window)", title: name + (span ?? label), used: value["usedPercent"] as? Double, resetsAt: (value["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }))
            }
        }
        guard !result.quotas.isEmpty else { throw UsageError.message("已連接，但服務未提供可顯示的額度視窗。") }
        return result
    }
}
