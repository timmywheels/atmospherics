# Atmospherics

Generated soundscapes for focus and sleep that follow the weather outside.

<img src="design/icon/icon-1024.png" width="128" alt="Atmospherics icon">

Sounds are lights on a field. Drag one toward the center to hear more of it, push it to the rim to fade it out.

- **Match outside** builds a mix from your local weather: rain follows precipitation, wind follows gusts, brown noise deepens as pressure drops.
- **Escape outside** plays somewhere else, picking the place whose weather is most unlike yours.
- **Library** has hand-made mixes for sleep, focus and relaxing.

44 sounds: 23 synthesized live (seven noise colors, rain, ocean, wind, thunder, lightning, fire, birds, crickets, cicadas, frogs, stream, city hum, train, fan, chimes, drone) and 21 public-domain field recordings (howler monkeys, owls, loons, whales, a café, church bells and more; see `design/sounds/SOURCES.md`). 42 places around the world, each with live weather.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open Atmospherics.xcodeproj
```

Weather comes from [Open-Meteo](https://open-meteo.com) (free, no API key).

## Releasing

Bump `CURRENT_PROJECT_VERSION` in `project.yml` for every upload (App Store Connect rejects a repeated build number), then:

```bash
xcodegen generate
xcodebuild -project Atmospherics.xcodeproj -scheme Atmospherics -configuration Release -destination 'generic/platform=iOS' -archivePath build/Atmospherics.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Atmospherics.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

App Store screenshots: `design/screenshots/make-upload.sh`.

## Layout

- `Atmospherics/` app source
  - `NoiseEngine.swift` real-time synthesis and mixing
  - `Mixer.swift` app state, weather following, playback
  - `Weather.swift` Open-Meteo client and weather-to-mix rules
  - `NowPlayingView.swift`, `MixerView.swift`, `LibraryView.swift` the three screens
- `design/icon/` icon source and render scripts
- `archive/pentagon/` an earlier UI direction, kept for reference

## License

MIT. See [LICENSE](LICENSE).
