import SwiftUI

@main
struct AlertClashIPApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(menuBarTint)
                    .frame(width: 8, height: 8)
                Image(systemName: model.menuBarSymbol)
                    .symbolRenderingMode(.monochrome)
                Text(model.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private var menuBarTint: Color {
        switch model.monitorService.snapshot.status.tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
