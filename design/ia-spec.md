# Atmospherics: information architecture spec (v2, final)

**What changed from v1.** This version follows the owner's direction more literally. Places are live only, and imagined weather is what a Scene is for. Scenes leave the wheel completely and live in the Library. Favorites and saved copies become one flat list, Yours. Two departures from the direction remain, and each is flagged where it appears (marked **Departure**): "Where to?" doubles as the Library's search field, and Favorites fold into Yours. The model risks the critique found are fixed in §8, and the stages are reordered so that each one really does ship on its own (§9). Rejected critique points are listed at the end.

Citations are relative to `/Users/timothy.wheeler/dev/ai/atmospherics/`. The repo was left untouched. Spelling is US throughout, to match the app ("Harbor", `Atmospheres.swift:136`).

---

## 1. Mental model and glossary

**In four sentences.** Listen plays one soundscape at a time. The wheel picks what you're traveling through, either Places (real, with live weather) or a mood, and swiping moves to the next one there. The Library holds everything the app can play, including the imagined Scenes, and you search it by saying where you'd like to go. Touching the sounds of whatever is playing lets you tune it, and your changes stay with that place, mix or scene until you reset them.

**Three rules that hold everywhere**
1. **Browsing keeps play or pause as it is; choosing plays.**
   - Browsing means turning the wheel, swiping, ←/→, the media keys' next and previous, and the Dock's travel items. None of them changes play state. That is how the code works today (`choose`, `Mixer.swift:1282-1299`).
   - Choosing means a tap in the Library or a search result, a Where to? chip, or the last step of onboarding. A choice plays, which matches the `play: true` defaults of `select`, `load`, `go(to:)` and `revisit` (`Mixer.swift:492`, `:1151`, `:850-855`).
2. **A Place is always live.** Its weather is the real weather now. You can't set a Place's sky. If you want rain in Tokyo when it's dry there, that is a Scene, an imagined place (§3 Search).
3. **Your edits belong to what you edited.** That holds for a place, a mix, a scene or something in Yours. Once you've tuned it, Tune shows **Reset**. Nothing breaks off into "Your mix" any more (`Mixer.swift:923-935`). You get a separate item only by asking for one with **Save as new…**.

**Swiping goes through where you came from.** If what's playing sits on a wheel stop, swiping moves through that stop. If it doesn't (a Scene, something in Yours, an item from Recent), swiping moves through the Library shelf you picked it from, and the wheel goes quiet (§2). Back always means the previous item in that ring.

**Glossary.** These are the only nouns and verbs users see.

| Word | Meaning | Replaces |
|---|---|---|
| **Places** | Real places with live weather: where you are, then the 44 curated places (`Places.swift:42`). It is also the first wheel stop. | Outside, Escape, `match`/`escape` |
| **Here** | A badge, never a title. It marks the place where you are, which is titled with its locality name ("Brooklyn"). | Outside, "Matching outside" |
| **Focus · Relax · Sleep · Meditate** | The four moods. Each is a wheel stop and a filter on the Mixes shelf. | Tag lenses (`Mixer.swift:1248-1271`) |
| **Mix** | A ready-made blend that isn't tied to a place, tagged with a mood. | Preset (`Library.swift:26-115`) |
| **Scene** | An imagined place with its own weather and time, such as "a log cabin in a snowstorm". | Atmosphere (`Atmospheres.swift:428-456`) |
| **Sound** | One ingredient, such as Rain on a tin roof. | SoundKind, layer, orb |
| **Live** | The weather word for Places: "Live · Drizzle · 9°". It is never used for anything else in the UI. | Match, "Back to Live Weather" |
| **Tune** | The verb, and the sheet or inspector where you change what's playing. | Layers, Edit sounds |
| **Library** | The catalog of everything. | Library sheet, Teleport IDEAS |
| **Search** | Searching the Library. Its field reads *Where to?* | Teleport, Describe the vibe |
| **Imagine** | Making a new Scene from words. It is the last row of any search. | Teleport go, Vibe |
| **Save** | The bookmark. It puts the current thing in Yours, tuning and all. | Favorite, Keep |
| **Save as new…** | Makes a separately named copy of what you're hearing, in Yours. | Save this mix |
| **Yours** | One list of everything you've saved. | Favorites + Yours |
| **Recent** | Where you've been. | Same |
| **Reset** | Undoes your tuning of the current thing. | Reset scene |

**Words that go:** Outside, Escape, Escaping to…, Atmosphere, Lens, Layers, Teleport, Favorites, Keep, Your mix, Describe the vibe, Sky as a control on places, Warm Night (`Mixer.swift:227`), and "Find on the map" (not in v1, see §9 Stage 7). "Where to?" is copy only, the prompt and the placeholder. Menus, hints and a11y say **Search**.

---

## 2. Listen

### iPhone, top to bottom
1. **Wheel: Places · Focus · Relax · Sleep · Meditate.** It stays endless.
   - Dragging gives a detent per word. A flick carries at most ±2 words. Tapping a word at the edge turns to it (`ModeWheel.swift:60`, `:92-107`).
   - **Every stop remembers its last item.** Moods use `lens.<Tag>` (`Mixer.swift:1294`). Places uses `pinnedPlace` (`Mixer.swift:164`, `:1161`), where nil means Here. Today `choose(.outside)` always calls `goHome()` (`:1291-1292`); it changes to restore `pinnedPlace`. So on iPhone, "back to Tokyo after a Focus mix" means turning back to Places.
   - Turning the wheel never plays. Fix the stale "plays" comments at `ModeWheel.swift:5` and `:110`.
   - **Off-wheel state.** When what's playing isn't on a stop (a Scene, a Yours item, a Recent item from another kind), the wheel dims to 40% with no word centered, and the a11y value reads "Listening to <title>, from the Library". Turning the wheel from this state lands on the stop nearest the center, on that stop's remembered item, without changing play state. When a Library choice lands on a stop, the wheel rolls there (`ModeWheel.swift:77-83`, `lensFollows` at `Mixer.swift:1275`).
