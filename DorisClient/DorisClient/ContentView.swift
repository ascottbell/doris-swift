import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DorisViewModel()
    @State private var showHistory = false
    
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
        ZStack {
            // Background - must be first and use edgesIgnoringSafeArea
            Color(hex: "d1684e")
                .edgesIgnoringSafeArea(.all)
            
            GeometryReader { geometry in
                ZStack {
                    // Response text at bottom
                    if !viewModel.lastResponse.isEmpty {
                        VStack {
                            Spacer()
                            
                            FadingTextView(text: viewModel.lastResponse)
                                .frame(maxHeight: geometry.size.height * 0.35)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 80)
                        }
                    }
                    
                    // Donut animation
                    DorisAnimationView(state: animationState)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 60)
                        .contentShape(Circle().scale(1.5))
                        .onTapGesture {
                            viewModel.handleTap()
                        }
                    
                    // History pull tab
                    VStack {
                        Spacer()
                        HStack {
                            HistoryPullTab()
                                .onTapGesture {
                                    showHistory = true
                                }
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 30)
                    }
                    
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
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }
        }
        .statusBarHidden(false)
        .persistentSystemOverlays(.visible)
        .sheet(isPresented: $showHistory) {
            HistoryDrawerView(history: viewModel.conversationHistory)
        }
    }
}

/// Text that fades in line by line from bottom
struct FadingTextView: View {
    let text: String
    
    @State private var lines: [FadingLine] = []
    @State private var timer: Timer?
    @State private var lineIndex: Int = 0
    
    private func splitIntoLines(_ text: String) -> [String] {
        var result: [String] = []
        var currentLine = ""
        
        for word in text.split(separator: " ") {
            let test = currentLine.isEmpty ? String(word) : currentLine + " " + word
            if test.count > 35 && !currentLine.isEmpty {
                result.append(currentLine)
                currentLine = String(word)
            } else {
                currentLine = test
            }
        }
        if !currentLine.isEmpty {
            result.append(currentLine)
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                Text(line.text)
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(.black.opacity(0.85))
                    .opacity(line.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { startAnimation() }
        .onChange(of: text) { _, _ in
            timer?.invalidate()
            lines = []
            lineIndex = 0
            startAnimation()
        }
        .onDisappear { timer?.invalidate() }
    }
    
    private func startAnimation() {
        let allLines = splitIntoLines(text)
        guard lineIndex < allLines.count else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            guard lineIndex < allLines.count else {
                timer?.invalidate()
                return
            }
            
            let newLine = FadingLine(text: allLines[lineIndex])
            lines.append(newLine)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.3)) {
                    if let idx = lines.firstIndex(where: { $0.id == newLine.id }) {
                        lines[idx].opacity = 1.0
                    }
                }
            }
            
            lineIndex += 1
        }
    }
}

struct FadingLine: Identifiable {
    let id = UUID()
    let text: String
    var opacity: Double = 0
}

struct HistoryPullTab: View {
    var body: some View {
        Circle()
            .fill(Color(hex: "FFF8F0"))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 4)
    }
}

struct HistoryDrawerView: View {
    let history: [ConversationMessage]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(history) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.isUser ? "You" : "Doris")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Text(message.text)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
