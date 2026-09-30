import Foundation

/// Reads Claude subscription usage with the login Claude Code already stores in the Keychain.
/// The token stays in memory for one request; it is never saved, logged or refreshed by this app.
/// Token refresh is left to Claude Code itself (`claude auth status`), so its stored login is never raced.
struct ClaudeClient {
    static func executable() -> String? {
        let home = NSHomeDirectory()
        let paths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", home + "/.local/bin/claude", home + "/.claude/local/claude"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    private struct Credential { var token: String; var expiresAt: Date?; var plan: String? }
    private enum Failure: Error { case unauthorized }

    static func fetch() throws -> Snapshot {
        var credential = try readCredential()
        if let expiry = credential.expiresAt, expiry < Date().addingTimeInterval(60) {
            refreshThroughClaudeCode()
            credential = try readCredential()
        }
        do { return try request(credential) }
        catch Failure.unauthorized {
            refreshThroughClaudeCode()
            do { return try request(readCredential()) }
            catch Failure.unauthorized { throw UsageError.message("Claude 登入已過期。請在終端機執行 claude，完成登入後再更新。") }
        }
    }

    private static func readCredential() throws -> Credential {
        // /usr/bin/security is the tool Claude Code itself uses, so the Keychain item stays readable without new prompts.
        guard let data = run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 10),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw UsageError.message("找不到 Claude Code 登入。請在終端機執行 claude，以 Claude 訂閱帳號登入。")
        }
        let expiry = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credential(token: token, expiresAt: expiry, plan: oauth["subscriptionType"] as? String)
    }

    private static func refreshThroughClaudeCode() {
        guard let path = executable() else { return }
        _ = run(path, ["auth", "status"], timeout: 20)
    }

    private static func request(_ credential: Credential) throws -> Snapshot {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 25)
        request.setValue("Bearer " + credential.token, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ai-usage-bar/1.1.0", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var body: Data?, status = 0, networkError: Error?
        URLSession.shared.dataTask(with: request) { data, response, error in
            body = data; status = (response as? HTTPURLResponse)?.statusCode ?? 0; networkError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if networkError != nil { throw UsageError.message("連線失敗。請確認網路正常，再重新整理。") }
        switch status {
        case 200: break
        case 401, 403: throw Failure.unauthorized
        case 429: throw UsageError.message("Claude 用量查詢過於頻繁，稍後會自動重試。")
        default: throw UsageError.message("Claude 無法讀取用量（HTTP \(status)），稍後重試。")
        }
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw UsageError.message("Claude 回應格式不符。")
        }
        var snapshot = try ClaudeParser.parse(object)
        snapshot.plan = credential.plan.map { "Claude " + $0.capitalized }
        return snapshot
    }

    /// Runs a short-lived helper with a hard deadline; output is small, so the pipe cannot fill.
    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate(); process.waitUntilExit(); return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return process.terminationStatus == 0 ? data : nil
    }
}

enum ClaudeParser {
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
    static func parse(_ object: [String: Any]) throws -> Snapshot {
        var result = Snapshot(source: "Claude Code 登入")
        for (key, title) in [("five_hour", "本次 · 5 小時"), ("seven_day", "本週 · 7 天"), ("seven_day_opus", "本週 · Opus"), ("seven_day_sonnet", "本週 · Sonnet")] {
            guard let window = object[key] as? [String: Any] else { continue }
            result.quotas.append(Quota(id: "claude.\(key)", title: title, used: window["utilization"] as? Double, resetsAt: date(window["resets_at"])))
        }
        guard !result.quotas.isEmpty else { throw UsageError.message("已連接，但 Claude 未提供可顯示的額度視窗。") }
        // Cloud session credits: a fixed dollar grant with an expiry (the API names this bucket internally).
        if let cloud = object["iguana_necktie"] as? [String: Any], let limit = cloud["limit_dollars"] as? Double {
            result.credits.append(Credit(id: "claude.cloud", title: "雲端 credits", detail: "到期", balance: cloud["remaining_dollars"] as? Double, currency: "USD", used: cloud["used_dollars"] as? Double, limit: limit, resetsAt: date(cloud["resets_at"])))
        }
        if let extra = object["extra_usage"] as? [String: Any] {
            let scale = pow(10, extra["decimal_places"] as? Double ?? 2)
            let enabled = extra["is_enabled"] as? Bool
            let capped = extra["spend_limit_reached"] as? Bool == true
            let status = capped ? (enabled == true ? "已達上限" : "已達上限 · 暫停") : enabled == true ? "已啟用" : enabled == false ? "未啟用" : "狀態未知"
            result.credits.append(Credit(id: "claude.extra", title: "Usage credits", detail: status, balance: nil, currency: extra["currency"] as? String ?? "USD", used: (extra["used_credits"] as? Double).map { $0 / scale }, limit: (extra["monthly_limit"] as? Double).map { $0 / scale }))
        }
        return result
    }
}
