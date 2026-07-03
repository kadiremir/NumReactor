import Combine
import Foundation

/// Thin observable wrapper around `GameEngine`. Owns high score persistence
/// and republishes engine state for SwiftUI and SpriteKit to consume.
@MainActor
final class GameState: ObservableObject {
    @Published private(set) var score: Int = 0
    @Published private(set) var bestScore: Int = 0
    @Published private(set) var combo: Int = 1
    @Published private(set) var maxCombo: Int = 1
    @Published private(set) var heat: Double = 0
    @Published private(set) var target: Int = 0
    @Published private(set) var stones: [Stone] = []
    @Published private(set) var selectedSum: Int = 0
    @Published private(set) var reactionCount: Int = 0
    @Published private(set) var isGameOver: Bool = false
    @Published private(set) var isNewBest: Bool = false
    @Published var lastReaction: GameEngine.ReactionResult?

    private let engine = GameEngine()
    private let bestScoreDefaultsKey = "NumReactor.bestScore"

    init() {
        bestScore = UserDefaults.standard.integer(forKey: bestScoreDefaultsKey)
    }

    func startNewGame() {
        lastReaction = nil
        isNewBest = false
        engine.startNewGame()
        sync()
    }

    func tick(deltaTime: TimeInterval) {
        guard !isGameOver else { return }
        engine.tick(deltaTime: deltaTime)
        sync()
        if engine.isGameOver {
            persistBestScoreIfNeeded()
        }
    }

    func selectStone(id: UUID) {
        guard !isGameOver else { return }
        lastReaction = engine.selectStone(id: id)
        sync()
    }

    func clearSelection() {
        engine.clearSelection()
        sync()
    }

    private func sync() {
        if score != engine.score { score = engine.score }
        if combo != engine.combo { combo = engine.combo }
        if maxCombo != engine.maxCombo { maxCombo = engine.maxCombo }
        if heat != engine.heat { heat = engine.heat }
        if target != engine.target { target = engine.target }
        if stones != engine.stones { stones = engine.stones }
        if selectedSum != engine.selectedSum { selectedSum = engine.selectedSum }
        if reactionCount != engine.reactionCount { reactionCount = engine.reactionCount }
        if isGameOver != engine.isGameOver { isGameOver = engine.isGameOver }
    }

    private func persistBestScoreIfNeeded() {
        guard score > bestScore else { return }
        bestScore = score
        isNewBest = true
        UserDefaults.standard.set(bestScore, forKey: bestScoreDefaultsKey)
    }
}
