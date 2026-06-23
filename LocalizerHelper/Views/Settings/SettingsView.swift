//
//  SettingsView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 22/06/26.
//


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
