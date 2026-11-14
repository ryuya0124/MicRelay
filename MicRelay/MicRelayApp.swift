// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import SwiftUI

@main
struct MicRelayApp: App {
    @StateObject private var monitor = MonitorModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack { MonitorView(model: monitor) }
                .task { monitor.startDiagnosticIfRequested() }
                .onChange(of: scenePhase) { _, phase in monitor.sceneChanged(phase) }
        }
    }
}
