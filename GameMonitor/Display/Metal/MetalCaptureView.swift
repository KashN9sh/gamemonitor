import AppKit
import CoreFoundation
import QuartzCore
import SwiftUI

/// Owns CAMetalLayer и держит drawableSize синхронным с backing-пикселями.
/// CADisplayLink крутится не на main runloop'е, а на выделенном render-thread'е с
/// QoS `.userInteractive`. Это изолирует pacing от SwiftUI-инвалидаций и AppKit-event'ов,
/// которые на main могут задерживать tick > 16.7мс и приводить к пропуску VSync
/// (наблюдалось как «59 FPS» при чистом 60-Гц источнике).
/// Metal-encoding thread-safe by design, поэтому renderer.tick() можно дёргать
/// прямо с render-thread'а без сериализации в main.
final class MetalCaptureView: NSView {
    let metalLayer = CAMetalLayer()

    /// Колбэк на каждый VSync. Снаружи подсовывают замыкание `renderer.tick()`.
    var onDisplayTick: (() -> Void)?

    private var vsyncLink: CADisplayLink?
    private var renderThread: Thread?
    /// CFRunLoop поднимается render-thread'ом и капчится сюда через семафор.
    /// Хранится, чтобы при teardown'е можно было корректно остановить цикл
    /// через `CFRunLoopStop` (флаг внутри CFRunLoop — thread-safe).
    private var renderRunLoop: CFRunLoop?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        // .never: AppKit вообще не трогает наш layer — Metal сам полностью управляет
        // его контентом через present(). С .duringViewResize AppKit во время layout'а
        // может временно подсовывать свой backing-store или window-snapshot,
        // что визуально выглядит как «моргание со старым кадром».
        layerContentsRedrawPolicy = .never

        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsGravity = .resizeAspect
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        // Не помечаем layer как "нужно перерисовать" при изменении bounds —
        // у нас вся отрисовка через CAMetalDrawable, AppKit'у тут делать нечего.
        metalLayer.needsDisplayOnBoundsChange = false

        layer = metalLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        teardownDisplayLink()
    }

    override var isFlipped: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
        updateDrawableSize()
        updateDisplayLink()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
        updateDrawableSize()
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    private func updateContentsScale() {
        guard let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor else { return }
        let layer = metalLayer
        performOnRenderThread {
            if layer.contentsScale != scale {
                layer.contentsScale = scale
            }
        }
    }

    private func updateDrawableSize() {
        let backing = convertToBacking(bounds.size)
        let size = CGSize(
            width: max(1, backing.width.rounded()),
            height: max(1, backing.height.rounded())
        )
        let layer = metalLayer
        performOnRenderThread {
            if layer.drawableSize != size {
                layer.drawableSize = size
            }
        }
    }

    /// Сериализуем мутации layer-state с `nextDrawable()`/`present()`, который живёт
    /// на render-thread'е. Иначе main меняет `drawableSize`/`contentsScale` пока
    /// render-thread в середине acquisition'а drawable'а — CoreAnimation на
    /// мгновение показывает кэшированный snapshot CALayer'а ("сильно предыдущий
    /// кадр" из доклада). Если render-thread ещё не поднят — делаем inline.
    private func performOnRenderThread(_ block: @escaping () -> Void) {
        guard let runLoop = renderRunLoop else {
            block()
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - Display link plumbing

    private func updateDisplayLink() {
        teardownDisplayLink()
        guard window != nil else { return }

        // displayLink(target:selector:) — NSView API, безопасно вызывать только на main.
        let link = displayLink(target: self, selector: #selector(handleVsync(_:)))

        // Поднимаем render-thread и через семафор перенимаем его CFRunLoop.
        let setupSemaphore = DispatchSemaphore(value: 0)
        let runLoopBox = RunLoopBox()

        let thread = Thread {
            Thread.current.name = "com.gamemonitor.render"
            Thread.current.qualityOfService = .userInteractive

            let cfRunLoop = CFRunLoopGetCurrent()
            runLoopBox.value = cfRunLoop

            // Подключаем уже созданный CADisplayLink к runloop'у этого thread'а.
            link.add(to: RunLoop.current, forMode: .common)

            setupSemaphore.signal()

            // Крутим CFRunLoop пока он не получит CFRunLoopStop. Используем
            // `CFRunLoopRunInMode(.defaultMode, 1.0, false)` в цикле — это надёжно
            // выходит при stop'е и не требует фиктивных Port-источников.
            while !Thread.current.isCancelled {
                let result = CFRunLoopRunInMode(.defaultMode, 1.0, false)
                if result == .stopped { break }
            }
        }
        thread.start()
        setupSemaphore.wait()

        vsyncLink = link
        renderThread = thread
        renderRunLoop = runLoopBox.value
    }

    private func teardownDisplayLink() {
        vsyncLink?.invalidate()
        vsyncLink = nil
        if let runLoop = renderRunLoop {
            CFRunLoopStop(runLoop)
        }
        renderThread?.cancel()
        renderThread = nil
        renderRunLoop = nil
    }

    @objc private func handleVsync(_ link: CADisplayLink) {
        onDisplayTick?()
    }
}

/// Маленький box для безопасной передачи CFRunLoop'а из render-thread'а на main
/// через DispatchSemaphore. Memory-barrier'ы семафора обеспечивают happens-before.
private final class RunLoopBox: @unchecked Sendable {
    var value: CFRunLoop?
}

/// SwiftUI-обёртка: создаёт MetalCaptureView и привязывает его CAMetalLayer к рендереру.
/// Важно: всё подключение делаем строго в `makeNSView`. `updateNSView` SwiftUI
/// дёргает на каждый rollover `@Published` (несколько раз в секунду от обновлений
/// статистики), и если каждый раз переписывать `onDisplayTick` или re-attach'ить
/// layer — получим race с render-thread'ом, который в этот момент рендерит,
/// и моргание на экране.
struct MetalCaptureSurface: NSViewRepresentable {
    let renderer: MetalRenderer

    func makeNSView(context: Context) -> MetalCaptureView {
        let view = MetalCaptureView()
        renderer.attach(layer: view.metalLayer)
        view.onDisplayTick = { [weak renderer] in
            renderer?.tick()
        }
        return view
    }

    func updateNSView(_ nsView: MetalCaptureView, context: Context) {
        // No-op: layer и callback подключены один раз в makeNSView.
        // attach у renderer идемпотентен, но даже его дёргать тут не нужно.
    }
}