2. **Form** (Carousel or SoundForm).
   - Swiping ←/→ travels through the current ring, with a tick at the one-third commit point and a rubber-band at the end (`NowPlayingView.swift:322`, `:374-377`).
   - Hold for 0.25s, then drag, to lift and turn the form. It stays an unannounced delight. **Fix:** a hold that never moves past the drag threshold now counts as a tap, so it no longer sets `skipTap` (`NowPlayingView.swift:254-278`) and taps don't get lost.
   - Storm strikes flash the halo (`:703-717`).
   - **Tap opens Tune.**
3. **Title, with a Save bookmark inline**, as on the Mac today (`NowPlayingView.swift:486`). There is no bookmark on Here, because it is always first among Places.
   - **Tapping the title opens Search**: the Library on the playing item's shelf, with the field focused. Its a11y hint is "Search the Library".
   - The title context menu is cut.
   - **The sub-line is one honest line:**
     - Place: "Live · Light rain · 14° · 4 hours behind".
     - Here: "Here · Drizzle · 9°". If location is off: "Location off · Allow in Settings" (`Mixer.swift:436-438`).
     - Mix: "Focus · strong evidence · 60 min". Once tuned: "Focus · tuned by you · 60 min". The evidence claim is dropped while it's no longer true.
     - Scene: "Imagined · snow, night".
     - Yours: "Saved · from Tokyo".
4. **Sound pills** (LayerStrip, `:598-635`). Tapping one opens Tune. A small dot means the thing is tuned. The Reset pill moves into Tune.
5. **VolumeLine.** Unchanged (`:1010-1082`).
6. **Play.**
   - Tap to play or pause.
   - Long-press opens the sleep timer dialog, **the only timer UI on iPhone**. Its a11y action stays (`:981-1000`). A first-run hint teaches it (§5).
   - The timer label shows only when the timer isn't the default 8h (`Mixer.swift:54`).

**Cut from Listen**
- **The ⋯ PageActions fan** (`:842-954`). Its jobs move:
  - Keep → the title bookmark (Save)
  - Edit → pills, form or swipe down
  - Library → swipe up
  - Teleport → title tap
  - Timer → long-press Play
  - Surprise → a chip in empty Search
- **The "Describe the vibe…" bar** (`:811-833`).

### Gestures (iPhone)

| Gesture | Does | Haptic |
|---|---|---|
| Swipe ←/→ on the form | Next or previous in the current ring | tick at threshold, thud on arrival |
| Swipe up | Library, on the playing item's shelf | soft |
| **Swipe down** | **Opens Tune**, replacing weather cycling (`:145-162`) | soft |
| Tap form or pills | Tune | tap |
| Tap title | Search | tap |
| Long-press Play | Sleep timer | thud, then tick on choice |
| With Tune open | Up expands it, down closes it (unchanged) | detent tick |

**Swipe-down start region.** Swipe down only starts below the wheel's frame. The top safe area and the wheel band (about the top 120pt) are excluded, so it doesn't compete with Notification Center, Control Center or a diagonal wheel drag. The 1.5× vertical ratio guard stays (`:150`).

**Accessibility actions on Listen:** Travel somewhere new · Go back · Tune · Library · Search · Sleep timer.

### What each ring holds
- **Places:** Here first, then your saved places, then the 44 curated places **ordered westward by UTC offset from Here**, so that swiping feels like turning a globe. Places near Here are skipped, as today (`Mixer.swift:1336-1337`). This order replaces the "least like home" pick (`:1139-1148`).
- **Focus, Relax, Sleep, Meditate:** that mood's mixes only. Focus stays evidence-pure (`Library.swift:7-9`).
- **Off-wheel rings:** the Library shelf the item came from, in the shelf's order. That is Scenes (curated, then Imagined lately), Yours, or Recent. Nothing is inserted on the fly, so the rings stay stable and the carousel's preloaded `upcoming` and `upcomingBack` stay correct (`Mixer.swift:1324-1338`).
- The Scenes `deck`, `draw` and `backStack` (`Mixer.swift:1316`) are deleted.

### Play and pause, precisely
- **Never change play state:**
  - the wheel
  - swipes and ←/→
  - media-key next and previous
  - Dock travel
  - opening or closing Tune or the Library
  - adding or removing a sound
- **Start playing:**
  - a tap in the Library or a search result
  - a Search chip
  - the onboarding choice
  - widget and Live Activity Play
- **Pause:** Play, the sleep timer ending, interruptions, and unplugging headphones (`Mixer.swift:280-300`).
- **Adding a sound while paused** previews that sound alone for 2s, then stops. That is your confirmation. The notice reads "Thunder joins Tokyo, for when you press play."

### Mac Listen (`Mac/MacListen.swift`)
- **The same stack:** wheel, form with hover TravelArrows (`:85-121`), title with bookmark, sub-line, VolumeLine.
- **Bottom bar:** sound pills (they open Tune) · Timer menu · Play.
- **Cut:** the Teleport globe, the Surprise button (it is the same as →, `:43-46`), and the separate ResetTuning, which moves into Tune.
- **Keys:**
  - ←/→ travel (`:58-59`).
  - **↑/↓ turn the wheel**, but only while focus is on Listen itself. When focus is in the Tune inspector, arrows belong to its controls.
  - ⌥⌘1–5 jump to a stop from anywhere.
  - Space plays or pauses.
