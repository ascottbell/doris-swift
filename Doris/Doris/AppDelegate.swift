//
//  AppDelegate.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var serverTask: Task<Void, Error>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🔵 AppDelegate: applicationDidFinishLaunching called")

        // Initialize DorisCore first (this creates all services)
        _ = DorisCore.shared

        // Start HTTP server in background
        serverTask = Task {
            let server = DorisServer(port: 8080)
            try await server.start()
        }

        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Doris")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())

        print("🟢 AppDelegate: Setup complete, server starting on port 8080")
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverTask?.cancel()
    }
    
    @objc func togglePopover() {
        print("🟣 togglePopover() called")
        if let button = statusItem.button {
            if popover.isShown {
                print("🟣 Closing popover")
                popover.performClose(nil)
            } else {
                print("🟣 Opening popover")
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Activate the app to ensure the popover receives focus
                NSApp.activate(ignoringOtherApps: true)
                print("🟣 Popover shown")
            }
        } else {
            print("🔴 ERROR: Status bar button is nil in togglePopover!")
        }
    }
}
