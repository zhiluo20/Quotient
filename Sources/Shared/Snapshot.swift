import Foundation

/// 宿主 App 与 Widget 扩展之间通过 App Group 容器共享的额度快照。
/// 只包含百分比、重置时间等展示数据，绝不包含任何 token 或凭据。
struct ServiceSnapshot: Codable {
    /// 非 nil 表示服务不可用，值为 L10n 消息键
    var messageKey: String?
    var plan: String?
    var asOf: Date?
    var windows: [WindowQuota]
    /// 无百分比、仅状态的服务（如 Gemini）：状态文案键与灯色
    var statusKey: String?
    var statusLed: String?
}

struct QuotaSnapshot: Codable {
    var codex: ServiceSnapshot
    var claude: ServiceSnapshot
    var gemini: ServiceSnapshot
    var zcode: ServiceSnapshot
    var lang: String
    var generatedAt: Date
    /// 当前显示哪些服务（最多两个）
    var shown: [Service] = [.codex, .claude]

    static let appGroupID = "97C4PCWN4C.quotient"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("snapshot.json")
    }

    func snapshot(for service: Service) -> ServiceSnapshot {
        switch service {
        case .codex:  return codex
        case .claude: return claude
        case .gemini: return gemini.limitedWindows(2)
        case .zcode:  return zcode
        }
    }

    init(codex: ServiceSnapshot, claude: ServiceSnapshot, gemini: ServiceSnapshot,
         zcode: ServiceSnapshot = Self.missingZCode, lang: String, generatedAt: Date,
         shown: [Service] = [.codex, .claude]) {
        self.codex = codex
        self.claude = claude
        self.gemini = gemini
        self.zcode = zcode
        self.lang = lang
        self.generatedAt = generatedAt
        self.shown = shown
    }

    private static var missingZCode: ServiceSnapshot {
        ServiceSnapshot(messageKey: "zcode_no_data", plan: nil, asOf: nil, windows: [])
    }

    func save() {
        guard let url = Self.fileURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> QuotaSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(QuotaSnapshot.self, from: data)
    }

    /// 组件画廊预览用的示例数据
    static var sample: QuotaSnapshot {
        QuotaSnapshot(
            codex: ServiceSnapshot(messageKey: nil, plan: "pro", asOf: Date(), windows: [
                WindowQuota(id: "codex_primary", windowMinutes: 300, labelKey: nil,
                            usedPercent: 12, resetsAt: Date().addingTimeInterval(3600 * 3)),
                WindowQuota(id: "codex_secondary", windowMinutes: 10080, labelKey: nil,
                            usedPercent: 65, resetsAt: Date().addingTimeInterval(86400 * 2)),
            ]),
            claude: ServiceSnapshot(messageKey: nil, plan: nil, asOf: Date(), windows: [
                WindowQuota(id: "claude_five_hour", windowMinutes: 300, labelKey: nil,
                            usedPercent: 49, resetsAt: Date().addingTimeInterval(3600 * 2)),
                WindowQuota(id: "claude_seven_day", windowMinutes: 10080, labelKey: nil,
                            usedPercent: 5, resetsAt: Date().addingTimeInterval(86400 * 5)),
            ]),
            gemini: ServiceSnapshot(messageKey: nil, plan: nil, asOf: Date(), windows: [],
                                    statusKey: "status_active", statusLed: "green"),
            zcode: ServiceSnapshot(messageKey: nil, plan: nil, asOf: Date(), windows: [
                WindowQuota(id: "zcode_glm_5_2", windowMinutes: nil, labelKey: nil,
                            usedPercent: 72, resetsAt: Date().addingTimeInterval(3600 * 9),
                            customLabel: "GLM-5.2"),
                WindowQuota(id: "zcode_glm_5_turbo", windowMinutes: nil, labelKey: nil,
                            usedPercent: 18, resetsAt: Date().addingTimeInterval(3600 * 9),
                            customLabel: "GLM-5-Turbo"),
            ]),
            lang: "zh",
            generatedAt: Date()
        )
    }
}

extension QuotaSnapshot {
    private enum CodingKeys: String, CodingKey {
        case codex, claude, gemini, zcode, lang, generatedAt, shown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codex = try c.decode(ServiceSnapshot.self, forKey: .codex)
        claude = try c.decode(ServiceSnapshot.self, forKey: .claude)
        gemini = try c.decode(ServiceSnapshot.self, forKey: .gemini)
        zcode = try c.decodeIfPresent(ServiceSnapshot.self, forKey: .zcode) ?? Self.missingZCode
        lang = try c.decode(String.self, forKey: .lang)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        shown = try c.decodeIfPresent([Service].self, forKey: .shown) ?? [.codex, .claude]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(codex, forKey: .codex)
        try c.encode(claude, forKey: .claude)
        try c.encode(gemini, forKey: .gemini)
        try c.encode(zcode, forKey: .zcode)
        try c.encode(lang, forKey: .lang)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(shown, forKey: .shown)
    }
}

extension ServiceSnapshot {
    func limitedWindows(_ limit: Int) -> ServiceSnapshot {
        var copy = self
        copy.windows = Array(copy.windows.prefix(limit))
        return copy
    }

    /// 从磁盘缓存还原为运行时状态：有窗口数据就当作上次成功结果
    var asServiceData: ServiceData {
        if !windows.isEmpty {
            return .ready(plan: plan, windows: windows, asOf: asOf)
        }
        if let statusKey {
            return .status(led: Led(rawValue: statusLed) ?? .gray, textKey: statusKey, asOf: asOf)
        }
        if let messageKey { return .unavailable(messageKey: messageKey) }
        return .loading
    }
}

extension Led {
    init?(rawValue: String?) {
        switch rawValue {
        case "green":  self = .green
        case "yellow": self = .yellow
        case "red":    self = .red
        case "gray":   self = .gray
        default:       return nil
        }
    }

    var rawValue: String {
        switch self {
        case .green:  return "green"
        case .yellow: return "yellow"
        case .red:    return "red"
        case .gray:   return "gray"
        }
    }
}

extension ServiceData {
    var isReady: Bool { if case .ready = self { return true }; return false }

    var snapshot: ServiceSnapshot {
        switch self {
        case .loading:
            return ServiceSnapshot(messageKey: "loading", plan: nil, asOf: nil, windows: [])
        case .unavailable(let key):
            return ServiceSnapshot(messageKey: key, plan: nil, asOf: nil, windows: [])
        case .ready(let plan, let windows, let asOf):
            return ServiceSnapshot(messageKey: nil, plan: plan, asOf: asOf, windows: windows)
        case .status(let led, let textKey, let asOf):
            return ServiceSnapshot(messageKey: nil, plan: nil, asOf: asOf, windows: [],
                                   statusKey: textKey, statusLed: led.rawValue)
        }
    }
}
