//
//  DorisApp.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import SwiftUI

@main
struct DorisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty scene - the AppDelegate handles everything
        Settings {
            EmptyView()
        }
    }
}
