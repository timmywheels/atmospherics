import SwiftUI

/// Everything the app can play, on shelves: Places (where you are first, then the real places,
/// in their live weather), Mixes by mood, Scenes by mood, every Sound, Yours (all you've kept, in
/// your order) and Recent. The field at the top, Where to?, finds anything on any shelf. A card
/// plays and closes the Library; a sound's pill adds it to what's playing and stays. It opens on
/// the shelf of what's playing, scrolled to it.
struct LibraryView: View {
    /// Where to go once something is chosen, when the Library is part of a window (on the Mac)
    /// rather than a sheet.
    var done: (() -> Void)? = nil
    @Environment(Mixer.self) private var mixer
    @Environment(\.dismiss) private var dismiss
    @State private var shelf: Shelf
    @State private var mood: Preset.Tag?
    @State private var query = ""
    @FocusState private var searching: Bool
    @State private var renaming: SavedMix?
    @State private var newName = ""
    @State private var deletes = 0
    @State private var showingScience = false
    private let current: Preset?

    private enum Shelf: String, CaseIterable, Hashable {
        case places = "Places", mixes = "Mixes", scenes = "Scenes", sounds = "Sounds", yours = "Yours", recent = "Recent"
    }

    init(current: Preset? = nil, done: (() -> Void)? = nil) {
        self.current = current
        self.done = done
        _shelf = State(initialValue: current?.isSaved == true ? .yours : current != nil ? .mixes : .places)
        _mood = State(initialValue: current?.tag)
    }

    private var finding: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(Theme.display(36))
                .padding(.horizontal, 4)

            searchField
                .padding(.top, 14)

            if !finding {
                chips(Shelf.allCases.filter { shelfShows($0) }.map { s in (s.rawValue, s == shelf, { shelf = s }) })
                    .padding(.top, 14)
                if shelf == .mixes || shelf == .scenes {
                    chips([("All", mood == nil, { mood = nil })]
                          + Preset.Tag.allCases.map { tag in (tag.rawValue, mood == tag, { mood = tag }) }, small: true)
                        .padding(.top, 8)
                }
            }

