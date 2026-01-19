import SwiftUI

struct MainPagerView: View {
    @ObservedObject var viewModel: DorisViewModel
    @AppStorage("lastUsedPage") private var selectedPage: Int = 0

    var body: some View {
        TabView(selection: $selectedPage) {
            VoiceView(viewModel: viewModel)
                .tag(0)

            TextChatView(viewModel: viewModel)
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
}
