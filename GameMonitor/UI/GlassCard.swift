import SwiftUI

/// Универсальная glass-карточка с заголовком и контентом. Используется как замена
/// `Section` в Settings: одинаковые отступы, скругление, glassEffect.
struct GlassCard<Content: View>: View {
    let title: String?
    let icon: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    Text(title)
                        .font(.headline)
                }
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