            if shelf == .sounds && !finding {
                SoundSections(height: nil)
                    .padding(.horizontal, -24)
                    .padding(.top, 8)
            } else {
                ScrollViewReader { proxy in
                    List {
                        if finding { results } else { shelfContent }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.immediately)
                    .padding(.top, 6)
                    .onAppear {
                        if let id = current?.id { proxy.scrollTo(id, anchor: .center) }
                    }
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
        .animation(.smooth(duration: 0.25), value: mood)
        .animation(.smooth(duration: 0.25), value: mixer.favorites)
        .animation(.smooth(duration: 0.25), value: mixer.recent)
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
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
        .onAppear {
            // Open where what's playing is: a scene among the scenes.
            if current == nil, mixer.mode == .atmosphere, let a = mixer.atmosphere {
                shelf = .scenes
                mood = a.mood
            }
        }
        .haptic(.tick, trigger: shelf)
        .haptic(.tick, trigger: mood)
        .haptic(.thud, trigger: deletes)
    }

    private func shelfShows(_ s: Shelf) -> Bool {
        switch s {
        case .yours: !mixer.yoursItems.isEmpty || shelf == .yours
        case .recent: !mixer.recent.isEmpty || shelf == .recent
        default: true
        }
    }

    // MARK: The field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
            TextField("", text: $query, prompt: Text("Where to?").foregroundStyle(Theme.secondary))
                .textFieldStyle(.plain)
                .font(Theme.label(16))
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel("Search the Library")
            if finding {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: Shelves

    @ViewBuilder private var shelfContent: some View {
        switch shelf {
        case .places:
            here
            ForEach(Place.Region.allCases.filter { $0 != .yours }, id: \.self) { region in
                let places = Place.all.filter { $0.region == region }
                if !places.isEmpty {
                    header(region.rawValue)
                    ForEach(places, id: \.name) { place($0) }
                }
            }
        case .mixes:
            if mood == .focus || mood == nil {
                science
            }
            ForEach(Preset.all.filter { mood == nil || $0.tag == mood }) { item($0) }
        case .scenes:
            ForEach(Atmosphere.curated.filter { mood == nil || $0.mood == mood }, id: \.self) { scene($0) }
        case .sounds:
            EmptyView()
        case .yours:
            ForEach(mixer.yoursItems) { entry in
                yoursRow(entry)
            }
            .onMove { mixer.moveYours(from: $0, to: $1) }
            if mixer.yoursItems.isEmpty {
                note("Tap the bookmark by a name to keep it here, or Save as new in Tune.")
            }
        case .recent:
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
    }

    @ViewBuilder private func yoursRow(_ entry: Mixer.YoursItem) -> some View {
        switch entry {
        case .saved(let mix):
            item(mix.preset)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", systemImage: "trash", role: .destructive) { remove(entry) }
                        .tint(.red)
                }
                .swipeActions(edge: .leading) {
                    Button("Rename", systemImage: "pencil") { newName = mix.name; renaming = mix }
                        .tint(Color(white: 0.35))
                }
                #if os(macOS)
                .contextMenu {
                    Button("Rename…") { newName = mix.name; renaming = mix }
                    Button("Delete", role: .destructive) { remove(entry) }
                }
                #endif
        case .kept(let f):
            Group {
                switch f {
                case .scene(let a): scene(a)
                case .mix(let p): item(p)
                case .place(let p): place(p)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Remove", systemImage: "bookmark.slash", role: .destructive) { remove(entry) }
            }
            #if os(macOS)
            .contextMenu { Button("Remove from Yours", role: .destructive) { remove(entry) } }
            #endif
        }
    }

    // MARK: Search

    /// Anything on any shelf whose name, or what it's made of, has every word typed.
    @ViewBuilder private var results: some View {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let has = { (text: String) in words.allSatisfy { text.lowercased().contains($0) } }
        let places = Place.all.filter { has("\($0.name) \($0.country) \($0.region.rawValue)") }
        let mixes = Preset.all.filter { p in has("\(p.name) \(p.tag?.rawValue ?? "") \(p.description) " + p.mix.map(\.0.name).joined(separator: " ")) }
        let scenes = Atmosphere.curated.filter { a in
            has("\(mixer.page(for: .atmosphere(a)).title) \(a.setting.info.name) \(a.sky.name) \(a.mood.rawValue)")
        }
        let sounds = SoundKind.available.filter { has("\($0.name) \($0.short) \($0.shelf.rawValue)") }
        let saved = mixer.savedMixes.filter { has("\($0.name) \($0.origin)") }
        if !places.isEmpty {
            header("Places")
            ForEach(places, id: \.name) { place($0) }
        }
        if !mixes.isEmpty {
            header("Mixes")
            ForEach(mixes) { item($0) }
        }
        if !scenes.isEmpty {
            header("Scenes")
            ForEach(scenes, id: \.self) { scene($0) }
        }
        if !sounds.isEmpty {
            header("Sounds · tap to add to what's playing")
            SoundPills(kinds: sounds)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        if !saved.isEmpty {
            header("Yours")
            ForEach(saved) { item($0.preset) }
        }
        if places.isEmpty && mixes.isEmpty && scenes.isEmpty && sounds.isEmpty && saved.isEmpty {
            note("Nothing by that name yet. Try a place, a mood or a sound: Tokyo, sleep, rain.")
        }
    }

    // MARK: Cards

    /// Played, and the Library closed (or, on the Mac, back to listening).
    private func close() {
        if let done { done() } else { dismiss() }
    }

    /// Where you are, first among places.
    private var here: some View {
        let page = mixer.page(for: .home)
        let current = mixer.mode == .match
        return Button {
            Haptics.play(.thud)
            mixer.playHere()
            close()
        } label: {
            ColorCard(hues: page.orbs.sorted { $0.volume > $1.volume }.prefix(3).map(\.kind.hue),
                      top: "Here" + (mixer.home.map { " · \($0.temperature)" } ?? ""), title: mixer.home?.place ?? "Where you are",
                      sounds: page.orbs, badge: current ? "Now" : nil, outlined: current)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id("here")
    }

    private var science: some View {
        Button { showingScience = true } label: {
            HStack(spacing: 6) {
                Text("How we chose the focus mixes")
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

    /// One mix: tap to play it. In Recent, `when` you last played it.
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
                      top: Self.top("\(a.mood.rawValue) · \(a.setting.info.name)", when), title: page.title, sounds: page.orbs,
                      badge: current ? "Now" : nil, outlined: current,
                      trailingRoom: 30)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) { FavoriteToggle(key: Mixer.favoriteKey(a)).padding(6) }
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(Mixer.favoriteKey(a))
    }

    /// A real place, in its weather now: tap to go there.
    private func place(_ p: Place, when: Date? = nil) -> some View {
        let page = mixer.page(for: .place(p))
        let current = mixer.mode == .escape && mixer.activePreset == nil && mixer.escape?.place.name == p.name
        let temp = mixer.placeConditions[p.name].map { " · \($0.temperature)" } ?? ""
        return Button {
            Haptics.play(.thud)
            mixer.revisit(.place(p))
            close()
        } label: {
            ColorCard(hues: page.orbs.sorted { $0.volume > $1.volume }.prefix(3).map(\.kind.hue),
                      top: Self.top(p.country + temp, when), title: p.title, sounds: page.orbs,
                      badge: current ? "Now" : nil, outlined: current,
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

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.caps(10))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .padding(.horizontal, 4)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.label(12))
            .foregroundStyle(Theme.secondary)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func remove(_ entry: Mixer.YoursItem) {
        deletes += 1
        withAnimation { mixer.removeFromYours(entry) }
        if mixer.yoursItems.isEmpty && shelf == .yours { shelf = .places }
    }

    /// A row of choices as capsules, scrolling sideways; `small` for a shelf's own filters.
    private func chips(_ items: [(String, Bool, () -> Void)], small: Bool = false) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                    let (label, selected, choose) = entry
                    Button(action: choose) {
                        Text(label)
                            .font(Theme.body(small ? 12 : 13, .medium))
                            .foregroundStyle(selected ? Theme.background : Theme.text)
                            .padding(.vertical, small ? 6 : 8)
                            .padding(.horizontal, small ? 12 : 14)
                            .background(Capsule().fill(selected ? Theme.text : .clear))
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -24)
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
                         badge: current ? "Now" : nil, outlined: current,
                         trailingRoom: 30)
    }
}

/// Sounds as pills that wrap, lit while playing: tap to bring one in or take it away.
private struct SoundPills: View {
    @Environment(Mixer.self) private var mixer
    let kinds: [SoundKind]

    var body: some View {
        let playing = Set(mixer.orbs.map(\.kind))
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(kinds) { kind in
                    let on = playing.contains(kind)
                    Button {
                        Haptics.play(.soft)
                        withAnimation(.snappy) { on ? mixer.removeAll(kind) : mixer.add(kind) }
                    } label: {
                        HStack(spacing: 7) {
                            Circle().fill(kind.orb).frame(width: 7, height: 7)
                            Text(kind.short).font(Theme.body(13, .medium))
                        }
                        .foregroundStyle(on ? Theme.background : Theme.text)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 14)
                        .background(Capsule().fill(on ? Theme.text : .clear))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Remove \(kind.name)" : "Add \(kind.name)")
                }
            }
        }
        .scrollIndicators(.hidden)
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
            .alert("Save as new", isPresented: $isPresented) {
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
