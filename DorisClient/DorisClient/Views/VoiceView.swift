import SwiftUI

struct VoiceView: View {
    @ObservedObject var viewModel: DorisViewModel

    private var animationState: DorisAnimationState {
        switch viewModel.state {
        case .idle:
            return .idle
        case .listening:
            return .listening(power: viewModel.audioPower)
        case .thinking:
            return .thinking
        case .speaking:
            return .speaking(power: viewModel.audioPower)
        case .error:
            return .idle
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(hex: "d1684e")
                    .ignoresSafeArea()

                // Donut animation - centered
                DorisAnimationView(state: animationState)
                    .frame(width: 350, height: 320)
                    .contentShape(Circle())
                    .onTapGesture {
                        viewModel.handleTap()
                    }
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2 - 60
                    )

                // Error overlay
                if case .error(let message) = viewModel.state {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))

                        Text(message)
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.black.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.3)
                }
            }
        }
        .persistentSystemOverlays(.visible)
    }
}
