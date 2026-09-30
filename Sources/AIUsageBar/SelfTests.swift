import Foundation

enum SelfTests {
    static func run() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            count += 1
        }
        do {
            let data: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 99]], "rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 28, "windowDurationMins": 300, "resetsAt": 1900000000], "secondary": NSNull()], "review": ["limitName": "Review", "primary": ["usedPercent": 60, "windowDurationMins": 10080]]]]
            let wire = try JSONSerialization.data(withJSONObject: data)
            let payload = try JSONSerialization.jsonObject(with: wire) as! [String: Any]
            let snapshot = try CodexParser.parse(payload)
            check(snapshot.quotas.count == 2, "multi bucket preserved, null window skipped")
            check(snapshot.quotas[0].remaining == 72, "prefer multi bucket over legacy")
            check(snapshot.quotas[0].title == "5 小時", "dynamic window label")
            check(snapshot.quotas[0].resetsAt == Date(timeIntervalSince1970: 1900000000), "seconds not milliseconds")
            check(snapshot.quotas[1].title.contains("Review"), "keep bucket name")
            let unknown = try CodexParser.parse(["rateLimits": ["primary": ["usedPercent": NSNull()]]])
            check(unknown.quotas[0].remaining == nil, "null is not full quota")
            let invalid = Quota(id: "bad", title: "bad", used: 101)
            check(invalid.remaining == nil, "invalid usage is unknown")
            check(Quota(id: "zero", title: "zero", used: 0).remaining == 100, "zero used is full")
            check(Quota(id: "full", title: "full", used: 100).remaining == 0, "full used is zero")
            let encoded = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(Snapshot.self, from: encoded)
            check(decoded == snapshot, "snapshot round trip")
            check(ProviderState(snapshot: snapshot, message: "", failed: true).stale(), "failed read marks old data stale")
            var expired = snapshot; expired.capturedAt = Date().addingTimeInterval(-700)
            check(ProviderState(snapshot: expired, message: "").stale(), "expired snapshot")
            do { _ = try CodexParser.parse([:]); check(false, "missing payload rejects") } catch { check(true, "missing payload rejects") }
            let claudeData: [String: Any] = ["five_hour": ["utilization": 4.0, "resets_at": "2026-09-30T05:59:59.845156+00:00"], "seven_day": ["utilization": 6, "resets_at": "2026-10-01T03:59:59+00:00"], "seven_day_opus": NSNull(), "iguana_necktie": ["limit_dollars": 100, "used_dollars": 0.0, "remaining_dollars": 100.0, "resets_at": "2026-11-05T07:59:00+00:00"], "extra_usage": ["is_enabled": false, "monthly_limit": 2000, "used_credits": 1234.0, "decimal_places": 2, "currency": "USD", "spend_limit_reached": true]]
            let claude = try ClaudeParser.parse(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: claudeData)) as! [String: Any])
            check(claude.quotas.map(\.remaining) == [96, 94], "claude session and week, null window skipped")
            check(abs((claude.quotas[0].resetsAt?.timeIntervalSince1970 ?? 0) - 1790747999.845) < 0.01, "claude fractional reset time")
            check(claude.quotas[1].resetsAt != nil, "claude reset time without fraction")
            check(claude.credits.first { $0.id == "claude.cloud" }?.balance == 100, "cloud credits kept separate")
            let extra = claude.credits.first { $0.id == "claude.extra" }
            check(extra?.used == 12.34 && extra?.limit == 20 && extra?.balance == nil, "usage credits scaled, no fake balance")
            check(extra?.detail == "已達上限 · 暫停", "usage credits status")
            let bare = try ClaudeParser.parse(["five_hour": ["utilization": NSNull()]])
            check(bare.quotas[0].remaining == nil && bare.credits.isEmpty, "claude missing values stay unknown")
            do { _ = try ClaudeParser.parse(["extra_usage": [:]]); check(false, "claude without windows rejects") } catch { check(true, "claude without windows rejects") }
            print("PASS: \(count) checks")
        } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
}
