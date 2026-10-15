import SwiftUI

/// Saved mixes, filterable by Sleep / Focus / Relax. Tapping one loads it onto the field.
/// Your own mixes come first: swipe left to delete, right to rename, hold and drag to reorder.
/// Recent is where you've been, newest first, to go back to. It opens on the mix that's
/// playing, under its own filter.
struct LibraryView: View {
    /// Where to go once a mix is chosen, when the Library is part of a window (on the Mac)
    /// rather than a sheet.
    var done: (() -> Void)? = nil
    @Environment(Mixer.self) private var mixer
    @Environment(\.dismiss) private var dismiss
    @State private var shelf: Shelf
    @State private var renaming: SavedMix?
    @State private var newName = ""
    @State private var deletes = 0
    @State private var showingScience = false
    private let current: Preset?

    /// What the list shows: everything, where you've been, your favorites, your own mixes, or
    /// the Library's mixes for sleep, focus or relaxing.
    private enum Shelf: Hashable {
        case all, recent, favorites, yours
        case tagged(Preset.Tag)
    }

    init(current: Preset? = nil, done: (() -> Void)? = nil) {
        self.current = current
        self.done = done
        _shelf = State(initialValue: current?.isSaved == true ? .yours : current?.tag.map(Shelf.tagged) ?? .all)
    }

