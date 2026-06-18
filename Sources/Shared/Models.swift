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
    /// 自定义标签（如 Gemini 的 "Pro" / "Flash"），优先于按分钟数生成的标签
    var customLabel: String? = nil

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
    /// 无百分比额度、仅有登录/可用状态的服务（如 Gemini）
    case status(led: Led, textKey: String, asOf: Date?)

    var windows: [WindowQuota] {
        if case .ready(_, let w, _) = self { return w }
        return []
    }

    /// 参与全局信号灯计算的灯色
    func led(now: Date) -> Led {
        switch self {
        case .ready(_, let w, _):
            return Led.worst(w.map { Led.from(remaining: $0.effectiveRemaining(now: now)) })
        case .status(let led, _, _):
            return led
        default:
            return .gray
        }
    }
}

extension ServiceData {
    func limitedWindows(_ limit: Int) -> ServiceData {
        switch self {
        case .ready(let plan, let windows, let asOf):
            return .ready(plan: plan, windows: Array(windows.prefix(limit)), asOf: asOf)
        default:
            return self
        }
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

enum Service: String, Codable, CaseIterable {
    case codex, claude, gemini, zcode

    var displayName: String {
        switch self {
        case .codex:  return "Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .zcode:  return "ZCode"
        }
    }
}

/// 设置页第二个服务槽位：可不显示，也可任选一个供应商。
enum ServiceSlot: String, Codable, CaseIterable {
    case none, codex, claude, gemini, zcode

    init(service: Service?) {
        switch service {
        case .codex:  self = .codex
        case .claude: self = .claude
        case .gemini: self = .gemini
        case .zcode:  self = .zcode
        case .none:   self = .none
        }
    }

    var service: Service? {
        switch self {
        case .none:   return nil
        case .codex:  return .codex
        case .claude: return .claude
        case .gemini: return .gemini
        case .zcode:  return .zcode
        }
    }

    var labelKey: String {
        switch self {
        case .none:   return "service_none"
        case .codex:  return "services_codex"
        case .claude: return "services_claude"
        case .gemini: return "services_gemini"
        case .zcode:  return "services_zcode"
        }
    }
}

enum ServiceSelection {
    static func shown(primary: Service, secondary: ServiceSlot) -> [Service] {
        var result = [primary]
        if let service = secondary.service, service != primary {
            result.append(service)
        }
        return result
    }
}

/// 旧版固定组合设置，仅用于迁移 UserDefaults 中的 `services`。
enum LegacyServiceFilter: String {
    case codex, claude, gemini
    case codexClaude, codexGemini, claudeGemini

    var shown: [Service] {
        switch self {
        case .codex:        return [.codex]
        case .claude:       return [.claude]
        case .gemini:       return [.gemini]
        case .codexClaude:  return [.codex, .claude]
        case .codexGemini:  return [.codex, .gemini]
        case .claudeGemini: return [.claude, .gemini]
        }
    }
}
