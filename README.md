# Traffic Jam Rush (iOS)

Native iOS port of the Android game in `/Volumes/Work/Raj/Android/Cartrafficjam`.
This folder is a complete, independent Xcode project. It shares nothing with the other games.

| | |
|---|---|
| Bundle ID | `com.puzzel.lab.cartrafficjam` |
| Platform | iPhone, iOS 17+ |
| Status | **Port in progress.** Currently a placeholder screen. |

## Run it
1. Open `TrafficJamRush.xcodeproj` in Xcode.
2. Pick an iPhone simulator (or your iPhone) and press **Run**.
3. For the App Store: in *Signing & Capabilities*, choose your Team once.

## What's inside
- `TrafficJamRush/`: app code, art, sounds (`Resources/Audio`, 48 kHz), fonts, icon.
- `TrafficJamRushTests/`: unit tests, including "same level as Android" checks.
- `Packages/GameKit/`: this game's own copy of the engine code (sound, haptics, saving, game loop, exact Android random numbers).
- `Reference/Android/`: screenshots of the Android version, used to compare the look.

## Port plan
- **Game.** Colour-sort parking jam. Cars, vans and buses (lengths 3/4/5, seats 4/6/10); 8 lot shapes.
  - Parking: 4 open slots, 3 locked slots and a VIP slot.
  - Rules: passenger boarding queue, mystery vehicles from level 25, Hard every 5th and Super Hard every 10th level.
  - 5,000 levels in 50 collections across 10 themes.
  - Boosters: Shuffle, Crane, Sort. 11 skins, daily streak.
- **Port.**
  - Engine: split `GameEngine` from Compose state (it uses `mutableStateOf`, `Path` and `PathMeasure`) into pure Swift, with path-measure helpers.
  - Board: rotated (0° or 15–35°) with inverse-transform hit testing.
  - Art: about 90 cached vehicle sprites, the "Coney" mascot, and 10 procedural city backdrops plus their ambient animation.
- **Must match.**
  - Generator: `kotlin.random.Random(n·7919 + 104729·attempt + 17)`, the 12-entry level cache, and the bounded queue scramble.
  - Star rule: the code version (3 stars with no boosters or revives, 2 with up to 2, else 1), not the plan's.
- **Screens.** Splash → Onboarding (4 pages, "Let's Go") → 5 tabs with a raised centre: Levels map (5,000 nodes) | Collections | Home | Garage | Settings.
  - Game overlays: Pause, Boosters, Revive, Fail, Win, Unlock Slot; the "No free spot" toast; the level-1 tutorial hand.
- **Simulator pass.** Level 1 tutorial, a blocked tap that lurches and springs back, a full-lot shake, revive → fail → skip, a mystery-vehicle level, a skin purchase, the daily chest.

## Upgrades over Android
- **Fixes:** No mid-level save
- **New features:** Daily Puzzle (seeded by date) with a streak calendar. Undo booster (counts as a booster for stars). Mid-level autosave. Colourblind patterns on cars and passengers.
