import SwiftUI

@main
struct GameMonitorApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Вид") {
                Button("На весь экран") {
                    appModel.enterFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Выйти из fullscreen") {
                    appModel.exitFullscreen()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }

        Settings {
            SettingsView(appModel: appModel)
        }
    }
}
