import SwiftUI

/// macOS side-by-side layout: Voice orb on left, chat on right
struct ChatWindowView: View {
    @EnvironmentObject var viewModel: DorisViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Left: Voice panel with orb
            VoicePane(viewModel: viewModel)
                .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)

            // Subtle divider
            Rectangle()
                .fill(DorisColors.warmWhite.opacity(0.15))
                .frame(width: 1)

            // Right: Chat panel
            ChatPane(viewModel: viewModel)
                .frame(minWidth: 350, idealWidth: 450)
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(DorisColors.coral)
    }
}

// MARK: - Voice Pane (Left Side)

struct VoicePane: View {
    @ObservedObject var viewModel: DorisViewModel

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
        GeometryReader { geometry in
            ZStack {
                DorisColors.coral

                // Doris animation - centered
                DorisAnimationView(state: animationState)
                    .frame(width: 200, height: 200)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 40)
                    .contentShape(Circle().scale(1.5))
                    .onTapGesture {
                        viewModel.handleTap()
                    }

                // State indicator below orb
                VStack {
                    Spacer()
                        .frame(height: geometry.size.height / 2 + 80)

                    stateIndicator
                        .padding(.horizontal, 20)

                    Spacer()
                }

                // Error overlay
                if case .error(let message) = viewModel.state {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.8))

                        Text(message)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.black.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch viewModel.state {
        case .idle:
            Text("Tap orb to talk")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(DorisColors.warmWhite.opacity(0.6))
        case .listening:
            Text("Listening...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DorisColors.warmWhite)
        case .thinking:
            Text("Thinking...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DorisColors.warmWhite)
        case .speaking:
            Text("Speaking...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DorisColors.warmWhite)
        case .error:
            EmptyView()
        }
    }
}

// MARK: - Chat Pane (Right Side)

struct ChatPane: View {
    @ObservedObject var viewModel: DorisViewModel
    @State private var inputText = ""
    @State private var isSearchMode = false
    @State private var searchText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar at top
            searchBar
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Messages or search results
            if isSearchMode {
                searchResultsView
            } else {
                messagesView
            }

            // Input bar at bottom
            if !isSearchMode {
                inputBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(DorisColors.coral.opacity(0.95))
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DorisColors.warmWhite.opacity(0.6))
                .padding(.leading, 12)

            TextField("Search messages...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(DorisColors.warmWhite)
                .onChange(of: searchText) { _, newValue in
                    isSearchMode = !newValue.isEmpty
                }

            if isSearchMode {
                Button(action: {
                    searchText = ""
                    isSearchMode = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DorisColors.warmWhite.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
        }
        .frame(height: 36)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DorisColors.warmWhite.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Messages grouped by date
                    ForEach(groupedMessages, id: \.date) { group in
                        // Date header
                        Text(formatDateHeader(group.date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DorisColors.warmWhite.opacity(0.5))
                            .padding(.vertical, 8)

                        // Messages for this date
                        ForEach(group.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.conversationHistory.count) { _, _ in
                if let last = viewModel.conversationHistory.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // Scroll to bottom on initial load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let last = viewModel.conversationHistory.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if filteredMessages.isEmpty {
                    Text("No messages found")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(DorisColors.warmWhite.opacity(0.5))
                        .padding(.top, 40)
                } else {
                    Text("\"\(searchText)\" - \(filteredMessages.count) results")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DorisColors.warmWhite.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ForEach(filteredMessages) { message in
                        SearchResultRow(message: message)
                            .onTapGesture {
                                searchText = ""
                                isSearchMode = false
                            }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message Doris...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(DorisColors.warmWhite)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(inputText.isEmpty ? DorisColors.warmWhite.opacity(0.4) : DorisColors.warmWhite)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty)
            .padding(.trailing, 8)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .frame(height: 44)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(DorisColors.warmWhite, lineWidth: 1.5)
        )
    }

    // MARK: - Helpers

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        viewModel.sendTextMessage(text)
    }

    private var filteredMessages: [ConversationMessage] {
        guard !searchText.isEmpty else { return [] }
        return viewModel.searchMessages(query: searchText)
    }

    private var groupedMessages: [MessageGroup] {
        let calendar = Calendar.current
        var groups: [Date: [ConversationMessage]] = [:]

        for message in viewModel.conversationHistory {
            let dateKey = calendar.startOfDay(for: message.timestamp)
            groups[dateKey, default: []].append(message)
        }

        return groups.map { MessageGroup(date: $0.key, messages: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundColor(message.isUser ? .white : .black.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser
                            ? Color.black.opacity(0.25)
                            : DorisColors.warmWhite.opacity(0.9)
                    )
                    .cornerRadius(18)

                Text(formatTime(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(DorisColors.warmWhite.opacity(0.5))
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
                .font(.system(size: 13))
                .foregroundColor(DorisColors.warmWhite)
                .lineLimit(2)

            Text(formatDate(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(DorisColors.warmWhite.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.12))
        .cornerRadius(10)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct MessageGroup {
    let date: Date
    let messages: [ConversationMessage]
}

#Preview {
    ChatWindowView()
        .environmentObject(DorisViewModel())
}
