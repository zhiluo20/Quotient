import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        Form {
            Picker(L10n.t("services_label", store.lang), selection: $store.services) {
                Text(L10n.t("services_both", store.lang)).tag(ServiceFilter.both)
                Text(L10n.t("services_codex", store.lang)).tag(ServiceFilter.codex)
                Text(L10n.t("services_claude", store.lang)).tag(ServiceFilter.claude)
            }
            Picker(L10n.t("language_label", store.lang), selection: $store.langPref) {
                Text(L10n.t("lang_system", store.lang)).tag(LangPref.system)
                Text("简体中文").tag(LangPref.zh)
                Text("English").tag(LangPref.en)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}
