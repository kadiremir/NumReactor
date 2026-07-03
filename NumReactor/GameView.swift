import SwiftUI
import SpriteKit

struct GameView: View {
    @ObservedObject var gameState: GameState
    var onExitToMenu: () -> Void

    @State private var scene = ReactorGameScene()
    @State private var isPaused = false
    @State private var meltdownOverlayVisible = false
    @State private var retryArmed = false

    private var heatFraction: Double { min(max(gameState.heat / 100, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Sibling order IS the draw order here (glow under pool under
                // housing, bevels over hex faces) — do not pass .ignoresSiblingOrder.
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .id(ObjectIdentifier(scene))
                    .ignoresSafeArea()
                    .onAppear { configureScene(size: proxy.size) }
                    .onChange(of: proxy.size) { _, newSize in
                        scene.size = newSize
                    }

                VStack(spacing: 0) {
                    topRow
                    forgeHeatBar
                    Spacer()
                    resultCapsule
                        .padding(.bottom, 30)
                    pauseButton
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)

                if isPaused {
                    pauseOverlay
                }

                // Meltdown overlay (SPEC §9 phase 3): scrim + text over the
                // still-settling embers, 1.15 s after the timer dies. Any tap
                // restarts once armed (meltT > 1.3 s in the reference).
                if meltdownOverlayVisible {
                    ContainmentOverlay(variant: .meltdown, score: gameState.score)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard retryArmed else { return }
                            restartGame(size: proxy.size)
                        }
                }
            }
        }
        .statusBarHidden()
    }

    private func configureScene(size: CGSize) {
        scene.size = size
        scene.scaleMode = .resizeFill
        scene.gameState = gameState
        scene.onExplosionComplete = {
            meltdownOverlayVisible = true
            retryArmed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { retryArmed = true }
        }
    }

    private func restartGame(size: CGSize) {
        gameState.startNewGame()
        meltdownOverlayVisible = false
        retryArmed = false
        isPaused = false
        // Fresh scene — clears explosion state, debris, and re-runs spawn-in.
        scene = ReactorGameScene()
        configureScene(size: size)
    }

    // MARK: Top row — SCORE / COMBO

    private var topRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SCORE")
                    .font(.custom("ChakraPetch-SemiBold", size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(3)
                Text("\(gameState.score)")
                    .font(.custom("ChakraPetch-Bold", size: 32))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: gameState.score)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("COMBO")
                    .font(.custom("ChakraPetch-SemiBold", size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(3)
                Text("x\(gameState.combo)")
                    .font(.custom("ChakraPetch-Bold", size: 32))
                    .foregroundStyle(Color(red: 126 / 255, green: 196 / 255, blue: 1))
                    .contentTransition(.numericText())
                    .scaleEffect(comboPop ? 1.5 : 1)
                    .animation(.interpolatingSpring(stiffness: 260, damping: 14), value: comboPop)
                    .onChange(of: gameState.combo) { _, _ in
                        comboPop = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { comboPop = false }
                    }
            }
        }
        .padding(.top, 6)
    }

    @State private var comboPop = false

    // MARK: Exit button — centered, glass pill

    private var pauseButton: some View {
        Button {
            isPaused = true
            scene.isPaused = true
        } label: {
            ExitSignGlyph()
        }
    }

    // MARK: Forge heat bar

    private var forgeHeatBar: some View {
        VStack(spacing: 7) {
            HStack {
                Text("◆ FORGE HEAT")
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(dangerStatusText)
                    .tracking(2.5)
                    .foregroundStyle(dangerStatusColor)
            }
            .font(.custom("ChakraPetch-SemiBold", size: 10))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
                    Capsule()
                        .fill(Color(barColor))
                        .frame(width: proxy.size.width * (1 - heatFraction))
                        .shadow(color: Color(barColor).opacity(0.8), radius: 5)
                        .animation(.easeOut(duration: 0.2), value: heatFraction)
                }
            }
            .frame(height: 9)
        }
        .padding(.top, 20)
    }

    private var barColor: SKColor { ForgeTheme.coreColor(danger: CGFloat(heatFraction)) }

    private var dangerStatusText: String {
        if heatFraction > 0.75 { return "CRITICAL" }
        if heatFraction > 0.5 { return "WARNING" }
        return "STABLE"
    }

    private var dangerStatusColor: Color {
        if heatFraction > 0.75 { return Color(red: 1, green: 90 / 255, blue: 74 / 255) }
        if heatFraction > 0.5 { return Color(red: 1, green: 176 / 255, blue: 40 / 255) }
        return .white.opacity(0.4)
    }

    // MARK: Result capsule — [ result / target ]

    private var resultCapsule: some View {
        let isOver = gameState.selectedSum > gameState.target
        return HStack(spacing: 6.5) {
            Text("[")
                .foregroundStyle(Color(red: 62 / 255, green: 166 / 255, blue: 1).opacity(0.5))
                .font(.custom("ChakraPetch-SemiBold", size: 11))
            Text("\(gameState.selectedSum)")
                .foregroundStyle(isOver ? Color(red: 1, green: 62 / 255, blue: 52 / 255) : .white)
            Text("/")
                .foregroundStyle(.white.opacity(0.4))
                .font(.custom("ChakraPetch-SemiBold", size: 12))
            Text("\(gameState.target)")
                .foregroundStyle(Color(red: 62 / 255, green: 166 / 255, blue: 1))
            Text("]")
                .foregroundStyle(Color(red: 62 / 255, green: 166 / 255, blue: 1).opacity(0.5))
                .font(.custom("ChakraPetch-SemiBold", size: 11))
        }
        .font(.custom("ChakraPetch-Bold", size: 19))
        .padding(.horizontal, 11)
        .padding(.vertical, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 62 / 255, green: 166 / 255, blue: 1).opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color(red: 62 / 255, green: 166 / 255, blue: 1).opacity(0.3), lineWidth: 0.5)
        )
    }


    // MARK: Exit confirm overlay

    private var pauseOverlay: some View {
        ZStack {
            // Fully opaque scrim — the reactor and stones must not be visible
            // (or tappable) behind this overlay, or the player could keep
            // playing/reading the board while "paused".
            Color(red: 4 / 255, green: 8 / 255, blue: 14 / 255)
                .opacity(0.98)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Text("ESCAPE REACTOR?")
                    .font(.custom("ChakraPetch-Bold", size: 24))
                    .foregroundStyle(.white)
                    .tracking(3)

                Button {
                    onExitToMenu()
                } label: {
                    Text("YES")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReactorButtonStyle(prominent: true))
                .padding(.horizontal, 60)

                Button {
                    isPaused = false
                    scene.isPaused = false
                } label: {
                    Text("NO")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReactorButtonStyle(prominent: false))
                .padding(.horizontal, 60)
            }
        }
    }
}

// MARK: - Exit button chrome

/// A little illuminated "EXIT" sign — dark plate, amber wordmark and frame,
/// mirroring the emergency-exit signage this reads as, re-skinned in the
/// reactor's titanium/amber palette instead of literal red/white/green.
private struct ExitSignGlyph: View {
    var body: some View {
        Image("ExitIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 42, height: 42)
    }
}
