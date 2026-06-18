import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class UsageStore: ObservableObject {
    private static let geminiWindowLimit = 2

    @Published var codex: ServiceData = .loading
    @Published var claude: ServiceData = .loading
    @Published var gemini: ServiceData = .loading
    @Published var zcode: ServiceData = .loading
    @Published var now = Date()

    @Published var langPref: LangPref {
        didSet {
            UserDefaults.standard.set(langPref.rawValue, forKey: "langPref")
            persistSnapshot()
        }
    }
    @Published var primaryService: Service {
        didSet {
            if secondaryService.service == primaryService {
                secondaryService = .none
            }
            UserDefaults.standard.set(primaryService.rawValue, forKey: "primaryService")
            persistSnapshot()
        }
    }
    @Published var secondaryService: ServiceSlot {
        didSet {
            if secondaryService.service == primaryService {
                secondaryService = .none
                return
            }
            UserDefaults.standard.set(secondaryService.rawValue, forKey: "secondaryService")
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
            onHiddenChange?(hidden)
        }
    }

    var onPinChange: ((Bool) -> Void)?
    var onHiddenChange: ((Bool) -> Void)?
    var onLedChange: ((Led) -> Void)?
    var onOpenSettings: (() -> Void)?

    private var timer: Timer?
    private var resetTimer: Timer?
    private var lastNetFetch: Date = .distantPast

    init() {
        let defaults = UserDefaults.standard
        langPref = LangPref(rawValue: defaults.string(forKey: "langPref") ?? "") ?? .system
        if let rawPrimary = defaults.string(forKey: "primaryService"),
           let primary = Service(rawValue: rawPrimary) {
            primaryService = primary
            secondaryService = ServiceSlot(
                rawValue: defaults.string(forKey: "secondaryService") ?? "") ?? .claude
        } else {
            let legacy = LegacyServiceFilter(
                rawValue: defaults.string(forKey: "services") ?? "") ?? .codexClaude
            let shown = legacy.shown
            primaryService = shown.first ?? .codex
            secondaryService = ServiceSlot(service: shown.dropFirst().first)
        }
        pinned = defaults.object(forKey: "pinned") as? Bool ?? true
        hidden = false
        defaults.removeObject(forKey: "hidden")

        // 冷启动先用磁盘上的上次结果填充，避免空窗/闪烁，断网时也有内容可看
        if let cached = QuotaSnapshot.load() {
            codex = cached.codex.asServiceData
            claude = cached.claude.asServiceData
            gemini = cached.gemini.asServiceData.limitedWindows(Self.geminiWindowLimit)
            zcode = cached.zcode.asServiceData
        }
    }

    /// 按服务取当前运行时数据
    func data(for service: Service) -> ServiceData {
        switch service {
        case .codex:  return codex
        case .claude: return claude
        case .gemini: return gemini.limitedWindows(Self.geminiWindowLimit)
        case .zcode:  return zcode
        }
    }

    var shownServices: [Service] {
        ServiceSelection.shown(primary: primaryService, secondary: secondaryService)
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
        zcode = ZCodeReader.read()

        // Claude / Gemini 走网络，5 分钟一次足够；手动刷新与重置触发时强制
        if force || now.timeIntervalSince(lastNetFetch) > 300 {
            lastNetFetch = now
            Task {
                let result = await ClaudeReader.read()
                self.apply(result, to: \.claude, transientPrefix: "claude")
                self.scheduleResetRefresh()
                self.persistSnapshot()
            }
            Task {
                let result = await GeminiReader.read()
                self.apply(result.limitedWindows(Self.geminiWindowLimit),
                           to: \.gemini, transientPrefix: "gemini")
                self.scheduleResetRefresh()
                self.persistSnapshot()
            }
        } else {
            scheduleResetRefresh()
        }
        persistSnapshot()
    }

    /// 应用网络服务的拉取结果：断网/接口错误时保留上次成功数据，
    /// 只有需要用户介入的状态（未登录/续期失败）才覆盖显示。
    private func apply(_ result: ServiceData, to keyPath: ReferenceWritableKeyPath<UsageStore, ServiceData>,
                       transientPrefix: String) {
        if result.isReady {
            self[keyPath: keyPath] = result
            return
        }
        if case .unavailable(let key) = result,
           key == "\(transientPrefix)_offline" || key == "\(transientPrefix)_error",
           self[keyPath: keyPath].isReady {
            return  // 保留旧值，UI 用 asOf 提示数据时间
        }
        self[keyPath: keyPath] = result
    }

    /// 把当前额度写入 App Group 共享容器，并通知系统刷新桌面小组件
    private func persistSnapshot() {
        QuotaSnapshot(
            codex: codex.snapshot,
            claude: claude.snapshot,
            gemini: gemini.limitedWindows(Self.geminiWindowLimit).snapshot,
            zcode: zcode.snapshot,
            lang: lang.rawValue,
            generatedAt: Date(),
            shown: shownServices
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
        onLedChange?(overallLed)
    }

    /// 在最近的额度重置时间点之后再刷新一次
    private func scheduleResetRefresh() {
        resetTimer?.invalidate()
        let upcoming = (codex.windows + claude.windows + gemini.windows + zcode.windows)
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
        Led.worst(shownServices.map { data(for: $0).led(now: now) })
    }
}
