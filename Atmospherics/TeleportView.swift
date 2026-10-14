import SwiftUI

/// Teleport: an atmosphere as a sentence, "Take me to a log cabin in a snowstorm right now".
/// Tap a part to change it, describe the vibe in your own words, or pick one of ours. The colors
/// follow what you're building, and it says when it's really like that somewhere right now.
struct TeleportView: View {
    @Environment(Mixer.self) private var mixer
    @Environment(\.dismiss) private var dismiss
    /// When Teleport is part of a window (a tab on the Mac) rather than a sheet: how to leave it.
    var close: (() -> Void)? = nil
    @State private var draft: Atmosphere
    @State private var slot: Slot = .setting
    @State private var words = ""
    @State private var notUnderstood = false
    /// Reading a description: a moment, or a few the first time the model loads.
    @State private var reading: Task<Void, Never>?
    /// What you've described before, and a few to try: shown when the box is empty.
    @State private var recent = Vibe.recent
    @State private var suggestions = Vibe.suggestions()
    /// Open with the keyboard up, ready to describe where to go.
    private let typing: Bool
    @FocusState private var describing: Bool

    private enum Slot { case setting, sky, time }

    init(start: Atmosphere? = nil, typing: Bool = false, close: (() -> Void)? = nil) {
        self.close = close
        self.typing = typing
        _draft = State(initialValue: start ?? Atmosphere.curated[0])
    }

