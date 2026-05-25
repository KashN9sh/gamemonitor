import SwiftUI

/// Узкая glass-капсула с предупреждением о несоответствии формата UVC. Появляется
/// сверху по центру, заменяет inline orange-блок в старом ContentView.
struct MismatchToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 720)
        .glassEffect(.regular, in: .capsule)
    }
}
