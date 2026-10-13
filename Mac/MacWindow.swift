import SwiftUI

/// The window: the scene's colors filling it, the four parts as pills in the toolbar with a way
/// back beside the window buttons, and the part you're in below.
struct MacWindow: View {
    @Environment(Mixer.self) private var mixer
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    /// Read so temperatures redraw when the unit changes in Settings.
    @AppStorage("tempUnit") private var tempUnit = "auto"

    var body: some View {
        @Bindable var navigation = navigation
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
        .modifier(WindowBar(selection: $navigation.tab))
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

/// The toolbar, as tall as a Mac's (the window buttons centered in it): a way back beside the
/// window buttons, and the four parts as pills in the middle. Plain, without the glass a
/// toolbar item gets by default.
private struct WindowBar: ViewModifier {
    @Binding var selection: MacNavigation.Tab

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .navigation) { BackButton(selection: $selection) }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) { TabPills(selection: $selection) }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .navigation) { BackButton(selection: $selection) }
                ToolbarItem(placement: .principal) { TabPills(selection: $selection) }
            }
        }
    }
}

/// The four parts in one capsule, the one you're in lit by a pill that slides between them.
private struct TabPills: View {
    @Binding var selection: MacNavigation.Tab
    @State private var hovered: MacNavigation.Tab?
    @Namespace private var pill

    var body: some View {
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
        .animation(.smooth(duration: 0.3), value: selection)
    }
}

/// From Teleport, Layers or the Library, back to listening; while listening, back to the place
/// before this one (as swiping right does), once there's been one.
private struct BackButton: View {
    @Environment(Mixer.self) private var mixer
    @Binding var selection: MacNavigation.Tab
    @State private var hovering = false

    var body: some View {
        Group {
            if selection != .listen {
                button("Back to Listen") { selection = .listen }
            } else if let last = mixer.backStack.last {
                button("Back to \(mixer.page(for: last).title)  ←") { mixer.requestTravel(forward: false) }
            }
        }
        .animation(.smooth(duration: 0.25), value: selection == .listen && mixer.backStack.isEmpty)
    }

    private func button(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Theme.text : Theme.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0.05)))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .transition(.opacity)
    }
}
