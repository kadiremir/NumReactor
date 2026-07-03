import CoreGraphics
import Foundation

/// Pure Swift game logic for Number Reactor. Holds no SpriteKit or SwiftUI
/// dependencies so it can be exercised directly from unit tests.
final class GameEngine {

    struct ReactionResult: Equatable {
        let scoreGain: Int
        let newScore: Int
        let combo: Int
        let maxCombo: Int
        let usedStoneIDs: [UUID]
        let resolvedTarget: Int
        let selectedCount: Int
        let speedBonus: Bool
        let chainBonus: Bool
        let heatRiskBonus: Bool
        let newTarget: Int
    }

    // MARK: Tunables

    private let heatReliefOnCorrect: Double = 12
    private let speedBonusWindow: TimeInterval = 2.5
    private let speedBonusRate: Double = 0.25
    private let chainBonusMinStones: Int = 4
    private let chainBonusRate: Double = 0.3
    private let heatRiskThreshold: Double = 75
    private let heatRiskBonusRate: Double = 0.35
    private let trivialTargetAttemptsPhase1: Double = 0.2

    // MARK: State

    private(set) var stones: [Stone] = []
    private(set) var target: Int = 0
    private(set) var score: Int = 0
    private(set) var combo: Int = 1
    private(set) var maxCombo: Int = 1
    private(set) var heat: Double = 0
    private(set) var reactionCount: Int = 0
    private(set) var difficulty: DifficultyConfig = .forReactionCount(0)
    private(set) var isGameOver: Bool = false

    private var ringCapacity: Int = 0
    private var globalRotation: CGFloat = 0
    private var timeSinceTargetSet: TimeInterval = 0
    private var timeSincePressureCheck: TimeInterval = 0

