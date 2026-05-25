import SwiftUI

/// Empty-state когда capture не запущен. По центру glass-карточка с CTA «Начать».
/// Заменяет нынешний loading-блок главного окна.
struct WelcomeOverlay: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 6) {
                Text("GameMonitor")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Switch (HDMI) → Cam Link → Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !appModel.rendererAvailable {
                Label("Metal недоступен на этом Mac", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let error = appModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button {
                appModel.start()
            } label: {
                Label("Начать", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!appModel.rendererAvailable)
            .keyboardShortcut(.return, modifiers: .command)

            Text("Включите Switch и подсоедините его к Cam Link перед стартом")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(36)
        .frame(maxWidth: 480)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}
