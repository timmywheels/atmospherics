import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Describe the vibe: a scene in your own words, "a sunny day at the beach, no wind, no birds".
// The place, weather and time of day are what the words name; what they leave unsaid comes from
// Apple's on-device model where there is one (iOS and macOS 26 with Apple Intelligence), so
// "a rainy night in Tokyo" is the city and "Christmas Eve" a cabin in the snow. What to leave out
// or bring in ("no birds", "with wolves", "just the waves") is read from the words alone, the
// same on every device.

/// A scene described in words: where to go, and what to change about its sounds.
struct Vibe {
    var atmosphere: Atmosphere
    var asks: [Ask] = []
    /// Only changes the sounds of the scene being built ("no birds"), so it keeps its earlier
    /// changes. Otherwise the scene is as described, starting from how it sounds by default.
    var refines = false
    /// The real place it's in, if it names one ("a retreat in Thailand" is Bangkok): the scene
    /// takes its weather from there.
    var place: Place?
    /// Whether it says what the weather's like, by name or by the rain, thunder or wind it asks
    /// for or leaves out. If not, and it names a place, the weather is the place's right now.
    var saysWeather = false

    /// A change to the scene's sounds, as asked: "no wind", "more fire", "less chatter", "just the
    /// waves", or just "palm trees" (there).
    struct Ask: Equatable {
        enum Change { case leaveOut, more, softer, only, present }
        let change: Change
        let sound: SoundWord
    }

    // MARK: Reading a description

    /// Reads a description into a scene. The weather and the time are what the words name; where
    /// it is, the on-device model reads from the whole description where there is one ("palm trees
    /// at night" is the beach, though "trees" names the forest), and otherwise the words and the
    /// sounds asked for ("just the waves" is the beach). Words that only change sounds or the hour
    /// ("no birds at night") change `draft`, the scene being built. Nil if there's no scene in it.
    @MainActor
    static func read(_ text: String, draft: Atmosphere) async -> Vibe? {
        let found = Ask.find(in: text)
        let named = Atmosphere.named(in: found.rest)
        var setting = named.setting, sky = named.sky, time = named.time
        var asks = found.asks
        // "Rainy and windy": the rain, with more wind than rain brings.
        if named.skies.contains(.wind), let sky, ![.wind, .snowstorm, .thunderstorm].contains(sky),
           !asks.contains(where: { $0.sound.kinds.contains(.wind) }), let wind = SoundWord.all.first(where: { $0.name == "wind" }) {
            asks.append(Ask(change: .more, sound: wind))
        }
        let wanted = asks.filter { $0.change == .more || $0.change == .only }.map(\.sound)
        sky = sky ?? Self.sky(bringing: wanted)
        // Words besides the names and the sounds, for the model: "a rainy night in Tokyo".
        var other = Words(found.unasked)
        _ = Atmosphere.named(in: &other)
        if other.saysSomething, let guess = await guess(found.rest) {
            setting = guess.setting
            sky = sky ?? guess.sky
            time = time ?? guess.time
        } else {
            setting = setting ?? Self.setting(for: wanted)
        }
        if setting == nil {
            if sky == nil {
                guard !asks.isEmpty || time != nil else { return nil }
                return Vibe(atmosphere: Atmosphere(draft.setting, draft.sky, time ?? draft.time), asks: asks, refines: true)
            }
            // "Make it snow": here, if it can.
            if let sky, draft.setting.info.skies.contains(sky) { setting = draft.setting }
        }
        // The scene being built, if that's where it is, keeps what wasn't said.
        if setting == draft.setting {
            sky = sky ?? draft.sky
            time = time ?? draft.time
        }
        var atmosphere = Atmosphere.suited(setting, sky, time ?? .now)
        // Weather that brings what was left out ("no rain") gives way, unless it was asked for by name.
        if named.sky == nil { atmosphere.sky = Self.sky(for: atmosphere, without: asks) }
        let weather: Set<SoundKind> = [.rain, .lightRain, .heavyRain, .thunder, .lightning, .wind, .breeze, .gusts, .howl, .treeWind]
        return Vibe(atmosphere: atmosphere, asks: asks, place: place(in: text, for: atmosphere.setting),
                    saysWeather: named.sky != nil || asks.contains { !weather.isDisjoint(with: $0.sound.kinds) })
    }

