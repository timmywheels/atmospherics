import SwiftUI

/// Saved mixes, filterable by Sleep / Focus / Relax. Tapping one loads it onto the field.
/// Your own mixes come first: swipe left to delete, right to rename, hold and drag to reorder.
/// It opens on the mix that's playing, under its own filter.
struct LibraryView: View {
    /// Where to go once a mix is chosen, when the Library is part of a window (on the Mac)
    /// rather than a sheet.
    var done: (() -> Void)? = nil
    @Environment(Mixer.self) private var mixer
    @Environment(\.dismiss) private var dismiss
    @State private var filter: Preset.Tag?
    @State private var showingYours: Bool
    @State private var showingFavorites = false
    @State private var renaming: SavedMix?
    @State private var newName = ""
    @State private var deletes = 0
    @State private var showingScience = false
    private let current: Preset?

    init(current: Preset? = nil, done: (() -> Void)? = nil) {
        self.current = current
        self.done = done
        _filter = State(initialValue: current?.tag)
        _showingYours = State(initialValue: current?.isSaved == true)
    }

    private var yours: [SavedMix] { filter == nil && !showingFavorites ? mixer.savedMixes : [] }
    private var builtIn: [Preset] {
        showingYours || showingFavorites ? [] : Preset.all.filter { filter == nil || $0.tag == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(Theme.display(36))
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                chip("All", selected: filter == nil && !showingYours && !showingFavorites) {
                    filter = nil; showingYours = false; showingFavorites = false
                }
                if !mixer.favorites.isEmpty || showingFavorites {
                    chip("Favorites", selected: showingFavorites) { filter = nil; showingYours = false; showingFavorites = true }
                }
                if !mixer.savedMixes.isEmpty {
                    chip("Yours", selected: showingYours) { filter = nil; showingYours = true; showingFavorites = false }
                }
                ForEach(Preset.Tag.allCases, id: \.self) { tag in
                    chip(tag.rawValue, selected: filter == tag && !showingYours && !showingFavorites) {
                        filter = tag; showingYours = false; showingFavorites = false
                    }
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollViewReader { proxy in
                List {
                    if filter == .focus {
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
                    if showingFavorites {
                        ForEach(mixer.favoriteItems) { favorite in
                            switch favorite {
                            case .scene(let a): scene(a)
                            case .mix(let p): item(p)
                            }
                        }
                        if mixer.favorites.isEmpty {
                            Text("Tap the ring on a scene or a mix to keep it here.")
                                .font(Theme.label(12))
                                .foregroundStyle(Theme.secondary)
                                .padding(.vertical, 12)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
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
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .animation(.smooth(duration: 0.25), value: filter)
        .animation(.smooth(duration: 0.25), value: showingYours)
        .animation(.smooth(duration: 0.25), value: showingFavorites)
        .animation(.smooth(duration: 0.25), value: mixer.favorites)
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
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.impact(weight: .medium), trigger: deletes)
        .sensoryFeedback(.selection, trigger: mixer.savedMixes.map(\.id))
    }

    /// One row of the list: tap to play it.
    private func item(_ preset: Preset) -> some View {
        Button {
            Haptics.tap()
            mixer.load(preset)
            if let done { done() } else { dismiss() }
        } label: {
            row(preset)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) { FavoriteToggle(key: Mixer.favoriteKey(preset)).padding(6) }
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(preset.id)
    }

    /// A favorite scene: tap to go there.
    private func scene(_ a: Atmosphere) -> some View {
        let page = mixer.page(for: .atmosphere(a))
        let current = mixer.mode == .atmosphere && mixer.activePreset == nil && mixer.atmosphere == a
        return Button {
            Haptics.tap()
            mixer.go(to: a)
            if let done { done() } else { dismiss() }
        } label: {
            ColorCard(hues: page.orbs.sorted { $0.volume > $1.volume }.prefix(3).map(\.kind.hue),
                      top: a.setting.info.name, title: page.title, sounds: page.orbs,
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

    private func delete(_ mix: SavedMix) {
        deletes += 1
        withAnimation { mixer.delete(mix) }
        if mixer.savedMixes.isEmpty { showingYours = false }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    /// A card in the colors of its mix: what it's for and how long at the top, its name at the bottom.
    private func row(_ preset: Preset) -> some View {
        let current = preset.id == mixer.activePreset?.id
        return ColorCard(hues: preset.mix.prefix(3).map(\.0.hue),
                         top: (preset.tag.map { "\($0.rawValue) · \(preset.length)" } ?? "Yours")
                             + (preset.evidence.map { " · \($0.rawValue)" } ?? ""),
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
            .sensoryFeedback(.success, trigger: saves)
    }
}

extension View {
    func saveMixPrompt(isPresented: Binding<Bool>) -> some View { modifier(SaveMixPrompt(isPresented: isPresented)) }
}
