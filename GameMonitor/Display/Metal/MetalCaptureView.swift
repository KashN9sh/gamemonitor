import AppKit
import QuartzCore
import SwiftUI

/// NSView, который владеет CAMetalLayer и держит drawableSize синхронным с backing-пикселями.
final class MetalCaptureView: NSView {
    let metalLayer = CAMetalLayer()

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

    override var isFlipped: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
        updateDrawableSize()
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
}

/// SwiftUI-обёртка: создаёт MetalCaptureView и привязывает его CAMetalLayer к рендереру.
struct MetalCaptureSurface: NSViewRepresentable {
    let renderer: MetalRenderer

    func makeNSView(context: Context) -> MetalCaptureView {
        let view = MetalCaptureView()
        renderer.attach(layer: view.metalLayer)
        return view
    }

    func updateNSView(_ nsView: MetalCaptureView, context: Context) {
        renderer.attach(layer: nsView.metalLayer)
    }
}
