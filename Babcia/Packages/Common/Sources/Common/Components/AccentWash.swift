import SwiftUI

// HeroBottomKey: hero reports its bottom Y (in a named coordinate space)
public struct HeroBottomKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// AccentWash: draws an accent color starting at startY and fading downward.
// This is a reusable building block you can use on any page without hacks.
public struct AccentWash: View {
    public let accent: Color
    public let startY: CGFloat

    public init(accent: Color, startY: CGFloat) {
        self.accent = accent
        self.startY = startY
    }

    public var body: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let height = max(0, total - startY)

            accent
                .frame(height: height)
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.6), location: 0.25),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: startY)
        }
        .ignoresSafeArea()
    }
}
