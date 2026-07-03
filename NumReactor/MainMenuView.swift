import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject private var gameState: GameState
    @Binding var screen: AppScreen
    @State private var titlePulsing = false

    var body: some View {
        ZStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Text("NUMBER")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                    Text("REACTOR")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                }
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .cyan.opacity(titlePulsing ? 0.75 : 0.5), radius: 24)
                .tracking(2)
                .scaleEffect(titlePulsing ? 1.03 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        titlePulsing = true
                    }
                }

                Text("BEST \(gameState.bestScore)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(5)

                Spacer()

                Button {
                    gameState.startNewGame()
                    screen = .game
                } label: {
                    Text("START")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReactorButtonStyle(prominent: true))
                .padding(.horizontal, 48)

                Text("Tap orbiting stones to match the reactor's target")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 48)
            }
        }
    }
}

struct ReactorButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .tracking(2)
            .foregroundStyle(prominent ? Color.black : Color.cyan)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(Color.white.opacity(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.cyan.opacity(prominent ? 0 : 0.6), lineWidth: 1.5)
            )
            .shadow(color: .cyan.opacity(prominent ? 0.45 : 0), radius: 14)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
