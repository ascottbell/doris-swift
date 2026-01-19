import SwiftUI

struct SpeakingView: View {
    var power: Double
    
    // Soft warm white
    private let warmWhite = Color(hex: "FFF8F0")
    
    // Base size matches the thinking loop's approximate diameter
    private let baseSize: CGFloat = 100
    
    var body: some View {
        ZStack {
            // Main ring that pulses with audio
            Circle()
                .stroke(warmWhite, lineWidth: 4 + (power * 2))
                .frame(
                    width: baseSize + (power * 20),
                    height: baseSize + (power * 20)
                )
            
            // Inner subtle ring
            Circle()
                .stroke(warmWhite.opacity(0.5), lineWidth: 2)
                .frame(
                    width: baseSize - 20 + (power * 10),
                    height: baseSize - 20 + (power * 10)
                )
            
            // Outer glow ring
            Circle()
                .stroke(warmWhite.opacity(0.3), lineWidth: 1.5)
                .frame(
                    width: baseSize + 30 + (power * 30),
                    height: baseSize + 30 + (power * 30)
                )
        }
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 12)
        .animation(.easeOut(duration: 0.08), value: power)
    }
}

#Preview {
    ZStack {
        Color(hex: "d1684e").ignoresSafeArea()
        
        VStack(spacing: 60) {
            SpeakingView(power: 0.0)
            SpeakingView(power: 0.5)
            SpeakingView(power: 1.0)
        }
    }
}
