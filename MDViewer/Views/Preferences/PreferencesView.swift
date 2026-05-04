import SwiftUI

struct PreferencesView: View {
    private enum Tab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
    }

    @State private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPrefsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(Tab.general)

            AppearancePrefsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(Tab.appearance)
        }
        .frame(width: 400, height: 340)
        .padding()
    }
}