    /// Injectable random sources so tests can drive deterministic outcomes.
    var rollInt: (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
    var rollDouble: () -> Double = { Double.random(in: 0...1) }

    var selectedSum: Int {
        stones.filter(\.isSelected).reduce(0) { $0 + $1.value }
    }

    // MARK: Lifecycle

    func startNewGame() {
        score = 0
        combo = 1
        maxCombo = 1
        heat = 0
        reactionCount = 0
        isGameOver = false
        globalRotation = 0
        timeSinceTargetSet = 0
        timeSincePressureCheck = 0
        difficulty = .forReactionCount(0)
        ringCapacity = difficulty.activeStoneCount
        stones = generateInitialStones()
        regenerateTarget()
    }

    /// Advances rotation and heat by `deltaTime` seconds. Call once per frame.
    func tick(deltaTime: TimeInterval) {
        guard !isGameOver else { return }

        globalRotation += difficulty.rotationSpeed * CGFloat(deltaTime)
        for i in stones.indices {
            stones[i].angle = slotBaseAngle(stones[i].ringIndex) + globalRotation
        }

        heat = min(100, heat + difficulty.heatGainPerSecond * deltaTime)
        timeSinceTargetSet += deltaTime
        timeSincePressureCheck += deltaTime

        if timeSincePressureCheck >= difficulty.pressureTimeout {
            combo = 1
            timeSincePressureCheck = 0
        }

        if heat >= 100 {
            heat = 100
            isGameOver = true
        }
    }

    /// Toggles selection on the stone with the given id. Returns a
    /// `ReactionResult` if the toggle produced a correct reaction.
    @discardableResult
    func selectStone(id: UUID) -> ReactionResult? {
        guard !isGameOver else { return nil }
        guard let idx = stones.firstIndex(where: { $0.id == id }) else { return nil }

        stones[idx].isSelected.toggle()

        if let result = resolveIfCorrect() {
            return result
        }

        applyOvershootPenaltyIfNeeded()
        return nil
    }

    func clearSelection() {
        for i in stones.indices {
            stones[i].isSelected = false
        }
    }

    // MARK: Reaction resolution

    @discardableResult
    private func resolveIfCorrect() -> ReactionResult? {
        guard !stones.isEmpty, selectedSum == target else { return nil }

        let usedStoneIDs = stones.filter(\.isSelected).map(\.id)
        let selectedCount = usedStoneIDs.count
        let heatAtSolve = heat
        let elapsed = timeSinceTargetSet
        let resolvedTarget = target

        combo += 1
        maxCombo = max(maxCombo, combo)

        let speedBonus = elapsed <= speedBonusWindow
        let chainBonus = selectedCount >= chainBonusMinStones
        let heatRiskBonus = heatAtSolve >= heatRiskThreshold

        let base = abs(resolvedTarget) * selectedCount * combo
        var bonus = 0
        if speedBonus { bonus += Int((Double(base) * speedBonusRate).rounded()) }
        if chainBonus { bonus += Int((Double(base) * chainBonusRate).rounded()) }
        if heatRiskBonus { bonus += Int((Double(base) * heatRiskBonusRate).rounded()) }
        let scoreGain = base + bonus

        score += scoreGain
        heat = max(0, heat - heatReliefOnCorrect)
        reactionCount += 1

        applyDifficulty()
        refillStones()
        regenerateTarget()

        return ReactionResult(
            scoreGain: scoreGain,
            newScore: score,
            combo: combo,
            maxCombo: maxCombo,
            usedStoneIDs: usedStoneIDs,
            resolvedTarget: resolvedTarget,
            selectedCount: selectedCount,
            speedBonus: speedBonus,
            chainBonus: chainBonus,
            heatRiskBonus: heatRiskBonus,
            newTarget: target
        )
    }

    private func applyOvershootPenaltyIfNeeded() {
        let sum = selectedSum
        guard sum != target else { return }
        let hasNegativeUnselected = stones.contains { !$0.isSelected && $0.value < 0 }
        if sum > target && !hasNegativeUnselected {
            combo = 1
        }
    }

    // MARK: Difficulty

    private func applyDifficulty() {
        difficulty = .forReactionCount(reactionCount)
    }

    // MARK: Stone generation

    private func slotBaseAngle(_ ringIndex: Int) -> CGFloat {
        guard ringCapacity > 0 else { return 0 }
        return (CGFloat(ringIndex) / CGFloat(ringCapacity)) * 2 * .pi
    }

    private func randomStoneValue() -> Int {
        if difficulty.allowNegatives && rollDouble() < difficulty.negativeChance {
            return rollInt(difficulty.minValue...(-1))
        }
        return rollInt(1...difficulty.maxValue)
    }

    private func makeStone(ringIndex: Int) -> Stone {
        Stone(
            value: randomStoneValue(),
            angle: slotBaseAngle(ringIndex) + globalRotation,
            ringIndex: ringIndex
        )
    }

    private func generateInitialStones() -> [Stone] {
        (0..<ringCapacity).map { makeStone(ringIndex: $0) }
    }

    private func refillStones() {
        let freedSlots = stones.filter(\.isSelected).map(\.ringIndex)
        stones.removeAll(where: \.isSelected)

        let newCapacity = difficulty.activeStoneCount
        var availableSlots = freedSlots
        if newCapacity > ringCapacity {
            availableSlots.append(contentsOf: ringCapacity..<newCapacity)
        }
        ringCapacity = newCapacity

        let deficit = max(0, newCapacity - stones.count)
        for slot in availableSlots.prefix(deficit) {
            stones.append(makeStone(ringIndex: slot))
        }
    }

    // MARK: Target generation

    private func regenerateTarget() {
        for _ in 0..<5 {
            if let picked = tryPickTarget() {
                target = picked.sum
                applyDecoys(avoiding: Set(picked.indices))
                timeSinceTargetSet = 0
                timeSincePressureCheck = 0
                return
            }
            stones = generateInitialStones()
        }

        // Guaranteed fallback: force a trivially-constructed, always-solvable target.
        let count = min(2, stones.count)
        target = stones.prefix(count).reduce(0) { $0 + $1.value }
        timeSinceTargetSet = 0
        timeSincePressureCheck = 0
    }

    private func tryPickTarget() -> (sum: Int, indices: [Int])? {
        guard !stones.isEmpty else { return nil }
        let lower = max(1, difficulty.solutionLengthRange.lowerBound)
        let upper = min(stones.count, difficulty.solutionLengthRange.upperBound)
        guard lower <= upper else { return nil }

        for _ in 0..<40 {
            let length = rollInt(lower...upper)
            let indices = shuffledIndices(count: length)
            let sum = indices.reduce(0) { $0 + stones[$1].value }

            if sum == 0 { continue }

            let singleStoneValues = Set(stones.map(\.value))
            if singleStoneValues.contains(sum) {
                let allowTrivial = reactionCount < 3 && rollDouble() < trivialTargetAttemptsPhase1
                if !allowTrivial { continue }
            }

            return (sum, indices)
        }
        return nil
    }

    private func shuffledIndices(count: Int) -> [Int] {
        var indices = Array(stones.indices)
        var result: [Int] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            guard !indices.isEmpty else { break }
            let pick = rollInt(0...(indices.count - 1))
            result.append(indices.remove(at: pick))
        }
        return result
    }

    private func applyDecoys(avoiding solutionIndices: Set<Int>) {
        guard rollDouble() < difficulty.decoyStrength else { return }
        let others = stones.indices.filter { !solutionIndices.contains($0) }
        guard others.count >= 2 else { return }

        let shuffledOthers = others.shuffled(using: rollInt)
        let decoyIndex = shuffledOthers[0]
        let anchorIndex = shuffledOthers[1]

        let jitter = rollInt(-2...2)
        let needed = target - stones[anchorIndex].value + jitter
        let clamped = min(max(needed, difficulty.minValue), difficulty.maxValue)
        guard clamped != 0 else { return }

        stones[decoyIndex].value = clamped
        stones[decoyIndex].kind = .decoy
    }

    // MARK: Test / diagnostic helpers

    /// Brute-force existence check used by tests to confirm the current
    /// target has at least one valid subset solution among active stones.
    func hasSolution() -> Bool {
        GameEngine.subsetSumExists(target: target, values: stones.map(\.value))
    }

    static func subsetSumExists(target: Int, values: [Int]) -> Bool {
        guard !values.isEmpty else { return target == 0 }
        var sums: Set<Int> = [0]
        for value in values {
            sums.formUnion(sums.map { $0 + value })
        }
        return sums.contains(target)
    }
}

private extension Array {
    func shuffled(using rollInt: (ClosedRange<Int>) -> Int) -> [Element] {
        var copy = self
        guard copy.count > 1 else { return copy }
        for i in stride(from: copy.count - 1, to: 0, by: -1) {
            let j = rollInt(0...i)
            copy.swapAt(i, j)
        }
        return copy
    }
}
