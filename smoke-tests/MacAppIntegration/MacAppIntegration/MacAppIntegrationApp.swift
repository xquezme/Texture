//
//  MacAppIntegrationApp.swift
//  MacAppIntegration
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

import SwiftUI

@main
struct MacAppIntegrationApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ButtonContentView()
                    .tabItem { Text("Button") }
                CollectionContentView()
                    .tabItem { Text("Collection") }
            }
            .frame(minWidth: 700, minHeight: 520)
        }
    }
}
