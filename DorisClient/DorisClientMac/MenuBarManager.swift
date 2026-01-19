import SwiftUI
import AppKit
import Combine

@MainActor
class MenuBarManager: ObservableObject {
    @Published var isPopoverShown = false

    func togglePopover() {
        isPopoverShown.toggle()

        if isPopoverShown {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showPopover() {
        if !isPopoverShown {
            isPopoverShown = true
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hidePopover() {
        isPopoverShown = false
    }
}
