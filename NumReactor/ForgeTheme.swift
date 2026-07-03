import SpriteKit
import UIKit

/// Colors, geometry fractions and gradient-texture helpers for the "Molten
/// Forge" visual reskin. Constants are ported 1:1 from the design handoff's
/// `reactor-engine.js` (`THEMES.forge`, `coreCol`, and the `forge` branches of
/// the various `draw*` functions) — this file has no gameplay logic.
enum ForgeTheme {

    // MARK: Palette (design_handoff_forge_reactor/README.md "Design Tokens")

    static let accent = SKColor(red: 62 / 255, green: 166 / 255, blue: 255 / 255, alpha: 1)      // #3EA6FF
    static let lightAccent = SKColor(red: 126 / 255, green: 196 / 255, blue: 255 / 255, alpha: 1) // #7EC4FF
    static let highlight = SKColor(red: 150 / 255, green: 210 / 255, blue: 255 / 255, alpha: 1)   // rgb(150,210,255)
    static let amber = SKColor(red: 255 / 255, green: 176 / 255, blue: 40 / 255, alpha: 1)        // #FFB020
    static let dangerRed = SKColor(red: 255 / 255, green: 62 / 255, blue: 52 / 255, alpha: 1)     // #FF3E34
    static let criticalText = SKColor(red: 255 / 255, green: 90 / 255, blue: 74 / 255, alpha: 1)  // #FF5A4A
    static let meltdownAccentText = SKColor(red: 255 / 255, green: 122 / 255, blue: 68 / 255, alpha: 1) // #FF7A44
    static let meltdownScoreText = SKColor(red: 255 / 255, green: 154 / 255, blue: 90 / 255, alpha: 1)  // #FF9A5A

    static let bg0 = SKColor(red: 11 / 255, green: 15 / 255, blue: 22 / 255, alpha: 1)
    static let bg1 = SKColor(red: 3 / 255, green: 5 / 255, blue: 8 / 255, alpha: 1)

    static let titaniumLight = SKColor(red: 0x9A / 255, green: 0x91 / 255, blue: 0x84 / 255, alpha: 1)
    static let titaniumMid = SKColor(red: 0x59 / 255, green: 0x52 / 255, blue: 0x4A / 255, alpha: 1)
    static let titaniumDark = SKColor(red: 0x2E / 255, green: 0x2A / 255, blue: 0x24 / 255, alpha: 1)

    static let housingStop0 = SKColor(red: 0x8D / 255, green: 0x84 / 255, blue: 0x78 / 255, alpha: 1)
    static let housingStop1 = SKColor(red: 0x4A / 255, green: 0x44 / 255, blue: 0x3C / 255, alpha: 1)
    static let housingStop2 = SKColor(red: 0xA8 / 255, green: 0x9E / 255, blue: 0x90 / 255, alpha: 1)
    static let housingStop3 = SKColor(red: 0x3C / 255, green: 0x36 / 255, blue: 0x2F / 255, alpha: 1)

    static let bolt = SKColor(red: 0x2C / 255, green: 0x28 / 255, blue: 0x22 / 255, alpha: 1)
    static let idleNumber = SKColor(red: 0xD8 / 255, green: 0xD2 / 255, blue: 0xC6 / 255, alpha: 1)
    static let selectedNumber = SKColor(red: 0x04 / 255, green: 0x1A / 255, blue: 0x30 / 255, alpha: 1)

    // MARK: Color math (mirrors `mix`/`coreCol` in reactor-engine.js)

    static func mix(_ a: SKColor, _ b: SKColor, _ t: CGFloat) -> SKColor {
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        a.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        b.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        let clampedT = min(max(t, 0), 1)
        return SKColor(
            red: r0 + (r1 - r0) * clampedT,
            green: g0 + (g1 - g0) * clampedT,
            blue: b0 + (b1 - b0) * clampedT,
            alpha: a0 + (a1 - a0) * clampedT
        )
    }

    /// core color drifts accent -> amber -> red as danger climbs (stays accent for first ~40%)
    static func coreColor(danger: CGFloat) -> SKColor {
        let h = min(max((danger - 0.4) / 0.6, 0), 1)
        if h <= 0 { return accent }
        if h < 0.5 { return mix(accent, amber, h / 0.5) }
        return mix(amber, dangerRed, (h - 0.5) / 0.5)
    }

    static func easeOut(_ t: CGFloat) -> CGFloat {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return 1 - pow(1 - t, 3)
    }

    static func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    // MARK: Geometry (README.md "Screen Layout", fractions of 390x844 reference)

    struct Layout {
        let width: CGFloat
        let height: CGFloat

        var center: CGPoint { CGPoint(x: width / 2, y: height * 0.5) }
        var orbitRadius: CGFloat { min(width, height) * 0.30 }
        var coreRadius: CGFloat { width * 0.155 }
        var nodeRadius: CGFloat { width * 0.074 }
    }

    // MARK: Hex path (flat-top hexagon, mirrors `hexPath` in reactor-engine.js)

    static func hexPath(radius: CGFloat, rotation: CGFloat = -.pi / 2) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = rotation + (CGFloat(i) / 6) * 2 * .pi
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Gradient textures

    /// SpriteKit misinterprets the byte order of `UIGraphicsImageRenderer`
    /// output (premultiplied BGRA) when the image carries an alpha gradient,
    /// rendering red and blue swapped. Re-render every generated image into a
    /// plain RGBA8 sRGB bitmap before creating the texture.
    static func texture(from image: UIImage) -> SKTexture {
        guard let cg = image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: cg.width, height: cg.height,
                  bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return SKTexture(image: image) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let normalized = ctx.makeImage() else { return SKTexture(image: image) }
        return SKTexture(cgImage: normalized)
    }

