import Foundation

/// 宿主 App 与 Widget 扩展之间通过 App Group 容器共享的额度快照。
/// 只包含百分比、重置时间等展示数据，绝不包含任何 token 或凭据。
struct ServiceSnapshot: Codable {
    /// 非 nil 表示服务不可用，值为 L10n 消息键
    var messageKey: String?
    var plan: String?
    var asOf: Date?
    var windows: [WindowQuota]
}

struct QuotaSnapshot: Codable {
    var codex: ServiceSnapshot
    var claude: ServiceSnapshot
    var lang: String
    var generatedAt: Date
    var showCodex: Bool = true
    var showClaude: Bool = true

    static let appGroupID = "97C4PCWN4C.quotient"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("snapshot.json")
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
            lang: "zh",
            generatedAt: Date()
        )
    }
}

extension ServiceData {
    var snapshot: ServiceSnapshot {
        switch self {
        case .loading:
            return ServiceSnapshot(messageKey: "loading", plan: nil, asOf: nil, windows: [])
        case .unavailable(let key):
            return ServiceSnapshot(messageKey: key, plan: nil, asOf: nil, windows: [])
        case .ready(let plan, let windows, let asOf):
            return ServiceSnapshot(messageKey: nil, plan: plan, asOf: asOf, windows: windows)
        }
    }
}
