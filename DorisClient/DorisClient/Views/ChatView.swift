import SwiftUI

/// Message bubble for individual chat messages
struct MessageBubble: View {
    let message: ConversationMessage
    private let warmWhite = Color(red: 1.0, green: 0.973, blue: 0.941)

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            Text(message.text)
                .font(.system(size: 15))
                .foregroundColor(message.isUser ? .black : warmWhite)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.isUser
                        ? warmWhite
                        : Color.black.opacity(0.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))

            if !message.isUser { Spacer(minLength: 60) }
        }
    }
}

/// Chat interface with message history and text input
struct ChatView: View {
    let messages: [ConversationMessage]
    let onSend: (String) -> Void
    @Binding var chatHeight: CGFloat
    let maxHeight: CGFloat
    let isProcessing: Bool

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private let warmWhite = Color(red: 1.0, green: 0.973, blue: 0.941)
    private let inputAreaHeight: CGFloat = 82  // Input field + padding

    var body: some View {
        VStack(spacing: 0) {
            // Message history (if any)
            if !messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        // Auto-scroll to bottom
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // Input field area
            HStack(spacing: 12) {
                TextField("Message Doris...", text: $inputText, prompt: Text("Message Doris...").foregroundColor(warmWhite.opacity(0.5)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundColor(warmWhite)
                    .tint(warmWhite)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .focused($isInputFocused)
                    .onSubmit {
                        send()
                    }
                    .disabled(isProcessing)

                Button(action: send) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: warmWhite))
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(inputText.isEmpty ? warmWhite.opacity(0.4) : warmWhite)
                    }
                }
                .disabled(inputText.isEmpty || isProcessing)
                .padding(.trailing, 8)
            }
            .frame(height: 50)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(warmWhite, lineWidth: 2)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 16)
        }
        .frame(height: calculatedHeight)
        .onAppear {
            updateChatHeight()
        }
        .onChange(of: messages.count) { _, _ in
            updateChatHeight()
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        onSend(text)
    }

    private func updateChatHeight() {
        let newHeight = calculatedHeight
        withAnimation(.easeOut(duration: 0.3)) {
            chatHeight = newHeight
        }
    }

    private var calculatedHeight: CGFloat {
        if messages.isEmpty {
            return inputAreaHeight
        }
        // Once there are messages, take up at least 50% of max (which is 75% of screen)
        // So minimum becomes ~37.5% of screen, expanding to 75% max
        let minWithMessages = maxHeight * 0.67  // 50% of screen (0.67 * 0.75 ≈ 0.5)
        return minWithMessages
    }
}

#Preview {
    ZStack {
        Color(hex: "d1684e").ignoresSafeArea()

        VStack {
            Spacer()
            ChatView(
                messages: [
                    ConversationMessage(text: "What's the weather today?", isUser: true, timestamp: Date()),
                    ConversationMessage(text: "It's currently 72 degrees and sunny in your area.", isUser: false, timestamp: Date())
                ],
                onSend: { _ in },
                chatHeight: .constant(200),
                maxHeight: 400,
                isProcessing: false
            )
        }
    }
}
