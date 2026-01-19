//
//  ContentView.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//
//  Note: This file is no longer used - the app now uses MenuBarView for the menu bar popover

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
