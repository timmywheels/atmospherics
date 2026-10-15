import SwiftUI

/// The window: the scene's colors filling it, the two parts as pills in the toolbar with a way
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
            case .listen:
                // Tune as a drawer over the right of Listen, as on the phone.
                GeometryReader { proxy in
                    ZStack(alignment: .trailing) {
                        MacListen()
                        if navigation.tuning {
                            TuneDrawer(room: proxy.size.width)
                                .transition(.move(edge: .trailing))
                        }
                    }
                }
                .animation(.smooth(duration: 0.28), value: navigation.tuning)
            case .library:
                LibraryView(current: mixer.activePreset, focus: navigation.searchNext) { navigation.tab = .listen }
                    .id(navigation.searchRequests)
                    .onAppear { navigation.searchNext = false }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .modifier(WindowBar(selection: $navigation.tab))
        .background {
            // Listening sits in the scene's colors; the Library has its own.
            SceneWash(orbs: mixer.byVolume)
                .opacity(navigation.tab == .listen ? 1 : 0)
                .background(Theme.background)
                .ignoresSafeArea()
        }
        // Wide enough for the toolbar's one piece (back and the two tabs) beside the window buttons.
        .frame(minWidth: 480, minHeight: 640)
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
        .haptic(.tick, trigger: navigation.tab)
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-previewPanel") { openWindow(id: "panelPreview") }
        }
        #endif
    }
}

/// The toolbar, as tall as a Mac's (the window buttons centered in it): a way back and the two
/// parts as pills, as one piece in the middle. One piece, so the toolbar never has to fit two
/// side by side and tuck one into an overflow menu when the window is narrow. Plain, without the
/// glass a toolbar item gets by default.
private struct WindowBar: ViewModifier {
    @Binding var selection: MacNavigation.Tab

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .principal) { bar }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .principal) { bar }
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            BackButton(selection: $selection)
            TabPills(selection: $selection)
        }
        .fixedSize()
    }
}

/// The two parts in one capsule, the one you're in lit by a pill that slides between them.
private struct TabPills: View {
    @Binding var selection: MacNavigation.Tab
    @State private var hovered: MacNavigation.Tab?
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MacNavigation.Tab.allCases) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue.uppercased())
                        .font(Theme.caps(10))
                        .tracking(0.9)
                        .foregroundStyle(selection == tab ? Theme.text : hovered == tab ? Theme.secondary : Theme.muted)
                        .padding(.horizontal, 9)
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
                .help("\(tab.rawValue)  ⌘\(String(tab.key.character).uppercased())")
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

/// From the Library, back to listening. One job: while listening it's out of
/// sight (traveling back is ←, ⌘← and the arrow over the halo), but keeps its place, so the tabs
/// never shift.
private struct BackButton: View {
    @Binding var selection: MacNavigation.Tab
    @State private var hovering = false

    var body: some View {
        let enabled = selection != .listen
        Button { selection = .listen } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Theme.text : Theme.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0.05)))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0)
        .onHover { hovering = $0 }
        .help("Back to Listen")
        .accessibilityLabel("Back to Listen")
        .accessibilityHidden(!enabled)
        .animation(.smooth(duration: 0.2), value: enabled)
    }
}

