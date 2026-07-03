import SwiftUI

@main
struct NumReactorApp: App {
    @StateObject private var gameState = GameState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gameState)
                .preferredColorScheme(.dark)
        }
    }
}

enum AppScreen: Equatable {
    case menu
    case game
}

private struct RootView: View {
    @EnvironmentObject private var gameState: GameState
    @State private var screen: AppScreen = .menu

    private var heatFraction: Double {
        screen == .game ? min(max(gameState.heat / 100, 0), 1) : 0
    }

    var body: some View {
        ZStack {
            // Single persistent instance so the hex chamber's animation state
            // (drift, roaming light) survives menu <-> game transitions
            // instead of restarting/jumping on every screen switch.
            HexChamberBackground(danger: heatFraction)
                .ignoresSafeArea()

            switch screen {
            case .menu:
                MainMenuView(screen: $screen)
            case .game:
                // Game over is handled inside GameView (meltdown overlay over the
                // still-live scene, tap to retry) — no separate screen.
                GameView(gameState: gameState) {
                    screen = .menu
                }
            }
        }
    }
}
