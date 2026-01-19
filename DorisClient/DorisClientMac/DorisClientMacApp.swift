//
//  DorisClientMacApp.swift
//  DorisClientMac
//
//  Created by Adam Bell on 1/17/26.
//

import SwiftUI
import AppKit
import Combine

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
                    // Enable wake word detection when app launches (unless mic is disabled)
                    if !viewModel.wakeWordEnabled && !viewModel.microphoneDisabled {
                        viewModel.enableWakeWord()
                    }
                }
        }
        .defaultSize(width: 450, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) { }  // Remove "New Window" menu item
        }

        // Menu bar quick access (secondary)
        MenuBarExtra {
            ChatPopoverView()
                .environmentObject(viewModel)
                .environmentObject(menuBarManager)
        } label: {
            MenuBarIcon(microphoneDisabled: viewModel.microphoneDisabled)
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

/// Settings view for configuring Doris
struct SettingsView: View {
    @EnvironmentObject var viewModel: DorisViewModel
    @AppStorage("serverURL") private var serverURL = "http://100.125.207.74:8000"

    var body: some View {
        Form {
            Section("Microphone") {
                Toggle("Disable Microphone", isOn: Binding(
                    get: { viewModel.microphoneDisabled },
                    set: { disabled in
                        viewModel.setMicrophoneDisabled(disabled)
                    }
                ))
                .toggleStyle(.switch)

                if viewModel.microphoneDisabled {
                    Label("Voice input and wake word are disabled", systemImage: "mic.slash.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Disable for meetings or when you don't want Doris listening.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Server") {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
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
        .frame(width: 400, height: 320)
        .padding()
    }
}

/// Menu bar icon that shows microphone state
struct MenuBarIcon: View {
    let microphoneDisabled: Bool

    var body: some View {
        if microphoneDisabled {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.orange, .secondary)
        } else {
            Image(systemName: "bubble.left.fill")
        }
    }
}
