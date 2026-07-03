import XCTest
@testable import NumReactor

final class GameEngineTests: XCTestCase {

    func testGeneratedTargetAlwaysHasSolution() {
        let engine = GameEngine()
        engine.startNewGame()
        for _ in 0..<200 {
            XCTAssertTrue(
                engine.hasSolution(),
                "target \(engine.target) has no subset solution among \(engine.stones.map(\.value))"
            )
            solveCurrentTarget(engine)
        }
    }

    func testSelectingCorrectSubsetTriggersSuccess() {
        let engine = GameEngine()
        engine.startNewGame()
        let result = solveCurrentTarget(engine)
        XCTAssertNotNil(result)
    }

    func testScoreIncreasesAfterSuccess() {
        let engine = GameEngine()
        engine.startNewGame()
        let before = engine.score
        solveCurrentTarget(engine)
        XCTAssertGreaterThan(engine.score, before)
    }

    func testComboIncreasesAfterSuccess() {
        let engine = GameEngine()
        engine.startNewGame()
        XCTAssertEqual(engine.combo, 1)
        solveCurrentTarget(engine)
        XCTAssertEqual(engine.combo, 2)
    }

    func testHeatReachesGameOver() {
        let engine = GameEngine()
        engine.startNewGame()
        var iterations = 0
        while !engine.isGameOver && iterations < 2000 {
            engine.tick(deltaTime: 1.0)
            iterations += 1
        }
        XCTAssertTrue(engine.isGameOver)
        XCTAssertEqual(engine.heat, 100)
    }

    func testDifficultyChangesAfterReactionThresholds() {
        let engine = GameEngine()
        engine.startNewGame()
        XCTAssertEqual(engine.difficulty.phase, 1)

        for _ in 0..<9 {
            solveCurrentTarget(engine)
        }
        XCTAssertEqual(engine.difficulty.phase, 2)

        for _ in 0..<12 {
            solveCurrentTarget(engine)
        }
        XCTAssertEqual(engine.difficulty.phase, 3)
    }

    func testNegativeNumbersOnlyAppearAfterAllowedPhase() {
        let engine = GameEngine()
        engine.startNewGame()

        for _ in 0..<20 {
            XCTAssertEqual(engine.difficulty.phase <= 2, true)
            XCTAssertFalse(
                engine.stones.contains { $0.value < 0 },
                "no negative stones expected before phase 3"
            )
            solveCurrentTarget(engine)
        }
    }

    // MARK: Helpers

    @discardableResult
    private func solveCurrentTarget(_ engine: GameEngine) -> GameEngine.ReactionResult? {
        guard let solution = Self.findSolution(target: engine.target, stones: engine.stones) else {
            XCTFail("no solution found for target \(engine.target) among \(engine.stones.map(\.value))")
            return nil
        }
        var result: GameEngine.ReactionResult?
        for id in solution {
            result = engine.selectStone(id: id) ?? result
        }
        return result
    }

    private static func findSolution(target: Int, stones: [Stone]) -> [UUID]? {
        let n = stones.count
        guard n <= 20, n > 0 else { return nil }
        for mask in 1..<(1 << n) {
            var sum = 0
            for i in 0..<n where mask & (1 << i) != 0 {
                sum += stones[i].value
            }
            if sum == target {
                var ids: [UUID] = []
                for i in 0..<n where mask & (1 << i) != 0 {
                    ids.append(stones[i].id)
                }
                return ids
            }
        }
        return nil
    }
}
