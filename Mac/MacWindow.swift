import SwiftUI

/// The window: the scene's colors filling it, the four parts named along the top beside the
/// window buttons, and the part you're in below.
struct MacWindow: View {
    @Environment(Mixer.self) private var mixer
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    /// Read so temperatures redraw when the unit changes in Settings.
    @AppStorage("tempUnit") private var tempUnit = "auto"
    /// The window's size, so sheets fit inside it.
    @State private var size = CGSize(width: 480, height: 760)

    var body: some View {
        @Bindable var navigation = navigation
        VStack(spacing: 0) {
            TabBar(selection: $navigation.tab)
            Group {
                switch navigation.tab {
                case .listen: MacListen()
                case .layers: MacLayers()
                case .library: LibraryView(current: mixer.activePreset) { navigation.tab = .listen }
                case .world: GlobeView { navigation.tab = .listen }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .ignoresSafeArea(edges: .top)
        .background {
            // Listening and Layers sit in the scene's colors; the Library and World have their own.
            SceneWash(orbs: mixer.byVolume)
                .opacity(navigation.tab == .listen || navigation.tab == .layers ? 1 : 0)
                .background(Theme.background)
                .ignoresSafeArea()
        }
        .frame(minWidth: 440, minHeight: 640)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { size = proxy.size }
                    .onChange(of: proxy.size) { _, new in size = new }
            }
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.text)
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.3), value: navigation.tab)
        .saveMixPrompt(isPresented: $navigation.saving)
        .sheet(isPresented: $navigation.choosing) {
            WhereToView(start: mixer.mode == .atmosphere ? mixer.atmosphere : nil, onGo: { navigation.tab = .listen })
                .frame(width: max(380, min(480, size.width - 40)), height: max(520, min(760, size.height - 60)))
        }
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
        HStack(spacing: 22) {
            ForEach(MacNavigation.Tab.allCases) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue.uppercased())
                        .font(Theme.mono(11, .medium))
                        .tracking(1.3)
                        .foregroundStyle(selection == tab ? Theme.text : hovered == tab ? Theme.secondary : Theme.mono)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? tab : (hovered == tab ? nil : hovered) }
                .help("\(tab.rawValue)  ⌘\(String(tab.key.character))")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        // The title bar is 32 points tall, with the window buttons centered in it.
        .frame(height: 32)
        .padding(.bottom, 14)
    }
}
