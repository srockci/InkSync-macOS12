import SwiftUI

struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = 8
    var minItemWidth: CGFloat = 40

    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 8, minItemWidth: CGFloat = 40, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.minItemWidth = minItemWidth
        self.content = content
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minItemWidth, maximum: .infinity), spacing: spacing)],
            alignment: .leading,
            spacing: spacing
        ) {
            content()
        }
    }
}