- **Hints:** "Swipe with two fingers, or press → to travel" and "↑ ↓ turn the wheel".

---

## 3. Library

**Layout, top to bottom**
1. A search field reading **Where to?**
2. **Shelf chips: Places · Mixes · Scenes · Sounds · Yours · Recent.** Yours and Recent are hidden when they're empty.
3. The shelf content.

The Library opens on the playing item's shelf, scrolled to that item (`LibraryView.swift:30`, `:137-139`). The title tap, ⌘K and the a11y Search action open it the same way, with the field focused.

**Departure (flagged):** the direction names "Where to?" only as the onboarding prompt. This spec also uses it as the Library field's placeholder, because a separate Where to? screen next to a searchable Library would be a second search. The noun for the feature is **Search**.

### Shelves

**Places**
- **Shows:**
  - Here first, titled with your locality: "Here · Drizzle · 9°", or "Location off".
  - The regions from `Places.swift:198-202`. Each card shows the live weather and temperature there.
- **Tap:** plays it and closes the Library, with a thud. The wheel rolls to Places, and `pinnedPlace` updates.
- **Long-press:** Save.

**Mixes**
- **Shows:**
  - Mood sub-chips for Focus, Relax, Sleep and Meditate.
  - Cards read "length · evidence".
  - **How we chose these ↗** stays on Focus (`LibraryView.swift:86-101`).
- **Tap:** plays it and closes the Library. The wheel rolls to that mood.
- **Long-press:** Save.

**Scenes**
- **Shows:**
  - All 28 curated Scenes as ColorCards (`TeleportView.swift:324-348`), grouped by mood.
  - Then **Imagined lately**: Scenes you made with Imagine, taken from Recent.
  - This fixes the fact that no shelf lists Scenes today (`LibraryView.swift:36-38`).
  - A card whose weather is true at Here right now carries a **Like here now** badge (this replaces the Teleport "Here" badge).
- **Tap:** plays it and closes the Library. The wheel goes quiet (off-wheel), and swiping moves through this shelf.
- **Long-press:** Save.

**Sounds**
- **Shows:** every available sound (`Sound.swift:63`) as pills, with the sound browser's filters (below).
- **Tap a pill:** adds the sound to what's playing, or removes it. The Library stays open.
- **Long-press:** previews the sound alone while held.

**Yours**
- **Shows:** one list in your own order of everything you've saved: places, mixes and scenes bookmarked with Save, and Save as new… copies. Each card says what it is ("Place", "Mix", "Scene", or "from Tokyo").
- **Tap:** plays it and closes the Library.
- **Swipe left:** Remove.
- **Swipe right:** Rename. This only applies to copies.
- **Drag:** reorder (`:113-131`).
- **Departure (flagged):** Favorites fold into Yours, so there is one saved list instead of two. This keeps the direction's single "Yours (saved)" noun and adds no sub-shelves.

**Recent**
- **Shows:** the last 20, with relative times and **Clear Recent** (`:65-85`).
- **Tap:** plays it and closes the Library.

**The current-item badge.** The current item shows **Now**. While it plays, the badge has a moving bar; while paused, the badge is still. This keeps today's Current/Playing distinction, which rule 1 makes common. The **All** chip is cut.

**Two tap meanings, kept visibly apart.** Cards (places, mixes, scenes, Yours, Recent) play and close. Pills (sounds) add and stay open. Search shows sounds as pills too, in their own group, so the shape tells you what a tap will do.

### Search
The search runs locally as you type, debounced by 120 ms. The on-device model is used only by Imagine.

**What each kind of item is matched on**

| Item | Fields matched |
|---|---|
| Places | Name, country, region, aliases ("NYC") |
| Mixes | Name, mood, description, the names of the sounds in it |
| Scenes | Title, setting, weather and time words |
| Sounds | Name, category, `SoundFamily` words (`Sound.swift:346-347`), so "waves" finds the ocean sounds |
| Yours | Name and origin |

**Ranking within each group**
1. Exact name
2. Name prefix
3. A word in the name
4. Alias or tag
5. Description

Ties go to the most recently visited.

**Group order.** The group with the best single match comes first. On a tie, the order is Places, Mixes, Scenes, Sounds, Yours.

**A real place with imagined weather** ("Tokyo in the rain at night"):
- The first result is **Tokyo, live**, with its true sub-line ("Live · Clear · 22°, it isn't raining there").
- Directly beneath it is **Imagine "Tokyo in the rain at night"**. This makes a Scene: the city setting with rain and night, titled "Tokyo, in the rain", with the asked-for sounds stored as its tweaks (`Mixer.swift:515-525`).
- That keeps rule 2: Tokyo stays live, and the imagined version is a Scene, honestly labeled "Imagined".

**The last row is always Imagine "q".** It runs `Vibe.read`, plays the Scene, and adds it to Recent, which also puts it in Scenes › Imagined lately. If Vibe fails, it reads "Try a place and some weather…" (`TeleportView.swift:234`).

**The empty, focused field shows:**
- recent phrases, with Clear (`Vibe.swift:161-168`)
- a few Try suggestions
- one **Surprise me** chip, which plays a random Scene or Place (`TeleportView.swift:240-300`)

**Preview hint.** A Scene result that's true somewhere real right now gets the line "It's like that in Bergen right now" (`TeleportView.swift:59-64`). Tapping it plays Bergen, live.

### Sound browser (Library › Sounds, and inside Tune)
- **Filter chips:**
  - **Playing**
  - **Belongs here** (the current place's or scene's own sounds, which SoundSections ordered first, `MixerView.swift:336-408`)
  - Water
  - Weather
  - Nature
  - Night
  - City & home
  - Calm
  - Tones
  - Noise