    private var yours: [SavedMix] { shelf == .all || shelf == .yours ? mixer.savedMixes : [] }
    private var builtIn: [Preset] {
        switch shelf {
        case .all: Preset.all
        case .tagged(let tag): Preset.all.filter { $0.tag == tag }
        case .recent, .favorites, .yours: []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(Theme.display(36))
                .padding(.horizontal, 4)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip("All", .all)
                    if !mixer.recent.isEmpty || shelf == .recent { chip("Recent", .recent) }
                    if !mixer.favorites.isEmpty || shelf == .favorites { chip("Favorites", .favorites) }
                    if !mixer.savedMixes.isEmpty { chip("Yours", .yours) }
                    ForEach(Preset.Tag.allCases, id: \.self) { tag in chip(tag.rawValue, .tagged(tag)) }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -24)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollViewReader { proxy in
                List {
                    if shelf == .recent {
                        ForEach(mixer.recentItems, id: \.visit.id) { entry in
                            switch entry.item {
                            case .scene(let a): scene(a, when: entry.visit.at)
                            case .mix(let p): item(p, when: entry.visit.at)
                            case .place(let p): place(p, when: entry.visit.at)
                            }
                        }
                        if mixer.recent.isEmpty {
                            note("Where you go shows up here, newest first.")
                        } else {
                            Button("Clear Recent") { mixer.clearRecent() }
                                .font(Theme.label(12, .medium))
                                .foregroundStyle(Theme.secondary)
                                .buttonStyle(.plain)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 4)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    if shelf == .tagged(.focus) {
                        Button { showingScience = true } label: {
                            HStack(spacing: 6) {
                                Text("How we chose these")
                                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                            }
                            .font(Theme.label(11, .medium))
                            .foregroundStyle(Theme.secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    if shelf == .favorites {
                        ForEach(mixer.favoriteItems) { favorite in
                            switch favorite {
                            case .scene(let a): scene(a)
                            case .mix(let p): item(p)
                            case .place(let p): place(p)
                            }
                        }
                        if mixer.favorites.isEmpty {
                            note("Tap the bookmark by a name to keep it here.")
                        }
                    }
                    ForEach(yours) { mix in
                        item(mix.preset)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(mix) }
                                    .tint(.red)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Rename", systemImage: "pencil") { newName = mix.name; renaming = mix }
                                    .tint(Color(white: 0.35))
                            }
                            #if os(macOS)
                            // With a mouse, the same through a right click.
                            .contextMenu {
                                Button("Rename…") { newName = mix.name; renaming = mix }
                                Button("Delete", role: .destructive) { delete(mix) }
                            }
                            #endif
                    }
                    .onMove { mixer.moveSavedMixes(from: $0, to: $1) }
                    ForEach(builtIn) { item($0) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .onAppear {
                    if let id = current?.id { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .notices(above: 28)
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .animation(.smooth(duration: 0.25), value: shelf)
        .animation(.smooth(duration: 0.25), value: mixer.favorites)
        .animation(.smooth(duration: 0.25), value: mixer.recent)
        .alert("Rename mix", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let r = renaming { mixer.rename(r, to: newName) } }
        }
        .sheet(isPresented: $showingScience) {
            FocusScienceView()
                #if os(macOS)
                .frame(width: 540, height: 680)
                #endif
        }
        .haptic(.tick, trigger: shelf)
        .haptic(.thud, trigger: deletes)
        .haptic(.tap, trigger: mixer.savedMixes.map(\.id))
    }

    /// Played, and the Library closed (or, on the Mac, back to listening).
    private func close() {
        if let done { done() } else { dismiss() }
    }

    /// One row of the list: tap to play it. In Recent, `when` you last played it.
    private func item(_ preset: Preset, when: Date? = nil) -> some View {
        Button {
            Haptics.play(.thud)
            mixer.load(preset)
            close()
        } label: {
            row(preset, when: when)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) { FavoriteToggle(key: Mixer.favoriteKey(preset)).padding(6) }
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(preset.id)
    }

    /// A scene: tap to go there (in Recent, with `when` you were last there).
    private func scene(_ a: Atmosphere, when: Date? = nil) -> some View {
        let page = mixer.page(for: .atmosphere(a))
        let current = mixer.mode == .atmosphere && mixer.activePreset == nil && mixer.atmosphere == a
        return Button {
            Haptics.play(.thud)
            mixer.revisit(.scene(a))
            close()
        } label: {
            ColorCard(hues: page.orbs.sorted { $0.volume > $1.volume }.prefix(3).map(\.kind.hue),
                      top: Self.top(a.setting.info.name, when), title: page.title, sounds: page.orbs,
                      badge: current ? (mixer.isPlaying ? "Playing" : "Here") : nil, outlined: current,
                      trailingRoom: 30)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) { FavoriteToggle(key: Mixer.favoriteKey(a)).padding(6) }
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(Mixer.favoriteKey(a))
    }

    /// A real place you've been: tap to go back, to its weather now.
    private func place(_ p: Place, when: Date? = nil) -> some View {
        let page = mixer.page(for: .place(p))
        let current = mixer.mode == .escape && mixer.activePreset == nil && mixer.escape?.place.name == p.name
        return Button {
            Haptics.play(.thud)
            mixer.revisit(.place(p))
            close()
        } label: {
            ColorCard(hues: page.orbs.sorted { $0.volume > $1.volume }.prefix(3).map(\.kind.hue),
                      top: Self.top(p.country, when), title: p.title, sounds: page.orbs,
                      badge: current ? (mixer.isPlaying ? "Playing" : "Here") : nil, outlined: current,
                      trailingRoom: 30)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) { FavoriteToggle(key: Mixer.favoriteKey(p)).padding(6) }
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id("place:\(p.name)")
    }

    /// A card's top line: "Temple garden · 2 hours ago".
    private static func top(_ what: String, _ when: Date?) -> String {
        [what, when.map { $0.formatted(.relative(presentation: .named)) }].compactMap { $0 }.joined(separator: " · ")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.label(12))
            .foregroundStyle(Theme.secondary)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func delete(_ mix: SavedMix) {
        deletes += 1
        withAnimation { mixer.delete(mix) }
        if mixer.savedMixes.isEmpty && shelf == .yours { shelf = .all }
    }

    private func chip(_ label: String, _ choice: Shelf) -> some View {
        let selected = shelf == choice
        return Button { shelf = choice } label: {
            Text(label)
                .font(Theme.body(13, .medium))
                .foregroundStyle(selected ? Theme.background : Theme.text)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Capsule().fill(selected ? Theme.text : .clear))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A card in the colors of its mix: what it's for and how long at the top (and in Recent, `when`
    /// you last played it), its name at the bottom.
    private func row(_ preset: Preset, when: Date? = nil) -> some View {
        let current = preset.id == mixer.activePreset?.id
        return ColorCard(hues: preset.mix.prefix(3).map(\.0.hue),
                         top: (preset.tag.map { "\($0.rawValue) · \(preset.length)" } ?? "Yours")
                             + (preset.evidence.map { " · \($0.rawValue)" } ?? "")
                             + (when.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? ""),
                         title: preset.name, subtitle: preset.description,
                         badge: current ? (mixer.isPlaying ? "Playing" : "Current") : nil, outlined: current,
                         trailingRoom: 30)
    }
}

/// Asks for a name, pre-filled with a suggestion, and saves the current mix.
struct SaveMixPrompt: ViewModifier {
    @Environment(Mixer.self) private var mixer
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var saves = 0

    func body(content: Content) -> some View {
        content
            .alert("Save this mix", isPresented: $isPresented) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    mixer.saveCurrent(named: name)
                    saves += 1
                }
            } message: {
                Text("It'll keep sounding exactly like this, in Library › Yours.")
            }
            .onChange(of: isPresented) { _, shown in if shown { name = mixer.suggestedSaveName } }
            .haptic(.thud, trigger: saves)
    }
}

extension View {
    func saveMixPrompt(isPresented: Binding<Bool>) -> some View { modifier(SaveMixPrompt(isPresented: isPresented)) }
}
