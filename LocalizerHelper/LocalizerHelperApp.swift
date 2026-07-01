//
//  LocalizerHelperApp.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import SwiftUI

@main
struct LocalizerHelperApp: App {
    init() {
        // Disable macOS's automatic window tabbing ("+" tab bar) — this app doesn't support multiple tabs per window.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 600)
                .environmentObject(GlobalIgnoreStore.shared)
                .onAppear {
                    // Maximize the window to fill the screen on first launch
                    DispatchQueue.main.async {
                        NSApplication.shared.mainWindow?.zoom(nil)
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands { AppCommands() }

        Settings {
            SettingsView()
                .environmentObject(GlobalIgnoreStore.shared)
        }
    }
}