    /// The real place a description is in, by its name or its country ("a retreat in Thailand" is
    /// Bangkok); of a country's places, the one most like the setting (Japan's temple is Kyoto's).
    private static func place(in text: String, for setting: Setting) -> Place? {
        // Whole words, without accents or case: " reykjavik ", " hawaii ".
        func plain(_ s: String) -> String {
            " " + s.replacingOccurrences(of: "[ʻ’']", with: "", options: .regularExpression)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
                .joined(separator: " ") + " "
        }
        let said = plain(text)
        func says(_ name: String) -> Bool { said.contains(plain(name)) }
        if let place = Place.all.first(where: { says($0.name) }) { return place }
        let own = Dictionary(setting.info.signature, uniquingKeysWith: max)
        func likeness(_ p: Place) -> Double { p.signature.reduce(0) { $0 + min($1.1, own[$1.0] ?? 0) } }
        return Place.all.filter { says($0.country) }.max { likeness($0) < likeness($1) }
    }

    /// Where sounds are most at home: the setting where they're loudest, counting each one's own
    /// sound twice, so "just birds" is the forest rather than the lake with its loons.
    private static func setting(for sounds: [SoundWord]) -> Setting? {
        let scored = Setting.allCases.filter { $0 != .flight }.map { setting in
            (setting, sounds.reduce(0.0) { sum, sound in
                sum + setting.info.signature.reduce(0.0) { s, entry in
                    s + (entry.0 == sound.kinds.first ? 2 * entry.1 : sound.kinds.contains(entry.0) ? entry.1 : 0)
                }
            })
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    /// The weather that brings sounds asked for: "lots of rain" is rainy.
    private static func sky(bringing sounds: [SoundWord]) -> Sky? {
        let kinds = Set(sounds.flatMap(\.kinds))
        if kinds.contains(.thunder) { return .thunderstorm }
        if kinds.contains(.rain) { return .rain }
        if kinds.contains(.wind) { return .wind }
        return nil
    }

    /// The scene's weather, or the nearest it can have that doesn't bring sounds that were left
    /// out: a snowstorm with no wind is snow, a thunderstorm with no thunder a downpour, and
    /// otherwise clear skies if it has them.
    private static func sky(for a: Atmosphere, without asks: [Ask]) -> Sky {
        let gone = Set(asks.filter { $0.change == .leaveOut }.flatMap(\.sound.kinds))
        func brings(_ sky: Sky) -> [SoundKind] {
            switch sky {
            case .drizzle, .rain, .downpour: [.rain]
            case .thunderstorm: [.rain, .thunder]
            case .wind, .snowstorm: [.wind]
            case .clear, .fog, .snow: []
            }
        }
        guard brings(a.sky).contains(where: gone.contains) else { return a.sky }
        let near: [Sky] = a.sky == .snowstorm ? [.snow] : a.sky == .thunderstorm ? [.downpour, .rain] : []
        let order = near + [.clear, .fog, .snow, .drizzle, .rain, .downpour, .wind, .thunderstorm, .snowstorm]
        return order.first { a.setting.info.skies.contains($0) && !brings($0).contains(where: gone.contains) } ?? a.sky
    }

    /// The model's reading of where a description is, its weather and its time of day.
    @MainActor
    private static func guess(_ text: String) async -> (setting: Setting, sky: Sky, time: TimeOfDay)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) { return await SceneReader.shared.read(text) }
        #endif
        return nil
    }

