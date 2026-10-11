# Atmospherics icon

The Now Playing halo, drawn exactly as the app draws it, scaled to fill the icon.

- `icon-1024.png` — iOS app icon (also in `Atmospherics/Assets.xcassets/AppIcon.appiconset`)
- `Atmospherics.icns` — macOS icon, with the rounded shape and shadow built in

Regenerate:

```bash
swift render.swift icon-1024.png
swift mac.swift icon-1024.png mac-1024.png
```

Then rebuild the `.iconset` with `sips` and run `iconutil -c icns`.
