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

/// The four parts as pills in the title bar, level with the window buttons, the one you're in
/// lit; and beside the window buttons, a way back.
private struct TabBar: View {
    @Environment(Mixer.self) private var mixer
    @Binding var selection: MacNavigation.Tab
    @State private var hovered: MacNavigation.Tab?
    @State private var hoveringBack = false
    @Namespace private var pill

    var body: some View {
        // Centered when there's room; in a narrow window, pushed right to clear the window
        // buttons and the way back.
        HStack(spacing: 0) {
            Spacer(minLength: 120)
            tabs
            Spacer(minLength: 12)
        }
        .overlay(alignment: .leading) { back.padding(.leading, 78) }
        // The title bar is 32 points tall, with the window buttons centered in it.
        .frame(height: 32)
        .padding(.bottom, 14)
        .animation(.smooth(duration: 0.25), value: mixer.backStack.isEmpty)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(MacNavigation.Tab.allCases) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue.uppercased())
                        .font(Theme.caps(10.5))
                        .tracking(1.1)
                        .foregroundStyle(selection == tab ? Theme.text : hovered == tab ? Theme.secondary : Theme.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background {
                            if selection == tab {
                                Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "lit", in: pill)
                            } else if hovered == tab {
                                Capsule().fill(.white.opacity(0.05))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? tab : (hovered == tab ? nil : hovered) }
                .help("\(tab.rawValue)  ⌘\(String(tab.key.character))")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .fixedSize()
    }

    /// From Teleport, Layers or the Library, back to listening; while listening, back to the
    /// place before this one (as swiping right does), once there's been one.
    @ViewBuilder private var back: some View {
        if selection != .listen {
            backButton("Back to Listen") { selection = .listen }
        } else if let last = mixer.backStack.last {
            backButton("Back to \(mixer.page(for: last).title)  ←") { mixer.requestTravel(forward: false) }
        }
    }

    private func backButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hoveringBack ? Theme.text : Theme.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(hoveringBack ? 0.12 : 0.05)))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringBack = $0 }
        .help(label)
        .accessibilityLabel(label)
        .transition(.opacity)
    }
}
