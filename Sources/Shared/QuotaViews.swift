import SwiftUI

/// 主 App 悬浮窗与 Widget 共用的额度渲染视图。
/// `mono` 表示处于单色渲染环境（桌面小组件的 vibrant/accented 模式），
/// 此时颜色会被系统压平，改用不透明度差异保证进度条可读。
struct LedDot: View {
    let led: Led
    let size: CGFloat
    var mono: Bool = false

    var body: some View {
        Circle()
            .fill(mono ? AnyShapeStyle(.primary) : AnyShapeStyle(led.color))
            .frame(width: size, height: size)
            .shadow(color: mono ? .clear : led.color.opacity(0.7), radius: size / 2.5)
            .opacity(mono ? (led == .green ? 1 : 0.6) : 1)
    }
}

struct QuotaBar: View {
    let remaining: Double
    let led: Led
    var mono: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(mono ? AnyShapeStyle(.primary.opacity(0.18)) : AnyShapeStyle(.white.opacity(0.13)))
                Capsule()
                    .fill(mono ? AnyShapeStyle(.primary) : AnyShapeStyle(led.color.gradient))
                    .frame(width: max(4, geo.size.width * remaining / 100))
            }
        }
        .frame(height: 5)
    }
}

struct WindowRowView: View {
    let window: WindowQuota
    let now: Date
    let lang: Lang
    var mono: Bool = false

    var body: some View {
        let remaining = window.effectiveRemaining(now: now)
        let led = Led.from(remaining: remaining)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                LedDot(led: led, size: 7, mono: mono)
                Text(L10n.windowLabel(minutes: window.windowMinutes,
                                      extraKey: window.labelKey, lang: lang))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(remaining.rounded()))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(mono ? AnyShapeStyle(.primary) : AnyShapeStyle(led.color))
            }
            QuotaBar(remaining: remaining, led: led, mono: mono)
            if let reset = L10n.resetText(resetsAt: window.resetsAt, now: now, lang: lang) {
                Text(reset)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct ServiceColumnView: View {
    let name: String
    let service: ServiceSnapshot
    let now: Date
    let lang: Lang
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                if let plan = service.plan {
                    Text(plan)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(.primary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            if let key = service.messageKey {
                HStack(spacing: 6) {
                    LedDot(led: .gray, size: 7, mono: mono)
                    Text(L10n.t(key, lang))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(service.windows) { window in
                    WindowRowView(window: window, now: now, lang: lang, mono: mono)
                }
                if let asOf = service.asOf, now.timeIntervalSince(asOf) > 360 {
                    Text("\(L10n.t("as_of", lang)) \(asOf.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
