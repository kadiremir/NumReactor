import SwiftUI
import UIKit
import QuartzCore

/// Animated "Hex Chamber" backdrop: vertical base gradient, drifting bokeh
/// orbs, a distance-lit hex grid with a roaming Lissajous light, a
/// danger-tinted core aura, and a vignette. Ported 1:1 from `bgHex()` in
/// `reactor-engine.js` per HEX_CHAMBER_BACKGROUND.md.
///
/// Rendered entirely with GPU-composited Core Animation layers rather than
/// per-frame Core Graphics drawing — profiling showed the original
/// `draw(rect:)` implementation (CPU-rasterized gradients + a ~140-cell hex
/// stroke, every frame) was the dominant CPU cost of the whole app. Only the
/// hex grid's two bitmaps are ever rasterized via Core Graphics, and only
/// once per view size (see `rebuildHexBitmapsIfNeeded`); everything else is
/// a plain layer property (`position`/`colors`) poked once per frame.
final class HexChamberBackgroundView: UIView {

    // Inputs you drive from the game
    var danger: CGFloat = 0          // 0…1, tints the aura toward amber/red

    // Theme (forge)
    private let bg0     = RGB(11, 15, 22)
    private let bg1     = RGB(3, 5, 8)
    private let accent  = RGB(62, 166, 255)
    private let warm    = RGB(150, 210, 255)
    private let amber   = RGB(255, 176, 40)
    private let red     = RGB(255, 62, 52)
    private let hexBase = RGB(150, 160, 178)