    /// Radial gradient disc. The gradient ends exactly at the image edge and
    /// the square corners stay transparent, so opaque-rimmed gradients (the
    /// molten pool) come out as clean discs without needing a crop mask.
    static func radialGradientImage(diameter: CGFloat, stops: [(CGFloat, SKColor)]) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgColors = stops.map { $0.1.cgColor } as CFArray
            let locations = stops.map { $0.0 }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: diameter / 2,
                options: []
            )
        }
    }

    static func linearGradientImage(size: CGSize, stops: [(CGFloat, SKColor)], from: CGPoint, to: CGPoint) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgColors = stops.map { $0.1.cgColor } as CFArray
            let locations = stops.map { $0.0 }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) else { return }
            ctx.cgContext.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    /// Off-center radial gradient for the node center plates. Mirrors the
    /// engine's `createRadialGradient(x, y − 0.3·ir, 0.1·ir, x, y, ir)` —
    /// the highlight sits above center, giving the plate a top-lit dome look.
    static func plateGradientImage(diameter: CGFloat, stops: [(CGFloat, SKColor)]) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgColors = stops.map { $0.1.cgColor } as CFArray
            let locations = stops.map { $0.0 }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) else { return }
            let r = diameter / 2
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: r, y: r - r * 0.3), startRadius: r * 0.1,
                endCenter: CGPoint(x: r, y: r), endRadius: r,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    /// Brushed-titanium housing annulus (ring at 1.2R, thickness 0.2R) baked
    /// as a bitmap. `SKShapeNode.fillTexture` silently fails to render on
    /// multi-subpath ring paths, so the conic gradient is rasterized here as
    /// pie wedges clipped to the annulus. Start angle 0.6 rad matches the
    /// engine's `createConicGradient(0.6, 0, 0)`.
    static func housingRingImage(coreRadius R: CGFloat) -> UIImage {
        let outer = R * 1.3, inner = R * 1.1
        let size = CGSize(width: outer * 2, height: outer * 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        let stops: [(CGFloat, SKColor)] = [
            (0, housingStop0), (0.2, housingStop1), (0.45, housingStop2), (0.7, housingStop3), (1, housingStop0),
        ]
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: outer, y: outer)
            let clip = CGMutablePath()
            clip.addEllipse(in: CGRect(x: 0, y: 0, width: outer * 2, height: outer * 2))
            clip.addEllipse(in: CGRect(x: outer - inner, y: outer - inner, width: inner * 2, height: inner * 2))
            cg.addPath(clip)
            cg.clip(using: .evenOdd)
            let segments = 240
            let startAngle: CGFloat = 0.6
            for i in 0..<segments {
                let t0 = CGFloat(i) / CGFloat(segments)
                let t1 = CGFloat(i + 1) / CGFloat(segments)
                let color = conicColor(at: (t0 + t1) / 2, stops: stops)
                let path = UIBezierPath()
                path.move(to: center)
                path.addArc(withCenter: center, radius: outer + 2,
                            startAngle: startAngle + t0 * 2 * .pi,
                            endAngle: startAngle + t1 * 2 * .pi + 0.004,
                            clockwise: true)
                path.close()
                color.setFill()
                path.fill()
            }
        }
    }

    /// White 3 pt rim ring with a soft 18 pt halo, tinted per frame via sprite
    /// color. Replaces `SKShapeNode.glowWidth`, which renders a fat solid band
    /// instead of the canvas reference's gaussian `shadowBlur` falloff.
    static func rimGlowImage(coreRadius R: CGFloat) -> UIImage {
        let pad: CGFloat = 30
        let size = CGSize(width: (R + pad) * 2, height: (R + pad) * 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let ring = CGRect(x: pad, y: pad, width: R * 2, height: R * 2)
            cg.setShadow(offset: .zero, blur: 18, color: UIColor.white.cgColor)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            cg.setLineWidth(3)
            cg.strokeEllipse(in: ring)
            cg.strokeEllipse(in: ring)
        }
    }

    private static func conicColor(at t: CGFloat, stops: [(CGFloat, SKColor)]) -> SKColor {
        guard var prev = stops.first else { return .white }
        for stop in stops {
            if t <= stop.0 {
                let span = stop.0 - prev.0
                let localT = span > 0 ? (t - prev.0) / span : 0
                return mix(prev.1, stop.1, localT)
            }
            prev = stop
        }
        return stops.last!.1
    }

    /// Bucketed texture cache keyed by a quantized danger value so gradients
    /// that drift continuously with `danger` aren't re-rasterized every frame.
    final class BucketedTextureCache {
        private var cache: [Int: SKTexture] = [:]
        private let buckets: Int

        init(buckets: Int = 40) {
            self.buckets = buckets
        }

        func texture(for danger: CGFloat, diameter: CGFloat, make: (SKColor) -> UIImage) -> SKTexture {
            let clamped = min(max(danger, 0), 1)
            let bucket = Int((clamped * CGFloat(buckets)).rounded())
            if let cached = cache[bucket] { return cached }
            let color = coreColor(danger: CGFloat(bucket) / CGFloat(buckets))
            let texture = ForgeTheme.texture(from: make(color))
            cache[bucket] = texture
            return texture
        }

        func clear() { cache.removeAll() }
    }
}
