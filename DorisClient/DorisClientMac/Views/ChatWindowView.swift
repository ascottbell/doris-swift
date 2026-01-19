import SwiftUI

/// Full window chat view - matches iOS design exactly
struct ChatWindowView: View {
    @EnvironmentObject var viewModel: DorisViewModel
    @State private var showHistory = false

    private var animationState: DorisAnimationState {
        switch viewModel.state {
        case .idle: return .idle
        case .listening: return .listening(power: viewModel.audioPower)
        case .thinking: return .thinking
        case .speaking: return .speaking(power: viewModel.audioPower)
        case .error: return .idle
        }
    }

    var body: some View {
        ZStack {
            // Full coral background - matches iOS
            DorisColors.coral
                .ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    // Response text at bottom - matches iOS
                    if !viewModel.lastResponse.isEmpty {
                        VStack {
                            Spacer()

                            FadingTextView(text: viewModel.lastResponse)
                                .frame(maxHeight: geometry.size.height * 0.35)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 80)
                        }
                    }

                    // Doris animation - centered, offset up by 60 points (matches iOS)
                    DorisAnimationView(state: animationState)
                        .frame(width: 200, height: 200)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 60)
                        .contentShape(Circle().scale(1.5))
                        .onTapGesture {
                            viewModel.handleTap()
                        }

                    // History pull tab (bottom left) - matches iOS
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: { showHistory = true }) {
                                Circle()
                                    .fill(DorisColors.warmWhite)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                            .help("View conversation history")
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 30)
                    }

                    // Error overlay - centered (matches iOS)
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
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 550)
        .sheet(isPresented: $showHistory) {
            HistoryView(history: viewModel.conversationHistory)
        }
    }
}

/// Conversation history sheet
struct HistoryView: View {
    let history: [ConversationMessage]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversation History")
                    .font(.headline)
                    .foregroundColor(DorisColors.warmWhite)
                Spacer()
                Button("Done") { dismiss() }
                    .foregroundColor(DorisColors.warmWhite)
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()
                .background(DorisColors.warmWhite.opacity(0.3))

            if history.isEmpty {
                Spacer()
                Text("No messages yet")
                    .foregroundColor(DorisColors.warmWhite.opacity(0.5))
                Spacer()
            } else {
                // Messages
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(history) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(message.isUser ? "You" : "Doris")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(DorisColors.warmWhite.opacity(0.7))

                                    Spacer()

                                    Text(message.timestamp, style: .time)
                                        .font(.system(size: 10))
                                        .foregroundColor(DorisColors.warmWhite.opacity(0.5))
                                }

                                Text(message.text)
                                    .font(.system(size: 14))
                                    .foregroundColor(DorisColors.warmWhite)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 350, minHeight: 400)
        .background(DorisColors.coral)
    }
}

#Preview {
    ChatWindowView()
        .environmentObject(DorisViewModel())
}