    private struct RGB {
        let r, g, b: CGFloat
        init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }
        func color(_ a: CGFloat) -> CGColor {
            CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
        }
        static func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB {
            RGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
        }
    }

    private struct Orb { var x, y, r, sp, ph: CGFloat; var warm: Bool }
    private var orbs: [Orb] = []
    private var t: CGFloat = 0
    private var displayLink: CADisplayLink?
    private var lastTS: CFTimeInterval = 0

    // MARK: GPU layers (z-order matches the original draw order 1...5)

    private let baseLayer = CAGradientLayer()
    private var orbLayers: [CAGradientLayer] = []
    private let hexGreyLayer = CALayer()
    private let hexAccentLayer = CALayer()
    private let hexLightMask = CAGradientLayer()
    private let auraLayer = CAGradientLayer()
    private let vignetteLayer = CAGradientLayer()

    private var cachedHexSize: CGSize = .zero
    private var auraColorCache: [Int: [CGColor]] = [:]
    private var lastAuraBucket = -1

    // Roaming-light falloff for the hex-accent mask. Collapses the original's
    // two independently-varying curves (alpha ∝ lit², color-mix ∝ lit) into a
    // single blended exponent (lit^1.3) — justified because the absolute alpha
    // range is tiny (0.028–0.188) and both source curves are smooth/monotonic
    // over the same 0...1 domain, so the difference is sub-perceptual.
    private static let lightMaskLocations: [NSNumber] = [0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]
    private static let lightMaskAlphas: [CGFloat] = [1.0, 0.872, 0.688, 0.515, 0.354, 0.209, 0.085, 0.0]
    private static let lightMaskColors: [CGColor] = lightMaskAlphas.map {
        CGColor(gray: 1, alpha: $0)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        orbs = (0..<4).map { i in
            Orb(x: .random(in: 0...1), y: .random(in: 0...1),
                r: .random(in: 90...240),
                sp: .random(in: 0.008...0.020),
                ph: .random(in: 0...(2 * .pi)),
                warm: i % 2 == 1)
        }
        setupLayers()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        baseLayer.type = .axial
        baseLayer.colors = [bg0.color(1), bg1.color(1)]
        baseLayer.locations = [0, 1]
        baseLayer.startPoint = CGPoint(x: 0.5, y: 0)
        baseLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(baseLayer)

        orbLayers = orbs.map { o in
            let l = CAGradientLayer()
            l.type = .radial
            let col = o.warm ? warm : accent
            l.colors = [col.color(0.05), col.color(0.02), col.color(0)]
            l.locations = [0, 0.7, 1]
            l.startPoint = CGPoint(x: 0.5, y: 0.5)
            l.endPoint = CGPoint(x: 1, y: 1)
            let side = o.r * CGFloat(2).squareRoot()
            l.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            layer.addSublayer(l)
            return l
        }

        hexGreyLayer.contentsGravity = .resize
        layer.addSublayer(hexGreyLayer)

        hexAccentLayer.contentsGravity = .resize
        hexAccentLayer.mask = hexLightMask
        layer.addSublayer(hexAccentLayer)

        hexLightMask.type = .radial
        hexLightMask.startPoint = CGPoint(x: 0.5, y: 0.5)
        hexLightMask.endPoint = CGPoint(x: 1, y: 1)
        hexLightMask.colors = Self.lightMaskColors
        hexLightMask.locations = Self.lightMaskLocations

        auraLayer.type = .radial
        auraLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        auraLayer.endPoint = CGPoint(x: 1, y: 1)
        auraLayer.locations = [0, 1]
        layer.addSublayer(auraLayer)

        vignetteLayer.type = .radial
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1, y: 1)
        vignetteLayer.colors = [
            CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.46),
        ]
        layer.addSublayer(vignetteLayer)

        updateAuraColor(force: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let W = bounds.width, H = bounds.height
        guard W > 0, H > 0 else { return }
        let cx = W / 2, cy = H * 0.5
        let orbitR = min(W, H) * 0.30
        let lr = min(W, H) * 0.55
        // CAGradientLayer's .radial with startPoint/endPoint on a shared axis (e.g.
        // endPoint = (1, 0.5)) renders degenerately (flat fill, no falloff) — using a
        // corner endPoint (1,1) is the well-behaved recipe, but it reaches location=1.0
        // at the corner (distance = side/2 * sqrt2 from center), so bounds must be sized
        // side = radius * sqrt(2) for the *edge midpoint* (our intended radius) to land
        // exactly at location 1.0, same as the original edge-based (side = radius*2) intent.
        let sqrt2 = CGFloat(2).squareRoot()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        baseLayer.frame = bounds

        let auraRadius = orbitR * 1.6
        let auraSide = auraRadius * sqrt2
        auraLayer.bounds = CGRect(x: 0, y: 0, width: auraSide, height: auraSide)
        auraLayer.position = CGPoint(x: cx, y: cy)

        let vignetteRadius = max(W, H) * 0.78
        let vignetteSide = vignetteRadius * sqrt2
        vignetteLayer.bounds = CGRect(x: 0, y: 0, width: vignetteSide, height: vignetteSide)
        vignetteLayer.position = CGPoint(x: cx, y: cy)
        let innerLocation = (min(W, H) * 0.45) / vignetteRadius
        vignetteLayer.locations = [0, NSNumber(value: Double(innerLocation)), 1]

        let lrSide = lr * sqrt2
        hexLightMask.bounds = CGRect(x: 0, y: 0, width: lrSide, height: lrSide)

        rebuildHexBitmapsIfNeeded()

        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate(); displayLink = nil
        guard window != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTS == 0 ? 0 : CGFloat(min(0.05, link.timestamp - lastTS))
        lastTS = link.timestamp
        t += dt

        let W = bounds.width, H = bounds.height
        guard W > 0, H > 0 else { return }
        let cx = W / 2, cy = H * 0.5

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (i, o) in orbs.enumerated() {
            let x = (o.x + sin(t * o.sp * 3 + o.ph) * 0.06) * W
            let y = (o.y - t * o.sp).truncatingRemainder(dividingBy: 1)
            let yy = ((y + 1).truncatingRemainder(dividingBy: 1)) * H
            orbLayers[i].position = CGPoint(x: x, y: yy)
        }

        let lx = cx + cos(t * 0.21) * W * 0.4
        let ly = cy + sin(t * 0.13) * H * 0.36
        hexLightMask.position = CGPoint(x: lx, y: ly)

        updateAuraColor(force: false)

        CATransaction.commit()
    }

    // accent → amber → red as danger climbs (stays accent for first ~40%)
    private func coreCol(_ danger: CGFloat) -> RGB {
        let h = max(0, min(1, (danger - 0.4) / 0.6))
        if h <= 0 { return accent }
        if h < 0.5 { return .mix(accent, amber, h / 0.5) }
        return .mix(amber, red, (h - 0.5) / 0.5)
    }

    // Quantizes `danger` into 40 buckets (mirrors ForgeTheme.BucketedTextureCache's
    // philosophy) so the aura's CGColor stops are only recomputed when the bucket
    // actually changes, not every frame.
    private func updateAuraColor(force: Bool) {
        let clamped = max(0, min(1, danger))
        let bucket = Int((clamped * 40).rounded())
        guard force || bucket != lastAuraBucket else { return }
        lastAuraBucket = bucket
        if let cached = auraColorCache[bucket] {
            auraLayer.colors = cached
        } else {
            let bucketDanger = CGFloat(bucket) / 40
            let c = coreCol(bucketDanger)
            let colors = [c.color(0.10 + bucketDanger * 0.06), c.color(0)]
            auraColorCache[bucket] = colors
            auraLayer.colors = colors
        }
    }

    // MARK: Hex grid bitmap baking (resize-triggered only, never per-frame)

    private func rebuildHexBitmapsIfNeeded() {
        guard bounds.size != .zero, bounds.size != cachedHexSize else { return }
        cachedHexSize = bounds.size
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2

        let greyColor = hexBase.color(0.028)
        // Baked as the delta above the floor (0.16, not 0.028+0.16) since this
        // layer composites *over* hexGreyLayer — see plan notes on alpha-stacking.
        let accentColor = RGB.mix(hexBase, accent, 0.75).color(0.16)

        if let img = renderHexGridBitmap(size: bounds.size, scale: scale, strokeColor: greyColor) {
            hexGreyLayer.contents = img
            hexGreyLayer.contentsScale = scale
        }
        if let img = renderHexGridBitmap(size: bounds.size, scale: scale, strokeColor: accentColor) {
            hexAccentLayer.contents = img
            hexAccentLayer.contentsScale = scale
        }
        hexGreyLayer.frame = bounds
        hexAccentLayer.frame = bounds
    }

    private func renderHexGridBitmap(size: CGSize, scale: CGFloat, strokeColor: CGColor) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            ctx.setLineWidth(1)
            ctx.setStrokeColor(strokeColor)
            let W = size.width, H = size.height
            let hs = max(30, W * 0.105)          // hex circumradius
            let lw = hs * 1.732, lh = hs * 1.5   // grid pitch
            var row = -1
            while CGFloat(row) * lh < H + lh {
                var col = -1
                while CGFloat(col) * lw < W + lw {
                    let hx = CGFloat(col) * lw + (row % 2 != 0 ? lw / 2 : 0)
                    let hy = CGFloat(row) * lh
                    let path = CGMutablePath()
                    for k in 0..<6 {
                        let a = CGFloat(k) / 6 * 2 * .pi + .pi / 6   // flat-top
                        let p = CGPoint(x: hx + cos(a) * hs * 0.94,
                                        y: hy + sin(a) * hs * 0.94)
                        k == 0 ? path.move(to: p) : path.addLine(to: p)
                    }
                    path.closeSubpath()
                    ctx.addPath(path)
                    ctx.strokePath()
                    col += 1
                }
                row += 1
            }
        }
        return image.cgImage
    }
}

/// SwiftUI wrapper — forwards `danger` into the `UIView` on every update.
struct HexChamberBackground: UIViewRepresentable {
    var danger: CGFloat

    func makeUIView(context: Context) -> HexChamberBackgroundView {
        HexChamberBackgroundView()
    }

    func updateUIView(_ uiView: HexChamberBackgroundView, context: Context) {
        uiView.danger = danger
    }
}
