import SwiftUI

struct ContentView: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        NavigationStack {
            NowPlayingView()
                .foregroundStyle(Theme.text)
                .background(Theme.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.text)
        .preferredColorScheme(.dark)
        .alert("Audio error", isPresented: .constant(mixer.errorMessage != nil)) {
            Button("OK") { mixer.errorMessage = nil }
        } message: {
            Text(mixer.errorMessage ?? "")
        }
    }
}