    /// Whether the on-device model is here to read moods and places in the world ("Christmas Eve",
    /// "Tokyo"), beyond the names the words alone know.
    static var readsMoods: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// A few descriptions to try when the box is empty, different each time, and ones this
    /// device can read.
    static func suggestions(_ count: Int = 4) -> [String] {
        let moods = ["a rainy night in Tokyo", "a snowy Christmas Eve", "a spooky forest with wolves",
                     "lofi café on a rainy afternoon", "a lighthouse in a storm", "deep focus, just rain",
                     "somewhere warm, just the waves", "a summer porch, lots of crickets"]
        let words = ["a sunny beach, no birds", "a cabin in a snowstorm, no wind", "rain on a tin roof", "a foggy harbor at dawn",
                     "a café in the rain, less chatter", "a tent in a thunderstorm, no thunder", "a lake at dusk with loons",
                     "a forest with lots of birds"]
        return Array((readsMoods ? moods + words.prefix(3) : words).shuffled().prefix(count))
    }

    /// Gets the model ready ahead of a description, so the first one doesn't wait for it to load.
    @MainActor
    static func prepare() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) { SceneReader.shared.prewarm() }
        #endif
    }

    // MARK: Recent descriptions

    /// Descriptions that went somewhere, newest first, for the box to offer again.
    static var recent: [String] { UserDefaults.standard.stringArray(forKey: "recentVibes") ?? [] }

    static func remember(_ text: String) {
        let kept = recent.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        UserDefaults.standard.set(Array(([text] + kept).prefix(8)), forKey: "recentVibes")
    }

    static func forgetRecent() { UserDefaults.standard.removeObject(forKey: "recentVibes") }

    // MARK: Its sounds

    /// The changes to the scene's sounds as tweaks over what it would play (`base`): left out is
    /// off whatever the weather brings, more is louder (or brought in if it isn't there), softer
    /// is half as loud, there is brought in if it isn't, and just these is everything else off.
    func tweaks(over base: [(SoundKind, Double)]) -> [String: Double] {
        var level: [SoundKind: Double] = [:]
        for (k, v) in base { level[k] = max(level[k] ?? 0, v) }
        var out: [String: Double] = [:]
        func bringIn(_ sound: SoundWord, at volume: Double) {
            if let k = sound.bringIn(at: atmosphere.setting) { out[k.rawValue] = volume }
        }
        let only = asks.filter { $0.change == .only }.map(\.sound)
        if !only.isEmpty {
            let keep = Set(only.flatMap(\.kinds))
            for k in SoundKind.allCases where !keep.contains(k) { out[k.rawValue] = -1 }
            for sound in only where !sound.kinds.contains(where: { level[$0] != nil }) { bringIn(sound, at: 0.45) }
        }
        for ask in asks {
            let playing = ask.sound.kinds.filter { level[$0] != nil }
            switch ask.change {
            case .leaveOut:
                for k in ask.sound.kinds { out[k.rawValue] = -1 }
            case .more:
                if playing.isEmpty { bringIn(ask.sound, at: 0.4) }
                for k in playing { out[k.rawValue] = 0.25 }
            case .softer:
                if playing.isEmpty { bringIn(ask.sound, at: 0.15) }
                for k in playing { out[k.rawValue] = -(level[k] ?? 0) / 2 }
            case .present:
                if playing.isEmpty { bringIn(ask.sound, at: 0.3) }
            case .only:
                break
            }
        }
        return out
    }

    /// What it changed, to say after going: "No wind or birds", "Just waves · More wind".
    var summary: String? {
        func list(_ names: [String], _ last: String) -> String {
            names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " \(last) " + names.last!
        }
        let parts: [(Ask.Change, String, String)] = [(.leaveOut, "No", "or"), (.only, "Just", "and"), (.more, "More", "and"),
                                                       (.present, "With", "and"), (.softer, "Less", "and")]
        let said = parts.compactMap { change, lead, last -> String? in
            var seen = Set<String>()
            let names = asks.filter { $0.change == change }.map(\.sound.name).filter { seen.insert($0).inserted }
            return names.isEmpty ? nil : "\(lead) \(list(names, last))"
        }
        return said.isEmpty ? nil : said.joined(separator: " · ")
    }
}

// MARK: - Sounds in words

