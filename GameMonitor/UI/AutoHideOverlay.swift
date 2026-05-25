import AppKit
import SwiftUI

/// ViewModifier, который держит overlay видимым пока юзер двигает мышь / кликает,
/// и плавно прячет его через `idleSeconds` без активности. Курсор тоже скрывается
/// вместе с HUD — ровно как в QuickTime / Apple TV.
///
/// Если `forceVisible == true` (например, capture не запущен — нужно видеть Welcome),
/// модификатор не прячет overlay.
struct AutoHideOverlay: ViewModifier {
    let idleSeconds: TimeInterval
    var forceVisible: Bool = false

    @State private var isVisible: Bool = true
    @State private var monitor: Any?
    @State private var hideWorkItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .opacity(forceVisible || isVisible ? 1 : 0)
            .animation(.smooth(duration: 0.32), value: isVisible)
            .animation(.smooth(duration: 0.32), value: forceVisible)
            .onAppear { installMonitor() }
            .onDisappear { removeMonitor() }
            .onChange(of: forceVisible) { _, newValue in
                if newValue {
                    isVisible = true
                    hideWorkItem?.cancel()
                    NSCursor.unhide()
                } else {
                    scheduleHide()
                }
            }
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]
        ) { event in
            handleActivity()
            return event
        }
        scheduleHide()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func handleActivity() {
        if !isVisible {
            isVisible = true
        }
        NSCursor.unhide()
        scheduleHide()
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        guard !forceVisible else { return }
        let item = DispatchWorkItem {
            isVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + idleSeconds, execute: item)
    }
}

extension View {
    /// Удобный синтаксис: `.autoHide(idle: 2.5, forceVisible: !appModel.capture.isRunning)`.
    func autoHide(idle seconds: TimeInterval, forceVisible: Bool = false) -> some View {
        modifier(AutoHideOverlay(idleSeconds: seconds, forceVisible: forceVisible))
    }
}