- **Display-only re-filing:** wind moves to Weather, the fountain to City & home, and fire to Calm (`Sound.swift:76-96`). `SoundKind` raw values are untouched.
- **A lit pill** is in the current soundscape.
- **Tap:**
  - Toggles the sound at level 0.5, with a soft haptic.
  - A notice says "Thunder joins Tokyo · Undo".
  - It records a tweak on the current thing (rule 3).
- **Long-press:** previews the sound alone while held, ducking the mix.

---

## 4. Tune

Tune is never top-level. It always means what's playing now.

**How it opens**
- **iPhone:** tap the pills or the form, swipe down, or use the a11y action. It is the existing sheet with medium and large detents, and the background stays interactive at medium (`MixerView.swift:22-24`, `:53-58`).
- **Mac:** a trailing inspector in Listen, opened with ⌘E or by clicking the pills. The Layers tab goes away, and `Mac/MacLayers.swift:5-33` becomes the inspector's body. The scene wash continues behind the inspector.
  - **Width:** opening the inspector widens the window by 300pt when the screen has room. If it doesn't, the form scales down to fit beside it. The inspector never overlays the form.

**Travel while Tune is open: Tune follows.**
- Swiping the form at medium detent still travels, and Tune's header and rows crossfade to the new item.
- If a level drag is in progress, travel is ignored until the drag ends.
- Edits always land on whatever is named in the header, so following is safe.

**Contents, top to bottom**
1. **Header:**
   - What's playing, with the Save bookmark.
   - **Reset**, shown only when the thing is tuned. It keeps its confirmation copy (`MixerView.swift:62-89`, `NowPlayingView.swift:768-808`).
2. **For a Place:** one read-only line, "Live · Light rain · 14°". There are no weather controls.
3. **For a Scene: Other skies for this cabin**, a row of chips such as Snow · Rain · Clear · Night · Day.
   - Each chip is a **different Scene** (`Atmosphere.id` is `setting.sky.time`, `Atmospheres.swift:320`), so choosing one *goes there* and plays it, with its own tweaks and its own Save state.
   - The chip row reads as navigation, not as a setting. The current chip is lit, and a choice gives a thud rather than a detent tick.
4. **Level rows**, unchanged:
   - Tap to glide, drag to set.
   - Drag into the far-left 4% to see "LET GO TO REMOVE", with a thud.
   - The pace chip cycles rhythmic sounds.
   - The context menu, plus a11y Remove and "More or less often" (`MixerView.swift:189-289`).
5. **"+ Add one that fits"** (`:305-331`) and **"All sounds…"**. On iPhone, All sounds expands the sheet to large and shows the sound browser inline.
6. **Save as new…** asks for a name, prefilled with "Tokyo, my way". The copy lands in Yours, with a thud (`LibraryView.swift:281-306`).

**Helper copy**
- "Drag a sound to set it, or to the far left to remove it."
- When tuned: "Your changes to Tokyo are kept. Reset to hear it as it was."

---

## 5. Onboarding ("Where would you like to go?")

**When it runs**
- On first launch only, while `onboarded` is false. Existing users are marked onboarded during migration (§8).
- It takes about 10 seconds, and **a tap skips to beat 5**.
- With **Reduce Motion**, it cross-fades straight to beat 5 with the form already whole.
- **There is no location prompt at launch.** §8 has the implementation.

**Beat by beat**
0. **Silence.** A black screen. Centered serif text fades in: *"Every place has a sound."* (about 1.5s)
1. **One light.** A soft point blooms where the form will be, and **rain** fades in over 1.2s. The pill "Rain" drops into the empty strip below. **soft** haptic.
2. **A second light.** A strand in wind colors curls in and joins the first. **Wind in the eaves** fades in, and its pill slides in. **soft** haptic.
3. **A third light.** A warm amber strand arrives with **a far harbor bell**, at a lower level, and its pill appears. **soft** haptic.
4. **It closes.**
   - The strands lock into the glass sculpture, and the halo blooms to the screen edges.
   - The title sets letter by letter: *"A harbor, at dusk."* **detent** haptic.
   - About 1s of the finished soundscape plays alone.
5. **The prompt.**
   - The title lifts and fades. *"Where would you like to go?"* appears with the Where to? field beneath it.
   - **Four chips**, staggered by 80 ms:
     - **Right here, as it is now.** This is the only path that asks for location: "To hear the weather where you are" (replacing `Info.plist:25`).
     - **Somewhere far.** A curated Place where it's night now and not clear.
     - **Somewhere to focus.** The top Focus mix by evidence.
     - **Somewhere imagined.** A random curated Scene.
   - Typing works exactly like Search, including Imagine.
6. **Arrival.**
   - A **thud**. The harbor strands dissolve and re-form into the choice, using the carousel's arrival animation.
   - You land on Listen, **playing**, with the wheel on the right stop (or off-wheel, for a Scene).
   - If location is denied after "Right here", you still land on Here, which shows "Location off" and plays a gentle default. No other chip needs location.
7. **Four hints**, one per session:
   1. Swipe to travel
   2. Swipe down to tune
   3. Hold play for a sleep timer
   4. Swipe up for everything

   They use a new `hintStep2` key. A hint whose gesture you've already used is skipped.

**After day one**, "Where would you like to go?" survives as the field's placeholder, "Where to?". The way in is Search: the title tap, ⌘K, the menu bar's "Search…".

**Cut**
- The Teleport sentence builder, "Take me / setting / sky / time" (`TeleportView.swift:129-191`). Its parts move:
  - settings → Library › Scenes
  - sky and time → Imagine and "Other skies"
  - example sentences → Try
