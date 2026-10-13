import SwiftUI

/// The window: the scene's colors filling it, the four parts named along the top beside the
/// window buttons, and the part you're in below.
struct MacWindow: View {
    @Environment(Mixer.self) private var mixer
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    /// Read so temperatures redraw when the unit changes in Settings.
    @AppStorage("tempUnit") private var tempUnit = "auto"

    var body: some View {
        @Bindable var navigation = navigation
        VStack(spacing: 0) {
            TabBar(selection: $navigation.tab)
            Group {
                switch navigation.tab {
                case .listen: MacListen()
                case .teleport:
                    TeleportView(start: mixer.mode == .atmosphere ? mixer.atmosphere : nil) { navigation.tab = .listen }
                case .layers: MacLayers()
                case .library: LibraryView(current: mixer.activePreset) { navigation.tab = .listen }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .ignoresSafeArea(edges: .top)
        .background {
            // Listening and Layers sit in the scene's colors; Teleport and the Library have their own.
            SceneWash(orbs: mixer.byVolume)
                .opacity(navigation.tab == .listen || navigation.tab == .layers ? 1 : 0)
                .background(Theme.background)
                .ignoresSafeArea()
        }
        .frame(minWidth: 440, minHeight: 640)
        .foregroundStyle(Theme.text)
        .tint(Theme.text)
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.3), value: navigation.tab)
        .saveMixPrompt(isPresented: $navigation.saving)
        .confirmReset(isPresented: $navigation.resetting)
        .alert("Audio error", isPresented: .constant(mixer.errorMessage != nil)) {
            Button("OK") { mixer.errorMessage = nil }
        } message: {
            Text(mixer.errorMessage ?? "")
        }
        .sensoryFeedback(.selection, trigger: navigation.tab)
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-previewPanel") { openWindow(id: "panelPreview") }
        }
        #endif
    }
}

/// The four parts as quiet words in the title bar, level with the window buttons, the one
/// you're in lit.
private struct TabBar: View {
    @Binding var selection: MacNavigation.Tab
    @State private var hovered: MacNavigation.Tab?

    var body: some View {
        // Centered when there's room; in a narrow window, pushed right to clear the window buttons.
        HStack(spacing: 0) {
            Spacer(minLength: 84)
            tabs
            Spacer(minLength: 12)
        }
        // The title bar is 32 points tall, with the window buttons centered in it.
        .frame(height: 32)
        .padding(.bottom, 14)
    }

    private var tabs: some View {
        HStack(spacing: 20) {
            ForEach(MacNavigation.Tab.allCases) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue.uppercased())
                        .font(Theme.caps(11))
                        .tracking(1.3)
                        .foregroundStyle(selection == tab ? Theme.text : hovered == tab ? Theme.secondary : Theme.muted)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? tab : (hovered == tab ? nil : hovered) }
                .help("\(tab.rawValue)  ⌘\(String(tab.key.character))")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}
