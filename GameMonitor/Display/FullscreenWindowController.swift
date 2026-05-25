import AppKit
import SwiftUI

extension Notification.Name {
    static let gameMonitorExitFullscreen = Notification.Name("GameMonitorExitFullscreen")
}

/// Доступ к подлежащему `NSWindow` из SwiftUI-вьюхи. Нужен, чтобы `AppModel` мог
/// управлять main window: переключать его в native fullscreen через
/// `toggleFullScreen(_:)` и перемещать на выбранный экран.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                self.onWindow(window)
            }
        }
    }
}
