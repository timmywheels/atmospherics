import SwiftUI

/// What swiping goes through, as a wheel of words that never ends: the lens you're in at the
/// center, its neighbours peeking in at the edges. Drag it and you feel each word go by, like a
/// date picker; let go and it settles on one and plays it. Tap a word at the edge to turn
/// to it. Turned some other way (the Library, Teleport), it rolls round to match, quietly.
struct ModeWheel: View {
    @Environment(Mixer.self) private var mixer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lenses = Mixer.Lens.allCases
    /// How far apart the words are.
    private static let slot: CGFloat = 104

    /// Where the wheel is, in words: a whole number is a word at the center. It grows without
    /// end either way, so the wheel goes round.
    @State private var position: Double = 0
    @State private var dragFrom: Double?
    /// The word last clicked past.
    @State private var clicked = 0
    @State private var settling: Task<Void, Never>?

    private static func index(_ i: Int) -> Int {
        let n = lenses.count
        return ((i % n) + n) % n
    }

    /// The nearest place on the wheel that shows `lens`, from where it is now.
    private func nearest(_ lens: Mixer.Lens) -> Int {
        let here = Int(position.rounded())
        let want = Self.lenses.firstIndex(of: lens) ?? 0
        var step = Self.index(want - here)
        if step > Self.lenses.count / 2 { step -= Self.lenses.count }
        return here + step
    }

    private func click(at word: Int) {
        guard word != clicked else { return }
        clicked = word
        Haptics.play(.detent)
    }

    var body: some View {
        GeometryReader { proxy in
            let mid = proxy.size.width / 2
            let center = Int(position.rounded())
            ZStack {
                ForEach(center - 3...center + 3, id: \.self) { i in
                    let offset = Double(i) - position
                    let lens = Self.lenses[Self.index(i)]
                    let near = max(0, 1 - abs(offset))
                    Text(lens.rawValue.uppercased())
                        .font(Theme.caps(12))
                        .tracking(1.6)
                        .foregroundStyle(near > 0.5 ? Theme.text : Theme.muted)
                        .opacity(0.35 + 0.65 * near)
                        .scaleEffect(0.9 + 0.1 * near)
                        .fixedSize()
                        .position(x: mid + CGFloat(offset) * Self.slot, y: proxy.size.height / 2)
                        .onTapGesture { turn(to: i) }
                        .accessibilityHidden(true)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            // The words fade out toward the edges, a peek of what's next either way.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                         .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .gesture(drag)
        }
        .frame(height: 30)
        .onAppear {
            position = Double(Self.lenses.firstIndex(of: mixer.lens) ?? 0)
            clicked = Int(position)
        }
        .onChange(of: mixer.lens) { _, lens in
            guard settling == nil, dragFrom == nil else { return }
            let target = nearest(lens)
            guard target != Int(position.rounded()) else { return }
            clicked = target
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) { position = Double(target) }
        }
        .accessibilityElement()
        .accessibilityLabel("Listening to")
        .accessibilityValue(mixer.lens.rawValue)
        .accessibilityAdjustableAction { direction in
            turn(to: Int(position.rounded()) + (direction == .increment ? 1 : -1))
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                settling?.cancel()
                settling = nil
                let from = dragFrom ?? position
                dragFrom = from
                position = from - Double(g.translation.width / Self.slot)
                click(at: Int(position.rounded()))
            }
            .onEnded { g in
                dragFrom = nil
                // A flick carries on, a word or two at most.
                let flung = -Double((g.predictedEndTranslation.width - g.translation.width) / Self.slot)
                turn(to: Int((position + max(-2, min(2, flung))).rounded()))
            }
    }

    /// Rolls to `word`, a detent for each on the way, then plays what it stopped on.
    private func turn(to word: Int) {
        settling?.cancel()
        let start = position
        let steps = word - Int(start.rounded())
        let duration = reduceMotion ? 0 : min(0.6, 0.22 + 0.1 * Double(abs(steps)))
        withAnimation(reduceMotion ? nil : .smooth(duration: duration)) { position = Double(word) }
        settling = Task { @MainActor in
            // The animation doesn't report where it is, so the detents keep its time instead.
            if steps != 0 {
                let n = abs(steps), dir = steps > 0 ? 1 : -1
                // Smooth slows into the end, so later words come further apart.
                func time(_ k: Int) -> Double { duration * pow(Double(k) / Double(n + 1), 0.8) }
                for k in 1...n {
                    try? await Task.sleep(for: .seconds(time(k) - time(k - 1)))
                    if Task.isCancelled { return }
                    click(at: Int(start.rounded()) + k * dir)
                }
            }
            if Task.isCancelled { return }
            settling = nil
            mixer.choose(Self.lenses[Self.index(word)])
        }
    }
}