    var body: some View {
        let preview = mixer.page(for: .atmosphere(draft))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // As a sheet it has its own name and a way out; in a window's tab, the tab says it.
                if close == nil {
                    HStack {
                        Text("TELEPORT")
                            .font(Theme.caps(11))
                            .tracking(1.3)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Button { Haptics.play(.tap); leave() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close")
                    }
                    .padding(.bottom, 18)
                }

                sentence

                Text(preview.line)
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .padding(.top, 14)
                    .animation(.smooth, value: preview.line)

                // Or in your own words, right under the sentence (and above the keyboard).
                describeIt
                    .padding(.top, 24)

                choices
                    .padding(.top, 22)

                HStack(spacing: 10) {
                    Button { surprise() } label: {
                        Label("Surprise me", systemImage: Atmosphere.surpriseSymbol)
                            .font(Theme.body(15, .medium))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 18)
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { go(to: draft) } label: {
                        Text("Teleport")
                            .font(Theme.body(16, .semibold))
                            .foregroundStyle(Theme.background)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 30)
                            .background(Capsule().fill(Theme.text))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Teleport to \(preview.title)")
                }
                .padding(.top, 24)


                ideas
                    .padding(.top, 34)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .task {
            Vibe.prepare()
            // Focus once the sheet has finished coming up; sooner, the keyboard doesn't show.
            guard typing else { return }
            try? await Task.sleep(for: .milliseconds(600))
            describing = true
        }
        .onDisappear { reading?.cancel() }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .notices(above: 28)
        .foregroundStyle(Theme.text)
        .background { SceneWash(orbs: preview.orbs) }
        .presentationBackground(Theme.background)
        .haptic(.tick, trigger: draft)
        .haptic(.tick, trigger: slot)
        #if os(macOS)
        .onExitCommand { leave() }
        #endif
    }

    // MARK: The sentence

    private var sentence: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Take me")
                .foregroundStyle(Theme.secondary)
            part(draft.setting.info.go, .setting)
            part(draft.sky.phrase, .sky)
            part(draft.time.phrase, .time)
        }
        .font(Theme.display(40))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// One part of the sentence, underlined; the one being changed is lit.
    private func part(_ text: String, _ which: Slot) -> some View {
        Button { withAnimation(.smooth(duration: 0.25)) { slot = which } } label: {
            Text(text)
                .foregroundStyle(slot == which ? Theme.text : Theme.text.opacity(0.62))
                .underline(true, pattern: slot == which ? .solid : .dot, color: Theme.text.opacity(slot == which ? 0.7 : 0.35))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Change this part")
    }

    // MARK: Choices for the part being changed

    @ViewBuilder private var choices: some View {
        let info = draft.setting.info
        FlowLayout(spacing: 8) {
            switch slot {
            case .setting:
                ForEach(Setting.allCases, id: \.self) { s in
                    chip(s.info.name, selected: s == draft.setting) { choose(setting: s) }
                }
            case .sky:
                ForEach(info.skies, id: \.self) { sky in
                    chip(sky.name, selected: sky == draft.sky) { draft = Atmosphere(draft.setting, sky, draft.time) }
                }
            case .time:
                ForEach(info.times, id: \.self) { t in
                    chip(t.name, selected: t == draft.time) { draft = Atmosphere(draft.setting, draft.sky, t) }
                }
            }
        }
        // Swap the choices at once rather than cross-fading two sets over each other.
        .transaction { $0.animation = nil }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.smooth(duration: 0.3)) { action() } } label: {
            Text(label)
                .font(Theme.body(14, .medium))
                .foregroundStyle(selected ? Theme.background : Theme.text)
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(Capsule().fill(selected ? Theme.text : .white.opacity(0.04)))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A new setting keeps the weather and time if they suit it.
    private func choose(setting: Setting) {
        draft = Atmosphere(setting, draft.sky, draft.time)
    }

    /// Somewhere new, chosen for you, and straight there: no need to press Teleport after.
    private func surprise() {
        var next = Atmosphere.random()
        while next == draft || next == mixer.atmosphere { next = Atmosphere.random() }
        go(to: next)
    }

    // MARK: In your own words

    private var describeIt: some View {
        VStack(alignment: .leading, spacing: 8) {
            caps("OR DESCRIBE THE VIBE")
            HStack(spacing: 10) {
                ZStack {
                    if reading != nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "text.bubble").foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 20)
                TextField("", text: $words, prompt: Text(Vibe.readsMoods ? "a rainy night in Tokyo, no traffic" : "a sunny beach, no birds")
                    .foregroundStyle(Theme.muted))
                    .textFieldStyle(.plain)
                    .focused($describing)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { understand() }
                    .onChange(of: words) { _, _ in notUnderstood = false }
            }
            .font(Theme.body(15))
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(Capsule().fill(.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            if notUnderstood {
                Text("Try a place and some weather, like “a cabin in the snow, no wind”.")
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.secondary)
                    .transition(.opacity)
            }
            // With the box empty, what you've described before and a few to try: one tap goes.
            if describing && words.isEmpty && reading == nil {
                VStack(alignment: .leading, spacing: 8) {
                    if !recent.isEmpty {
                        HStack {
                            caps("RECENT")
                            Spacer()
                            Button {
                                Haptics.play(.tap)
                                Vibe.forgetRecent()
                                withAnimation(.smooth(duration: 0.25)) { recent = [] }
                            } label: {
                                caps("CLEAR").contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear recent descriptions")
                        }
                        phrases(Array(recent.prefix(4)), yours: true)
                        caps("TRY").padding(.top, 4)
                    }
                    phrases(Array(suggestions.prefix(recent.isEmpty ? 4 : 3)), yours: false)
                }
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: notUnderstood)
        .animation(.smooth(duration: 0.25), value: describing)
    }

    private func caps(_ text: String) -> some View {
        Text(text)
            .font(Theme.caps(10))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
    }

    /// Descriptions to tap, yours brighter than ours.
    private func phrases(_ list: [String], yours: Bool) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(list, id: \.self) { phrase in
                Button {
                    Haptics.play(.tick)
                    words = phrase
                    understand()
                } label: {
                    Text(phrase)
                        .font(Theme.body(13))
                        .foregroundStyle(yours ? Theme.text : Theme.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 300, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(.white.opacity(yours ? 0.06 : 0)))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Reads the description, then goes there.
    private func understand() {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, reading == nil else { return }
        notUnderstood = false
        reading = Task {
            let vibe = await Vibe.read(text, draft: draft)
            reading = nil
            guard !Task.isCancelled else { return }
            guard let vibe else {
                notUnderstood = true
                return
            }
            Vibe.remember(text)
            Haptics.play(.thud)
            mixer.go(to: vibe)
            leave()
        }
    }

    // MARK: Ours

    private var ideas: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IDEAS")
                .font(Theme.caps(10))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            LazyVStack(spacing: 10) {
                ForEach(Atmosphere.curated) { a in
                    let page = mixer.page(for: .atmosphere(a))
                    let current = mixer.mode == .atmosphere && mixer.activePreset == nil && mixer.atmosphere == a
                    let source = mixer.liveSource(for: a)
                    Button { go(to: a) } label: {
                        ColorCard(hues: page.orbs.sorted { $0.volume > $1.volume }.prefix(3).map(\.kind.hue),
                                  top: source.map { "Live from \($0.place.title) · \($0.conditions.temperature)" } ?? a.setting.info.name,
                                  title: page.title, sounds: page.orbs,
                                  badge: current ? (mixer.isPlaying ? "Playing" : "Here") : nil, outlined: current, minHeight: 112,
                                  trailingRoom: 30)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottomTrailing) {
                        FavoriteToggle(key: Mixer.favoriteKey(a)).padding(6)
                    }
                }
            }
        }
    }

    private func go(to atmosphere: Atmosphere) {
        Haptics.play(.thud)
        mixer.go(to: atmosphere)
        leave()
    }

    private func leave() {
        if let close { close() } else { dismiss() }
    }
}

/// Lays chips out in rows, wrapping to the next line when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
