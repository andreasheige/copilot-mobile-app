import SwiftUI

@main
struct CopilotMenuBarApp: App {
    @StateObject private var watcher = SessionWatcher()
    @StateObject private var localWatcher = LocalProcessWatcher()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(watcher)
                .environmentObject(localWatcher)
        } label: {
            MenuBarIcon(
                isConnected: watcher.isConnected,
                activeCount: watcher.terminalSessions.filter { $0.status == .running }.count
                    + watcher.agentSessions.filter { if case .idle = $0.status { return false }; return true }.count
                    + localWatcher.aiProcesses.count
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIcon: View {
    let isConnected: Bool
    let activeCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "terminal.fill")
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
        }
        .foregroundStyle(isConnected ? .primary : .secondary)
        .opacity(isConnected ? 1.0 : 0.4)
    }
}
