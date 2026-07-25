import SwiftUI

enum XD {
    static let bgTop = Color(hex: 0xFFF5DB)
    static let bgBottom = Color(hex: 0xFFFDF2)
    static let primaryYellow = Color(hex: 0xFFD24A)
    static let primaryYellowDeep = Color(hex: 0xF6C94D)
    static let softYellow = Color(hex: 0xFFEB9E)
    static let paleYellow = Color(hex: 0xFFF4C7)
    static let cardBg = Color(hex: 0xFFFDF8)
    static let cardBorder = Color(hex: 0xEFE2CC)
    static let softDivider = Color(hex: 0xEFE3D2)

    static let textPrimary = Color(hex: 0x403027)
    static let textSecondary = Color(hex: 0x857367)
    static let textTertiary = Color(hex: 0xADA194)

    static let glassBorder = Color.white.opacity(0.55)
    static let warmShadow = Color(hex: 0x7A4E20).opacity(0.06)
    static let success = Color(hex: 0x3C9B55)
    static let danger = Color(hex: 0xB34732)

    static let cornerLarge: CGFloat = 24
    static let cornerMedium: CGFloat = 18
    static let cornerSmall: CGFloat = 14
    static let buttonHeight: CGFloat = 56

    static let largeTitle = Font.system(size: 32, weight: .bold, design: .rounded)
    static let title = Font.system(size: 20, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16.5, weight: .regular, design: .rounded)
    static let subhead = Font.system(size: 15, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 13, weight: .regular, design: .rounded)
    static let button = Font.system(size: 17, weight: .semibold, design: .rounded)
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct XDBackground: View {
    var body: some View {
        LinearGradient(colors: [XD.bgTop, XD.bgBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct XDYellowButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(XD.button)
            .foregroundStyle(XD.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: XD.buttonHeight)
            .background(
                LinearGradient(colors: [XD.primaryYellow, XD.primaryYellowDeep], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(Capsule())
            .shadow(color: XD.warmShadow, radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct XDOutlineButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(XD.button)
            .foregroundStyle(XD.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(XD.cardBg)
            .overlay(
                Capsule().stroke(XD.cardBorder, lineWidth: 1.5)
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct XDCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(XD.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: XD.cornerMedium, style: .continuous)
                    .stroke(XD.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: XD.cornerMedium, style: .continuous))
            .shadow(color: XD.warmShadow, radius: 10, x: 0, y: 5)
    }
}

extension View {
    func xdCard() -> some View { modifier(XDCardModifier()) }
}
