import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AISettingsView()
                .tabItem {
                    Label("AI Translation", systemImage: "sparkles")
                }

            IgnoredKeysSettingsView()
                .tabItem {
                    Label("Ignored Keys", systemImage: "eye.slash")
                }
        }
        .frame(width: 560, height: 480)
    }
}
