import SwiftUI

/// Saved mixes, filterable by Sleep / Focus / Relax. Tapping one loads it onto the field.
struct LibraryView: View {
    @Environment(Mixer.self) private var mixer
    @Environment(\.dismiss) private var dismiss
    @State private var filter: Preset.Tag?

    private var presets: [Preset] {
        Preset.all.filter { filter == nil || $0.tag == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(Theme.display(30))
                .tracking(-0.6)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                chip("All", selected: filter == nil) { filter = nil }
                ForEach(Preset.Tag.allCases, id: \.self) { tag in
                    chip(tag.rawValue, selected: filter == tag) { filter = tag }
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(presets) { preset in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            mixer.load(preset)
                            dismiss()
                        } label: {
                            row(preset)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .animation(.smooth(duration: 0.25), value: filter)
        .sensoryFeedback(.selection, trigger: filter)
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

    private func row(_ preset: Preset) -> some View {
        HStack(spacing: 16) {
            MiniField(preset: preset)
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name).font(Theme.body(17))
                Text(preset.description)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.mono)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(preset.length)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.mono)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A tiny preview of where a preset puts its sounds on the field.
private struct MiniField: View {
    let preset: Preset
    private let size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.04))
            Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1)
            ForEach(Array(preset.mix.enumerated()), id: \.offset) { j, entry in
                let (kind, v) = entry
                let r = (1 - v) * 0.4
                let angle = Double(j) * 2.4 + 0.6
                let dot = 6 + v * 8
                Circle()
                    .fill(Color.oklch(0.78, 0.13, kind.hue))
                    .frame(width: dot, height: dot)
                    .shadow(color: .oklch(0.78, 0.13, kind.hue), radius: 4)
                    .position(x: size * (0.5 + cos(angle) * r), y: size * (0.5 + sin(angle) * r))
            }
        }
        .frame(width: size, height: size)
    }
}
