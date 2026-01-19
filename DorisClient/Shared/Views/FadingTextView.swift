import SwiftUI

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

#Preview {
    ZStack {
        DorisColors.coral.ignoresSafeArea()
        FadingTextView(text: "Hello! I'm Doris, your AI assistant. How can I help you today?")
            .padding()
    }
}