/// A sound by the names people give it, meaning one or more of ours.
struct SoundWord: Equatable {
    /// For saying what changed: "No birds".
    let name: String
    let words: [String]
    /// The sounds it means. The first the place has (or else the first) is brought in when none is playing.
    let kinds: [SoundKind]

    /// The one to bring in at a place: one it has if it can, as it plays here.
    func bringIn(at setting: Setting) -> SoundKind? {
        let cast = Set(setting.info.signature.map(\.0))
        return (kinds.filter(cast.contains) + kinds.filter { !cast.contains($0) }).lazy.compactMap(\.playable).first
    }

    static func == (a: SoundWord, b: SoundWord) -> Bool { a.name == b.name }

    /// Every sound by the names people give it, from the catalog (`SoundFamily`, `SoundKind.aliases`):
    /// each family as a whole ("birds"), then each sound by its own ("seagulls"). In a sentence,
    /// the longest name wins, so "wind chimes" are chimes rather than wind.
    static let all: [SoundWord] = SoundFamily.allCases.map { family in
        SoundWord(name: family.name, words: family.words, kinds: SoundKind.allCases.filter { $0.family == family })
    } + SoundKind.allCases.filter { !$0.aliases.isEmpty }.map { kind in
        SoundWord(name: kind.name.lowercased(), words: kind.aliases, kinds: [kind])
    }
}

extension Vibe.Ask {
    /// The asks in a description, the rest of it without what it leaves out (so "no wind"
    /// doesn't make it windy), and what's left without any of them. There are four ways to ask
    /// (no, more, less, just), each a cue, a word or two, then a sound or a list of them: "without
    /// any wind, birds or people". A few words after a sound say it too: "waves only", "and nothing
    /// else", "birds in the distance".
    static func find(in text: String) -> (asks: [Vibe.Ask], rest: String, unasked: String) {
        // Read without the small words ("I don't want to hear any birds" is "don't want hear
        // birds"), then map what's asked back onto the whole text.
        let all = Words(text).tokens
        let kept = all.indices.filter { !Words.stopWords.contains(all[$0]) }
        let words = Words(tokens: kept.map { all[$0] })
        let t = words.tokens
        func whole(_ r: Range<Int>) -> ClosedRange<Int> { kept[r.lowerBound]...kept[r.upperBound - 1] }
        // Words that name the scene (its place, weather, hour) aren't asks of their own: "rain on a
        // tin roof" is a rainy scene, "a light rain" drizzle, "on a plane" a flight without flyovers.
        var probe = words
        _ = Atmosphere.named(in: &probe)
        func names(_ r: Range<Int>) -> Bool { r.allSatisfy { probe.tokens[$0].isEmpty } }
        var asks: [Vibe.Ask] = []
        var leftOut = IndexSet(), asked = IndexSet()
        var i = 0
        while i < t.count {
            if let (change, start) = cue(in: words, at: i), let (sounds, end) = list(in: words, from: start, filling: true) {
                var changes = sounds.map { _ in change }
                var stop = end
                if let (after, next) = after(in: words, at: end) {
                    switch after {
                    case .only where change != .only:
                        changes[changes.count - 1] = .only   // "No wind, waves only"
                        stop = next
                    case .softer where change == .more:
                        changes = changes.map { _ in .softer }   // "with birds in the distance"
                        stop = next
                    default:
                        break
                    }
                }
                if change == .leaveOut || !names(i..<end) {
                    asks += zip(changes, sounds).map { Vibe.Ask(change: $0, sound: $1) }
                    if change == .leaveOut { leftOut.insert(integersIn: whole(i..<end)) }
                    asked.insert(integersIn: whole(i..<stop))
                }
                i = stop
            } else if let (sounds, end) = list(in: words, from: i, filling: false) {
                // Named with no cue, a sound is wanted: "palm trees rustling", "waves only".
                let (change, next) = after(in: words, at: end) ?? (.present, end)
                if change != .present || !names(i..<end) {
                    asks += sounds.map { Vibe.Ask(change: change, sound: $0) }
                    asked.insert(integersIn: whole(i..<next))
                }
                i = next
            } else {
                i += 1
            }
        }
        func without(_ set: IndexSet) -> String { all.indices.filter { !set.contains($0) }.map { all[$0] }.joined(separator: " ") }
        return (asks, without(leftOut), without(asked))
    }