- The name Teleport.

---

## 6. Mac

**Window** (`Mac/AtmosphericsMacApp.swift:29-38`, `Mac/MacWindow.swift`)
- **Two toolbar pills, Listen and Library**, with explicit ⌘1 and ⌘2. Today the shortcuts come from the array index (`AtmosphericsMacApp.swift:120-123`).
- **Library** is full-window, with the search field in the toolbar. ⌘K from Listen opens it on the playing item's shelf with the field focused, the same as on iPhone.
- **The back button** appears only in Library and returns to Listen. Its travel-back job (`MacWindow.swift:126-153`) moves to ⌘← and the hover arrow.
- **The Tune inspector:** see §4.

**Shortcuts**

| Key | Action |
|---|---|
| ⌘1 / ⌘2 | Listen / Library |
| ⌘K, or ⌘F in Library | Search |
| ⌘E | Show or hide Tune |
| ↑ / ↓ (focus on Listen) · ⌥⌘1–5 | Turn the wheel · go to stop *n* |
| ← → · ⌘← ⌘→ | Previous / next |
| Space | Play or pause |
| ⌘↑ / ⌘↓ | Louder / softer |
| ⇧⌘H | **Where You Are**: Places, at Here (`MacCommands.swift:66`) |
| ⇧⌘B | **Back to Tokyo**: the last place, shown while a mix or scene plays. This replaces `leavePreset` (`MacCommands.swift:67`). |
| ⌘D | Save |
| ⇧⌘S | Save as New… |

**Menus** (`Mac/MacCommands.swift`)
- **View:** Listen, Library, Show Tune.
- **Playback:**
  - Play/Pause
  - Louder, Softer
  - Next, Previous
  - **Go To ▸** (the five stops)
  - Where You Are
  - Back to *place*
  - Search…
  - Sleep Timer ▸ (off, 30m, 1h, 2h, 8h)
  - Save
  - Save as New…
  - Reset *Tokyo*…
- **Cut:** the two Weather/Time pickers and "Back to Live Weather" (`:82-99`, `:97`), because Places are live. A Scene's other skies are in the Tune inspector.
- **App menu and Settings:** unchanged (`:115-136`).

**Menu bar panel** (`Mac/MenuBarPanel.swift`)
- Halo, title and sub-line (`:64-70`).
- **A new row** with the stop name between ‹ and ›. It is dimmed when off-wheel.
- ← Play → and volume (`:73-89`).
- **Footer:** Timer · Search… · Open · Quit.
- `MenuBarIcon` is unchanged (`:166-247`).

**Unchanged:** the Dock menu (`AtmosphericsMacApp.swift:87-96`), media keys (`Mixer.swift:376-386`), trackpad swipes, weather refresh and Sparkle.

---

## 7. Feature mapping

| Inventory item | New home | Reason |
|---|---|---|
| NavigationStack shell, forced dark | Kept; onboarding is presented over it | — |
| Audio error alert, background audio, interruptions, unplug | Kept | — |
| Weather refresh every 30 min and on activate | Kept, but it no longer requests location before onboarding (§8) | No prompt at launch |
| Location prompt copy | "To hear the weather where you are", asked in context | — |
| Location off, Checking, Offline | On the Here sub-line and the Here card | — |
| No iOS Now Playing panel; Live Activity instead | Kept | — |
| ModeWheel, 6 words | 5 words, plus an off-wheel state | Owner direction |
| Wheel drag, flick, edge tap, detent, a11y, Reduce Motion | Kept | — |
| Wheel keeps play state; per-stop memory | Kept; Places memory added via `pinnedPlace` | Rule 1, consistency |
| Wheel follows external changes | Kept; goes quiet when what's playing isn't on a stop | — |
| Carousel swipe, tick, rubber-band | Kept | — |
| Outside ring | Places ring, ordered westward | Globe feel |
| Scenes deck, draw and back history | Deleted; Scenes swipe through their shelf | One meaning for Back |
| Mood rings | Kept, mixes only | Direction keeps Scenes in the Library |
| Tap form opens Layers | Opens Tune | — |
| Long-press and drag form | Kept, unhinted; a hold without movement counts as a tap | Taps no longer lost |
| Lightning flash | Kept | — |
| a11y Travel and Go back | Kept | — |
| Title tap opens Teleport | Opens Search; hint "Search the Library" | — |
| Title context menu | Cut | Each item has a direct home |
| Sub-line | One honest line per kind | — |
| ⋯ PageActions fan | Cut; mapped in §2 | — |
| LayerStrip pills | Open Tune, with a tuned dot | — |
| Timer label | Shown only when not the default | — |
| Reset pill | In the Tune header | — |
| VolumeLine | Kept | — |
| "Describe the vibe…" bar | Cut | Search |
| Play tap, long-press timer, haptics, a11y | Kept, plus a hint | Sole timer UI |
| Swipe up opens Library | Kept | — |
| Swipe down cycles weather with a toast | Opens Tune (excluding the top band); Place weather is live only | Rule 2 |
| Swipe ignored after a glass turn | Kept | — |
| 7 first-run hints | 4 hints plus onboarding | — |
| Notices | Kept; "Added to Favorites" → "Saved to Yours"; Undo for added sounds | — |
| Layers sheet, detents, interactive background | Tune | — |
| Layers header: Save and Reset | Tune header (Save, Reset) and footer (Save as new…) | — |
| LevelRow (glide, drag, remove, pace, menu, a11y) | Kept | — |
| "+ Add one that fits" | Kept | — |
| SoundSections, place's sounds first | Shared sound browser with a "Belongs here" filter | One component |
| Teleport sheet, header, ×, Esc | Cut | — |
| Teleport sentence and chips | Cut; parts mapped in §5 | Second grammar |
| Teleport preview line | Search result hint and Scene card wash | — |
| Teleport "Here" badge on IDEAS | "Like here now" badge on Scene cards | — |
| Vibe field, recent phrases, Try, Surprise me | Search field and its empty state | — |
| Teleport go button | Return, or tap a result | — |
| Teleport IDEAS | Library › Scenes | — |
| Teleport haptics | Kept on Search | — |
| Library chips (All, Recent, Favorites, Yours, tags) | Places · Mixes · Scenes · Sounds · Yours · Recent | — |
| Opens on playing shelf | Kept | — |
| Recent shelf, Clear | Kept | — |
| Focus "How we chose these ↗", FocusScienceView | Kept | — |
| Favorites shelf | Folded into Yours (flagged departure) | One saved list |
| Yours delete, rename, reorder | Kept | — |
| Card "Current" and "Playing" badges | **Now** badge, moving when playing, still when paused | — |
| Card tap loads and dismisses | Kept; it also plays | Rule 1 |
| Save prompt | "Save as new…" | — |
| FavoriteToggle | Save bookmark; "Save" / "Remove from Yours" | — |
| Widget, PlayPauseIntent, drift timeline | **Unchanged.** The widget's mix-name title is deliberate (`Mixer.swift:316-318`) | — |
| Live Activity, Dynamic Island | Unchanged | — |
| Mac 4 tabs with index shortcuts | Listen and Library, ⌘1/⌘2 | — |
| Mac back button with two jobs | Library only | — |
| Mac Teleport tab, seeded with the current scene (`MacWindow.swift:18`) | Cut; ⌘K | — |
| Mac Layers tab with scene wash | Tune inspector with wash | — |
| Mac LayersLink, ResetTuning | Pills; Reset in Tune | — |
| Mac globe and Surprise | Cut | Duplicates |
| Mac TimerMenu, PlayButton, ←/→ | Kept; ↑/↓ added with focus rules | — |
| Playback menu | Restructured (§6) | — |
| Weather/Time pickers, Back to Live Weather | Cut | Places are live |
| ⇧⌘H, two meanings | Where You Are only | — |
| `leavePreset` "Back to {origin}" | ⇧⌘B "Back to *place*"; on iPhone, turn to Places | — |
| Menu bar panel | Kept, plus the stop row and Search… | — |
| Dock menu, media keys, trackpad, Sparkle, Settings | Kept | — |
| "Warm Night" and "Escaping to…" (`Mixer.swift:227`, `:448-466`) | Cut; place names | Leaked internals |

