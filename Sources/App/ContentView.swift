import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: UsageStore
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            let shown = store.services.shown
            ForEach(Array(shown.enumerated()), id: \.element) { index, service in
                if index > 0 {
                    Divider().opacity(0.25)
                }
                ServiceColumnView(name: service.displayName,
                                  service: store.data(for: service).snapshot,
                                  now: store.now, lang: store.lang)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: store.services.shown.count > 1 ? 384 : 208, alignment: .topLeading)
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            controls
                .padding(.top, 8)
                .padding(.trailing, 10)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .onHover { hovering = $0 }
    }

    private var controls: some View {
        HStack(spacing: 9) {
            ControlButton(
                systemName: store.pinned ? "pin.fill" : "pin",
                help: L10n.t(store.pinned ? "pin_on" : "pin_off", store.lang)
            ) {
                store.pinned.toggle()
            }
            ControlButton(systemName: "gearshape", help: L10n.t("settings", store.lang)) {
                store.onOpenSettings?()
            }
            ControlButton(systemName: "arrow.clockwise", help: L10n.t("refresh", store.lang)) {
                store.refresh(force: true)
            }
            ControlButton(systemName: "minus", help: L10n.t("hide", store.lang)) {
                store.hidden = true
            }
            ControlButton(systemName: "xmark", help: L10n.t("quit", store.lang)) {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.25), in: Capsule())
    }
}

private struct ControlButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - 液态玻璃背景

private struct GlassBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}
