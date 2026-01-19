import SwiftUI

/// Compact chat view for menu bar popover - matches iOS design
struct ChatPopoverView: View {
    @EnvironmentObject var viewModel: DorisViewModel
    @EnvironmentObject var menuBarManager: MenuBarManager
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

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
            // Full coral background
            DorisColors.coral.ignoresSafeArea()

            VStack(spacing: 0) {
                // Animation orb (centered, tap to talk)
                Spacer()

                DorisAnimationView(state: animationState)
                    .frame(width: 160, height: 160)
                    .contentShape(Circle().scale(1.5))
                    .onTapGesture {
                        viewModel.handleTap()
                    }

                // State indicator
                stateIndicator
                    .padding(.top, 8)

                Spacer()

                // Response text (fades in line by line)
                if !viewModel.lastResponse.isEmpty {
                    FadingTextView(text: viewModel.lastResponse)
                        .frame(maxHeight: 100)
                        .padding(.horizontal, 16)
                }

                Spacer()
                    .frame(height: 12)

                // Input field at bottom
                HStack(spacing: 8) {
                    TextField("Message Doris...", text: $inputText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DorisColors.warmWhite.opacity(0.2))
                        .cornerRadius(20)
                        .foregroundColor(DorisColors.warmWhite)
                        .focused($isInputFocused)
                        .onSubmit { sendMessage() }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(DorisColors.warmWhite)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty || viewModel.state == .thinking)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // Top bar: Settings (left) and Expand (right)
            VStack {
                HStack {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .foregroundColor(DorisColors.warmWhite.opacity(0.7))
                            .padding(8)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: openFullWindow) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundColor(DorisColors.warmWhite.opacity(0.7))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 320, height: 440)
        .onAppear {
            isInputFocused = true
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch viewModel.state {
        case .idle:
            Text("Tap to talk")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(DorisColors.warmWhite.opacity(0.7))
        case .listening:
            Text("Listening...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DorisColors.warmWhite)
        case .thinking:
            Text("Thinking...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DorisColors.warmWhite)
        case .speaking:
            Text("Speaking")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DorisColors.warmWhite)
        case .error(let msg):
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(DorisColors.warmWhite.opacity(0.8))
                .lineLimit(1)
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        viewModel.sendTextMessage(text)
    }

    private func openFullWindow() {
        menuBarManager.hidePopover()

        // Open the full window
        NSApp.sendAction(Selector(("showWindow:")), to: nil, from: nil)

        if let window = NSApp.windows.first(where: { $0.title == "Doris" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

}

#Preview {
    ChatPopoverView()
        .environmentObject(DorisViewModel())
        .environmentObject(MenuBarManager())
}
