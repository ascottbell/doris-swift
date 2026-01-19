import SwiftUI

struct IdleView: View {
    @State private var isBreathing = false
    
    // Soft warm white
    private let warmWhite = Color(hex: "FFF8F0")

    var body: some View {
        Circle()
            .fill(warmWhite)
            .frame(width: 120, height: 120)
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 12)
            .scaleEffect(isBreathing ? 1.0 : 0.8)
            .animation(
                Animation.easeInOut(duration: 3.0)
                    .repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear {
                isBreathing = true
            }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ZStack {
        Color(hex: "d1684e").ignoresSafeArea()
        IdleView()
    }
}
