import SwiftUI

struct TextChatView: View {
    @ObservedObject var viewModel: DorisViewModel
    @State private var inputText = ""
    @State private var isSearchMode = false
    @State private var searchText = ""
    @FocusState private var isInputFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var loadedMessageCount: Int = 50
    @State private var isLoadingMore: Bool = false

    private let warmWhite = Color(red: 1.0, green: 0.973, blue: 0.941)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: "d1684e")
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar at top - more padding from Dynamic Island
                    searchBar
                        .padding(.top, 4)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    // Messages or search results
                    if isSearchMode {
                        searchResultsView
                    } else {
                        messagesView
                    }

                    // Input bar at bottom (hidden during search)
                    if !isSearchMode {
                        inputBar
                            .padding(.horizontal, 16)
                            .padding(.bottom, max(16, keyboardHeight - geometry.safeAreaInsets.bottom + 8))
                    }
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear {
            setupKeyboardObservers()
        }
        .onDisappear {
            removeKeyboardObservers()
        }
        .onTapGesture {
            isInputFocused = false
            isSearchFocused = false
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(warmWhite.opacity(0.6))
                .padding(.leading, 12)

            TextField("Search messages...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(warmWhite)
                .tint(warmWhite)
                .focused($isSearchFocused)
                .onChange(of: searchText) { _, newValue in
                    isSearchMode = !newValue.isEmpty
                }
                .onSubmit {
                    // Trigger search
                }

            if isSearchMode {
                Button(action: {
                    searchText = ""
                    isSearchMode = false
                    isSearchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(warmWhite.opacity(0.6))
                }
                .padding(.trailing, 12)
            }
        }
        .frame(height: 44)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(warmWhite.opacity(0.5), lineWidth: 1.5)
        )
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Load more button at top
                    if viewModel.conversationHistory.count >= loadedMessageCount {
                        Button(action: loadEarlierMessages) {
                            if isLoadingMore {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: warmWhite.opacity(0.6)))
                                    .padding(.vertical, 12)
                            } else {
                                Text("Load earlier messages")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(warmWhite.opacity(0.6))
                                    .padding(.vertical, 12)
                            }
                        }
                        .disabled(isLoadingMore)
                    }

                    // Messages grouped by date
                    ForEach(groupedMessages, id: \.date) { group in
                        // Date header
                        Text(formatDateHeader(group.date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(warmWhite.opacity(0.5))
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
        }
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if filteredMessages.isEmpty {
                    Text("No messages found")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(warmWhite.opacity(0.5))
                        .padding(.top, 40)
                } else {
                    Text("\"\(searchText)\" - \(filteredMessages.count) results")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(warmWhite.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ForEach(filteredMessages) { message in
                        SearchResultRow(message: message)
                            .onTapGesture {
                                // Exit search and scroll to message
                                searchText = ""
                                isSearchMode = false
                                // TODO: Scroll to message
                            }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message Doris...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(warmWhite)
                .tint(warmWhite)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }
                .disabled(viewModel.isProcessingText)

            Button(action: sendMessage) {
                if viewModel.isProcessingText {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: warmWhite))
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(inputText.isEmpty ? warmWhite.opacity(0.4) : warmWhite)
                }
            }
            .disabled(inputText.isEmpty || viewModel.isProcessingText)
            .padding(.trailing, 8)
        }
        .frame(height: 50)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(warmWhite, lineWidth: 2)
        )
    }

    // MARK: - Helpers

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        viewModel.sendTextMessage(text)
    }

    private func loadEarlierMessages() {
        guard !isLoadingMore else { return }
        isLoadingMore = true

        // Use a small delay to allow UI to update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let loaded = viewModel.loadEarlierMessages(offset: loadedMessageCount)
            if loaded > 0 {
                loadedMessageCount += loaded
            }
            isLoadingMore = false
        }
    }

    /// Search messages using FTS5 full-text search
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

    // MARK: - Keyboard Handling

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }

    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
}

// MARK: - Supporting Types

struct MessageGroup {
    let date: Date
    let messages: [ConversationMessage]
}

struct SearchResultRow: View {
    let message: ConversationMessage
    private let warmWhite = Color(red: 1.0, green: 0.973, blue: 0.941)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
                .font(.system(size: 15))
                .foregroundColor(warmWhite)
                .lineLimit(2)

            Text(formatDate(message.timestamp))
                .font(.system(size: 12))
                .foregroundColor(warmWhite.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.15))
        .cornerRadius(12)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    TextChatView(viewModel: DorisViewModel())
}
