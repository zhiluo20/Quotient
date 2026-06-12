import Foundation
import SwiftUI

enum Lang: String {
    case zh, en
}

enum Led {
    case green, yellow, red, gray

    var color: Color {
        switch self {
        case .green:  return Color(red: 0.20, green: 0.90, blue: 0.45)
        case .yellow: return Color(red: 1.00, green: 0.80, blue: 0.15)
        case .red:    return Color(red: 1.00, green: 0.27, blue: 0.27)
        case .gray:   return Color.secondary.opacity(0.5)
        }
    }

    /// 红绿灯规则：剩余 >= 10% 绿，0 < 剩余 < 10% 黄，剩余 <= 0 红
    static func from(remaining: Double) -> Led {
        if remaining >= 10 { return .green }
        if remaining > 0 { return .yellow }
        return .red
    }

    static func worst(_ leds: [Led]) -> Led {
        if leds.contains(.red) { return .red }
        if leds.contains(.yellow) { return .yellow }
        if leds.contains(.green) { return .green }
        return .gray
    }
}

struct WindowQuota: Identifiable, Codable {
    let id: String
    /// 窗口长度（分钟），用于生成 "5h" / "7d" 标签
    let windowMinutes: Int?
    /// 特殊窗口的附加标签键（如 Claude 的 Opus 窗口）
    let labelKey: String?
    /// 已用百分比 0–100
    let usedPercent: Double
    let resetsAt: Date?

    /// 渲染时按当前时间计算的剩余百分比：重置时间已过则视为已重置（100% 剩余）
    func effectiveRemaining(now: Date) -> Double {
        if let r = resetsAt, r <= now { return 100 }
        return max(0, min(100, 100 - usedPercent))
    }

    func isElapsed(now: Date) -> Bool {
        if let r = resetsAt { return r <= now }
        return false
    }
}

enum ServiceData {
    case loading
    case unavailable(messageKey: String)
    case ready(plan: String?, windows: [WindowQuota], asOf: Date?)

    var windows: [WindowQuota] {
        if case .ready(_, let w, _) = self { return w }
        return []
    }
}

enum LangPref: String, CaseIterable {
    case system, zh, en

    var resolved: Lang {
        switch self {
        case .zh: return .zh
        case .en: return .en
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
        }
    }
}

enum ServiceFilter: String, CaseIterable {
    case both, codex, claude

    var showCodex: Bool { self != .claude }
    var showClaude: Bool { self != .codex }
}
