import SwiftUI

/// The field: drag a light toward the center to hear more of it, toward the rim to fade it out.
struct MixerView: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mixer")
                    .font(Theme.display(30))
                    .tracking(-0.6)
                Spacer()
                Text(mixer.weather.head)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.mono)
            }
            .padding(.horizontal, 8)

            Text("Drag closer to hear more. Drag off the edge to remove.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            FieldView()
                .frame(width: 350, height: 350)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)

            Spacer(minLength: 16)

            if !mixer.unusedSounds.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ADD TO FIELD")
                        .font(Theme.mono(11, .medium))
                        .tracking(1.3)
                        .foregroundStyle(Theme.mono)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(SoundKind.Category.allCases, id: \.self) { category in
                                let kinds = mixer.unusedSounds.filter { $0.category == category }
                                if !kinds.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(category.rawValue)
                                            .font(Theme.mono(10))
                                            .foregroundStyle(Theme.mono.opacity(0.8))
                                        FlowLayout(spacing: 8) {
                                            ForEach(kinds) { kind in chip(kind) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 230)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func chip(_ kind: SoundKind) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { mixer.add(kind) }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(kind.orb).frame(width: 8, height: 8)
                Text(kind.short).font(Theme.body(13))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(kind.name)")
    }
}

/// The circular field with its rings and draggable orbs.
private struct FieldView: View {
    @Environment(Mixer.self) private var mixer
    private let size: CGFloat = 350

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.white.opacity(0.05), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.35))
            Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1)
            Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1).padding(58)
            Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1).padding(117)
            Circle().fill(.white).frame(width: 8, height: 8)

            ForEach(mixer.orbs) { orb in
                OrbView(orb: orb, fieldSize: size)
            }
        }
        .coordinateSpace(name: "field")
        .sensoryFeedback(.impact(weight: .light), trigger: mixer.orbs.count)
    }
}

private struct OrbView: View {
    @Environment(Mixer.self) private var mixer
    let orb: Orb
    let fieldSize: CGFloat
    @State private var dragging = false
    /// Where the finger is, in field units, while it's dragged past the rim.
    @State private var outside: CGPoint?

    /// Past this distance from center (the rim is 0.5), letting go removes the sound.
    private static let removeDistance = 0.68

    private var removing: Bool {
        guard let p = outside else { return false }
        return hypot(p.x - 0.5, p.y - 0.5) > Self.removeDistance
    }

    var body: some View {
        let v = orb.volume
        let size = 20 + v * 40
        let pct = Int((v * 100).rounded())
        let at = outside ?? CGPoint(x: orb.x, y: orb.y)

        Circle()
            .fill(removing ? Theme.mono.opacity(0.5) : orb.kind.orb)
            .frame(width: size, height: size)
            .shadow(color: removing ? .clear : orb.kind.glow, radius: (16 + v * 44) / 2)
            .overlay {
                if removing {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.background)
                }
            }
            .scaleEffect(removing ? 0.8 : dragging ? 1.12 : 1)
            .overlay(alignment: .top) {
                Text(removing ? "Release to remove" : outside != nil ? "Drag further to remove" : "\(orb.kind.short) \(pct)")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(removing ? Theme.text : Theme.orbLabel)
                    .fixedSize()
                    .offset(y: size + 6)
                    .allowsHitTesting(false)
            }
            .frame(width: max(size, 44), height: max(size, 44))   // comfortable touch target
            .contentShape(Circle())
            .position(x: at.x * fieldSize, y: at.y * fieldSize)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("field"))
                    .onChanged { g in
                        dragging = true
                        let p = CGPoint(x: g.location.x / fieldSize, y: g.location.y / fieldSize)
                        // Inside the circle the light moves the sound; past the rim it follows
                        // the finger out (the sound sits silent at the rim) so it can be thrown away.
                        outside = hypot(p.x - 0.5, p.y - 0.5) > 0.5 ? p : nil
                        mixer.move(orb.id, toX: p.x, y: p.y)
                    }
                    .onEnded { _ in
                        if removing {
                            withAnimation(.snappy) { mixer.remove(orb.id) }
                        } else {
                            withAnimation(.spring(duration: 0.35, bounce: 0.35)) { outside = nil }
                        }
                        dragging = false
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { mixer.remove(orb.id) }
            }
            .animation(.snappy(duration: 0.2), value: dragging)
            .animation(.snappy(duration: 0.18), value: removing)
            // A soft tap on pickup, a tick per 10% of volume, and a firm snap when it's ready to remove.
            .sensoryFeedback(.impact(flexibility: .soft), trigger: dragging) { _, isDragging in isDragging }
            .sensoryFeedback(.selection, trigger: pct / 10) { _, _ in dragging && outside == nil }
            .sensoryFeedback(.impact(weight: .heavy), trigger: removing) { _, now in now }
            .zIndex(dragging ? 1 : 0)
            .accessibilityElement()
            .accessibilityLabel(orb.kind.name)
            .accessibilityValue("\(pct) percent")
            .accessibilityAdjustableAction { direction in
                mixer.adjustVolume(orb.id, by: direction == .increment ? 0.1 : -0.1)
            }
            .accessibilityAction(named: "Remove") { mixer.remove(orb.id) }
    }
}

/// Lays out children left to right, wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += rows[last].indices.isEmpty ? size.width : size.width + spacing
            rows[last].height = max(rows[last].height, size.height)
            rows[last].indices.append(i)
        }
        return rows
    }
}
