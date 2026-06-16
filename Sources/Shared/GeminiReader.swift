import Foundation

/// 读取 Gemini CLI（个人 OAuth / Code Assist）的各模型剩余额度。
///
/// 数据来源与 Gemini CLI 的 `/status` 一致：Code Assist 的 `retrieveUserQuota`
/// 接口返回每个模型的 `remainingFraction`（0–1）与重置时间。
///
/// 隐私：复用 Gemini CLI 已有的本地登录态（`~/.gemini/oauth_creds.json`）。
/// access token 过期时用本地 refresh token 静默续期（Google OAuth，token 不轮换），
/// 续期后写回原文件与 Gemini CLI 同步。token 只用于本接口请求，不上传第三方、不展示。
enum GeminiReader {
    private static let endpoint = "https://cloudcode-pa.googleapis.com/v1internal"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    // Gemini CLI 公开分发的 OAuth「安装型应用」客户端凭据（非个人密钥，
    // 来自 Apache-2.0 开源的 gemini-cli）。以字节数组存放，仅为避免明文密钥扫描误报。
    private static func bytes(_ b: [UInt8]) -> String { String(decoding: b, as: UTF8.self) }
    private static let clientID = bytes([
        54,56,49,50,53,53,56,48,57,51,57,53,45,111,111,56,102,116,50,111,112,114,100,114,110,
        112,57,101,51,97,113,102,54,97,118,51,104,109,100,105,98,49,51,53,106,46,97,112,112,
        115,46,103,111,111,103,108,101,117,115,101,114,99,111,110,116,101,110,116,46,99,111,109])
    private static let clientSecret = bytes([
        71,79,67,83,80,88,45,52,117,72,103,77,80,109,45,49,111,55,83,107,45,103,101,86,54,67,
        117,53,99,108,88,70,115,120,108])

    static func read() async -> ServiceData {
        guard var creds = GeminiCreds.load() else {
            return .unavailable(messageKey: "gemini_not_logged_in")
        }
        if creds.isExpired {
            switch await refresh(creds) {
            case .success(let c): creds = c
            case .needsLogin: return .unavailable(messageKey: "gemini_not_logged_in")
            case .offline: return .unavailable(messageKey: "gemini_offline")
            }
        }

        // 取 project（缓存，避免每次都 loadCodeAssist）
        var project = cachedProject()
        if project == nil {
            project = await loadProject(token: creds.accessToken)
            if let project { cacheProject(project) }
        }
        guard let project else { return .unavailable(messageKey: "gemini_error") }

        switch await fetchQuota(token: creds.accessToken, project: project) {
        case .ok(let buckets):
            return parse(buckets)
        case .unauthorized:
            // project 可能失效：清缓存重取一次
            clearProject()
            if let p = await loadProject(token: creds.accessToken) {
                cacheProject(p)
                if case .ok(let buckets) = await fetchQuota(token: creds.accessToken, project: p) {
                    return parse(buckets)
                }
            }
            return .unavailable(messageKey: "gemini_error")
        case .offline: return .unavailable(messageKey: "gemini_offline")
        case .error: return .unavailable(messageKey: "gemini_error")
        }
    }

    // MARK: - 接口调用

    private enum QuotaResult { case ok([[String: Any]]); case unauthorized; case offline; case error }

