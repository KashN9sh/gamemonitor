import AppKit
import CoreMedia
import CoreVideo
import Foundation
import Metal
import MetalFX
import QuartzCore
import simd

enum UpscaleMode: String, CaseIterable, Identifiable, Codable {
    case off
    case spatial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Без апскейла (нативный UVC)"
        case .spatial: return "MetalFX Spatial (до экрана)"
        }
    }
}

private struct YUVShaderUniforms {
    var row0: SIMD4<Float>
    var row1: SIMD4<Float>
    var row2: SIMD4<Float>
    var bias: SIMD4<Float>
}

private struct BlitShaderUniforms {
    var dstScale: SIMD2<Float>
    var dstOffset: SIMD2<Float>
}

/// Прямой Metal-тракт: NV12 (CVPixelBuffer/IOSurface) → YUV→RGB шейдер →
/// опц. MTLFXSpatialScaler → CAMetalLayer drawable. Без копий через CPU.
final class MetalRenderer {
    let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let yuvPipeline: MTLRenderPipelineState
    private let blitPipeline: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache

    private weak var attachedLayer: CAMetalLayer?
    private let stateLock = NSLock()

    private var inputWidth = 0
    private var inputHeight = 0
    private var rgbTexture: MTLTexture?

    private var spatialScaler: MTLFXSpatialScaler?
    private var spatialInputWidth = 0
    private var spatialInputHeight = 0
    private var spatialOutputWidth = 0
    private var spatialOutputHeight = 0
    private var spatialOutputTexture: MTLTexture?

    private var requestedMode: UpscaleMode = .spatial

    // Pending frame from capture side. submit() пишет, tick() (с VSync) читает и
    // обнуляет hasNewFrame. Это и есть основа decoupled pacing: UVC-callback не
    // пытается сам презентить, а просто отдаёт «последний актуальный кадр».
    private let frameLock = NSLock()
    private var pendingPixelBuffer: CVPixelBuffer?
    private var pendingFormatDescription: CMFormatDescription?
    private var hasNewFrame = false

    // Stats — все счётчики защищены statsLock, потому что tick живёт на main,
    // а completion-handler GPU прилетает на Metal-thread.
    private let statsLock = NSLock()
    private var uniqueFramesInWindow = 0
    private var displayTicksInWindow = 0
    private var statsWindowStart = CFAbsoluteTimeGetCurrent()
    private let statsWindowSeconds: CFTimeInterval = 1.0
    private var gpuMsAccum: Double = 0
    private var gpuMsSamples: Int = 0
    private(set) var presentedFps: Double = 0
    private(set) var displayFps: Double = 0
    private(set) var droppedFrames: UInt64 = 0
    private(set) var lastGpuMilliseconds: Double = 0

    var statsCallback: ((MetalRendererStats) -> Void)?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = device.makeCommandQueue() else { return nil }
        guard let library = device.makeDefaultLibrary() else {
            print("[MetalRenderer] No default Metal library found.")
            return nil
        }

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard cacheStatus == kCVReturnSuccess, let cache else {
            print("[MetalRenderer] CVMetalTextureCacheCreate failed: \(cacheStatus)")
            return nil
        }

