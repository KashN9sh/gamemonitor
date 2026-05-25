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
            // Расширяем стандартное View-меню (там уже живёт "Enter Full Screen"
            // от macOS), а не создаём дубль.
            CommandGroup(after: .sidebar) {
                Divider()
                Button("На весь экран") {
                    appModel.enterFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Захват") {
                Button(appModel.capture.isRunning ? "Стоп" : "Старт") {
                    if appModel.capture.isRunning {
                        appModel.stop()
                    } else {
                        appModel.start()
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                Toggle("Показывать статистику", isOn: $appModel.showStatsOverlay)
            }
        }

        Settings {
            SettingsView(appModel: appModel)
        }
    }
}
