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
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 600)
                .environmentObject(GlobalIgnoreStore.shared)
                .onAppear {
                    DispatchQueue.main.async {
                        guard let window = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first,
                              let screenFrame = window.screen?.visibleFrame else { return }
                        window.setFrame(screenFrame, display: true)
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
