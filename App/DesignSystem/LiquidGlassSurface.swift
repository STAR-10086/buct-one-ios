import SwiftUI

struct BuctBackdropBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.05, green: 0.07, blue: 0.14), Color(red: 0.08, green: 0.12, blue: 0.22)]
                    : [Color(red: 0.92, green: 0.96, blue: 1.00), Color(red: 0.96, green: 0.94, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -110, y: -260)

            Circle()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.16 : 0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 130, y: 180)
        }
        .ignoresSafeArea()
    }
}

struct BuctGlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat
    let interactive: Bool
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled && !reduceTransparency {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
    }
}

extension View {
    func buctGlassCard(
        cornerRadius: CGFloat = 22,
        interactive: Bool = false,
        enabled: Bool = true
    ) -> some View {
        modifier(
            BuctGlassCardModifier(
                cornerRadius: cornerRadius,
                interactive: interactive,
                enabled: enabled
            )
        )
    }
}
