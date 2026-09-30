import Foundation
import Darwin

struct CodexClient {
    static func executable(custom: String) -> String? {
        if !custom.isEmpty { return FileManager.default.isExecutableFile(atPath: custom) ? custom : nil }
        let paths = [ "/opt/homebrew/bin/codex", "/usr/local/bin/codex", NSHomeDirectory() + "/.local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex"]
        return paths.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func fetch(path: String) throws -> Snapshot {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice // Never log authentication or server diagnostics.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            // Bound shutdown; kill only the child created for this single read.
            for _ in 0..<10 { if !process.isRunning { break }; usleep(20_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        let deadline = Date().addingTimeInterval(25)
        var buffer = Data()
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func response(id: Int) throws -> [String: Any] {
            while Date() < deadline {
                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.subdata(in: 0..<newline)
                    buffer.removeSubrange(0...newline)
                    guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any], value["id"] as? Int == id else { continue }
                    if let error = value["error"] as? [String: Any] {
                        let code = error["code"] as? Int ?? 0
                        throw UsageError.message("Codex 無法讀取額度（\(code)）。請確認已用 ChatGPT 訂閱帳號登入，或稍後重試。")
                    }
                    guard let result = value["result"] as? [String: Any] else { throw UsageError.message("Codex 回應格式不符，請確認 CLI 版本。") }
                    return result
                }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&descriptor, 1, 200)
                if ready < 0 { if errno == EINTR { continue }; throw UsageError.message("讀取 Codex 程序失敗。") }
                if ready > 0 {
                    var chunk = [UInt8](repeating: 0, count: 8192)
                    let count = Darwin.read(descriptor.fd, &chunk, chunk.count)
                    guard count > 0 else { throw UsageError.message("Codex 程序已結束，請檢查 CLI 登入狀態與設定。") }
                    buffer.append(contentsOf: chunk.prefix(count))
                    if buffer.count > 2_000_000 { throw UsageError.message("Codex 回應超過預期大小。") }
                }
            }
            throw UsageError.message("連線逾時。請確認網路正常，再重新整理。")
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "ai_usage_bar", "title": "AI Usage Bar", "version": "1.1.0"]]])
        _ = try response(id: 1)
        try send(["method": "initialized", "params": [:]])
        try send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
        let account = try response(id: 2)
        guard let details = account["account"] as? [String: Any], details["type"] as? String != "apiKey" else {
            throw UsageError.message("請先在 Codex CLI 以 ChatGPT 訂閱帳號登入：codex login。")
        }
        try send(["id": 3, "method": "account/rateLimits/read"])
        var snapshot = try CodexParser.parse(response(id: 3))
        snapshot.account = details["email"] as? String
        return snapshot
    }
}