    /// The four ways to ask, and a few words for each.
    private static let cues: [(Change, [String])] = [
        (.leaveOut, ["don't want", "dont want", "do not want", "no more", "no", "without", "minus", "skip"]),
        (.more, ["lots", "lot", "more", "louder", "extra", "with", "plus", "add"]),
        (.softer, ["little", "bit", "less", "quieter", "softer", "faint", "distant", "light", "gentle", "soft", "slight"]),
        (.only, ["nothing but", "only", "just"]),
    ]

    /// Cues, longest first, so "no more" is read before "no".
    private static let cuePhrases: [(Change, [String])] = cues.flatMap { change, phrases in
        phrases.map { (change, $0.split(separator: " ").map(String.init)) }
    }
    .sorted { $0.1.count > $1.1.count }

    /// Words a cue can't reach a sound across, besides another cue.
    private static let stops: Set<String> = ["and", "or", "but", "nor", "then", "so", "only", "alone"]

    /// Words after a sound that ask for it too, and where they end: "waves only", "and nothing
    /// else" (just these); "in the distance", "far away" (less). A word may come between, as in
    /// "wolves howling far away".
    private static func after(in words: Words, at i: Int) -> (Change, Int)? {
        let t = words.tokens
        let starts = i + 1 < t.count && !punctuation(t[i]) && !stops.contains(t[i]) && cue(in: words, at: i) == nil ? [i, i + 1] : [i]
        for start in starts {
            for (change, phrases) in afters {
                for phrase in phrases {
                    if let end = words.match(phrase, at: start) { return (change, end) }
                }
            }
        }
        return nil
    }

    private static let afters: [(Change, [[String]])] = [
        (.only, ["only", "alone", "and nothing else", "nothing else"]),
        (.softer, ["distance", "background", "far away", "far off"]),
    ].map { change, phrases in (change, phrases.map { $0.split(separator: " ").map(String.init) }) }

    private static func cue(in words: Words, at i: Int) -> (Change, Int)? {
        for (change, phrase) in cuePhrases {
            if let end = words.match(phrase, at: i) { return (change, end) }
        }
        return nil
    }

    /// A sound starting at word `i`, the longest name first.
    private static func sound(in words: Words, at i: Int) -> (SoundWord, Int)? {
        var best: (SoundWord, Int)?
        for sound in SoundWord.all {
            for name in sound.words {
                if let end = words.match(name.split(separator: " ").map(String.init), at: i), end > (best?.1 ?? 0) {
                    best = (sound, end)
                }
            }
        }
        return best
    }

    /// One sound, after up to two words in between if `filling` ("crackling fire", "annoying loud
    /// birds", but not across another cue: "with a little wind" is a little), then any more after
    /// commas, "and" or "or": "wind, birds or people".
    private static func list(in words: Words, from start: Int, filling: Bool) -> ([SoundWord], Int)? {
        let t = words.tokens
        var i = start
        var first: (SoundWord, Int)?
        while i < t.count {
            if let found = sound(in: words, at: i) { first = found; break }
            guard filling, i - start < 2, !punctuation(t[i]), !stops.contains(t[i]), cue(in: words, at: i) == nil else { break }
            i += 1
        }
        guard let (sound, end) = first else { return nil }
        var sounds = [sound]
        var j = end
        while true {
            var k = j
            while k < t.count, punctuation(t[k]) && t[k] != "." || ["and", "or", "nor"].contains(t[k]) { k += 1 }
            guard k > j else { break }
            guard let (next, e) = Self.sound(in: words, at: k) else { break }
            sounds.append(next)
            j = e
        }
        return (sounds, j)
    }