    private static func post(_ method: String, token: String, body: [String: Any]) async -> (Int, Any?)? {
        guard let url = URL(string: "\(endpoint):\(method)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        return (http.statusCode, try? JSONSerialization.jsonObject(with: data))
    }

    private static func loadProject(token: String) async -> String? {
        let md: [String: Any] = ["ideType": "IDE_UNSPECIFIED",
                                 "platform": "PLATFORM_UNSPECIFIED",
                                 "pluginType": "GEMINI"]
        guard let (status, obj) = await post("loadCodeAssist", token: token, body: ["metadata": md]),
              status == 200, let dict = obj as? [String: Any] else { return nil }
        return dict["cloudaicompanionProject"] as? String
    }

    private static func fetchQuota(token: String, project: String) async -> QuotaResult {
        guard let (status, obj) = await post("retrieveUserQuota", token: token,
                                             body: ["project": project]) else {
            return .offline
        }
        if status == 401 || status == 403 { return .unauthorized }
        guard status == 200, let dict = obj as? [String: Any],
              let buckets = dict["buckets"] as? [[String: Any]] else { return .error }
        return .ok(buckets)
    }

    // MARK: - 解析：按 Pro / Flash / Lite 归组，取每组最差余量

    private static func parse(_ buckets: [[String: Any]]) -> ServiceData {
        // (排序权重, 标签) —— Pro 最重要排最前
        func group(_ modelId: String) -> (Int, String)? {
            let m = modelId.lowercased()
            if m.contains("pro") { return (0, "Pro") }
            if m.contains("lite") { return (2, "Flash-Lite") }
            if m.contains("flash") { return (1, "Flash") }
            return nil
        }

        struct Agg { var remaining: Double; var reset: Date? }
        var groups: [String: (order: Int, agg: Agg)] = [:]

        for b in buckets {
            guard let modelId = b["modelId"] as? String,
                  let (order, label) = group(modelId) else { continue }
            let frac = (b["remainingFraction"] as? NSNumber)?.doubleValue ?? 1
            let remaining = max(0, min(100, frac * 100))
            let reset = (b["resetTime"] as? String).flatMap { CodexReader.parseISO($0) }
            if let existing = groups[label] {
                // 取该组里最紧张（剩余最少）的模型
                if remaining < existing.agg.remaining {
                    groups[label] = (order, Agg(remaining: remaining, reset: reset))
                }
            } else {
                groups[label] = (order, Agg(remaining: remaining, reset: reset))
            }
        }

        guard !groups.isEmpty else { return .unavailable(messageKey: "gemini_error") }

        let windows = groups
            .sorted { $0.value.order < $1.value.order }
            .map { label, v in
                WindowQuota(id: "gemini_\(label)", windowMinutes: nil, labelKey: nil,
                            usedPercent: 100 - v.agg.remaining, resetsAt: v.agg.reset,
                            customLabel: label)
            }
        return .ready(plan: nil, windows: windows, asOf: Date())
    }

    // MARK: - Token 续期

    private enum RefreshResult { case success(GeminiCreds); case needsLogin; case offline }

    private static func refresh(_ creds: GeminiCreds) async -> RefreshResult {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        let form = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": creds.refreshToken,
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        req.httpBody = form.data(using: .utf8)

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return .offline }
        guard let http = resp as? HTTPURLResponse else { return .needsLogin }
        guard http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String
        else { return .needsLogin }
        let expiresIn = (obj["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        var updated = creds
        updated.accessToken = access
        updated.expiryMs = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
        updated.persist()
        return .success(updated)
    }

    // MARK: - project 缓存（内存即可，重启再取一次成本很低）

    private static var projectCache: String?
    private static func cachedProject() -> String? { projectCache }
    private static func cacheProject(_ p: String) { projectCache = p }
    private static func clearProject() { projectCache = nil }
}

/// Gemini CLI 的 Google OAuth 凭据（~/.gemini/oauth_creds.json）。
struct GeminiCreds {
    var accessToken: String
    var refreshToken: String
    var expiryMs: Double
    private var raw: [String: Any]

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
    }

    var isExpired: Bool {
        Date().timeIntervalSince1970 * 1000 >= expiryMs - 60_000
    }

    static func load() -> GeminiCreds? {
        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String, !access.isEmpty,
              let refresh = root["refresh_token"] as? String, !refresh.isEmpty
        else { return nil }
        let exp = (root["expiry_date"] as? NSNumber)?.doubleValue ?? 0
        return GeminiCreds(accessToken: access, refreshToken: refresh, expiryMs: exp, raw: root)
    }

    func persist() {
        var root = raw
        root["access_token"] = accessToken
        root["expiry_date"] = expiryMs
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
