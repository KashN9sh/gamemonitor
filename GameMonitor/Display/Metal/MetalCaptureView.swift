import AppKit
import QuartzCore
import SwiftUI

/// NSView, который владеет CAMetalLayer и держит drawableSize синхронным с backing-пикселями.
/// Сам же владеет CADisplayLink'ом — на каждый VSync пинаем renderer.tick(), который
/// презентит «последний актуальный» кадр от capture-pipeline.
final class MetalCaptureView: NSView {
    let metalLayer = CAMetalLayer()

    /// Колбэк на каждый VSync. Прокидывается из NSViewRepresentable — снаружи там
    /// сидит `renderer.tick()`. Закрытие, потому что view не должен знать про MetalRenderer.
    var onDisplayTick: (() -> Void)?

    /// CADisplayLink ходит на main runloop. NSView.displayLink сам отслеживает,
    /// на каком экране сидит окно, и корректно меняет частоту при перетаскивании
    /// между внешним 60-Гц монитором и встроенным ProMotion 120-Гц.
    private var vsyncLink: CADisplayLink?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize

        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsGravity = .resizeAspect
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor

        layer = metalLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        vsyncLink?.invalidate()
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
        if let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor {
            metalLayer.contentsScale = scale
        }
    }

    private func updateDrawableSize() {
        let backing = convertToBacking(bounds.size)
        let size = CGSize(
            width: max(1, backing.width.rounded()),
            height: max(1, backing.height.rounded())
        )
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
        }
    }

    private func updateDisplayLink() {
        vsyncLink?.invalidate()
        vsyncLink = nil
        guard window != nil else { return }
        // NSView.displayLink: macOS 14+. Сам отслеживает screen окна и
        // подстраивает частоту под актуальный display refresh.
        let link = displayLink(target: self, selector: #selector(handleVsync(_:)))
        link.add(to: .main, forMode: .common)
        vsyncLink = link
    }

    @objc private func handleVsync(_ link: CADisplayLink) {
        onDisplayTick?()
    }
}

/// SwiftUI-обёртка: создаёт MetalCaptureView и привязывает его CAMetalLayer к рендереру.
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
        renderer.attach(layer: nsView.metalLayer)
        nsView.onDisplayTick = { [weak renderer] in
            renderer?.tick()
        }
    }
}
