# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Number Reactor is a native iOS arcade game: a glowing "reactor" shows a target number, numbered "stones" orbit it, and the player taps stones whose sum matches the target to trigger a reaction (score, combo, heat relief) before the reactor's heat maxes out. SwiftUI + SpriteKit, no external dependencies, no network, portrait-only, iPhone-only.

## Commands

Build and test both require a simulator destination (there's no macOS/generic target). List available simulators with `xcrun simctl list devices available`.

```bash
# Build for simulator
xcodebuild -project "NumReactor.xcodeproj" -scheme "NumReactor" -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run the full test suite
xcodebuild -project "NumReactor.xcodeproj" -scheme "NumReactor" -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run a single test (target name has a space, not the underscore used in the Swift module name)
xcodebuild -project "NumReactor.xcodeproj" -scheme "NumReactor" -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:"NumReactorTests/GameEngineTests/testScoreIncreasesAfterSuccess" test
```

To see it running: build, `xcrun simctl install <device> <path-to-.app>` (found under the build's `DerivedData/.../Build/Products/Debug-iphonesimulator/NumReactor.app`), then `xcrun simctl launch <device> Kadir.NumReactor`.

There is no separate lint step or linter config in this repo.

## Project structure quirk: no manual Xcode project editing needed for new source files

The app target uses Xcode's file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`, Xcode 16+). Any `.swift` file dropped into `NumReactor/` is automatically part of the `NumReactor` build target — there is no need to touch `project.pbxproj` to add a source file.

The `NumReactorTests` target and its scheme, however, were **not** created through Xcode's UI — they were added by scripting `project.pbxproj` directly with the `xcodeproj` Ruby gem (installed as part of the system's CocoaPods install), since no CLI existed to do this via `xcodebuild`. If the test target ever needs structural changes (new build settings, a second test target, etc.), the same approach works:

```bash
GEM_HOME="/opt/homebrew/Cellar/cocoapods/<version>/libexec" ruby -e "require 'xcodeproj'; ..."
```

Adding a new test *file* to the existing `NumReactorTests` target still requires this kind of scripted edit (or opening the project in Xcode once) since the tests folder is a plain `PBXGroup`, not a synchronized one.

## Architecture

The game is deliberately split so gameplay logic has zero dependency on any rendering framework:

- **`GameEngine.swift`** — pure Swift, no `import SpriteKit`/`SwiftUI`. Owns all rules: stone generation, target generation (always constructed *from* a real subset of current stones so it's guaranteed solvable, then perturbed with decoy near-misses — see `regenerateTarget`/`applyDecoys`), selection/scoring, combo, heat, and the 4-tier difficulty curve (`DifficultyConfig.forReactionCount`). This is what `NumReactorTests/GameEngineTests.swift` exercises directly. Random number generation is injected (`rollInt`/`rollDouble` closures) specifically so tests can be deterministic.
- **`Stone.swift` / `DifficultyConfig.swift`** — plain value types used by `GameEngine`.
- **`GameState.swift`** — the only bridge between `GameEngine` and the UI. An `ObservableObject` that owns a `GameEngine` instance, republishes its state as `@Published` properties every tick, and persists best score via `UserDefaults`. SwiftUI views and the SpriteKit scene both read from this, never from `GameEngine` directly.
- **`ReactorGameScene.swift`** — SpriteKit `SKScene`, purely presentational. Reads `GameState` every frame in `update(_:)`, renders the reactor/orbiting stones/selection beams/heat-driven visuals, hit-tests taps and forwards them back into `GameState.selectStone`/`clearSelection`. Also owns the reactor-explosion sequence played on game over (staged: implosion beat → `detonate()` → shard/ember/smoke debris, with the core dying to a dark ember stub per the handoff spec), which calls `onExplosionComplete` at the 1.15 s mark — the SwiftUI layer waits for that callback rather than reacting the instant `isGameOver` flips true, so the explosion has time to play.
- **`NumReactorApp.swift`** — app entry point; owns the single `GameState` instance (`@StateObject`) and a small `RootView` that switches between `MainMenuView` / `GameView` based on a local `AppScreen` enum (not persisted — always starts at `.menu`). Game over is *not* a separate screen: `GameView` stays up and shows the meltdown overlay in place.
- **`GameView.swift`** — hosts `SpriteView(scene:)` plus the SwiftUI HUD (score/combo/heat bar/selected-sum) as an overlay in a `ZStack`. The `ReactorGameScene` instance is created once via `@State` and configured (`gameState`, `onExplosionComplete`) in `onAppear`. When the explosion completes it shows `ContainmentOverlay` over the still-settling scene; any tap (armed 0.15 s after the overlay appears, mirroring the reference's 1.3 s gate) restarts by resetting `GameState` and swapping in a fresh scene. The pause overlay carries the only route back to the main menu.
- **`MainMenuView.swift`** — plain SwiftUI; defines `ReactorBackground` and `ReactorButtonStyle`.
- **`GameOverView.swift`** — defines `ContainmentOverlay`, the buttonless end-of-run overlay from the design handoff (radial scrim + centered Chakra Petch text column). Has a `.meltdown` variant (in use) and a `.stabilized` win variant (built to spec §11.2; unused until the game grows a win condition).

Data flow is one-directional per frame: `ReactorGameScene.update(_:)` → `gameState.tick(deltaTime:)` → `GameEngine` mutates → `GameState` republishes → both SwiftUI HUD and the next SpriteKit frame read the new values. Taps go the other way: SpriteKit hit-test → `GameState.selectStone(id:)` → `GameEngine` → republished state.

Nothing else in the game depends on SwiftUI's environment/navigation beyond the single `AppScreen` switch — there's no persisted navigation or deep linking.
