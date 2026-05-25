import SwiftUI

struct FrameIntervalStats {
    let count: Int
    let mean: Double
    let stdDev: Double
    let min: Double
    let max: Double
    let outlierShare: Double  // Доля кадров вне ±10% от среднего.

    static func compute(samples: [Double]) -> FrameIntervalStats {
        guard !samples.isEmpty else {
            return FrameIntervalStats(count: 0, mean: 0, stdDev: 0, min: 0, max: 0, outlierShare: 0)
        }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0.0) { acc, x in acc + (x - mean) * (x - mean) } / Double(samples.count)
        let stdDev = variance.squareRoot()
        let minV = samples.min() ?? 0
        let maxV = samples.max() ?? 0
        let tolerance = mean * 0.1
        let outliers = samples.filter { abs($0 - mean) > tolerance }.count
        let share = Double(outliers) / Double(samples.count)
        return FrameIntervalStats(
            count: samples.count,
            mean: mean,
            stdDev: stdDev,
            min: minV,
            max: maxV,
            outlierShare: share
        )
    }
}

/// Гистограмма интервалов между кадрами в миллисекундах.
/// Корзины ~5 мс. Самые яркие столбики — там где плотность.
struct FrameIntervalHistogram: View {
    let samples: [Double]   // в секундах
    let targetFps: Double   // целевой fps (для отметки)

    private let binWidthMs: Double = 5
    private let binCount: Int = 14   // 0..70 ms

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                drawAxes(context: &context, size: size)
                drawBars(context: &context, size: size)
                drawTargetMarker(context: &context, size: size)
            }
            .frame(height: 110)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 4) {
                ForEach(0..<binCount, id: \.self) { idx in
                    Text(binLabel(idx))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func binLabel(_ index: Int) -> String {
        let lower = Int(Double(index) * binWidthMs)
        return "\(lower)"
    }

    private func histogram() -> [Int] {
        var bins = Array(repeating: 0, count: binCount)
        for s in samples {
            let ms = s * 1000.0
            let idx = min(binCount - 1, max(0, Int(ms / binWidthMs)))
            bins[idx] += 1
        }
        return bins
    }

    private func drawAxes(context: inout GraphicsContext, size: CGSize) {
        let path = Path { p in
            p.move(to: CGPoint(x: 0, y: size.height))
            p.addLine(to: CGPoint(x: size.width, y: size.height))
        }
        context.stroke(path, with: .color(.gray.opacity(0.4)), lineWidth: 1)
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        let bins = histogram()
        let maxValue = max(bins.max() ?? 1, 1)
        let barWidth = size.width / CGFloat(binCount)

        for (idx, value) in bins.enumerated() {
            let normalized = CGFloat(value) / CGFloat(maxValue)
            let barHeight = max(2, normalized * (size.height - 4))
            let rect = CGRect(
                x: CGFloat(idx) * barWidth + 1,
                y: size.height - barHeight,
                width: barWidth - 2,
                height: barHeight
            )
            let path = Path(roundedRect: rect, cornerRadius: 2)
            let color = colorForBin(index: idx, count: value)
            context.fill(path, with: .color(color))
        }
    }

    private func colorForBin(index: Int, count: Int) -> Color {
        guard count > 0 else { return .gray.opacity(0.2) }
        let lowerMs = Double(index) * binWidthMs
        let upperMs = lowerMs + binWidthMs
        guard targetFps > 0 else { return .accentColor }
        let targetMs = 1000.0 / targetFps
        if targetMs >= lowerMs, targetMs < upperMs {
            return .green
        }
        let off = abs((lowerMs + upperMs) * 0.5 - targetMs) / targetMs
        if off < 0.1 { return .accentColor }
        if off < 0.3 { return .orange }
        return .red
    }

    private func drawTargetMarker(context: inout GraphicsContext, size: CGSize) {
        guard targetFps > 0 else { return }
        let targetMs = 1000.0 / targetFps
        let totalMs = Double(binCount) * binWidthMs
        let xRatio = min(1.0, targetMs / totalMs)
        let x = CGFloat(xRatio) * size.width
        let path = Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(path, with: .color(.green.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
    }
}
