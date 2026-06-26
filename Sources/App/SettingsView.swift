import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("service_primary_label", store.lang),
                       selection: $store.primaryService) {
                    ForEach(Service.allCases, id: \.self) { service in
                        Text(service.displayName).tag(service)
                    }
                }
                Picker(L10n.t("service_secondary_label", store.lang),
                       selection: $store.secondaryService) {
                    ForEach(ServiceSlot.allCases, id: \.self) { slot in
                        Text(slot.service?.displayName ?? L10n.t(slot.labelKey, store.lang))
                            .tag(slot)
                            .disabled(slot.service == store.primaryService)
                    }
                }
            } header: {
                Text(L10n.t("settings_title", store.lang))
            } footer: {
                Text(L10n.t("settings_widget_only_hint", store.lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(L10n.t("language_label", store.lang), selection: $store.langPref) {
                Text(L10n.t("lang_system", store.lang)).tag(LangPref.system)
                Text("简体中文").tag(LangPref.zh)
                Text("English").tag(LangPref.en)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
