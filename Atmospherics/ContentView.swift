import SwiftUI

struct ContentView: View {
    @Environment(Mixer.self) private var mixer
    @AppStorage("onboarded") private var onboarded = true

    var body: some View {
        NavigationStack {
            NowPlayingView()
                .foregroundStyle(Theme.text)
                .background(Theme.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
        }
        // The first time: the welcome, over everything.
        .overlay {
            if !onboarded {
                Onboarding { withAnimation(.smooth(duration: 0.6)) { onboarded = true } }
                    .transition(.opacity)
            }
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