        do {
            self.device = device
            self.commandQueue = queue
            self.textureCache = cache

            let yuvDescriptor = MTLRenderPipelineDescriptor()
            yuvDescriptor.label = "YUV→RGB"
            yuvDescriptor.vertexFunction = library.makeFunction(name: "yuvVertex")
            yuvDescriptor.fragmentFunction = library.makeFunction(name: "yuvFragment")
            yuvDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            self.yuvPipeline = try device.makeRenderPipelineState(descriptor: yuvDescriptor)

            let blitDescriptor = MTLRenderPipelineDescriptor()
            blitDescriptor.label = "Blit to drawable"
            blitDescriptor.vertexFunction = library.makeFunction(name: "blitVertex")
            blitDescriptor.fragmentFunction = library.makeFunction(name: "blitFragment")
            blitDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            self.blitPipeline = try device.makeRenderPipelineState(descriptor: blitDescriptor)
        } catch {
            print("[MetalRenderer] Pipeline init failed: \(error)")
            return nil
        }
    }

    func attach(layer: CAMetalLayer) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 2
        layer.presentsWithTransaction = false
        layer.isOpaque = true
        layer.contentsGravity = .resizeAspect
        attachedLayer = layer
    }

    func setUpscaleMode(_ mode: UpscaleMode) {
        stateLock.lock()
        requestedMode = mode
        if mode == .off {
            spatialScaler = nil
            spatialOutputTexture = nil
            spatialInputWidth = 0
            spatialInputHeight = 0
            spatialOutputWidth = 0
            spatialOutputHeight = 0
        }
        stateLock.unlock()
    }

    /// Вызывается с capture-callback'а. Просто атомарно складывает «последний кадр»;
    /// презентация произойдёт на ближайшем vsync через tick(). UVC-callback не
    /// блокируется на nextDrawable() — это и убирает inter-frame jitter.
    func submit(pixelBuffer: CVPixelBuffer, formatDescription: CMFormatDescription) {
        frameLock.lock()
        pendingPixelBuffer = pixelBuffer
        pendingFormatDescription = formatDescription
        hasNewFrame = true
        frameLock.unlock()
    }

    /// Сбросить отложенный кадр — вызывается при остановке захвата, чтобы не держать
    /// последний CVPixelBuffer.
    func resetPending() {
        frameLock.lock()
        pendingPixelBuffer = nil
        pendingFormatDescription = nil
        hasNewFrame = false
        frameLock.unlock()
    }

    /// Дёргается из CADisplayLink на VSync. Если есть свежий кадр — рендерит и
    /// презентит ровно на этот VSync; иначе ничего не делает (предыдущий drawable
    /// остаётся на экране → нулевой GPU-cost, идеальный hold).
    func tick() {
        frameLock.lock()
        let isNew = hasNewFrame
        let pb = pendingPixelBuffer
        let fd = pendingFormatDescription
        hasNewFrame = false
        frameLock.unlock()

        countDisplayTick()
        guard isNew, let pb, let fd else { return }
        renderInternal(pixelBuffer: pb, formatDescription: fd)
    }

    private func renderInternal(pixelBuffer: CVPixelBuffer, formatDescription: CMFormatDescription) {
        guard let layer = attachedLayer else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        guard let yTexture = makePlaneTexture(pixelBuffer: pixelBuffer, planeIndex: 0, format: .r8Unorm),
              let cbcrTexture = makePlaneTexture(pixelBuffer: pixelBuffer, planeIndex: 1, format: .rg8Unorm) else {
            recordDrop()
            return
        }

        ensureRGBTexture(width: width, height: height)
        guard let rgbTexture else {
            recordDrop()
            return
        }

        guard let drawable = layer.nextDrawable() else {
            recordDrop()
            return
        }

        let drawableWidth = drawable.texture.width
        let drawableHeight = drawable.texture.height
        let mode: UpscaleMode = stateLock.withLock { requestedMode }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            recordDrop()
            return
        }
        commandBuffer.label = "GameMonitor frame"

        let uniforms = makeYUVUniforms(formatDescription: formatDescription, pixelBuffer: pixelBuffer)
        encodeYUVConversion(commandBuffer: commandBuffer,
                            yTexture: yTexture,
                            cbcrTexture: cbcrTexture,
                            target: rgbTexture,
                            uniforms: uniforms)

        let upscaledTexture = encodeMetalFXIfNeeded(commandBuffer: commandBuffer,
                                                    mode: mode,
                                                    sourceWidth: width,
                                                    sourceHeight: height,
                                                    outputWidth: drawableWidth,
                                                    outputHeight: drawableHeight)

        encodeBlit(commandBuffer: commandBuffer,
                   source: upscaledTexture ?? rgbTexture,
                   sourceWidth: upscaledTexture?.width ?? width,
                   sourceHeight: upscaledTexture?.height ?? height,
                   destination: drawable.texture)

        commandBuffer.addCompletedHandler { [weak self] buffer in
            guard let self else { return }
            let gpuMs = (buffer.gpuEndTime - buffer.gpuStartTime) * 1_000.0
            self.recordGpuSample(gpuMs)
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        countUniqueFrame()
    }

    private func makePlaneTexture(pixelBuffer: CVPixelBuffer,
                                  planeIndex: Int,
                                  format: MTLPixelFormat) -> MTLTexture? {
        let planeWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let planeHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        guard planeWidth > 0, planeHeight > 0 else { return nil }

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            format,
            planeWidth,
            planeHeight,
            planeIndex,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func ensureRGBTexture(width: Int, height: Int) {
        if rgbTexture != nil, inputWidth == width, inputHeight == height { return }
        inputWidth = width
        inputHeight = height

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        rgbTexture = device.makeTexture(descriptor: descriptor)
        rgbTexture?.label = "UVC BGRA"
    }

    private func encodeYUVConversion(commandBuffer: MTLCommandBuffer,
                                     yTexture: MTLTexture,
                                     cbcrTexture: MTLTexture,
                                     target: MTLTexture,
                                     uniforms: YUVShaderUniforms) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "YUV→RGB"
        encoder.setRenderPipelineState(yuvPipeline)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(cbcrTexture, index: 1)
        var uniformsCopy = uniforms
        encoder.setFragmentBytes(&uniformsCopy, length: MemoryLayout<YUVShaderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeMetalFXIfNeeded(commandBuffer: MTLCommandBuffer,
                                       mode: UpscaleMode,
                                       sourceWidth: Int,
                                       sourceHeight: Int,
                                       outputWidth: Int,
                                       outputHeight: Int) -> MTLTexture? {
        guard mode == .spatial,
              outputWidth > 0,
              outputHeight > 0,
              sourceWidth < outputWidth || sourceHeight < outputHeight,
              let rgbTexture else {
            return nil
        }

        let (targetW, targetH) = MetalRenderer.aspectFitSize(
            srcWidth: sourceWidth,
            srcHeight: sourceHeight,
            dstWidth: outputWidth,
            dstHeight: outputHeight
        )
        guard targetW > 0, targetH > 0 else { return nil }

        let needsRebuild = spatialScaler == nil ||
            spatialInputWidth != sourceWidth ||
            spatialInputHeight != sourceHeight ||
            spatialOutputWidth != targetW ||
            spatialOutputHeight != targetH

        if needsRebuild {
            let descriptor = MTLFXSpatialScalerDescriptor()
            descriptor.inputWidth = sourceWidth
            descriptor.inputHeight = sourceHeight
            descriptor.outputWidth = targetW
            descriptor.outputHeight = targetH
            descriptor.colorTextureFormat = .bgra8Unorm
            descriptor.outputTextureFormat = .bgra8Unorm
            descriptor.colorProcessingMode = .perceptual

            spatialScaler = descriptor.makeSpatialScaler(device: device)
            spatialInputWidth = sourceWidth
            spatialInputHeight = sourceHeight
            spatialOutputWidth = targetW
            spatialOutputHeight = targetH

            let outDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: targetW,
                height: targetH,
                mipmapped: false
            )
            outDescriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            outDescriptor.storageMode = .private
            spatialOutputTexture = device.makeTexture(descriptor: outDescriptor)
            spatialOutputTexture?.label = "MetalFX upscaled"
        }

        guard let spatialScaler, let spatialOutputTexture else { return nil }

        spatialScaler.colorTexture = rgbTexture
        spatialScaler.outputTexture = spatialOutputTexture
        spatialScaler.encode(commandBuffer: commandBuffer)
        return spatialOutputTexture
    }

    private func encodeBlit(commandBuffer: MTLCommandBuffer,
                            source: MTLTexture,
                            sourceWidth: Int,
                            sourceHeight: Int,
                            destination: MTLTexture) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = destination
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "Blit"
        encoder.setRenderPipelineState(blitPipeline)
        encoder.setFragmentTexture(source, index: 0)

        let (fitW, fitH) = MetalRenderer.aspectFitSize(
            srcWidth: sourceWidth,
            srcHeight: sourceHeight,
            dstWidth: destination.width,
            dstHeight: destination.height
        )

        // Convert pixel rect to clip-space quad scale/offset.
        let dstWf = Float(destination.width)
        let dstHf = Float(destination.height)
        let scaleX = Float(fitW) / dstWf
        let scaleY = Float(fitH) / dstHf

        var uniforms = BlitShaderUniforms(
            dstScale: SIMD2<Float>(scaleX, scaleY),
            dstOffset: SIMD2<Float>(0, 0)
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<BlitShaderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeYUVUniforms(formatDescription: CMFormatDescription,
                                 pixelBuffer: CVPixelBuffer) -> YUVShaderUniforms {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isFullRange = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
            pixelFormat == kCVPixelFormatType_420YpCbCr8PlanarFullRange

        let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [CFString: Any]
        let matrixString = extensions?[kCVImageBufferYCbCrMatrixKey] as? String
        let isBT601 = matrixString == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String) ||
            matrixString == (kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 as String)

        let row0: SIMD3<Float>
        let row1: SIMD3<Float>
        let row2: SIMD3<Float>

        if isBT601 {
            if isFullRange {
                row0 = SIMD3<Float>(1.0,  0.0,       1.402)
                row1 = SIMD3<Float>(1.0, -0.344136, -0.714136)
                row2 = SIMD3<Float>(1.0,  1.772,     0.0)
            } else {
                row0 = SIMD3<Float>(1.164384,  0.0,       1.596027)
                row1 = SIMD3<Float>(1.164384, -0.391762, -0.812968)
                row2 = SIMD3<Float>(1.164384,  2.017232,  0.0)
            }
        } else {
            // BT.709 by default for HD content.
            if isFullRange {
                row0 = SIMD3<Float>(1.0,  0.0,      1.5748)
                row1 = SIMD3<Float>(1.0, -0.18732, -0.46812)
                row2 = SIMD3<Float>(1.0,  1.8556,   0.0)
            } else {
                row0 = SIMD3<Float>(1.164384,  0.0,       1.792741)
                row1 = SIMD3<Float>(1.164384, -0.213249, -0.532909)
                row2 = SIMD3<Float>(1.164384,  2.112402,  0.0)
            }
        }

        let bias: SIMD3<Float> = isFullRange
            ? SIMD3<Float>(0.0, 0.5, 0.5)
            : SIMD3<Float>(16.0 / 255.0, 0.5, 0.5)

        return YUVShaderUniforms(
            row0: SIMD4<Float>(row0, 0),
            row1: SIMD4<Float>(row1, 0),
            row2: SIMD4<Float>(row2, 0),
            bias: SIMD4<Float>(bias, 0)
        )
    }

    private static func aspectFitSize(srcWidth: Int, srcHeight: Int,
                                      dstWidth: Int, dstHeight: Int) -> (Int, Int) {
        guard srcWidth > 0, srcHeight > 0, dstWidth > 0, dstHeight > 0 else { return (0, 0) }
        let srcAspect = Double(srcWidth) / Double(srcHeight)
        let dstAspect = Double(dstWidth) / Double(dstHeight)
        if srcAspect > dstAspect {
            let h = Int((Double(dstWidth) / srcAspect).rounded())
            return (dstWidth, max(1, h))
        } else {
            let w = Int((Double(dstHeight) * srcAspect).rounded())
            return (max(1, w), dstHeight)
        }
    }

    private func recordDrop() {
        statsLock.lock()
        droppedFrames &+= 1
        let snapshot = currentStatsSnapshotLocked()
        statsLock.unlock()
        statsCallback?(snapshot)
    }

    private func countDisplayTick() {
        statsLock.lock()
        displayTicksInWindow += 1
        let snapshot = rollWindowLocked()
        statsLock.unlock()
        if let snapshot {
            statsCallback?(snapshot)
        }
    }

    private func countUniqueFrame() {
        statsLock.lock()
        uniqueFramesInWindow += 1
        statsLock.unlock()
    }

    private func recordGpuSample(_ gpuMs: Double) {
        statsLock.lock()
        gpuMsAccum += gpuMs
        gpuMsSamples += 1
        statsLock.unlock()
    }

    /// Если за statsLock прошло окно — пересчитываем published-значения и
    /// возвращаем snapshot для статистического callback'а. Иначе nil.
    private func rollWindowLocked() -> MetalRendererStats? {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - statsWindowStart
        guard elapsed >= statsWindowSeconds else { return nil }
        presentedFps = Double(uniqueFramesInWindow) / elapsed
        displayFps = Double(displayTicksInWindow) / elapsed
        if gpuMsSamples > 0 {
            lastGpuMilliseconds = gpuMsAccum / Double(gpuMsSamples)
        }
        uniqueFramesInWindow = 0
        displayTicksInWindow = 0
        gpuMsAccum = 0
        gpuMsSamples = 0
        statsWindowStart = now
        return currentStatsSnapshotLocked()
    }

    private func currentStatsSnapshotLocked() -> MetalRendererStats {
        MetalRendererStats(
            presentedFps: presentedFps,
            displayFps: displayFps,
            droppedFrames: droppedFrames,
            gpuMilliseconds: lastGpuMilliseconds
        )
    }
}

struct MetalRendererStats {
    /// Уникальные кадры с источника, презентованные за окно. На стабильном 60 Гц-сорсе
    /// и при display ≥ 60 Гц — должно быть 60.0 без джиттера.
    let presentedFps: Double
    /// Темп тиков display link'а — фактическая частота VSync.
    let displayFps: Double
    let droppedFrames: UInt64
    let gpuMilliseconds: Double
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