---

## 8. Data model and migration

**Principle:** keep the persisted shape. Change meaning only where a rule needs it. Migration runs once in `Mixer.init`, guarded by `migratedIA = 1`.

### Model
- **`Lens`:**
  - Drop `.scenes`. Labels become Places, Focus, Relax, Sleep, Meditate. The raw value "Outside" stays.
  - Add an off-wheel state: `lens: Lens?`, where nil means off-wheel, plus `ring: RingSource` (`.lens(Lens)`, `.shelf(.scenes | .yours | .recent)`). Neither is persisted.
  - `lensFollows` sets `lens = nil` and `ring = .shelf(...)` for anything not on a stop, including saved mixes with `tag == nil` (`Mixer.swift:909-912`). Today that case leaves `firstIndex` at -1.
- **Places stop memory:** `choose(.outside)` restores `pinnedPlace` (nil = Here) instead of calling `goHome()`. `select(place)` already writes it (`:1161`). `pinnedPlace` stops meaning "Escape destination" and means "last place heard".
- **Scene mood, computed, not stored:** `Atmosphere.mood` is a computed property, a lookup by `id` in a curated table, with inference as the fallback (night, snow or rain → Sleep; a meditative setting → Meditate; else Relax). `Atmosphere` keeps its synthesized `Hashable` (`Atmospheres.swift:309`), so copies rebuilt by `init?(id:)` (`:323-328`) still `==` the curated ones. It is used only to group the Scenes shelf.
- **Places are live only:**
  - The `skyOverride` and `timeOverride` controls are removed from the UI, along with the rule that they "drop you out of a mix" (`Mixer.swift:108-109`).
  - Migration: set both keys to Live. If either wasn't Live, post one notice on next launch: "Places now always play their real weather. For imagined weather, try a Scene."
  - No per-place sky storage is added, so there is no name-collision risk to manage.
- **Mixes get their own slot.** `load(preset)` no longer writes `titles[mode]` and `fields[mode]` for real places (`Mixer.swift:900-915`), so a Focus mix played from Tokyo leaves Tokyo intact. No migration: the next `goHome` or `select` recomposes the field from the weather.
- **Edits stay with what you edited:**
  - **`tweakKey`:**
    - built-in mix → `"mix:<id>"` (today nil, `Mixer.swift:941-946`). Built-in preset ids are frozen from now on, and any future display rename uses a separate `title` field, so tweaks are never orphaned.
    - saved item → `"saved:<uuid>"` (`SavedMix.id` is a UUID, `Library.swift:159`, so renaming is safe)
    - scene → `atmosphere.tweakKey` (unchanged, `Atmospheres.swift:331`)
    - place → name, or `home` (unchanged)
  - **Saved items keep a baseline.** `SavedMix.orbs` stays as the as-saved baseline. Edits go to `placeTweaks["saved:<uuid>"]`, so Reset works for saved items too.
  - **`markCustom`** always records a tweak. The "Your mix" path (`:930-934`, `:432`, `:665`, `:675`) is deleted.
  - **"Your mix" migration:** for **each** of the three `title.<mode>` slots that reads "Your mix" (`Mixer.swift:226-228`), convert that mode's stored field into a SavedMix named "Your mix (kept)", numbered if there are several. Then reset the slot's title to its place name.
