//
//  WindowCoordinator.swift
//  LocalizerHelper
//

import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()

    private var windows: [NSWindowController] = []

    func openProjectWindow(with projectURL: URL? = nil) {
        let hostingController = NSHostingController(
            rootView: ContentView(
                initialProjectURL: projectURL,
                autoOpenLastProject: false
            )
            .environmentObject(GlobalIgnoreStore.shared)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.title = "StringPilot"
        window.center()

        let controller = NSWindowController(window: window)
        windows.append(controller)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
