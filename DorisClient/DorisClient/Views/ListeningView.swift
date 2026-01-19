import SwiftUI

struct ListeningView: View {
    var power: Double
    
    // Soft warm white
    private let warmWhite = Color(hex: "FFF8F0")
    
    var body: some View {
        ZStack {
            // Outer glow ring that pulses with audio
            Circle()
                .stroke(warmWhite.opacity(0.3), lineWidth: 2)
                .frame(width: 140 + (power * 40), height: 140 + (power * 40))
                .animation(.easeOut(duration: 0.1), value: power)
            
            // Middle ring
            Circle()
                .stroke(warmWhite.opacity(0.5), lineWidth: 3)
                .frame(width: 120 + (power * 20), height: 120 + (power * 20))
                .animation(.easeOut(duration: 0.1), value: power)
            
            // Core circle that pulses with mic input
            Circle()
                .fill(warmWhite)
                .frame(width: 100 + (power * 30), height: 100 + (power * 30))
                .animation(.easeOut(duration: 0.1), value: power)
            
            // Inner highlight
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.0)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 90 + (power * 25), height: 90 + (power * 25))
                .animation(.easeOut(duration: 0.1), value: power)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        ListeningView(power: 0.0)
        ListeningView(power: 0.5)
        ListeningView(power: 1.0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(hex: "d1684e"))
}
