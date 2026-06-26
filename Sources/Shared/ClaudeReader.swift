import Foundation
import Security

/// 使用 Claude Code 已有的本地登录态查询官方 OAuth 用量接口。
///
/// 钥匙串只读策略：凭据存在 macOS 钥匙串里时，Quotient **绝不写入**。原因是写入
/// （SecItemUpdate）会重置该钥匙串记录的 ACL，导致所有“始终允许”失效、反复弹密码窗。
/// token 的刷新交给 Claude Code 自己（它是这条记录的属主，会自行续期）；Quotient 只读取
/// 当前 access token。只有当凭据来自普通文件（~/.claude/.credentials.json）时才会续期并写回，
/// 因为文件写入不涉及钥匙串 ACL。
///
/// 隐私：accessToken 只在内存中用于请求头，不向任何第三方上传，也不显示任何 token。
enum ClaudeReader {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let userAgent = "claude-cli/2.1.50 (external, cli)"

    static func read() async -> ServiceData {
        guard var cred = Credentials.load() else {
            return .unavailable(messageKey: "claude_not_logged_in")
        }

        // token 过期：仅当凭据来自文件（写回不影响钥匙串 ACL）才续期；
        // 钥匙串凭据保持只读，过期就当作暂时不可用、沿用上次缓存，等 Claude Code 自己刷新。
        if cred.isExpired {
            guard cred.writable else { return .unavailable(messageKey: "claude_offline") }
            switch await refresh(cred) {
            case .success(let updated): cred = updated
            case .needsLogin: return .unavailable(messageKey: "claude_expired")
            case .offline: return .unavailable(messageKey: "claude_offline")
            }
        }

        switch await fetchUsage(token: cred.accessToken) {
        case .ok(let obj):
            return parse(obj)
        case .unauthorized:
            // token 被服务端提前失效：可写则续一次重试，钥匙串只读则沿用缓存
            guard cred.writable else { return .unavailable(messageKey: "claude_offline") }
            switch await refresh(cred) {
            case .success(let updated):
                if case .ok(let obj) = await fetchUsage(token: updated.accessToken) {
                    return parse(obj)
                }
                return .unavailable(messageKey: "claude_error")
            case .needsLogin: return .unavailable(messageKey: "claude_expired")
            case .offline: return .unavailable(messageKey: "claude_offline")
            }
        case .offline:
            return .unavailable(messageKey: "claude_offline")
        case .error:
            return .unavailable(messageKey: "claude_error")
        }
    }

    // MARK: - 用量请求

    private enum UsageResult { case ok([String: Any]); case unauthorized; case offline; case error }

    private static func fetchUsage(token: String) async -> UsageResult {
        var req = URLRequest(url: usageURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            return .offline
        }
        guard let http = resp as? HTTPURLResponse else { return .error }
        if http.statusCode == 401 || http.statusCode == 403 { return .unauthorized }
        guard http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .error }
        return .ok(obj)
    }

    // MARK: - Token 续期

    private enum RefreshResult { case success(Credentials); case needsLogin; case offline }

    private static func refresh(_ cred: Credentials) async -> RefreshResult {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": cred.refreshToken,
        ])

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            return .offline
        }
        guard let http = resp as? HTTPURLResponse else { return .needsLogin }
        guard http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String
        else {
            // 4xx（invalid_grant 等）说明 refresh token 失效，只能重新登录
            return .needsLogin
        }
        let newRefresh = (obj["refresh_token"] as? String) ?? cred.refreshToken
        let expiresIn = (obj["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        var updated = cred
        updated.accessToken = access
        updated.refreshToken = newRefresh
        updated.expiresAtMs = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
        updated.persist()  // 立即写回，避免轮换后的 token 丢失
        return .success(updated)
    }

    // MARK: - 解析

    private static func parse(_ obj: [String: Any]) -> ServiceData {
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
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        return nil
    }
}

// MARK: - 凭据读写

/// Claude Code 的 OAuth 凭据，读自钥匙串或 ~/.claude/.credentials.json，
/// 续期后原样写回同一位置（保留其余字段），与 Claude Code 共享同一份登录态。
struct Credentials {
    var accessToken: String
    var refreshToken: String
    var expiresAtMs: Double
    /// 续期时需要原样保留的其他字段（scopes、subscriptionType 等）
    private var rawRoot: [String: Any]
    private var fromKeychain: Bool

    private static let service = "Claude Code-credentials"

    var isExpired: Bool {
        // 留 60 秒余量，避免临界点请求失败
        Date().timeIntervalSince1970 * 1000 >= expiresAtMs - 60_000
    }

    /// 是否可安全写回：仅文件凭据可写。钥匙串凭据只读，避免写入重置 ACL 触发反复弹窗。
    var writable: Bool { !fromKeychain }

    static func load() -> Credentials? {
        if let data = keychainData(), let c = decode(data, fromKeychain: true) { return c }
        if let data = fileData(), let c = decode(data, fromKeychain: false) { return c }
        return nil
    }

    private static func decode(_ data: Data, fromKeychain: Bool) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let access = oauth["accessToken"] as? String, !access.isEmpty,
              let refresh = oauth["refreshToken"] as? String, !refresh.isEmpty
        else { return nil }
        let exp = (oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0
        return Credentials(
            accessToken: access, refreshToken: refresh, expiresAtMs: exp,
            rawRoot: root, fromKeychain: fromKeychain)
    }

    /// 把续期后的 token 写回原存储位置，保留其余字段。
    /// 注意：**绝不写钥匙串**——写入会重置 ACL 触发反复弹密码窗。钥匙串凭据由 Claude Code
    /// 自己续期，Quotient 只读。仅文件凭据在这里写回。
    func persist() {
        guard !fromKeychain else { return }
        var root = rawRoot
        if var oauth = root["claudeAiOauth"] as? [String: Any] {
            oauth["accessToken"] = accessToken
            oauth["refreshToken"] = refreshToken
            oauth["expiresAt"] = expiresAtMs
            root["claudeAiOauth"] = oauth
        } else {
            root["accessToken"] = accessToken
            root["refreshToken"] = refreshToken
            root["expiresAt"] = expiresAtMs
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        try? data.write(to: url, options: .atomic)
    }

    private static func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func fileData() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }
}
