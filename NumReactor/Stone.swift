import CoreGraphics
import Foundation

enum StoneKind: Equatable {
    case normal
    case decoy
}

struct Stone: Identifiable, Equatable {
    let id: UUID
    var value: Int
    var angle: CGFloat
    var ringIndex: Int
    var isSelected: Bool
    var kind: StoneKind

    init(
        id: UUID = UUID(),
        value: Int,
        angle: CGFloat,
        ringIndex: Int,
        isSelected: Bool = false,
        kind: StoneKind = .normal
    ) {
        self.id = id
        self.value = value
        self.angle = angle
        self.ringIndex = ringIndex
        self.isSelected = isSelected
        self.kind = kind
    }
}
