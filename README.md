# Atmospherics

Generated soundscapes for focus and sleep that follow the weather outside.

<img src="design/icon/icon-1024.png" width="128" alt="Atmospherics icon">

Sounds are lights on a field. Drag one toward the center to hear more of it, push it to the rim to fade it out.

- **Match outside** builds a mix from your local weather: rain follows precipitation, wind follows gusts, brown noise deepens as pressure drops.
- **Escape outside** plays somewhere else, picking the place whose weather is most unlike yours.
- **Library** has hand-made mixes for sleep, focus and relaxing.

Every sound is synthesized live (no audio files): brown, pink, white and green noise, plus rain, ocean, wind, thunder, fire and birds.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open Atmospherics.xcodeproj
```

Weather comes from [Open-Meteo](https://open-meteo.com) (free, no API key).

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
