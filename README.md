# Atmospherics

Atmospheres for focus and sleep: the scenes you'd ask for by name, alive with real weather.

<img src="design/icon/icon-1024.png" width="128" alt="Atmospherics icon">

- **Atmospheres** are scenes by name: "a log cabin in a snowstorm", "a rainy night in the city". Swipe through them, or **Teleport**: build one as a sentence ("Take me to a tent in a thunderstorm at night") or say it in your own words. When it's really like that somewhere right now, the scene follows that place's live weather ("Snowing in Lofoten right now"). (`Atmospherics/Atmospheres.swift`)
- **Outside** builds a mix from your own weather: rain follows precipitation, wind follows gusts, and what's around you (a coast, a lake, a city) is heard in season and at its hour.
- **Library** has mixes for sleep, relaxing and focus, the focus ones built on what research supports (`design/focus/RESEARCH.md`).
- **The sculpture**: what's playing is a soft 3D form of light, one body per sound, bigger and higher the louder it is. It turns and drifts on the home screen; in **Layers** each sound is a row filled in its color as far across as it's loud, to tap or drag across to set its level. It's drawn by a Metal shader compiled at run time (`Atmospherics/Sculpture.swift`, `SculptureShader.swift`).

Noise colors, focus tones, drone, chimes, fan and lightning are synthesized live; everything that should sound real (rain, surf, wind, thunder, fire, birds, insects, frogs, streams, trains, city streets, cafés, howler monkeys, loons, whales and more) is a public-domain or CC0 field recording, credited in `design/sounds/SOURCES.md`. Live weather comes from 44 real places and your own location.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open Atmospherics.xcodeproj
```

Two apps share one codebase: the `Atmospherics` scheme is the iPhone app, `AtmosphericsMac` the Mac app (macOS 14+). The Mac app is one window (Listen, Teleport, Layers, Library) plus a control in the menu bar, and keeps playing when the window is closed. A two-finger swipe or ← → travels, Space plays and pauses, and the media keys work once something has played.

Weather comes from [Open-Meteo](https://open-meteo.com) (free, no API key).

## Releasing

Bump `CURRENT_PROJECT_VERSION` in `project.yml` for every upload (App Store Connect rejects a repeated build number), then:

```bash
xcodegen generate
xcodebuild -project Atmospherics.xcodeproj -scheme Atmospherics -configuration Release -destination 'generic/platform=iOS' -archivePath build/Atmospherics.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Atmospherics.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

App Store screenshots: `design/screenshots/make-upload.sh` frames the iPhone captures in `raw/` (6.9", from the simulator with a 9:41 status bar) and exports the 6.9", 6.5" and 6.3" sets. The Mac set is `design/screenshots/mac/`: capture the window at 2x into `raw/`, then `swift compose.swift` there for 2880x1800 frames. Debug builds take `-screenshotLocation 45.52,-122.68,Portland` so the corner shows a stand-in town rather than yours (Mac: `open … --args -screenshotLocation …`; simulator: `xcrun simctl launch booted com.timwheeler.atmospherics -screenshotLocation …`). App Store copy is in `design/appstore/`.

The Mac app has its own build number (`CURRENT_PROJECT_VERSION` under `AtmosphericsMac`) and uploads to the same App Store Connect app, once macOS has been added there as a platform:

```bash
xcodebuild -project Atmospherics.xcodeproj -scheme AtmosphericsMac -configuration Release -destination 'generic/platform=macOS' -archivePath build/AtmosphericsMac.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/AtmosphericsMac.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/export-mac -allowProvisioningUpdates
```

## Layout

- `Atmospherics/` app source
  - `NoiseEngine.swift` real-time synthesis and mixing
  - `Mixer.swift` app state, weather following, playback
  - `Weather.swift` Open-Meteo client and weather-to-mix rules
  - `Atmospheres.swift` settings, weather and times of day, their names, and live matching to real places
  - `Ecology.swift` what's out at a place right now: season, hour, weather
  - `NowPlayingView.swift`, `TeleportView.swift`, `MixerView.swift` (Layers), `LibraryView.swift` the screens
- `Mac/` the Mac app: its window, menu bar panel, menus and trackpad swipes, built on the shared views above
- `design/icon/` icon source and render scripts
- `archive/pentagon/` an earlier UI direction, kept for reference

## License

MIT. See [LICENSE](LICENSE).

Titles and names are set in [Instrument Serif](https://github.com/Instrument/instrument-serif) (© 2022 The Instrument Serif Project Authors), under the SIL Open Font License 1.1, which the font file carries with it.
