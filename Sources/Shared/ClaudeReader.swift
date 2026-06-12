import Foundation
import Security

/// 使用 Claude Code 已有的本地登录态查询官方 OAuth 用量接口。
/// Token 只在内存中用于本次请求的 Authorization 头，不落盘、不展示、不上传到第三方。
enum ClaudeReader {
    static func read() async -> ServiceData {
        guard let token = loadAccessToken() else {
            return .unavailable(messageKey: "claude_not_logged_in")
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            return .unavailable(messageKey: "claude_offline")
        }
        guard let http = resp as? HTTPURLResponse else {
            return .unavailable(messageKey: "claude_error")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return .unavailable(messageKey: "claude_expired")
        }
        guard http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .unavailable(messageKey: "claude_error")
        }
        return parse(obj)
    }

    private static func parse(_ obj: [String: Any]) -> ServiceData {
        // 已知窗口键 -> (窗口分钟数, 附加标签键)
        let known: [(key: String, minutes: Int, extra: String?)] = [
            ("five_hour", 300, nil),
            ("seven_day", 10080, nil),
            ("seven_day_opus", 10080, "win_opus"),
        ]

        var windows: [WindowQuota] = []
        for spec in known {
            guard let w = obj[spec.key] as? [String: Any],
                  let used = CodexReader.doubleValue(w["utilization"])
            else { continue }
            windows.append(WindowQuota(
                id: "claude_\(spec.key)",
                windowMinutes: spec.minutes,
                labelKey: spec.extra,
                usedPercent: used,
                resetsAt: anyDate(w["resets_at"])
            ))
        }

        // 兜底：接口结构变化时，扫出所有带 utilization 的子对象
        if windows.isEmpty {
            for (key, value) in obj {
                guard let w = value as? [String: Any],
                      let used = CodexReader.doubleValue(w["utilization"])
                else { continue }
                windows.append(WindowQuota(
                    id: "claude_\(key)",
                    windowMinutes: nil,
                    labelKey: nil,
                    usedPercent: used,
                    resetsAt: anyDate(w["resets_at"])
                ))
            }
        }

        guard !windows.isEmpty else {
            return .unavailable(messageKey: "claude_error")
        }
        return .ready(plan: nil, windows: windows, asOf: Date())
    }

    private static func anyDate(_ any: Any?) -> Date? {
        if let s = any as? String { return CodexReader.parseISO(s) }
        if let n = (any as? NSNumber)?.doubleValue {
            // 区分秒级与毫秒级时间戳
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        return nil
    }

    // MARK: - 本地凭据

    private static func loadAccessToken() -> String? {
        for data in [credentialsFileData(), keychainData()] {
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let oauth = (obj["claudeAiOauth"] as? [String: Any]) ?? obj
            if let token = oauth["accessToken"] as? String, !token.isEmpty {
                return token
            }
        }
        return nil
    }

    private static func credentialsFileData() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }

    private static func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }
}
