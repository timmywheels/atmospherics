import SwiftUI

/// Saved mixes, filterable by Sleep / Focus / Relax. Tapping one loads it onto the field.
/// Your own mixes come first: swipe left to delete, right to rename, hold and drag to reorder.
/// It opens on the mix that's playing, under its own filter.
struct LibraryView: View {
    @Environment(Mixer.self) private var mixer
    @Environment(\.dismiss) private var dismiss
    @State private var filter: Preset.Tag?
    @State private var showingYours: Bool
    @State private var renaming: SavedMix?
    @State private var newName = ""
    @State private var deletes = 0
    private let current: Preset?

    init(current: Preset? = nil) {
        self.current = current
        _filter = State(initialValue: current?.tag)
        _showingYours = State(initialValue: current?.isSaved == true)
    }

    private var yours: [SavedMix] { filter == nil ? mixer.savedMixes : [] }
    private var builtIn: [Preset] { showingYours ? [] : Preset.all.filter { filter == nil || $0.tag == filter } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(Theme.display(30))
                .tracking(-0.6)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                chip("All", selected: filter == nil && !showingYours) { filter = nil; showingYours = false }
                if !mixer.savedMixes.isEmpty {
                    chip("Yours", selected: showingYours) { filter = nil; showingYours = true }
                }
                ForEach(Preset.Tag.allCases, id: \.self) { tag in
                    chip(tag.rawValue, selected: filter == tag && !showingYours) { filter = tag; showingYours = false }
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollViewReader { proxy in
                List {
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
        .alert("Rename mix", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let r = renaming { mixer.rename(r, to: newName) } }
        }
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.impact(weight: .medium), trigger: deletes)
        .sensoryFeedback(.selection, trigger: mixer.savedMixes.map(\.id))
    }

    /// One row of the list: tap to play it.
    private func item(_ preset: Preset) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            mixer.load(preset)
            dismiss()
        } label: {
            row(preset)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(preset.id)
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
        let hues = preset.mix.prefix(3).map(\.0.hue)
        let first = hues.first ?? 250
        let second = hues.count > 1 ? hues[1] : first
        let third = hues.count > 2 ? hues[2] : second
        let current = preset.id == mixer.activePreset?.id
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(preset.tag.map { "\($0.rawValue) · \(preset.length)" } ?? "Yours")
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                if current {
                    Text(mixer.isPlaying ? "Playing" : "Current")
                        .font(Theme.mono(10, .medium))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 9)
                        .background(Capsule().fill(.black.opacity(0.3)))
                }
            }
            Spacer(minLength: 22)
            Text(preset.name)
                .font(Theme.body(21))
                .lineLimit(1)
            Text(preset.description)
                .font(Theme.mono(10.5))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [.oklch(0.4, 0.085, first), .oklch(0.27, 0.06, second)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.oklch(0.62, 0.12, first).opacity(0.55), .clear],
                               center: UnitPoint(x: 0.8, y: 0.25), startRadius: 0, endRadius: 150)
                RadialGradient(colors: [.oklch(0.55, 0.11, third).opacity(0.35), .clear],
                               center: UnitPoint(x: 0.15, y: 1), startRadius: 0, endRadius: 130)
            }
        }
        .clipShape(shape)
        .overlay { if current { shape.strokeBorder(.white.opacity(0.6), lineWidth: 1.2) } }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
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
