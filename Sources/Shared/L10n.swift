import Foundation

enum L10n {
    static func t(_ key: String, _ lang: Lang) -> String {
        (lang == .zh ? zh[key] : en[key]) ?? key
    }

    private static let zh: [String: String] = [
        "title": "Quotient",
        "remaining": "剩余",
        "reset_done": "已重置",
        "loading": "读取中…",
        "codex_no_data": "未找到 Codex 使用记录",
        "widget_no_data": "请先打开 Quotient 应用",
        "hide": "隐藏（从菜单栏恢复）",
        "claude_not_logged_in": "未找到 Claude Code 登录信息",
        "claude_expired": "Claude 登录已过期，请重新 /login",
        "claude_error": "Claude 额度接口请求失败",
        "claude_offline": "网络不可用，无法获取 Claude 额度",
        "win_opus": "Opus",
        "as_of": "数据时间",
        "pin_on": "取消置顶",
        "pin_off": "置顶显示",
        "refresh": "刷新",
        "quit": "退出 Quotient",
        "show_panel": "显示悬浮窗",
        "hide_panel": "隐藏悬浮窗",
        "about": "关于 Quotient",
        "settings": "设置…",
        "settings_title": "Quotient 设置",
        "services_label": "显示服务",
        "services_both": "Codex 和 Claude",
        "services_codex": "仅 Codex",
        "services_claude": "仅 Claude",
        "language_label": "语言",
        "lang_system": "跟随系统",
        "credits": "作者：Zhi Luo\n由 Claude Code 协助完成",
    ]

    private static let en: [String: String] = [
        "title": "Quotient",
        "remaining": "left",
        "reset_done": "reset",
        "loading": "loading…",
        "codex_no_data": "No Codex usage records found",
        "widget_no_data": "Open the Quotient app first",
        "hide": "Hide (restore from menu bar)",
        "claude_not_logged_in": "Claude Code login not found",
        "claude_expired": "Claude login expired, run /login",
        "claude_error": "Claude usage request failed",
        "claude_offline": "Network unavailable for Claude usage",
        "win_opus": "Opus",
        "as_of": "as of",
        "pin_on": "Unpin",
        "pin_off": "Pin on top",
        "refresh": "Refresh",
        "quit": "Quit Quotient",
        "show_panel": "Show Panel",
        "hide_panel": "Hide Panel",
        "about": "About Quotient",
        "settings": "Settings…",
        "settings_title": "Quotient Settings",
        "services_label": "Show services",
        "services_both": "Codex & Claude",
        "services_codex": "Codex only",
        "services_claude": "Claude only",
        "language_label": "Language",
        "lang_system": "Match system",
        "credits": "Author: Zhi Luo\nBuilt with the help of Claude Code",
    ]

    /// "300 分钟" -> "5h" / "5 小时"；"10080" -> "7d" / "7 天"
    static func windowLabel(minutes: Int?, extraKey: String?, lang: Lang) -> String {
        var label: String
        switch minutes {
        case .some(let m) where m % 1440 == 0:
            label = lang == .zh ? "\(m / 1440) 天" : "\(m / 1440)d"
        case .some(let m) where m % 60 == 0:
            label = lang == .zh ? "\(m / 60) 小时" : "\(m / 60)h"
        case .some(let m):
            label = lang == .zh ? "\(m) 分钟" : "\(m)m"
        case .none:
            label = lang == .zh ? "窗口" : "window"
        }
        if let extraKey {
            label = "\(t(extraKey, lang)) \(label)"
        }
        return label
    }

    /// 距重置时间的人性化倒计时
    static func resetText(resetsAt: Date?, now: Date, lang: Lang) -> String? {
        guard let resetsAt else { return nil }
        if resetsAt <= now { return t("reset_done", lang) }
        let s = Int(resetsAt.timeIntervalSince(now))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        let span: String
        if d > 0 {
            span = lang == .zh ? "\(d) 天 \(h) 小时" : "\(d)d \(h)h"
        } else if h > 0 {
            span = lang == .zh ? "\(h) 小时 \(m) 分" : "\(h)h \(m)m"
        } else {
            span = lang == .zh ? "\(max(m, 1)) 分钟" : "\(max(m, 1))m"
        }
        return lang == .zh ? "\(span)后重置" : "resets in \(span)"
    }
}
