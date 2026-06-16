import SwiftUI
import WidgetKit

@main
struct QuotientWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuotientWidget()
    }
}

struct QuotientWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Quotient", provider: Provider()) { entry in
            QuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Quotient")
        .description("Codex & Claude quota at a glance")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        let snap = context.isPreview ? .sample : (QuotaSnapshot.load() ?? .sample)
        completion(QuotaEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let snap = QuotaSnapshot.load()
        let now = Date()

        // 在每个即将到来的重置时间点放一个条目，让 LED 到点自动变绿
        var dates: [Date] = [now]
        if let snap {
            let resets = (snap.codex.windows + snap.claude.windows)
                .compactMap(\.resetsAt)
                .filter { $0 > now && $0.timeIntervalSince(now) < 86400 }
            dates.append(contentsOf: resets.map { $0.addingTimeInterval(5) })
        }
        dates.sort()

        let entries = dates.prefix(8).map { QuotaEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - Views

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: QuotaEntry

    private var lang: Lang {
        Lang(rawValue: entry.snapshot?.lang ?? "") ?? .zh
    }

    /// 桌面单色/着色模式下系统会压平颜色，切换为不透明度对比方案
    private var mono: Bool { renderingMode != .fullColor }

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                switch family {
                case .systemMedium:
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(snap.shown.enumerated()), id: \.element) { index, service in
                            if index > 0 {
                                Divider().opacity(0.4)
                            }
                            ServiceColumnView(name: service.displayName,
                                              service: snap.snapshot(for: service),
                                              now: entry.date, lang: lang, mono: mono)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                default:
                    SmallView(snapshot: snap, now: entry.date, lang: lang, mono: mono)
                }
            } else {
                Text(L10n.t("widget_no_data", lang))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .containerBackground(.regularMaterial, for: .widget)
    }
}

/// 小尺寸：每个服务一行，最差窗口的灯 + 剩余百分比
private struct SmallView: View {
    let snapshot: QuotaSnapshot
    let now: Date
    let lang: Lang
    let mono: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                LedDot(led: overallLed, size: 9, mono: mono)
                Text("Quotient")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.shown, id: \.self) { service in
                ServiceLine(name: service.displayName,
                            service: snapshot.snapshot(for: service), now: now, lang: lang, mono: mono)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overallLed: Led {
        Led.worst(snapshot.shown.map { snapshot.snapshot(for: $0).asServiceData.led(now: now) })
    }
}

private struct ServiceLine: View {
    let name: String
    let service: ServiceSnapshot
    let now: Date
    let lang: Lang
    let mono: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                LedDot(led: led, size: 8, mono: mono)
                Text(name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                if let statusKey = service.statusKey {
                    Text(L10n.t(statusKey, lang))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if let worst {
                    Text("\(Int(worst.rounded()))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(mono ? AnyShapeStyle(.primary) : AnyShapeStyle(led.color))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            if service.statusKey == nil, let worst {
                QuotaBar(remaining: worst, led: led, mono: mono)
            }
        }
    }

    private var worst: Double? {
        service.windows.map { $0.effectiveRemaining(now: now) }.min()
    }

    private var led: Led {
        if let statusKey = service.statusKey, !statusKey.isEmpty {
            return Led(rawValue: service.statusLed) ?? .green
        }
        guard let worst else { return service.messageKey != nil ? .gray : .gray }
        return Led.from(remaining: worst)
    }
}