    private static func punctuation(_ token: String) -> Bool { token.count == 1 && ",.;:!?&/+".contains(token) }
}

extension Words {
    /// Whether there's anything to read a scene from, beyond small words.
    var saysSomething: Bool {
        let small = Words.stopWords.union(["and", "or", "but", "want", "take", "make", "go", "somewhere", "something", "with", "just"])
        return tokens.contains { $0.count > 1 && $0.first!.isLetter && !small.contains($0) }
    }

    /// Small words that carry nothing here, left out when reading what's asked. The ones that do
    /// (no, not, more, less, just, only, and, or) stay.
    static let stopWords: Set<String> = [
        "a", "an", "the", "of", "to", "any", "some", "my", "our", "your", "this", "that", "these", "those", "there", "here",
        "is", "are", "be", "it", "its", "it's", "in", "on", "at", "by", "for", "from", "into", "i", "i'd", "i'm", "me", "we",
        "us", "you", "please", "like", "so", "very", "really",
    ]
}

// MARK: - The on-device model

#if canImport(FoundationModels)
/// Apple's on-device model, reading where a description is, its weather and its time of day,
/// from our own lists. That's all it's asked: it does it well and in under a second, while asked
/// for sounds as well it listed ones nobody had asked for. A session answers one description.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class SceneReader {
    static let shared = SceneReader()
    private var ready: LanguageModelSession?

    /// Loads the model now, so it's ready for a description: when Teleport opens.
    func prewarm() {
        guard SystemLanguageModel.default.isAvailable, ready == nil else { return }
        let session = Self.session()
        session.prewarm()
        ready = session
    }

    /// Nil if there's no model here, it can't answer, or it takes longer than `patience` seconds.
    func read(_ text: String, patience: Double = 15) async -> (setting: Setting, sky: Sky, time: TimeOfDay)? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = ready ?? Self.session()
        ready = nil
        let reading: SceneReading? = await withTaskGroup(of: SceneReading?.self) { group in
            group.addTask {
                try? await session.respond(to: text, generating: SceneReading.self,
                                           options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 60)).content
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(patience))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let reading, let setting = Setting.allCases.first(where: { SceneReading.name(of: $0) == reading.place }),
              let sky = Sky.allCases.first(where: { SceneReading.name(of: $0) == reading.weather }),
              let time = TimeOfDay(rawValue: reading.time) else { return nil }
        return (setting, sky, time)
    }

    private static func session() -> LanguageModelSession {
        LanguageModelSession(instructions: "Imagine the description as a place you could hear. Choose where it is, the weather and the time of day.")
    }
}

/// What the model is asked for. The settings are offered in words rather than by their names
/// in code, and the few it confused carry a hint ("a harbor by a lighthouse"): it chose better.
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct SceneReading {
    @Guide(description: "Where it sounds like", .anyOf(Setting.allCases.map(SceneReading.name(of:))))
    var place: String
    @Guide(description: "The weather", .anyOf(Sky.allCases.map(SceneReading.name(of:))))
    var weather: String
    @Guide(description: "The time of day, or now if it doesn't suggest one", .anyOf(TimeOfDay.allCases.map(\.rawValue)))
    var time: String

    static func name(of setting: Setting) -> String {
        switch setting {
        case .cabin: "a log cabin by the fire"
        case .city: "a city street"
        case .cafe: "a café"
        case .beach: "a beach"
        case .tent: "a tent"
        case .forest: "a forest"
        case .jungle: "a jungle"
        case .lake: "a lake"
        case .harbor: "a harbor by a lighthouse"
        case .train: "a sleeper train"
        case .library: "a library"
        case .temple: "a temple garden"
        case .mountains: "the mountains"
        case .tinRoof: "a tin roof in the tropics"
        case .porch: "a porch on a summer night"
        case .market: "a market"
        case .flight: "a long flight"
        }
    }

    static func name(of sky: Sky) -> String {
        switch sky {
        case .wind: "windy"
        case .fog: "foggy"
        default: sky.rawValue
        }
    }
}
#endif
