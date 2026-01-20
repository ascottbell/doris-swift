//
//  DorisClientMacApp.swift
//  DorisClientMac
//
//  Created by Adam Bell on 1/17/26.
//

import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let clearConversation = Notification.Name("clearConversation")
}

@main
struct DorisClientMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = DorisViewModel()
    @StateObject private var menuBarManager = MenuBarManager()

    init() {
        // Register global hotkey: Option+Space
        GlobalHotkeyManager.shared.register {
            // This will be handled by the app delegate
        }
    }

    var body: some Scene {
        // Main window - primary interface
        WindowGroup("Doris") {
            ChatWindowView()
                .environmentObject(viewModel)
                .onAppear {
                    // Enable wake word detection when app launches
                    if !viewModel.wakeWordEnabled {
                        viewModel.enableWakeWord()
                    }
                }
        }
        .defaultSize(width: 450, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) { }  // Remove "New Window" menu item
            CommandGroup(after: .pasteboard) {
                Button("Clear Conversation") {
                    NotificationCenter.default.post(name: .clearConversation, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        // Menu bar quick access (secondary)
        MenuBarExtra {
            ChatPopoverView()
                .environmentObject(viewModel)
                .environmentObject(menuBarManager)
        } label: {
            MenuBarIcon(micDisabled: viewModel.microphoneDisabled)
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}

/// App Delegate for handling app lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the main window is visible on launch
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopen the main window when clicking dock icon
        if !flag {
            for window in NSApp.windows {
                if window.title == "Doris" {
                    window.makeKeyAndOrderFront(self)
                    break
                }
            }
        }
        return true
    }
}

/// Menu bar icon that changes when mic is disabled
struct MenuBarIcon: View {
    let micDisabled: Bool

    var body: some View {
        if micDisabled {
            Image(systemName: "mic.slash.fill")
                .foregroundColor(.orange)
        } else {
            Image(systemName: "bubble.left.fill")
        }
    }
}

/// Settings view for configuring Doris
struct SettingsView: View {
    @EnvironmentObject var viewModel: DorisViewModel
    @AppStorage("serverURL") private var serverURL = "http://100.125.207.74:8000"

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Microphone") {
                Toggle("Disable Microphone", isOn: Binding(
                    get: { viewModel.microphoneDisabled },
                    set: { disabled in
                        viewModel.setMicrophoneDisabled(disabled)
                    }
                ))

                Text("Disable all voice input for use during meetings or calls.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Wake Word") {
                Toggle("Enable \"Hey Doris\" wake word", isOn: Binding(
                    get: { viewModel.wakeWordEnabled },
                    set: { enabled in
                        if enabled {
                            viewModel.enableWakeWord()
                        } else {
                            viewModel.disableWakeWord()
                        }
                    }
                ))
                .disabled(viewModel.microphoneDisabled)

                Text("Say \"Hey Doris\" to activate voice input from anywhere.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Keyboard Shortcuts") {
                HStack {
                    Text("Summon Doris")
                    Spacer()
                    Text("⌥ Space")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Open Full Window")
                    Spacer()
                    Text("⇧⌘D")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 380)
        .padding()
    }
}
