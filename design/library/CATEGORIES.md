# Categorizing the Library

Notes from a paid focus-music app's Explore screen (a competitor, screenshots shared 2026-10-13; not kept here since this repo is public), and how a similar structure could fit our Library.

## How they do it

- **Search** across everything: "by name, genre, instrumentation or mood".
- **Activity** as the top-level filter: Focus, Relax, Sleep, Meditate. Everything below changes with it.
- **Genres**, each with a small line icon, filterable All / Music / Nature: Atmospheric, Beach, Chimes & Bowls, Electronic, Forest, Nightsounds, Rain, Rainforest, River, Thunder, Underwater, Wind.
- **Moods** as plain chips, a long list per activity: Brooding, Calm, Chill, Dark, Downtempo, Dreamlike, Driving, Energizing, Epic, Floating, Heavy, Hopeful, Inspiring, Meditative, Mysterious, Ominous, Optimistic, Playful, Ponderous, Serene, Strong, Upbeat, Uplifting.

## What we have now

- Library mixes carry one tag: Focus, Sleep or Relax (`Preset.tag`), plus Yours and Favorites.
- Sounds sit in categories (`SoundKind.Category`): Noise, Water & weather, Nature, Jungle, Night & forest, Places & home, Calm, Focus tones.
- Atmospheres are a setting (log cabin, city, café, beach, tent, forest, jungle, lake, harbor, sleeper train, library, temple garden, mountains, tin roof, summer porch, market, long flight) in a sky (clear, wind, fog, drizzle, rain, downpour, thunderstorm, snow, snowstorm) at a time of day.

## Ideas for ours

1. **Activity first, as they do.** Our tags already are activities; adding Meditate (or Calm) would match the four people expect. A mix can belong to more than one.
2. **Genres = places and elements, with icons.** Ours map almost one to one: Beach, Forest, Night (their Nightsounds), Rain, Jungle (Rainforest), Stream (River), Thunder, Ocean and whales (Underwater), Wind, Chimes & bells (Chimes & Bowls), Drone (Atmospheric), plus ones they lack: City, Café, Trains and flights, Fire, Snow.
3. **Fewer, truer moods.** Their moods are music words (Upbeat, Driving, Epic). For soundscapes a short set says more: Calm, Cozy, Serene, Dreamy, Wild, Stormy, Mysterious, Bright. Each atmosphere could earn its moods from its sky and time (a thunderstorm at night is Stormy and Mysterious; a clear dawn is Bright and Serene), so they'd never need tagging by hand.
4. **Search** by name, place, sound and mood, on the Library and in Teleport.
