import CoreGraphics
import Foundation

struct DifficultyConfig: Equatable {
    var phase: Int
    var activeStoneCount: Int
    var minValue: Int
    var maxValue: Int
    var allowNegatives: Bool
    var negativeChance: Double
    var solutionLengthRange: ClosedRange<Int>
    var rotationSpeed: CGFloat
    var heatGainPerSecond: Double
    var decoyStrength: Double
    var pressureTimeout: TimeInterval

    static func forReactionCount(_ count: Int) -> DifficultyConfig {
        switch count {
        case 0..<9:
            return DifficultyConfig(
                phase: 1,
                activeStoneCount: 6,
                minValue: 1, maxValue: 9,
                allowNegatives: false,
                negativeChance: 0,
                solutionLengthRange: 2...2,
                rotationSpeed: 0.09,
                heatGainPerSecond: 1.6,
                decoyStrength: 0.2,
                pressureTimeout: 9
            )
        case 9..<21:
            return DifficultyConfig(
                phase: 2,
                activeStoneCount: 7,
                minValue: 1, maxValue: 12,
                allowNegatives: false,
                negativeChance: 0,
                solutionLengthRange: 2...3,
                rotationSpeed: 0.13,
                heatGainPerSecond: 2.1,
                decoyStrength: 0.35,
                pressureTimeout: 7.5
            )
        case 21..<41:
            return DifficultyConfig(
                phase: 3,
                activeStoneCount: 8,
                minValue: -5, maxValue: 15,
                allowNegatives: true,
                negativeChance: 0.25,
                solutionLengthRange: 3...3,
                rotationSpeed: 0.18,
                heatGainPerSecond: 2.7,
                decoyStrength: 0.5,
                pressureTimeout: 6
            )
        default:
            let stoneCount = count.isMultiple(of: 2) ? 10 : 9
            return DifficultyConfig(
                phase: 4,
                activeStoneCount: stoneCount,
                minValue: -9, maxValue: 20,
                allowNegatives: true,
                negativeChance: 0.45,
                solutionLengthRange: 3...4,
                rotationSpeed: 0.24,
                heatGainPerSecond: 3.4,
                decoyStrength: 0.7,
                pressureTimeout: 5
            )
        }
    }
}