- **Yours:**
  - The `favorites` keys (`mix:`, `scene:`) stay as they are and are shown in Yours. Add `place:<name>`, using the same format as `Visit.key` (`Mixer.swift:781-784`). `Destination.favoriteKey` gains `.place`.
  - Here is never saved.
  - Yours' order is a new `yoursOrder: [String]` that mixes favorite keys and `saved:<uuid>`. On migration it is seeded with saved mixes first, then favorites.
- **Vibe:** `Vibe.read` first checks `allPlaces` names and aliases. On a match it returns the city setting, titled "<Place>, in the rain", for Imagine. The live place itself comes from the search index, not from Vibe. `recentVibes` becomes Search's recent phrases.
- **Sound display categories:** add a `displayCategory` mapping. `SoundKind` and `Category` stay as they are.
- **Location gating (no prompt at launch):**
  - `refreshWeather` (`Mixer.swift:1044`) calls `location.current()` only when authorization is already `.authorizedWhenInUse` or `.authorizedAlways`, or when the user has chosen Here (the "Right here" chip, a Library tap on Here, or ⇧⌘H).
  - Otherwise it skips the home fetch and still refreshes place weather.
  - `current()` keeps its `requestWhenInUseAuthorization` (`Weather.swift:220`) but is no longer called from launch or activate (`AtmosphericsApp.swift:12-22`) before then.
  - Existing users with authorization already granted see no change.
- **Place-name collisions:** these are pre-existing (`placeTweaks` and `favorites` key on the name). No custom places can be added in v1, so the 44 curated names stay unique. Stage 7 must dedupe on add.

### Keys

| Key | Fate |
|---|---|
| `volume`, `fields`, `title.*`, `following.*`, `mode`, `atmosphere`, `customPlaces`, `pinnedPlace`, `placeTweaks`, `paces`, `savedMixes`, `activePreset`, `favorites`, `recent`, `recentVibes`, `homeCast`, `lens.*`, `tempUnit`, `showInMenuBar` | Unchanged in shape. `pinnedPlace` changes meaning; "Your mix" titles are migrated. |
| `skyOverride`, `timeOverride` | Set to Live once, then no longer read |
| `hintStep`, `macHintStep` | Read once. If ≥ 1, set `onboarded = true`. If ≥ 7, set `hintStep2 = 4`. |
| New: `onboarded`, `hintStep2`, `yoursOrder`, `migratedIA` | — |

`onboarded` is also set for any existing user who has `mode`, `savedMixes` or `recent`.

### Widgets and intents
No change. `NowPlayingSnapshot` (`Shared/NowPlayingSnapshot.swift:11-15`), `PlayPauseIntent` and `SoundscapeActivity` stay as they are. A "Go To stop" App Intent is out of scope.

---

## 9. Staged build plan

Each stage ships on its own. Order: 1 → 2 → 3 → 4 → 5 → 6, with 7 optional.

