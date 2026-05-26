import SwiftUI

/// Минималистичный HUD в стиле часов на iPhone Lock Screen:
/// крупная полупрозрачная цифра FPS, soft halo сзади (даёт liquid-glass
/// «свечение»), drop shadow для читаемости поверх ярких сцен.
/// Без подложки и капсул — цифры «парят» поверх плеера.
struct CompactFPSOverlay: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        digits
            .contentTransition(.numericText(value: Double(fpsValue)))
            .animation(.smooth(duration: 0.25), value: fpsValue)
            .padding(.top, 20)
            .padding(.trailing, 24)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Текущая частота кадров: \(fpsValue) FPS"))
    }

    // MARK: - Digits

    /// Трёхслойный рендер для эффекта Liquid Glass-цифр (как часы на Lock Screen iOS):
    /// 1. soft-halo сзади — отделяет от любого фона;
    /// 2. material-as-foregroundStyle — глифы превращаются в «окошки» с vibrancy,
    ///    через которые виден размытый/осветлённый кадр (это и есть стекло);
    /// 3. тонкий белый «блик» сверху — добавляет characteristic glass-sheen и
    ///    держит читаемость поверх ярких сцен.
    private var digits: some View {
        let glyphFont: Font = .system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()
        return ZStack(alignment: .trailing) {
            Text(fpsString)
                .font(glyphFont)
                .foregroundStyle(.white.opacity(0.28))
                .blur(radius: 6)
                .accessibilityHidden(true)

            Text(fpsString)
                .font(glyphFont)
                .foregroundStyle(.ultraThinMaterial)

            Text(fpsString)
                .font(glyphFont)
                .foregroundStyle(.white.opacity(0.2))
        }
        .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
    }

    // MARK: - Derived state

    private var fpsValue: Int { max(0, Int(appModel.presentedFps.rounded())) }

    private var fpsString: String {
        guard appModel.capture.isRunning, appModel.presentedFps > 0 else { return "—" }
        return String(fpsValue)
    }
}
