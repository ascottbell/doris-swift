import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DorisViewModel()

    var body: some View {
        MainPagerView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}