| # | Stage | What ships | Files | Effort |
|---|---|---|---|---|
| 1 | **Rules and shell** | <ul><li>⋯ fan, title menu and Describe bar cut. The title tap still opens the Teleport sheet for now.</li><li>One iPhone timer UI, plus the timer hint.</li><li>**Save bookmark on the title for everything except Here.** The `place:` favorite key lands here, so keeping a place is never stranded.</li><li>Hold-without-move counts as a tap.</li><li>ModeWheel comment fixed. "Warm Night" and "Escaping to…" removed.</li><li>Mac: ⌘1/⌘2 explicit (Teleport tab kept for now); back button with one job; Surprise and globe cut; ↑/↓ with focus rules; ⇧⌘H = Where You Are; ⇧⌘B = Back to *place*.</li></ul> | `NowPlayingView.swift`, `ModeWheel.swift`, `Mixer.swift`, `Favorites.swift`, `Mac/AtmosphericsMacApp.swift`, `Mac/MacWindow.swift`, `Mac/MacListen.swift`, `Mac/MacCommands.swift` | 3 days |
| 2 | **Edits stay put** | <ul><li>`tweakKey` for mixes and saved items.</li><li>Saved baseline plus Reset.</li><li>`markCustom` stops forking. "Your mix" removed, with the all-slots migration.</li><li>A mix gets its own field slot.</li><li>"Tuned by you" sub-line.</li><li>`Mode` moves out of `Library.swift`.</li></ul> Comes before any surface that adds sounds. | `Mixer.swift`, `Library.swift`, `MixerView.swift`, `NowPlayingView.swift` | 3–4 days |
| 3 | **Tune** | <ul><li>Swipe down opens Tune, with the top band excluded.</li><li>Reset in the header.</li><li>Places live only: override UI removed, migration and notice.</li><li>Scene "Other skies" row.</li><li>Tune follows travel.</li><li>Shared sound browser ("Belongs here" filter, preview, Undo, paused preview) replaces SoundSections.</li><li>Mac: the Layers tab becomes the ⌘E inspector with the width rule; Weather/Time pickers cut.</li></ul> | `MixerView.swift`, `NowPlayingView.swift`, `Mixer.swift`, new `SoundBrowser.swift`, `Sound.swift`, `Mac/MacLayers.swift`, `Mac/MacWindow.swift`, `Mac/MacCommands.swift`, `Mac/MenuBarPanel.swift` | 5 days |
| 4 | **Library catalog** | <ul><li>Shelves Places, Mixes, Scenes, Sounds, Yours, Recent.</li><li>Favorites folded into Yours, with `yoursOrder`.</li><li>**Now** badge.</li><li>Computed `Atmosphere.mood`, plus the curated table for grouping.</li><li>Library taps play; `goHome(play:)` gains its parameter and its first caller (the Here card).</li></ul> The Scenes wheel stop still exists in this stage, which is harmless, since Scenes aren't on any mood ring. | `LibraryView.swift`, `Favorites.swift`, `Mixer.swift`, `Atmospheres.swift`, `Places.swift`, `ColorCard.swift` | 5–6 days |
| 5 | **Search; Scenes and Teleport leave** | <ul><li>Local index and ranking; sounds as pills; Imagine; place-plus-weather → live place and Imagine rows.</li><li>Title tap, ⌘K and a11y Search open the focused Library.</li><li>`Lens.scenes`, `deck`, `draw` and `backStack` removed.</li><li>Off-wheel state and shelf rings.</li><li>Places memory via `pinnedPlace`; Places ring ordered westward.</li><li>Teleport sheet and Mac tab deleted, in the same release as ⌘K search, so the Mac never has a gap.</li></ul> | `LibraryView.swift`, new `Search.swift`, `Vibe.swift`, `Mixer.swift` (Lens, ring, `refreshUpcoming`, `lensFollows`, `choose`), `ModeWheel.swift`, `TeleportView.swift` (deleted), `Mac/*` | 7–8 days |
| 6 | **Onboarding** | <ul><li>Assembling animation, the prompt and four chips.</li><li>**Location gating**, so there is no prompt at launch.</li><li>`onboarded` and hint migration; 4 hints.</li><li>Mac first launch shows the prompt in the window.</li></ul> | New `Onboarding.swift`, `ContentView.swift`, `Hints.swift`, `Sculpture.swift`, `AtmosphericsApp.swift`, `Weather.swift`, `Mixer.swift` (`refreshWeather`), `Info.plist`, `Mac/MacWindow.swift` | 5–6 days |
| 7 | *Optional:* **Find a place** | <ul><li>Geocode a typed place (a new MapKit search; `PlaceSearch` today only has `cast(near:)`, `PlaceSearch.swift:8`).</li><li>Build its cast and fetch its weather.</li><li>Append to `customPlaces`, deduped by coordinate. Nothing writes to it today (`Mixer.swift:237`).</li><li>A "Your places" group, and Remove.</li><li>A search row: **Find "q"**.</li></ul> | `PlaceSearch.swift`, `Mixer.swift`, `Search.swift`, `LibraryView.swift`, `Places.swift` | 4–5 days |

**Total:** about 28–32 days for stages 1–6.

**Gates**
- After Stage 3: TestFlight check that people who used swipe-down weather find "Other skies" and Imagine, and that nobody misses place weather overrides.
- After Stage 5: check that people swiping in a Scene understand the quiet wheel.

---

## 10. Open questions for the owner

**Decided 2026-10-14:** the owner took every recommended answer below (1–8).

1. **Places are live only, so Tokyo in the rain is a Scene. OK?** *Recommended: yes.* It is the plainest reading of "real places with live weather", and it removes the Sky-versus-Scene overlap. The cost is that existing users lose weather overrides on places, which the one-time notice explains.
2. **Scenes: Library only, or their own wheel stop?** *Recommended: Library only, as directed.* Swiping inside a Scene moves through the Scenes shelf, with the wheel quiet. If testing shows that people want to browse Scenes from Listen, add a sixth stop, "Scenes", rather than mixing them into the mood rings.
3. **Fold Favorites into Yours (one saved list)?** *Recommended: yes.* Two saved lists is the kind of overlap the owner wants gone. The alternative is keeping a separate Favorites shelf.
4. **"Where to?" as the Library's search placeholder?** *Recommended: yes.* The alternative is a separate prompt screen after onboarding, which would be a second search.
5. **When you tune a Mix, does it stay that Mix (with Reset) or fork into a copy?** *Recommended: stay*, with "tuned by you" replacing the evidence line. "Save as new…" is the explicit fork.
6. **Places swipe order: westward by time zone, or by region?** *Recommended: westward.*
7. **Meditate has 5 mixes. Merge it into Relax?** *Recommended: keep it for now, and commission 3 to 5 more Meditate mixes.* Scenes no longer pad it.
8. **Ship Stage 7 (Find a place) in this cycle?** *Recommended: no.* The 44 curated places plus Imagine cover v1.

---

## Critique points rejected or only partly taken

- **"Imagine is a fifth verb."** Kept. It names something no other verb covers, making a new Scene from words, and it suits the literary tone. Teleport, Keep and Favorite were removed instead, so the verb count still falls.
- **"Mac ↑/↓ collides with ⌘↑/⌘↓ volume; use ⌥↑/↓."** Partly taken. Focus rules settle the clash with the inspector. ↑/↓ stays unmodified, because it is the most discoverable mapping, and ⌘ volume is a different chord.
- **"Merging Favorites into Yours is unasked-for."** Kept, but flagged as a departure and put to the owner as open question 3. The Kept/Made sub-taxonomy is dropped.
- **"Where to? as Library search is a reinterpretation."** Kept, but flagged and put as open question 4. The feature's noun is now Search, so "Where to?" no longer has three jobs.
- All other points were accepted. Some were settled by changing the model rather than patching around it. Live-only Places remove the per-place-sky collision risk, the scene-sky id problem, "Back to Live Weather" and the Sky/Time naming overlap. Taking Scenes off the rings removes stored-mood equality issues, ring mutation and the stage 3/4 ordering conflict.
