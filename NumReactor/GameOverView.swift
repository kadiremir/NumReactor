import SwiftUI

/// End-of-run overlays from the design handoff — SPEC §9 phase 3 (meltdown)
/// and §11.2 (win). A full-screen radial scrim rendered over the still-settling
/// reactor scene with a centered text column. No buttons, no card — the whole
/// screen is the tap target (handled by the presenting view).
struct ContainmentOverlay: View {
    enum Variant {
        case meltdown
        case stabilized
    }

    let variant: Variant
    let score: Int

    private static let ember = Color(red: 255 / 255, green: 122 / 255, blue: 68 / 255)     // #FF7A44
    private static let emberScore = Color(red: 255 / 255, green: 154 / 255, blue: 90 / 255) // #FF9A5A
    private static let accent = Color(red: 62 / 255, green: 166 / 255, blue: 255 / 255)     // #3EA6FF

    /// Comma thousands separators, as in the reference ("1,240") — not locale-dependent.
    private var formattedScore: String {
        score.formatted(IntegerFormatStyle<Int>().locale(Locale(identifier: "en_US")))
    }

    var body: some View {
        ZStack {
            scrim
            switch variant {
            case .meltdown: meltdownColumn
            case .stabilized: stabilizedColumn
            }
        }
        .ignoresSafeArea()
    }

    /// CSS `radial-gradient(circle at 50% 46%, …)` — center → farthest corner.
    private var scrim: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.46)
            let endRadius = hypot(
                max(center.x, size.width - center.x),
                max(center.y, size.height - center.y)
            )
            RadialGradient(
                colors: variant == .meltdown
                    ? [
                        Color(red: 102 / 255, green: 20 / 255, blue: 6 / 255).opacity(0.62),
                        Color(red: 9 / 255, green: 4 / 255, blue: 4 / 255).opacity(0.9),
                    ]
                    : [
                        Color(red: 8 / 255, green: 40 / 255, blue: 70 / 255).opacity(0.55),
                        Color(red: 3 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.88),
                    ],
                center: UnitPoint(x: 0.5, y: 0.46),
                startRadius: 0,
                endRadius: endRadius
            )
        }
    }

    private var meltdownColumn: some View {
        VStack(spacing: 5) {
            Text("CONTAINMENT LOST")
                .font(.custom("ChakraPetch-SemiBold", size: 13))
                .tracking(5)
                .foregroundStyle(Self.ember)
            Text("MELTDOWN")
                .font(.custom("ChakraPetch-Bold", size: 46))
                .tracking(1)
                .foregroundStyle(.white)
            Text("FINAL SCORE")
                .font(.custom("ChakraPetch-SemiBold", size: 11))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 18)
            Text(formattedScore)
                .font(.custom("ChakraPetch-Bold", size: 42))
                .foregroundStyle(Self.emberScore)
            Text("TAP TO RETRY")
                .font(.custom("ChakraPetch-SemiBold", size: 12))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 22)
        }
    }

    private var stabilizedColumn: some View {
        VStack(spacing: 5) {
            Text("CONTAINMENT HELD")
                .font(.custom("ChakraPetch-SemiBold", size: 13))
                .tracking(5)
                .foregroundStyle(Self.accent)
            // Two lines at CSS line-height 1.05 (≈40 pt boxes for 38 pt type).
            VStack(spacing: -8) {
                Text("REACTOR")
                Text("STABILIZED")
            }
            .font(.custom("ChakraPetch-Bold", size: 38))
            .tracking(1)
            .foregroundStyle(.white)
            Text("SCORE")
                .font(.custom("ChakraPetch-SemiBold", size: 11))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 16)
            Text(formattedScore)
                .font(.custom("ChakraPetch-Bold", size: 42))
                .foregroundStyle(Self.accent)
            Text("TAP TO PLAY AGAIN")
                .font(.custom("ChakraPetch-SemiBold", size: 12))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 22)
        }
    }
}
