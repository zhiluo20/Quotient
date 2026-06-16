import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class UsageStore: ObservableObject {
    @Published var codex: ServiceData = .loading
    @Published var claude: ServiceData = .loading
    @Published var gemini: ServiceData = .loading
    @Published var now = Date()

    @Published var langPref: LangPref {
        didSet {
            UserDefaults.standard.set(langPref.rawValue, forKey: "langPref")
            persistSnapshot()
        }
    }
    @Published var services: ServiceFilter {
        didSet {
            UserDefaults.standard.set(services.rawValue, forKey: "services")
            persistSnapshot()
        }
    }

    /// 实际生效语言：跟随系统或用户指定
    var lang: Lang { langPref.resolved }
    @Published var pinned: Bool {
        didSet {
            UserDefaults.standard.set(pinned, forKey: "pinned")
            onPinChange?(pinned)
        }
    }
    @Published var hidden: Bool {
        didSet {
            UserDefaults.standard.set(hidden, forKey: "hidden")
            onHiddenChange?(hidden)
        }
    }

    var onPinChange: ((Bool) -> Void)?
    var onHiddenChange: ((Bool) -> Void)?
    var onLedChange: ((Led) -> Void)?
    var onOpenSettings: (() -> Void)?

    private var timer: Timer?
    private var resetTimer: Timer?
    private var lastClaudeFetch: Date = .distantPast

    init() {
        let defaults = UserDefaults.standard
        langPref = LangPref(rawValue: defaults.string(forKey: "langPref") ?? "") ?? .system
        services = ServiceFilter(rawValue: defaults.string(forKey: "services") ?? "") ?? .codexClaude
        pinned = defaults.object(forKey: "pinned") as? Bool ?? true
        hidden = defaults.bool(forKey: "hidden")

        // 冷启动先用磁盘上的上次结果填充，避免空窗/闪烁，断网时也有内容可看
        if let cached = QuotaSnapshot.load() {
            codex = cached.codex.asServiceData
            claude = cached.claude.asServiceData
            gemini = cached.gemini.asServiceData
        }
    }

    /// 按服务取当前运行时数据
    func data(for service: Service) -> ServiceData {
        switch service {
        case .codex:  return codex
        case .claude: return claude
        case .gemini: return gemini
        }
    }

    func start() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.refresh(force: false)
            }
        }
    }

    func refresh(force: Bool) {
        now = Date()
        codex = CodexReader.read()
        gemini = GeminiReader.read()

        // Claude 走网络，5 分钟一次足够；手动刷新与重置触发时强制
        if force || now.timeIntervalSince(lastClaudeFetch) > 300 {
            lastClaudeFetch = now
            Task {
                let result = await ClaudeReader.read()
                self.applyClaude(result)
                self.scheduleResetRefresh()
                self.persistSnapshot()
            }
        } else {
            scheduleResetRefresh()
        }
        persistSnapshot()
    }

    /// 应用 Claude 拉取结果：网络类失败（断网/接口错误）时保留上次成功数据，
    /// 只有需要用户介入的状态（未登录/续期失败）才覆盖显示。
    private func applyClaude(_ result: ServiceData) {
        if result.isReady {
            claude = result
            return
        }
        if case .unavailable(let key) = result,
           key == "claude_offline" || key == "claude_error",
           claude.isReady {
            return  // 保留旧值，UI 用 asOf 提示数据时间
        }
        claude = result
    }

    /// 把当前额度写入 App Group 共享容器，并通知系统刷新桌面小组件
    private func persistSnapshot() {
        QuotaSnapshot(
            codex: codex.snapshot,
            claude: claude.snapshot,
            gemini: gemini.snapshot,
            lang: lang.rawValue,
            generatedAt: Date(),
            shown: services.shown
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
        onLedChange?(overallLed)
    }

    /// 在最近的额度重置时间点之后再刷新一次
    private func scheduleResetRefresh() {
        resetTimer?.invalidate()
        let upcoming = (codex.windows + claude.windows)
            .compactMap(\.resetsAt)
            .filter { $0 > now }
            .min()
        guard let upcoming else { return }
        let delay = upcoming.timeIntervalSince(now) + 5
        resetTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(force: true)
            }
        }
    }

    var overallLed: Led {
        Led.worst(services.shown.map { data(for: $0).led(now: now) })
    }
}
