import SwiftUI

/// Everything the app can play, on shelves: Travel (where you are first, then the real places,
/// in their live weather), Imagine (the scenes, in weather of their own, by mood), Mixes by mood, every Sound, Yours (all you've kept, in
/// your order) and Recent. The field at the top, Where to?, finds anything on any shelf, best match
/// first, and its last answer is always to imagine what you typed: a scene made from your words.
/// A card plays and closes the Library; a sound's pill adds it to what's playing and stays. It
/// opens on the shelf of what's playing, scrolled to it, or ready to type (`focus`).
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
    /// Searching: from the moment the field is asked for (or opened ready) until Cancel. Not the
    /// keyboard's focus, which a tap on a suggestion takes away before the tap lands.
    @State private var searchActive: Bool
    @State private var renaming: SavedMix?
    @State private var newName = ""
    @State private var deletes = 0
    @State private var showingScience = false
    /// Imagining what was typed: a moment, or a few the first time the model loads.
    @State private var imagining: Task<Void, Never>?
    @State private var notUnderstood = false
    @State private var recentPhrases = Vibe.recent
    @State private var suggestions = Vibe.suggestions()
    private let current: Preset?
    private let focus: Bool

    private enum Shelf: String, CaseIterable, Hashable {
        case places = "Travel", scenes = "Imagine", mixes = "Mixes", sounds = "Sounds", yours = "Yours", recent = "Recent"
    }

    init(current: Preset? = nil, focus: Bool = false, done: (() -> Void)? = nil) {
        self.current = current
        self.focus = focus
        self.done = done
        _searchActive = State(initialValue: focus)
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

            // The shelves stay while a dropdown of suggestions is open over them; typing turns
            // them into what was found.
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
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
                        fromScratch
                            .padding(.top, 10)
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
                if searchActive && !finding {
                    // Everything behind, dimmed: a tap there puts the suggestions away.
                    Color.black.opacity(0.45)
                        .padding(.horizontal, -24)
                        .ignoresSafeArea(edges: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture { cancelSearch() }
                        .transition(.opacity)
                    dropdown
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .offset(y: -6)))
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
        .task {
            Vibe.prepare()
            // Ready to type once a sheet has finished coming up; sooner, the keyboard doesn't show.
            // (On the Mac there's no sheet: at once.)
            guard focus else { return }
            #if os(iOS)
            try? await Task.sleep(for: .milliseconds(450))
            #else
            try? await Task.sleep(for: .milliseconds(30))
            #endif
            searching = true
        }
        .onDisappear { imagining?.cancel() }
        .onChange(of: query) { _, _ in notUnderstood = false }
        .onChange(of: searching) { _, now in
            if now { withAnimation(.smooth(duration: 0.25)) { searchActive = true } }
        }
        .animation(.smooth(duration: 0.25), value: searchActive)
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
        HStack(spacing: 12) {
            field
            if searchActive {
                Button("Cancel", action: cancelSearch)
                .font(Theme.label(15))
                .foregroundStyle(Theme.text)
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
            TextField("", text: $query, prompt: Text("Where to?").foregroundStyle(Theme.secondary))
                .textFieldStyle(.plain)
                .font(Theme.label(16))
                .focused($searching)
                .submitLabel(.go)
                .onSubmit(submit)
                .autocorrectionDisabled()
                .accessibilityLabel("Search the Library")
            if imagining != nil {
                ProgressView().controlSize(.small)
            } else if finding {
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
            fromScratch
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

    /// What a search found, best first within each kind, the kinds in order of their best.
    private struct Found {
        var places: [(Place, Int)] = []
        var mixes: [(Preset, Int)] = []
        var scenes: [(Atmosphere, Int)] = []
        var sounds: [(SoundKind, Int)] = []
        var yours: [(SavedMix, Int)] = []
        var isEmpty: Bool { places.isEmpty && mixes.isEmpty && scenes.isEmpty && sounds.isEmpty && yours.isEmpty }
    }

    /// How well `query` matches: 5 the whole name, 4 the start of it, 3 the start of a word in it,
    /// 2 every word in it, 1 every word somewhere in what it's made of; 0 not at all.
    private static func score(_ query: String, name: String, more: String) -> Int {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let n = name.lowercased()
        let words = q.split(separator: " ").map(String.init)
        if n == q { return 5 }
        if n.hasPrefix(q) { return 4 }
        if n.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 3 }
        if words.allSatisfy(n.contains) { return 2 }
        let all = n + " " + more.lowercased()
        return words.allSatisfy(all.contains) ? 1 : 0
    }

    private func find(_ q: String) -> Found {
        func best<T>(_ items: [T], name: (T) -> String, more: (T) -> String) -> [(T, Int)] {
            items.map { ($0, Self.score(q, name: name($0), more: more($0))) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        }
        var f = Found()
        f.places = best(Place.all, name: \.name) { "\($0.country) \($0.region.rawValue)" }
        // A place named within more ("Tokyo in the rain"): it, live, first, with Imagine under it.
        let lower = q.lowercased()
        for p in Place.all where !f.places.contains(where: { $0.0.name == p.name }) && lower.contains(p.name.lowercased()) {
            f.places.insert((p, 3), at: 0)
        }
        f.mixes = best(Preset.all, name: \.name) { p in "\(p.tag?.rawValue ?? "") \(p.description) " + p.mix.map(\.0.name).joined(separator: " ") }
        f.scenes = best(Atmosphere.curated, name: { mixer.page(for: .atmosphere($0)).title }) {
            "\($0.setting.info.name) \($0.sky.name) \($0.time.name) \($0.mood.rawValue)"
        }
        f.sounds = best(SoundKind.available, name: \.name) { "\($0.short) \($0.shelf.rawValue) " + $0.aliases.joined(separator: " ") }
        f.yours = best(mixer.savedMixes, name: \.name, more: \.origin)
        return f
    }

    @ViewBuilder private var results: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let f = find(q)
        let groups: [(Int, AnyView)] = [
            (f.places.first?.1 ?? 0, AnyView(Group {
                header("Travel")
                ForEach(f.places, id: \.0.name) { place($0.0) }
                // A real place with more asked of it ("Tokyo in the rain"): it, live, then imagined so.
                if let top = f.places.first, top.1 < 5, q.lowercased() != top.0.name.lowercased() { imagine(q) }
            })),
            (f.mixes.first?.1 ?? 0, AnyView(Group { header("Mixes"); ForEach(f.mixes, id: \.0.id) { item($0.0) } })),
            (f.scenes.first?.1 ?? 0, AnyView(Group { header("Imagine"); ForEach(f.scenes, id: \.0) { scene($0.0) } })),
            (f.sounds.first?.1 ?? 0, AnyView(Group {
                header("Sounds · tap to add to what's playing")
                SoundPills(kinds: f.sounds.map(\.0))
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            })),
            (f.yours.first?.1 ?? 0, AnyView(Group { header("Yours"); ForEach(f.yours, id: \.0.id) { item($0.0.preset) } })),
        ]
        // Kinds in order of their best match; on a tie, as listed.
        ForEach(Array(groups.enumerated().filter { $0.element.0 > 0 }.sorted { $0.element.0 > $1.element.0 }), id: \.offset) { _, group in
            group.1
        }
        if f.isEmpty {
            note("Nothing by that name. Imagine it instead:")
                .padding(.top, 8)
        }
        // Under a place it's already offered, right beneath it.
        if !(f.places.first.map { $0.1 < 5 && q.lowercased() != $0.0.name.lowercased() } ?? false) {
            imagine(q)
        }
        if notUnderstood {
            note("Try a place and some weather, like “a cabin in the snow, no wind”.")
        }
    }

    /// The last answer to any search: a scene made from the words.
    private func imagine(_ q: String) -> some View {
        Button { imagineIt(q) } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Imagine “\(q)”")
                        .font(Theme.label(15, .medium))
                        .lineLimit(2)
                    Text("A scene made from your words")
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(imagining != nil)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Reads the words into a scene, then goes there.
    private func imagineIt(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, imagining == nil else { return }
        notUnderstood = false
        imagining = Task {
            let vibe = await Vibe.read(text, draft: mixer.atmosphere ?? Atmosphere.curated[0])
            imagining = nil
            guard !Task.isCancelled else { return }
            guard let vibe else {
                notUnderstood = true
                return
            }
            Vibe.remember(text)
            Haptics.play(.thud)
            mixer.go(to: vibe)
            close()
        }
    }

    /// Return: the one it is, if the name was typed whole; otherwise imagine it.
    private func submit() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let f = find(q)
        if let p = f.places.first, p.1 == 5 { Haptics.play(.thud); mixer.revisit(.place(p.0)); return close() }
        if let m = f.mixes.first, m.1 == 5 { Haptics.play(.thud); mixer.load(m.0); return close() }
        if let a = f.scenes.first, a.1 == 5 { Haptics.play(.thud); mixer.revisit(.scene(a.0)); return close() }
        imagineIt(q)
    }

    private func cancelSearch() {
        query = ""
        searching = false
        searchActive = false
    }

    /// With the field empty and ready, a dropdown under it: what you've asked for before and a few
    /// to try, a tap each, and Surprise me pinned along its foot.
    private var dropdown: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !recentPhrases.isEmpty {
                        HStack {
                            caps("Recent")
                            Spacer()
                            Button {
                                Haptics.play(.tap)
                                Vibe.forgetRecent()
                                withAnimation(.smooth(duration: 0.25)) { recentPhrases = [] }
                            } label: {
                                caps("Clear").contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear recent searches")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                        ForEach(Array(recentPhrases.prefix(4)), id: \.self) { suggestion($0, icon: "clock.arrow.circlepath") }
                    }
                    caps("Try")
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    // Ideas you haven't asked for already.
                    ForEach(Array(suggestions.filter { !recentPhrases.contains($0) }.prefix(recentPhrases.isEmpty ? 5 : 3)), id: \.self) {
                        suggestion($0, icon: "sparkles")
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Theme.hairline).frame(height: 1)
            Button {
                Haptics.play(.thud)
                surprise()
            } label: {
                Label("Surprise me", systemImage: Theme.Symbol.surprise)
                    .font(Theme.body(15, .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.background.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }

    /// One suggestion, a row to tap: it imagines it.
    private func suggestion(_ phrase: String, icon: String) -> some View {
        Button {
            Haptics.play(.tick)
            query = phrase
            imagineIt(phrase)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)
                Text(phrase)
                    .font(Theme.label(15))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func caps(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.caps(10))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
    }

    /// A scene or a real place, chosen for you, and straight there.
    private func surprise() {
        if Bool.random() {
            var next = Atmosphere.random()
            while next == mixer.atmosphere { next = Atmosphere.random() }
            mixer.revisit(.scene(next))
        } else if let p = Place.all.filter({ $0.name != mixer.escape?.place.name }).randomElement() {
            mixer.revisit(.place(p))
        }
        close()
    }

    // MARK: Cards

    /// An empty mix to build from any sounds.
    private var fromScratch: some View {
        Button {
            Haptics.play(.thud)
            mixer.startFromScratch()
            close()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start from scratch")
                        .font(Theme.display(24))
                    Text("An empty mix: bring in any sounds you like")
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("An empty mix, with Tune open to add sounds")
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

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
