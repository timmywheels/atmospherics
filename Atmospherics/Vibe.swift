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

    /// A change to the scene's sounds, as asked: "no wind", "more fire", "just the waves",
    /// "palms rustling" (there, as they are).
    struct Ask: Equatable {
        enum Change { case leaveOut, more, softer, only, present }
        let change: Change
        let sound: SoundWord
    }

    // MARK: Reading a description

    /// Reads a description into a scene. Where it is, the weather and the time are what the words
    /// name, then what the sounds asked for suggest ("just the waves" is the beach), and the
    /// on-device model, where there is one, reads the rest ("Christmas Eve"). Words that only
    /// change sounds or the hour ("no birds at night") change `draft`, the scene being built.
    /// Nil if there's no scene in it.
    @MainActor
    static func read(_ text: String, draft: Atmosphere) async -> Vibe? {
        let found = Ask.find(in: text)
        let named = Atmosphere.named(in: found.rest)
        var setting = named.setting, sky = named.sky, time = named.time
        let wanted = found.asks.filter { $0.change == .more || $0.change == .only }.map(\.sound)
        sky = sky ?? Self.sky(bringing: wanted)
        // Words besides the names and the sounds, for the model: "a rainy night in Tokyo".
        var other = Words(found.unasked)
        _ = Atmosphere.named(in: &other)
        if other.saysSomething {
            if setting == nil || sky == nil || time == nil, let guess = await guess(found.rest) {
                setting = setting ?? guess.setting
                sky = sky ?? guess.sky
                time = time ?? guess.time
            }
        } else {
            setting = setting ?? Self.setting(for: wanted)
        }
        if setting == nil {
            if sky == nil {
                guard !found.asks.isEmpty || time != nil else { return nil }
                return Vibe(atmosphere: Atmosphere(draft.setting, draft.sky, time ?? draft.time), asks: found.asks, refines: true)
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
        if named.sky == nil { atmosphere.sky = Self.sky(for: atmosphere, without: found.asks) }
        return Vibe(atmosphere: atmosphere, asks: found.asks)
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

    /// What it changed, to say after going: "No wind or birds", "Just waves · More wind",
    /// "With palms · Softer birds".
    var summary: String? {
        func list(_ names: [String], _ last: String) -> String {
            names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " \(last) " + names.last!
        }
        let parts: [(Ask.Change, String, String)] = [(.leaveOut, "No", "or"), (.only, "Just", "and"), (.more, "More", "and"),
                                                       (.present, "With", "and"), (.softer, "Softer", "and")]
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

    private static let birds: [SoundKind] = [.birds, .winterBirds, .jungleBirds, .parrots, .gulls, .owls, .loons, .geese]
    private static let water: [SoundKind] = [.stream, .waterfall, .fountain, .lake, .lapping, .caveDrips, .ocean, .rocks]

    /// Longer names before the ones inside them: "wind chimes" before "wind".
    static let all: [SoundWord] = [
        SoundWord(name: "birds", words: ["bird", "birdsong", "songbird", "birdcall"], kinds: birds),
        SoundWord(name: "gulls", words: ["gull", "seagull", "seabird"], kinds: [.gulls]),
        SoundWord(name: "owls", words: ["owl", "hooting"], kinds: [.owls]),
        SoundWord(name: "loons", words: ["loon"], kinds: [.loons]),
        SoundWord(name: "geese", words: ["geese", "goose"], kinds: [.geese]),
        SoundWord(name: "parrots", words: ["parrot", "macaw"], kinds: [.parrots, .jungleBirds]),
        SoundWord(name: "chimes", words: ["wind chime", "chime"], kinds: [.chimes]),
        SoundWord(name: "wind", words: ["wind", "breeze", "gust", "gale"], kinds: [.wind, .breeze, .treeWind, .gusts, .howl]),
        SoundWord(name: "leaves", words: ["rustling leaves", "leaves"], kinds: [.leaves, .palms]),
        SoundWord(name: "palms", words: ["palm frond", "palm tree", "palm"], kinds: [.palms]),
        SoundWord(name: "rain", words: ["rain", "raindrop", "rainfall", "drizzle"],
                  kinds: [.rain, .lightRain, .heavyRain, .tentRain, .tinRoof, .rainyStreet]),
        SoundWord(name: "thunder", words: ["thunder", "thunderclap", "thunderstorm", "lightning"], kinds: [.thunder, .lightning]),
        SoundWord(name: "waves", words: ["ocean waves", "wave", "surf", "ocean", "sea", "breakers"], kinds: [.ocean, .lapping, .rocks]),
        SoundWord(name: "water", words: ["water", "running water"], kinds: water),
        SoundWord(name: "stream", words: ["babbling brook", "stream", "creek", "brook", "river"], kinds: [.stream]),
        SoundWord(name: "waterfall", words: ["waterfall"], kinds: [.waterfall]),
        SoundWord(name: "fountain", words: ["fountain"], kinds: [.fountain]),
        SoundWord(name: "crickets", words: ["cricket"], kinds: [.crickets]),
        SoundWord(name: "cicadas", words: ["cicada"], kinds: [.cicadas]),
        SoundWord(name: "insects", words: ["insect", "bug"], kinds: [.crickets, .cicadas, .canopy]),
        SoundWord(name: "frogs", words: ["frog", "toad", "peeper", "croaking"], kinds: [.frogs, .treeFrogs, .peepers]),
        SoundWord(name: "fire", words: ["fire", "fireplace", "campfire", "bonfire", "fireside"], kinds: [.fire]),
        SoundWord(name: "wolves", words: ["wolves", "wolf"], kinds: [.wolves]),
        SoundWord(name: "monkeys", words: ["howler monkey", "monkey", "howler"], kinds: [.howlers]),
        SoundWord(name: "whales", words: ["whale song", "whalesong", "whale"], kinds: [.whales]),
        SoundWord(name: "chatter", words: ["people", "voice", "chatter", "talking", "crowd", "conversation", "chatting"],
                  kinds: [.cafe, .bazaar]),
        SoundWord(name: "traffic", words: ["traffic", "car", "vehicle", "scooter", "motorbike", "motorcycle", "honking", "highway"],
                  kinds: [.traffic, .highway, .motorbikes]),
        SoundWord(name: "city noise", words: ["city noise", "street noise", "city sound"], kinds: [.cityHum, .cityNight]),
        SoundWord(name: "trains", words: ["train", "tram", "streetcar", "railway"], kinds: [.train, .tram]),
        SoundWord(name: "planes", words: ["plane", "airplane", "aircraft", "jet"], kinds: [.planes]),
        SoundWord(name: "bells", words: ["church bell", "temple bell", "bell"], kinds: [.bells, .templeBell, .buoy]),
        SoundWord(name: "foghorn", words: ["foghorn", "fog horn"], kinds: [.foghorn]),
        SoundWord(name: "boats", words: ["boat", "sailboat", "rigging", "buoy", "halyard"], kinds: [.halyards, .buoy, .foghorn]),
        SoundWord(name: "clock", words: ["clock", "ticking"], kinds: [.clock]),
        SoundWord(name: "typing", words: ["typing", "keyboard", "typewriter"], kinds: [.typing]),
        SoundWord(name: "fan", words: ["fan"], kinds: [.fan]),
        SoundWord(name: "brown noise", words: ["brown noise"], kinds: [.brown]),
        SoundWord(name: "pink noise", words: ["pink noise"], kinds: [.pink]),
        SoundWord(name: "white noise", words: ["white noise"], kinds: [.white]),
        SoundWord(name: "animals", words: ["animal", "wildlife", "critter", "creature"],
                  kinds: birds + [.wolves, .howlers, .whales, .frogs, .treeFrogs, .peepers, .crickets, .cicadas]),
    ]
}

extension Vibe.Ask {
    /// The asks in a description, the rest of it without what it leaves out (so "no wind"
    /// doesn't make it windy), and what's left without any of them. An ask is a cue ("no",
    /// "with", "less", "just"), a word or two, then a sound or a list of them: "without any wind,
    /// birds or people". Words after a sound say how too: "waves only", "palms rustling", "birds in
    /// the distance"; and before one, what it's doing: "crashing waves".
    static func find(in text: String) -> (asks: [Vibe.Ask], rest: String, unasked: String) {
        let words = Words(text)
        let t = words.tokens
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
                    case .present:
                        stop = next
                    default:
                        break
                    }
                }
                asks += zip(changes, sounds).map { Vibe.Ask(change: $0, sound: $1) }
                if change == .leaveOut { leftOut.insert(integersIn: i..<end) }
                asked.insert(integersIn: i..<stop)
                i = stop
            } else if let (sounds, end) = list(in: words, from: i, filling: false), let (change, next) = after(in: words, at: end) {
                asks += sounds.map { Vibe.Ask(change: change, sound: $0) }
                asked.insert(integersIn: i..<next)
                i = next
            } else if doing.contains(t[i]), let (sounds, end) = list(in: words, from: i + 1, filling: false) {
                asks += sounds.map { Vibe.Ask(change: .present, sound: $0) }
                asked.insert(integersIn: i..<end)
                i = end
            } else {
                i += 1
            }
        }
        func without(_ set: IndexSet) -> String { t.indices.filter { !set.contains($0) }.map { t[$0] }.joined(separator: " ") }
        return (asks, without(leftOut), without(asked))
    }

    private static let cues: [(Change, [String])] = [
        (.leaveOut, ["don't want to hear", "dont want to hear", "do not want to hear", "don't want", "dont want", "do not want",
                     "don't need", "get rid of", "free of", "no more", "nothing like", "no", "without", "minus", "skip", "drop",
                     "mute", "lose", "zero", "not", "never", "remove"]),
        (.only, ["nothing but", "only", "just", "purely", "solely"]),
        (.softer, ["not too much", "barely any", "hardly any", "a little bit of", "a little", "a bit of", "a touch of", "a hint of",
                   "turn down", "less", "quieter", "softer", "fainter", "gentle", "gentler", "faint", "distant", "far off", "subtle"]),
        (.more, ["lots and lots of", "lots of", "lot of", "plenty of", "loads of", "tons of", "full of", "turn up", "bring in",
                 "want to hear", "more", "extra", "louder", "with", "plus", "add", "hear"]),
    ]

    /// Cues, longest first, so "no more" is read before "no".
    private static let cuePhrases: [(Change, [String])] = cues.flatMap { change, phrases in
        phrases.map { (change, $0.split(separator: " ").map(String.init)) }
    }
    .sorted { $0.1.count > $1.1.count }

    /// Words a cue can't reach a sound across, besides another cue.
    private static let stops: Set<String> = ["and", "or", "but", "nor", "then", "so", "only", "alone"]

    /// Words after a sound that say how it's wanted, and where they end: "only", "and nothing
    /// else", "rustling", "in the distance" (or "crashing in the distance").
    private static func after(in words: Words, at i: Int) -> (Change, Int)? {
        let t = words.tokens
        guard i < t.count else { return nil }
        let doingEnd = doing.contains(t[i]) ? i + 1 : i
        if doingEnd < t.count, ["only", "alone"].contains(t[doingEnd]) { return (.only, doingEnd + 1) }
        for phrase in [["and", "nothing", "else"], ["nothing", "else"]] {
            if let end = words.match(phrase, at: doingEnd) { return (.only, end) }
        }
        for phrase in distances {
            if let end = words.match(phrase, at: doingEnd) { return (.softer, end) }
        }
        return doingEnd > i ? (.present, doingEnd) : nil
    }

    /// What sounds do, for "palms rustling" and "crashing waves".
    private static let doing: Set<String> = [
        "rustling", "singing", "chirping", "crashing", "crackling", "howling", "hooting", "croaking", "chattering", "babbling",
        "rolling", "rumbling", "lapping", "pattering", "drumming", "tolling", "ringing", "buzzing", "calling", "humming",
        "ticking", "whistling", "roaring", "tapping", "trickling", "splashing", "flowing", "falling", "blowing", "swaying",
        "passing", "overhead", "chiming", "purring", "murmuring", "trilling", "cooing",
    ]

    /// Where a sound is when it's far: "birds in the distance", "traffic in the background".
    private static let distances: [[String]] = ["in the distance", "in the background", "far away", "far off", "faraway",
                                                "faintly", "softly", "quietly", "gently"].map { $0.split(separator: " ").map(String.init) }

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

    /// One sound, after up to three words in between if `filling` ("a crackling fire", "any of the
    /// birds", but not across another cue: "with a little wind" is a little), then any more after
    /// commas, "and" or "or": "wind, birds or people".
    private static func list(in words: Words, from start: Int, filling: Bool) -> ([SoundWord], Int)? {
        let t = words.tokens
        var i = start
        var first: (SoundWord, Int)?
        while i < t.count {
            if let found = sound(in: words, at: i) { first = found; break }
            guard filling, i - start < 3, !punctuation(t[i]), !stops.contains(t[i]), cue(in: words, at: i) == nil else { break }
            i += 1
        }
        guard let (sound, end) = first else { return nil }
        var sounds = [sound]
        var j = end
        while true {
            var k = j
            while k < t.count, punctuation(t[k]) && t[k] != "." || ["and", "or", "nor"].contains(t[k]) { k += 1 }
            guard k > j else { break }
            if k < t.count, ["the", "any"].contains(t[k]) { k += 1 }
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
        let small: Set<String> = ["a", "an", "the", "and", "or", "but", "please", "i", "i'd", "want", "me", "take", "to", "it",
                                  "make", "of", "in", "on", "at", "with", "some", "like", "go", "somewhere", "something", "just"]
        return tokens.contains { $0.count > 1 && $0.first!.isLetter && !small.contains($0) }
    }
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
