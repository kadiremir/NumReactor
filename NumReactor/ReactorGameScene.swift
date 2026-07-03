import SpriteKit
import UIKit

/// SpriteKit presentation layer, "Molten Forge" visual reskin. Reads state
/// from `GameState` every frame and forwards taps back into it — all
/// gameplay rules still live in `GameEngine`; only the rendering here mirrors
/// `design_handoff_forge_reactor/reactor-engine.js`'s `forge` theme branch.
final class ReactorGameScene: SKScene {

    var gameState: GameState?
    var onExplosionComplete: (() -> Void)?

    // MARK: Layout

    private var layout = ForgeTheme.Layout(width: 390, height: 844)
    private var reactorCenter: CGPoint = .zero
    private var backgroundSizeCache: CGSize = .zero

    // MARK: Layers

    private let backgroundAura = SKSpriteNode()
    private let vignetteSprite = SKSpriteNode()
    private let flashSprite = SKSpriteNode(color: .white, size: .zero)
    private let shakeRoot = SKNode()
    private let orbitLayer = SKNode()
    private let beamsLayer = SKNode()
    private let coreGroup = SKNode()
    private let nodeLayer = SKNode()
    private let particles = ForgeParticleSystem()

    // MARK: Orbit

    private let orbitRail = SKShapeNode()
    private let orbitHairlineLight = SKShapeNode()
    private let orbitHairlineDark = SKShapeNode()
    private let orbitRivets = SKNode()
    private let orbitRunnerPivot = SKNode()
    private let orbitRunnerShape = SKShapeNode()
    private var orbitRunnerAngle: CGFloat = 0

    // MARK: Core

    private let coreGlow = SKSpriteNode()
    private let corePoolBase = SKSpriteNode()
    private var coreBlobs: [SKSpriteNode] = []
    private var coreCrusts: [SKSpriteNode] = []
    private let coreRim = SKSpriteNode()
    private let coreHousing = SKSpriteNode()
    private let coreHousingHairlineOuter = SKShapeNode()
    private let coreHousingHairlineInner = SKShapeNode()
    private let coreBolts = SKNode()
    private let coreChargeArcGlow = SKShapeNode()
    private let coreChargeArc = SKShapeNode()
    private let coreWell = SKSpriteNode()
    private var lastBakedCoreRadius: CGFloat = 0
    private let coreLabel = SKLabelNode(fontNamed: "ChakraPetch-Bold")
    private let coreLabelStroke = SKLabelNode(fontNamed: "ChakraPetch-Bold")

    // MARK: Stones / beams

    private var stoneNodes: [UUID: ForgeStoneNode] = [:]
    private var beamNodes: [UUID: ForgeBeamNode] = [:]

    // MARK: Texture caches

    private let poolBaseCache = ForgeTheme.BucketedTextureCache()
    private let blobCache = ForgeTheme.BucketedTextureCache()
    private let crustCache = ForgeTheme.BucketedTextureCache()
    private let plateSelectedCache = ForgeTheme.BucketedTextureCache()
    private var radialFadeOutTexture: SKTexture!
    private var radialFadeInTexture: SKTexture!
    private var coreGlowTexture: SKTexture!
    private var haloTexture: SKTexture!
    private var hexFaceTexture: SKTexture!
    private var plateIdleTexture: SKTexture!
    private var wellTexture: SKTexture!
    private var flareTexture: SKTexture!
    private var fireballTexture: SKTexture!

    // MARK: Stone geometry cache
    // hexPath/hexBevelLight/plate are identical for every stone (all driven by
    // layout.nodeRadius alone) — rebuilding them per-stone per-frame was pure waste.
    // The wobble/rotation is applied via zRotation instead of being baked into the path.
    private var cachedStoneNodeRadius: CGFloat = -1
    private var cachedHexPath: CGPath?
    private var cachedHexBevelLightPath: CGPath?
    private var cachedPlatePath: CGPath?

    // MARK: Frame state

    private var lastUpdateTime: TimeInterval?
    private var elapsedTime: TimeInterval = 0
    private var lastObservedHeat: Double = 0
    private var hasTriggeredExplosion = false
    private var flashIntensity: CGFloat = 0
    private var shakeAmplitude: CGFloat = 0
    private var orbitPull: CGFloat = 1
    private var moteTimer: TimeInterval = 0

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.isOpaque = false
        backgroundColor = .clear
        anchorPoint = .zero
        buildStaticTextures()
        buildNodeTree()
        layoutScene()
        lastObservedHeat = gameState?.heat ?? 0
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutScene()
    }

    private func buildStaticTextures() {
        radialFadeOutTexture = ForgeTheme.texture(from: ForgeTheme.radialGradientImage(diameter: 160, stops: [
            (0, SKColor.white.withAlphaComponent(1)), (1, SKColor.white.withAlphaComponent(0))
        ]))
        radialFadeInTexture = ForgeTheme.texture(from: ForgeTheme.radialGradientImage(diameter: 160, stops: [
            (0, SKColor.white.withAlphaComponent(0)), (1, SKColor.white.withAlphaComponent(1))
        ]))
        // Engine glow: gradient from 0.4R (α .55) → .18 at half → 0 at 2.3R.
        // Remapped to a full-disc texture (0.4/2.3 ≈ 0.174 inner plateau).
        coreGlowTexture = ForgeTheme.texture(from: ForgeTheme.radialGradientImage(diameter: 256, stops: [
            (0, SKColor.white),
            (0.17, SKColor.white),
            (0.59, SKColor.white.withAlphaComponent(0.33)),
            (1, SKColor.white.withAlphaComponent(0))
        ]))
        // Selected-node halo: engine gradient from 0.5r (α .42) → 0 at 1.9r.
        haloTexture = ForgeTheme.texture(from: ForgeTheme.radialGradientImage(diameter: 160, stops: [
            (0, SKColor.white),
            (0.26, SKColor.white),
            (1, SKColor.white.withAlphaComponent(0))
        ]))
        hexFaceTexture = ForgeTheme.texture(from: ForgeTheme.linearGradientImage(
            size: CGSize(width: 160, height: 160),
            stops: [(0, ForgeTheme.titaniumLight), (0.45, ForgeTheme.titaniumMid), (1, ForgeTheme.titaniumDark)],
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 160, y: 160)
        ))
        plateIdleTexture = ForgeTheme.texture(from: ForgeTheme.plateGradientImage(diameter: 160, stops: [
            (0, SKColor(red: 34 / 255, green: 36 / 255, blue: 40 / 255, alpha: 1)),
            (1, SKColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: 1))
        ]))
        wellTexture = ForgeTheme.texture(from: ForgeTheme.radialGradientImage(diameter: 160, stops: [
            (0, SKColor(red: 3 / 255, green: 13 / 255, blue: 15 / 255, alpha: 0.74)),
            (0.55, SKColor(red: 3 / 255, green: 13 / 255, blue: 15 / 255, alpha: 0.52)),
            (1, SKColor(red: 3 / 255, green: 13 / 255, blue: 15 / 255, alpha: 0))
        ]))
        flareTexture = ForgeTheme.texture(from: ForgeTheme.linearGradientImage(
            size: CGSize(width: 160, height: 8),
            stops: [(0, SKColor.white.withAlphaComponent(0)), (0.5, SKColor.white.withAlphaComponent(0.95)), (1, SKColor.white.withAlphaComponent(0))],
            from: CGPoint(x: 0, y: 4), to: CGPoint(x: 160, y: 4)
        ))
        fireballTexture = ForgeTheme.texture(from: ForgeTheme.radialGradientImage(diameter: 256, stops: [
            (0, SKColor.white.withAlphaComponent(0.98)),
            (0.3, SKColor(red: 1, green: 200 / 255, blue: 90 / 255, alpha: 0.95)),
            (0.62, SKColor(red: 1, green: 84 / 255, blue: 40 / 255, alpha: 0.7)),
            (1, SKColor(red: 1, green: 40 / 255, blue: 30 / 255, alpha: 0))
        ]))
    }

    private func buildNodeTree() {
        addChild(backgroundAura)
        backgroundAura.texture = radialFadeOutTexture
        backgroundAura.blendMode = .add
        backgroundAura.zPosition = -95

        addChild(vignetteSprite)
        vignetteSprite.texture = radialFadeInTexture
        vignetteSprite.color = ForgeTheme.dangerRed
        vignetteSprite.colorBlendFactor = 1
        vignetteSprite.zPosition = -50
        vignetteSprite.alpha = 0

        addChild(shakeRoot)
        shakeRoot.addChild(orbitLayer)
        orbitLayer.zPosition = -10
        shakeRoot.addChild(beamsLayer)
        beamsLayer.zPosition = 5
        shakeRoot.addChild(coreGroup)
        coreGroup.zPosition = 10
        shakeRoot.addChild(nodeLayer)
        nodeLayer.zPosition = 20
        shakeRoot.addChild(particles)

        buildOrbit()
        buildCore()

        addChild(flashSprite)
        flashSprite.zPosition = 200
        flashSprite.blendMode = .add
        flashSprite.alpha = 0
    }

    private func buildOrbit() {
        orbitLayer.addChild(orbitRail)
        orbitRail.strokeColor = SKColor(white: 0.055, alpha: 0.9)
        orbitRail.fillColor = .clear

        orbitLayer.addChild(orbitHairlineLight)
        orbitHairlineLight.strokeColor = SKColor(red: 130 / 255, green: 120 / 255, blue: 108 / 255, alpha: 0.5)
        orbitHairlineLight.fillColor = .clear
        orbitHairlineLight.lineWidth = 1.2

        orbitLayer.addChild(orbitHairlineDark)
        orbitHairlineDark.strokeColor = SKColor.black.withAlphaComponent(0.6)
        orbitHairlineDark.fillColor = .clear
        orbitHairlineDark.lineWidth = 1.2

        orbitLayer.addChild(orbitRivets)

        orbitLayer.addChild(orbitRunnerPivot)
        orbitRunnerPivot.addChild(orbitRunnerShape)
        orbitRunnerShape.fillColor = .clear
        orbitRunnerShape.lineWidth = 2.6
        orbitRunnerShape.lineCap = .round
        orbitRunnerShape.blendMode = .add
        orbitRunnerShape.glowWidth = 8
    }

    private func buildCore() {
        coreGroup.addChild(coreGlow)
        coreGlow.texture = coreGlowTexture
        coreGlow.blendMode = .add

        // Pool stack sits directly in coreGroup — the baked pool disc plus
        // blobs/crusts (which never drift past the pool radius) need no crop
        // mask, and SKCropNode's offscreen pass misrenders tinted/additive
        // children on some configurations anyway.
        coreGroup.addChild(corePoolBase)
        corePoolBase.blendMode = .alpha
        for _ in 0..<3 {
            let blob = SKSpriteNode(texture: radialFadeOutTexture)
            blob.blendMode = .add
            coreGroup.addChild(blob)
            coreBlobs.append(blob)
        }
        for _ in 0..<4 {
            let crust = SKSpriteNode(texture: radialFadeOutTexture)
            crust.blendMode = .alpha
            coreGroup.addChild(crust)
            coreCrusts.append(crust)
        }

        coreGroup.addChild(coreRim)
        coreRim.blendMode = .add
        coreRim.colorBlendFactor = 1

        coreGroup.addChild(coreHousing)

        coreGroup.addChild(coreHousingHairlineOuter)
        coreHousingHairlineOuter.strokeColor = SKColor.white.withAlphaComponent(0.14)
        coreHousingHairlineOuter.fillColor = .clear
        coreHousingHairlineOuter.lineWidth = 1.4

        coreGroup.addChild(coreHousingHairlineInner)
        coreHousingHairlineInner.strokeColor = SKColor.black.withAlphaComponent(0.55)
        coreHousingHairlineInner.fillColor = .clear
        coreHousingHairlineInner.lineWidth = 1.4

        coreGroup.addChild(coreBolts)

        // Charge arc: white 5 pt stroke over a colored soft-glow underlay —
        // SKShapeNode can't stroke white while glowing in `c`, so split in two.
        coreGroup.addChild(coreChargeArcGlow)
        coreChargeArcGlow.fillColor = .clear
        coreChargeArcGlow.lineCap = .round
        coreChargeArcGlow.lineWidth = 5
        coreChargeArcGlow.blendMode = .add
        coreChargeArcGlow.glowWidth = 10
        coreChargeArcGlow.alpha = 0.85
        coreChargeArcGlow.isHidden = true

        coreGroup.addChild(coreChargeArc)
        coreChargeArc.fillColor = .clear
        coreChargeArc.lineCap = .round
        coreChargeArc.lineWidth = 5
        coreChargeArc.blendMode = .add
        coreChargeArc.isHidden = true

        coreGroup.addChild(coreWell)
        coreWell.texture = wellTexture

        coreLabelStroke.horizontalAlignmentMode = .center
        coreLabelStroke.verticalAlignmentMode = .center
        coreLabelStroke.fontColor = SKColor(red: 2 / 255, green: 11 / 255, blue: 13 / 255, alpha: 0.55)
        coreLabelStroke.zPosition = 1
        coreGroup.addChild(coreLabelStroke)

        coreLabel.horizontalAlignmentMode = .center
        coreLabel.verticalAlignmentMode = .center
        coreLabel.fontColor = .white
        coreLabel.zPosition = 2
        coreGroup.addChild(coreLabel)
    }

    private func layoutScene() {
        guard size.width > 0, size.height > 0 else { return }
        layout = ForgeTheme.Layout(width: size.width, height: size.height)
        reactorCenter = layout.center

        if backgroundSizeCache != size {
            backgroundSizeCache = size
            poolBaseCache.clear()
            blobCache.clear()
            crustCache.clear()
            plateSelectedCache.clear()
        }

        backgroundAura.position = reactorCenter
        backgroundAura.size = CGSize(width: layout.orbitRadius * 3.2, height: layout.orbitRadius * 3.2)

        vignetteSprite.position = reactorCenter
        let vignetteDiameter = max(size.width, size.height) * 1.5
        vignetteSprite.size = CGSize(width: vignetteDiameter, height: vignetteDiameter)

        flashSprite.size = CGSize(width: size.width * 2.2, height: size.height * 2.2)
        flashSprite.position = reactorCenter

        layoutOrbit()
        layoutCore()
    }

    private func layoutOrbit() {
        let r = layout.orbitRadius
        orbitRail.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        orbitRail.position = reactorCenter
        orbitRail.lineWidth = 13

        orbitHairlineLight.path = CGPath(ellipseIn: CGRect(x: -(r - 6.5), y: -(r - 6.5), width: (r - 6.5) * 2, height: (r - 6.5) * 2), transform: nil)
        orbitHairlineLight.position = reactorCenter
        orbitHairlineDark.path = CGPath(ellipseIn: CGRect(x: -(r + 6.5), y: -(r + 6.5), width: (r + 6.5) * 2, height: (r + 6.5) * 2), transform: nil)
        orbitHairlineDark.position = reactorCenter

        orbitRivets.removeAllChildren()
        orbitRivets.position = reactorCenter
        for i in 0..<24 {
            let angle = CGFloat(i) / 24 * 2 * .pi
            let px = cos(angle) * r, py = sin(angle) * r
            let light = SKShapeNode(circleOfRadius: 1.6)
            light.fillColor = SKColor(red: 165 / 255, green: 155 / 255, blue: 142 / 255, alpha: 0.55)
            light.strokeColor = .clear
            light.position = CGPoint(x: px, y: py + 0.5)
            orbitRivets.addChild(light)
            let dark = SKShapeNode(circleOfRadius: 1.3)
            dark.fillColor = SKColor.black.withAlphaComponent(0.5)
            dark.strokeColor = .clear
            dark.position = CGPoint(x: px, y: py - 1)
            orbitRivets.addChild(dark)
        }

        orbitRunnerPivot.position = reactorCenter
        let runnerPath = CGMutablePath()
        runnerPath.addArc(center: .zero, radius: r, startAngle: -0.7, endAngle: 0.7, clockwise: false)
        orbitRunnerShape.path = runnerPath
    }

    private func layoutCore() {
        let R = layout.coreRadius

        // All core children live in coreGroup-relative coordinates so the
        // pulse/implosion scale pivots on the core center, not the scene origin.
        coreGroup.position = reactorCenter

        corePoolBase.position = .zero
        corePoolBase.size = CGSize(width: R * 2, height: R * 2)

        if abs(R - lastBakedCoreRadius) > 0.5 {
            lastBakedCoreRadius = R
            coreRim.texture = ForgeTheme.texture(from: ForgeTheme.rimGlowImage(coreRadius: R))
            coreHousing.texture = ForgeTheme.texture(from: ForgeTheme.housingRingImage(coreRadius: R))
        }
        coreRim.size = CGSize(width: (R + 30) * 2, height: (R + 30) * 2)
        coreRim.position = .zero
        coreHousing.size = CGSize(width: R * 2.6, height: R * 2.6)
        coreHousing.position = .zero

        let housingOuter = R * 1.31, housingRing = R * 1.2, housingInner = R * 1.1
        coreHousingHairlineOuter.path = CGPath(ellipseIn: CGRect(x: -housingOuter, y: -housingOuter, width: housingOuter * 2, height: housingOuter * 2), transform: nil)
        coreHousingHairlineInner.path = CGPath(ellipseIn: CGRect(x: -housingInner, y: -housingInner, width: housingInner * 2, height: housingInner * 2), transform: nil)

        coreBolts.removeAllChildren()
        for i in 0..<8 {
            let angle = CGFloat(i) / 8 * 2 * .pi + .pi / 8
            let bx = cos(angle) * housingRing, by = sin(angle) * housingRing
            let bolt = SKShapeNode(circleOfRadius: R * 0.055)
            bolt.fillColor = ForgeTheme.bolt
            bolt.strokeColor = .clear
            bolt.position = CGPoint(x: bx, y: by)
            coreBolts.addChild(bolt)
            let highlight = SKShapeNode(circleOfRadius: R * 0.028)
            highlight.fillColor = SKColor.white.withAlphaComponent(0.25)
            highlight.strokeColor = .clear
            highlight.position = CGPoint(x: bx - 0.8, y: by + 0.8)
            coreBolts.addChild(highlight)
        }

        coreWell.position = .zero
        coreWell.size = CGSize(width: R * 1.96, height: R * 1.96)

        // Engine says 0.92R (em), but the reference shots render digits ~0.8R
        // tall; Chakra Petch's cap height is 0.70em, so match the ref pixels.
        let fontSize = R * 1.15
        coreLabel.fontSize = fontSize
        coreLabelStroke.fontSize = fontSize
        coreLabel.position = CGPoint(x: 0, y: -R * 0.04)
        coreLabelStroke.position = coreLabel.position
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        guard let gameState else { return }

        let dt: TimeInterval
        if let last = lastUpdateTime {
            dt = min(currentTime - last, 1.0 / 20)
        } else {
            dt = 0
        }
        lastUpdateTime = currentTime
        elapsedTime += dt

        gameState.tick(deltaTime: dt)

        let danger = CGFloat(min(max(gameState.heat / 100, 0), 1))

        flashIntensity = max(0, flashIntensity - CGFloat(dt) * 3)
        shakeAmplitude = max(0, shakeAmplitude - CGFloat(dt) * 24)
        if danger > 0.72 {
            shakeAmplitude = max(shakeAmplitude, ((danger - 0.72) / 0.28) * 3.2)
        }
        shakeRoot.position = shakeAmplitude > 0.1
            ? CGPoint(x: CGFloat.random(in: -shakeAmplitude...shakeAmplitude), y: CGFloat.random(in: -shakeAmplitude...shakeAmplitude))
            : .zero
        flashSprite.alpha = min(flashIntensity * 0.5, 0.72)

        particles.update(dt: CGFloat(dt), time: CGFloat(elapsedTime))
        updateVignette(danger: danger, meltdown: hasTriggeredExplosion)
        updateBackgroundAura(danger: danger)

        guard !hasTriggeredExplosion else { return }

        spawnAmbientMotesIfNeeded(dt: dt, danger: danger)

        if gameState.isGameOver {
            hasTriggeredExplosion = true
            playReactorExplosion()
            return
        }

        if let reaction = gameState.lastReaction {
            handleReaction(reaction)
            gameState.lastReaction = nil
        }

        updateStones(with: gameState.stones, danger: danger)
        updateBeams(with: gameState.stones, danger: danger)
        updateOrbit(danger: danger, dt: dt)
        updateCore(danger: danger, stones: gameState.stones, target: gameState.target)

        if gameState.heat - lastObservedHeat > 1.2 {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
        }
        lastObservedHeat = gameState.heat
    }

    private func updateVignette(danger: CGFloat, meltdown: Bool) {
        let d = meltdown ? 1 : min(max((danger - 0.5) / 0.5, 0), 1)
        let pulse = 0.5 + 0.5 * sin(CGFloat(elapsedTime) * (6 + d * 8))
        vignetteSprite.alpha = d * (0.7 + 0.3 * pulse)
    }

    private func updateBackgroundAura(danger: CGFloat) {
        backgroundAura.color = ForgeTheme.coreColor(danger: danger)
        backgroundAura.colorBlendFactor = 1
        backgroundAura.alpha = 0.10 + danger * 0.06
    }

    private func spawnAmbientMotesIfNeeded(dt: TimeInterval, danger: CGFloat) {
        moteTimer += dt
        guard moteTimer > 0.35 else { return }
        moteTimer = 0
        guard CGFloat.random(in: 0...1) < 0.6 else { return }
        particles.spawnMote(near: reactorCenter, minRadius: layout.coreRadius * 1.25, maxRadius: layout.orbitRadius * 1.1, color: ForgeTheme.coreColor(danger: danger))
    }

    // MARK: Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let gameState, !isPaused else { return }
        let location = touch.location(in: self)

        // Geometric hit test (handoff §1.7): nearest stone within
        // nodeR × 1.35 + 6 wins. `nodes(at:)` is unusable here — it also
        // returns plain container nodes by their accumulated child frames, so
        // the glow-bearing coreGroup would swallow every tap on the ring.
        let hitRadius = layout.nodeRadius * 1.35 + 6
        var best: (id: UUID, distanceSquared: CGFloat)?
        for stone in gameState.stones {
            guard let node = stoneNodes[stone.id] else { continue }
            let dx = location.x - node.position.x
            let dy = location.y - node.position.y
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared <= hitRadius * hitRadius,
               distanceSquared < (best?.distanceSquared ?? .infinity) {
                best = (stone.id, distanceSquared)
            }
        }

        if let best {
            let wasSelected = gameState.stones.first(where: { $0.id == best.id })?.isSelected ?? false
            gameState.selectStone(id: best.id)
            if !wasSelected, let stoneNode = stoneNodes[best.id] {
                let danger = CGFloat(min(max(gameState.heat / 100, 0), 1))
                particles.spawnTapEffect(at: stoneNode.position, nodeRadius: layout.nodeRadius, accent: ForgeTheme.coreColor(danger: danger))
            }
            return
        }

        // Tap on the core itself clears the selection (existing behavior).
        if hypot(location.x - reactorCenter.x, location.y - reactorCenter.y) <= layout.coreRadius * 1.31 {
            gameState.clearSelection()
        }
    }

    // MARK: Orbit update

    private func updateOrbit(danger: CGFloat, dt: TimeInterval) {
        let c = ForgeTheme.coreColor(danger: danger)
        orbitRunnerShape.strokeColor = c.withAlphaComponent(0.55)
        orbitRunnerAngle += 0.34 * CGFloat(dt)
        orbitRunnerPivot.zRotation = orbitRunnerAngle
    }

    // MARK: Core update

    private func updateCore(danger: CGFloat, stones: [Stone], target: Int) {
        let R = layout.coreRadius
        let c = ForgeTheme.coreColor(danger: danger)
        let pulseSpeed = 2 + danger * 7
        let pulse = 1 + sin(CGFloat(elapsedTime) * pulseSpeed) * (0.02 + danger * 0.03)
        coreGroup.setScale(pulse)

        corePoolBase.texture = poolBaseCache.texture(for: danger, diameter: R * 2) { color in
            ForgeTheme.radialGradientImage(diameter: R * 2, stops: [
                (0.0, ForgeTheme.mix(color, .white, 0.72)),
                (0.45, color),
                (0.8, ForgeTheme.mix(color, .black, 0.45)),
                (1.0, ForgeTheme.mix(color, .black, 0.7)),
            ])
        }

        // Blob/crust colors are baked into the textures rather than applied via
        // colorBlendFactor — tinted sprites inside the SKCropNode's offscreen
        // pass render with red/blue swapped.
        let blobTexture = blobCache.texture(for: danger, diameter: R * 0.72) { color in
            let bright = ForgeTheme.mix(color, .white, 0.8)
            return ForgeTheme.radialGradientImage(diameter: R * 0.72, stops: [
                (0, bright.withAlphaComponent(0.55)),
                (1, bright.withAlphaComponent(0)),
            ])
        }
        for (i, blob) in coreBlobs.enumerated() {
            let a = CGFloat(elapsedTime) * (0.6 + CGFloat(i) * 0.22) + CGFloat(i) * 2.2
            blob.position = CGPoint(x: cos(a) * R * 0.35, y: sin(a * 1.5) * R * 0.35)
            let br = R * 0.36
            blob.size = CGSize(width: br * 2, height: br * 2)
            blob.texture = blobTexture
        }

        let crustTexture = crustCache.texture(for: danger, diameter: R * 0.84) { color in
            let crustColor = ForgeTheme.mix(color, .black, 0.82)
            return ForgeTheme.radialGradientImage(diameter: R * 0.84, stops: [
                (0, crustColor.withAlphaComponent(0.55)),
                (0.2, crustColor.withAlphaComponent(0.55)),
                (1, crustColor.withAlphaComponent(0)),
            ])
        }
        for (i, crust) in coreCrusts.enumerated() {
            let a = -CGFloat(elapsedTime) * (0.2 + CGFloat(i) * 0.07) + CGFloat(i) * 1.7
            crust.position = CGPoint(x: cos(a) * R * 0.5, y: sin(a * 0.8 + CGFloat(i)) * R * 0.5)
            let br = R * (0.3 + CGFloat(i % 2) * 0.12)
            crust.size = CGSize(width: br * 2, height: br * 2)
            crust.texture = crustTexture
        }

        let glowR = R * (2.3 + danger * 0.5)
        coreGlow.size = CGSize(width: glowR * 2, height: glowR * 2)
        coreGlow.color = c
        coreGlow.colorBlendFactor = 1
        coreGlow.alpha = 0.55

        coreRim.color = c

        let hasSelection = stones.contains(where: \.isSelected)
        if hasSelection {
            let selectedSum = stones.filter(\.isSelected).reduce(0) { $0 + $1.value }
            let over = abs(selectedSum) > abs(target)
            let progress = target != 0 ? min(max(CGFloat(abs(selectedSum)) / CGFloat(abs(target)), 0), 1) : 1
            coreChargeArc.isHidden = false
            coreChargeArcGlow.isHidden = false
            coreChargeArc.strokeColor = over ? ForgeTheme.dangerRed : .white
            coreChargeArcGlow.strokeColor = over ? ForgeTheme.dangerRed : c
            // From 12 o'clock, sweeping clockwise (canvas arc(-π/2 → -π/2+sweep) in y-down coords).
            let sweep = over ? 2 * CGFloat.pi : progress * 2 * CGFloat.pi
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: R * 1.16, startAngle: .pi / 2, endAngle: .pi / 2 - sweep, clockwise: true)
            coreChargeArc.path = path
            coreChargeArcGlow.path = path
        } else {
            coreChargeArc.isHidden = true
            coreChargeArcGlow.isHidden = true
        }

        coreLabel.text = "\(target)"
        coreLabelStroke.text = "\(target)"
    }

    // MARK: Stones

    private func stoneNode(for stone: Stone) -> ForgeStoneNode {
        if let existing = stoneNodes[stone.id] { return existing }
        let node = ForgeStoneNode()
        node.name = stone.id.uuidString
        node.bobPhase = CGFloat(abs(stone.id.hashValue % 1000)) / 1000 * 2 * .pi
        node.halo.texture = haloTexture
        node.pulseOverlay.texture = radialFadeOutTexture
        node.label.fontName = "ChakraPetch-SemiBold"
        node.labelShadow.fontName = "ChakraPetch-SemiBold"
        nodeLayer.addChild(node)
        stoneNodes[stone.id] = node
        node.setScale(0.4)
        node.alpha = 0
        let scaleUp = SKAction.scale(to: 1, duration: 0.4)
        scaleUp.timingMode = .easeOut
        node.run(.group([scaleUp, .fadeIn(withDuration: 0.4)]))
        return node
    }

    private func updateStones(with stones: [Stone], danger: CGFloat) {
        let currentIDs = Set(stones.map(\.id))
        for (id, node) in stoneNodes where !currentIDs.contains(id) {
            node.removeFromParent()
            stoneNodes.removeValue(forKey: id)
        }

        let r = layout.nodeRadius
        let c = ForgeTheme.coreColor(danger: danger)

        // hex/bevel/plate geometry is identical for every stone — only layout.nodeRadius
        // drives it — so it's rebuilt once here rather than per-stone, per-frame.
        let geometryDirty = abs(r - cachedStoneNodeRadius) > 0.01
        if geometryDirty {
            cachedStoneNodeRadius = r
            let hexR = r * 1.06
            cachedHexPath = ForgeTheme.hexPath(radius: hexR, rotation: -.pi / 2)
            cachedHexBevelLightPath = ForgeTheme.hexPath(radius: hexR - max(1.5, r * 0.06) * 0.6, rotation: -.pi / 2)
            let ir = r * 0.72
            cachedPlatePath = CGPath(ellipseIn: CGRect(x: -ir, y: -ir, width: ir * 2, height: ir * 2), transform: nil)
        }

        for stone in stones {
            let isNewNode = stoneNodes[stone.id] == nil
            let node = stoneNode(for: stone)
            let bob = sin(CGFloat(elapsedTime) * 1.3 + node.bobPhase) * 0.02
            let radius = layout.orbitRadius * orbitPull * (1 + bob)
            node.position = CGPoint(
                x: reactorCenter.x + cos(stone.angle) * radius,
                y: reactorCenter.y + sin(stone.angle) * radius
            )

            // Wobble is a transform, not baked into the path (see geometry cache above).
            let wobble = sin(CGFloat(elapsedTime) * 0.5 + node.bobPhase) * 0.04
            node.hex.zRotation = wobble
            node.hexShadow.zRotation = wobble
            node.hexBevelLight.zRotation = wobble
            node.hexBevelDark.zRotation = wobble

            let ir = r * 0.72
            if isNewNode || geometryDirty {
                node.hex.path = cachedHexPath
                node.hex.fillTexture = hexFaceTexture
                node.hexShadow.path = cachedHexPath
                node.hexShadow.position = CGPoint(x: 0, y: -r * 0.14)
                node.hexBevelLight.path = cachedHexBevelLightPath
                node.hexBevelLight.lineWidth = max(1.5, r * 0.06)
                node.hexBevelDark.path = cachedHexPath
                node.hexBevelDark.lineWidth = max(1, r * 0.035)

                node.plate.path = cachedPlatePath
                node.plateStroke.path = cachedPlatePath
                node.pulseOverlay.size = CGSize(width: ir * 2, height: ir * 2)
                node.halo.size = CGSize(width: r * 3.8, height: r * 3.8)

                node.label.fontSize = r * 0.85
                node.labelShadow.fontSize = r * 0.85
                node.label.position = CGPoint(x: 0, y: -r * 0.02)
                node.labelShadow.position = CGPoint(x: 0, y: -r * 0.02 - 1.4)
            }

            // True minus glyph (U+2212) per spec §6.1, not an ASCII hyphen.
            let text = stone.value >= 0 ? "+\(stone.value)" : "−\(abs(stone.value))"
            if node.label.text != text {
                node.label.text = text
                node.labelShadow.text = text
            }

            if stone.isSelected {
                node.halo.isHidden = false
                node.halo.color = c
                node.halo.colorBlendFactor = 1
                node.halo.alpha = 0.42
                node.plate.fillTexture = plateSelectedCache.texture(for: danger, diameter: ir * 2) { color in
                    ForgeTheme.plateGradientImage(diameter: ir * 2, stops: [
                        (0.0, ForgeTheme.mix(color, .white, 0.62)),
                        (0.6, color),
                        (1.0, ForgeTheme.mix(color, .black, 0.55)),
                    ])
                }
                node.plateStroke.strokeColor = c
                node.plateStroke.lineWidth = 1.5
                node.plateStroke.glowWidth = 12
                node.pulseOverlay.color = ForgeTheme.mix(c, .white, 0.75)
                node.pulseOverlay.colorBlendFactor = 1
                node.pulseOverlay.alpha = 0.25 + 0.15 * sin(CGFloat(elapsedTime) * 7 + node.bobPhase * 3)
                node.label.fontColor = ForgeTheme.selectedNumber
                node.labelShadow.isHidden = true
            } else {
                node.halo.isHidden = true
                node.plate.fillTexture = plateIdleTexture
                node.plateStroke.strokeColor = SKColor.black.withAlphaComponent(0.6)
                node.plateStroke.lineWidth = 1.5
                node.plateStroke.glowWidth = 0
                node.pulseOverlay.alpha = 0
                node.label.fontColor = ForgeTheme.idleNumber
                node.labelShadow.isHidden = false
            }
        }
    }

    // MARK: Beams

    private func updateBeams(with stones: [Stone], danger: CGFloat) {
        let selected = stones.filter(\.isSelected)
        let selectedIDs = Set(selected.map(\.id))
        for (id, node) in beamNodes where !selectedIDs.contains(id) {
            node.removeFromParent()
            beamNodes.removeValue(forKey: id)
        }

        let c = ForgeTheme.coreColor(danger: danger)
        let t = CGFloat(elapsedTime)
        for stone in selected {
            guard let stoneNode = stoneNodes[stone.id] else { continue }
            let beam = beamNodes[stone.id] ?? makeBeam(id: stone.id)

            let p0 = stoneNode.position
            let d = CGPoint(x: reactorCenter.x - p0.x, y: reactorCenter.y - p0.y)
            let length = max(sqrt(d.x * d.x + d.y * d.y), 0.0001)
            let u = CGPoint(x: d.x / length, y: d.y / length)
            let perp = CGPoint(x: -u.y, y: u.x)

            // Spec §7: undulating sine wave traveling node → core, rebuilt every frame.
            let path = CGMutablePath()
            var started = false
            var s: CGFloat = 0
            while s <= 1.0001 {
                let clampedS = min(s, 1)
                let wobble = sin(clampedS * 9 + t * 10) * 5 * sin(clampedS * .pi)
                let point = CGPoint(
                    x: p0.x + d.x * clampedS + perp.x * wobble,
                    y: p0.y + d.y * clampedS + perp.y * wobble
                )
                if started {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    started = true
                }
                s += 0.05
            }

            beam.glowPath.path = path
            beam.glowPath.strokeColor = c.withAlphaComponent(0.5)
            beam.corePath.path = path
        }
    }

    private func makeBeam(id: UUID) -> ForgeBeamNode {
        let beam = ForgeBeamNode()
        beamsLayer.addChild(beam)
        beamNodes[id] = beam
        return beam
    }

    // MARK: Reaction effects

    private func handleReaction(_ reaction: GameEngine.ReactionResult) {
        for id in reaction.usedStoneIDs {
            beamNodes[id]?.removeFromParent()
            beamNodes.removeValue(forKey: id)
            guard let node = stoneNodes.removeValue(forKey: id) else { continue }
            let flyIn = SKAction.group([
                .move(to: reactorCenter, duration: 0.5),
                .scale(to: 0.3, duration: 0.5),
                .fadeOut(withDuration: 0.5)
            ])
            flyIn.timingMode = .easeIn
            node.run(.sequence([flyIn, .removeFromParent()]))
        }

        let danger = CGFloat(min(max((gameState?.heat ?? 0) / 100, 0), 1))
        let c = ForgeTheme.coreColor(danger: danger)
        let R = layout.coreRadius

        for k in 0..<3 {
            particles.spawnRing(at: reactorCenter, radius: R * 0.85, growthRate: 270 + CGFloat(k) * 130, life: 0.6 + CGFloat(k) * 0.1, color: k % 2 == 0 ? c : .white, lineWidth: 3, zPosition: 40)
        }
        for _ in 0..<28 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 120...380)
            particles.spawnSpark(at: reactorCenter, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed), gravity: 70, drag: 1.6, life: CGFloat.random(in: 0.5...1), radius: CGFloat.random(in: 1.5...3.5), color: Bool.random() ? c : .white, zPosition: 40)
        }
        spawnFloatingScoreText(gain: reaction.scoreGain)

        flashIntensity = max(flashIntensity, 1)
        shakeAmplitude = max(shakeAmplitude, 9)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func spawnFloatingScoreText(gain: Int) {
        let label = SKLabelNode(fontNamed: "ChakraPetch-Bold")
        label.text = "+\(gain)"
        label.fontSize = layout.coreRadius * 0.52
        label.fontColor = ForgeTheme.highlight
        label.position = CGPoint(x: reactorCenter.x, y: reactorCenter.y + layout.coreRadius + 12)
        label.zPosition = 45
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 46, duration: 1.15), .fadeOut(withDuration: 1.15)]),
            .removeFromParent()
        ]))
    }

    // MARK: Meltdown

    private func playReactorExplosion() {
        for (_, beam) in beamNodes { beam.removeFromParent() }
        beamNodes.removeAll()

        let R = layout.coreRadius
        let orbitR = layout.orbitRadius
        let big = max(size.width, size.height)
        let c = ForgeTheme.coreColor(danger: 1)

        for _ in 0..<52 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let d = CGFloat.random(in: (R * 1.8)...(big * 0.6))
            let origin = CGPoint(x: reactorCenter.x + cos(angle) * d, y: reactorCenter.y + sin(angle) * d)
            let tArr = CGFloat.random(in: 0.2...0.34)
            let velocity = CGVector(dx: -cos(angle) * (d / tArr), dy: -sin(angle) * (d / tArr))
            let color = [c, .white, ForgeTheme.amber].randomElement()!
            particles.spawnStreak(at: origin, velocity: velocity, drag: 0, life: tArr, length: CGFloat.random(in: 16...44), lineWidth: CGFloat.random(in: 1...2.6), color: color, zPosition: 95)
        }
        particles.spawnRing(at: reactorCenter, radius: orbitR * 1.35, growthRate: -(orbitR * 1.35 - R * 0.4) / 0.34, life: 0.34, color: .white, lineWidth: 2.5, zPosition: 95)

        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        flashIntensity = max(flashIntensity, 0.3)
        shakeAmplitude = max(shakeAmplitude, 5)

        let implode = SKAction.scale(to: 0.68, duration: 0.34)
        implode.timingMode = .easeInEaseOut
        coreGroup.run(implode)

        let pullAction = SKAction.customAction(withDuration: 0.34) { [weak self] _, elapsed in
            guard let self else { return }
            let p = min(1, elapsed / 0.34)
            self.orbitPull = 1 - 0.3 * ForgeTheme.easeInOut(p)
            self.shakeAmplitude = max(self.shakeAmplitude, 2 + p * 8)
        }
        run(.sequence([pullAction, .run { [weak self] in self?.detonate() }]))

        run(.sequence([.wait(forDuration: 1.15), .run { [weak self] in self?.onExplosionComplete?() }]))
    }

    private func detonate() {
        let R = layout.coreRadius
        let big = max(size.width, size.height)

        flashIntensity = max(flashIntensity, 2.2)
        shakeAmplitude = max(shakeAmplitude, 34)

        killCoreToEmberStub()

        speed = 0.3
        run(.sequence([.wait(forDuration: 0.3 * 0.3), .run { [weak self] in self?.speed = 1 }]))

        for _ in 0..<26 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let d = CGFloat.random(in: 0...(R * 0.9))
            let sp = CGFloat.random(in: 26...150)
            let origin = CGPoint(x: reactorCenter.x + cos(angle) * d, y: reactorCenter.y + sin(angle) * d)
            particles.spawnSmoke(at: origin, velocity: CGVector(dx: cos(angle) * sp, dy: sin(angle) * sp - CGFloat.random(in: 6...40)), gravity: -16, drag: 0.85, life: CGFloat.random(in: 1.7...3.4), radius: CGFloat.random(in: 12...26), growthRate: CGFloat.random(in: 13...26), zPosition: 60)
        }

        for (_, node) in stoneNodes {
            let angle = atan2(node.position.y - reactorCenter.y, node.position.x - reactorCenter.x)
            for _ in 0..<3 {
                let a = angle + CGFloat.random(in: -0.5...0.5)
                let sp = CGFloat.random(in: 300...720)
                particles.spawnShard(at: node.position, velocity: CGVector(dx: cos(a) * sp, dy: sin(a) * sp), gravity: 260, drag: 0.5, life: CGFloat.random(in: 1.1...2.2), radius: CGFloat.random(in: 8...14), color: ForgeTheme.titaniumMid, hot: true, zPosition: 90)
            }
            particles.burstShards(at: node.position, count: 6, color: ForgeTheme.titaniumLight)
            node.removeFromParent()
        }
        stoneNodes.removeAll()
        particles.burstShards(at: reactorCenter, count: 46, color: ForgeTheme.dangerRed)

        spawnFireball()
        spawnFlare(length: big * 0.55)

        for _ in 0..<64 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let sp = CGFloat.random(in: 380...1050)
            let color: SKColor = [SKColor(red: 1, green: 236 / 255, blue: 190 / 255, alpha: 1), SKColor(red: 1, green: 150 / 255, blue: 70 / 255, alpha: 1), .white].randomElement()!
            particles.spawnStreak(at: reactorCenter, velocity: CGVector(dx: cos(angle) * sp, dy: sin(angle) * sp), drag: 2.3, life: CGFloat.random(in: 0.35...0.8), length: CGFloat.random(in: 30...80), lineWidth: CGFloat.random(in: 1.5...3.2), color: color, zPosition: 92)
        }

        for _ in 0..<110 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let sp = CGFloat.random(in: 140...760)
            let color: SKColor = [SKColor(red: 1, green: 200 / 255, blue: 90 / 255, alpha: 1), SKColor(red: 1, green: 92 / 255, blue: 50 / 255, alpha: 1), SKColor(red: 1, green: 240 / 255, blue: 200 / 255, alpha: 1)].randomElement()!
            particles.spawnSpark(at: reactorCenter, velocity: CGVector(dx: cos(angle) * sp, dy: sin(angle) * sp), gravity: 130, drag: 1.25, life: CGFloat.random(in: 0.5...1.5), radius: CGFloat.random(in: 1.4...3.4), color: color, zPosition: 93)
        }

        for _ in 0..<64 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let sp = CGFloat.random(in: 40...340)
            let color: SKColor = [SKColor(red: 1, green: 180 / 255, blue: 60 / 255, alpha: 1), SKColor(red: 1, green: 92 / 255, blue: 50 / 255, alpha: 1), SKColor(red: 1, green: 232 / 255, blue: 184 / 255, alpha: 1)].randomElement()!
            particles.spawnEmber(at: reactorCenter, velocity: CGVector(dx: cos(angle) * sp, dy: sin(angle) * sp - 80), gravity: 150, drag: 1, life: CGFloat.random(in: 1.0...2.6), radius: CGFloat.random(in: 2...5), color: color, zPosition: 91)
        }

        for k in 0..<5 {
            let color: SKColor = k == 0 ? .white : (k % 2 == 1 ? SKColor(red: 1, green: 224 / 255, blue: 150 / 255, alpha: 1) : ForgeTheme.dangerRed)
            particles.spawnRing(at: reactorCenter, radius: R * 0.4, growthRate: big * (1.3 + CGFloat(k) * 0.5), life: 0.5 + 0.11 * CGFloat(k), color: color, lineWidth: 7 - CGFloat(k), zPosition: 94)
        }

        UINotificationFeedbackGenerator().notificationOccurred(.error)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        for t in [0.52 - 0.34, 0.78 - 0.34, 1.05 - 0.34] {
            run(.sequence([.wait(forDuration: t), .run { [weak self] in self?.spawnSecondaryPop() }]))
        }
    }

    /// SPEC §9 phase 2 core rendering: the housing blows away with the blast
    /// and the molten pool dies to an ember stub — a dark disc at 40% radius
    /// with a dull rust rim — while the outer glow drops to 15% and the target
    /// number fades out in rgb(255,120,90) (engine: alpha = 1 − meltT).
    private func killCoreToEmberStub() {
        let R = layout.coreRadius

        corePoolBase.isHidden = true
        coreBlobs.forEach { $0.isHidden = true }
        coreCrusts.forEach { $0.isHidden = true }
        coreWell.isHidden = true
        coreHousing.isHidden = true
        coreHousingHairlineOuter.isHidden = true
        coreHousingHairlineInner.isHidden = true
        coreBolts.isHidden = true
        coreChargeArc.isHidden = true
        coreChargeArcGlow.isHidden = true
        coreRim.isHidden = true

        // The implosion contraction ends at the blast (engine draws the stub
        // from the unscaled core radius).
        coreGroup.removeAllActions()
        coreGroup.setScale(1)

        let stubR = R * 0.4
        let ember = SKColor(red: 40 / 255, green: 30 / 255, blue: 28 / 255, alpha: 1)
        let stub = SKSpriteNode(texture: ForgeTheme.texture(from: ForgeTheme.radialGradientImage(diameter: stubR * 2, stops: [
            (0.0, ember.withAlphaComponent(0.6)),
            (0.7, ForgeTheme.mix(ember, .black, 0.4).withAlphaComponent(0.85)),
            (1.0, ForgeTheme.mix(ember, .black, 0.65).withAlphaComponent(0.95)),
        ])))
        stub.size = CGSize(width: stubR * 2, height: stubR * 2)
        stub.position = .zero
        coreGroup.addChild(stub)

        let rustRim = SKShapeNode(circleOfRadius: stubR)
        rustRim.fillColor = .clear
        rustRim.strokeColor = SKColor(red: 120 / 255, green: 60 / 255, blue: 50 / 255, alpha: 0.5)
        rustRim.lineWidth = 3
        rustRim.glowWidth = 3
        rustRim.blendMode = .add
        coreGroup.addChild(rustRim)

        coreGlow.alpha = 0.15
        let glowR = stubR * 2.8
        coreGlow.size = CGSize(width: glowR * 2, height: glowR * 2)

        coreLabelStroke.isHidden = true
        coreLabel.fontColor = SKColor(red: 255 / 255, green: 120 / 255, blue: 90 / 255, alpha: 1)
        coreLabel.alpha = 0.66
        coreLabel.run(.fadeOut(withDuration: 0.66))
    }

    private func spawnFireball() {
        let R = layout.coreRadius
        let fireball = SKSpriteNode(texture: fireballTexture)
        fireball.blendMode = .add
        fireball.position = reactorCenter
        fireball.zPosition = 96
        fireball.size = CGSize(width: R * 2, height: R * 2)
        fireball.setScale(0.02)
        addChild(fireball)

        for i in 0..<6 {
            let lobe = SKSpriteNode(texture: radialFadeOutTexture)
            lobe.color = SKColor(red: 1, green: 160 / 255, blue: 70 / 255, alpha: 1)
            lobe.colorBlendFactor = 1
            lobe.blendMode = .add
            lobe.alpha = 0.5
            let br = R * 0.42
            lobe.size = CGSize(width: br * 2, height: br * 2)
            let angle = CGFloat(i) / 6 * 2 * .pi
            lobe.position = CGPoint(x: cos(angle) * R * 0.4, y: sin(angle) * R * 0.38)
            fireball.addChild(lobe)
        }

        let grow = SKAction.scale(to: 4.8, duration: 0.2)
        grow.timingMode = .easeOut
        let shrink = SKAction.group([.scale(to: 0.001, duration: 1.2), .fadeOut(withDuration: 1.2)])
        fireball.run(.sequence([grow, shrink, .removeFromParent()]))
    }

    private func spawnFlare(length: CGFloat) {
        let h = SKSpriteNode(texture: flareTexture)
        h.blendMode = .add
        h.position = reactorCenter
        h.zPosition = 97
        h.size = CGSize(width: length, height: 3.5)
        addChild(h)

        let v = SKSpriteNode(texture: flareTexture)
        v.blendMode = .add
        v.position = reactorCenter
        v.zRotation = .pi / 2
        v.zPosition = 97
        v.size = CGSize(width: length * 0.3, height: 2.5)
        addChild(v)

        let fade = SKAction.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()])
        h.run(fade)
        v.run(fade)
    }

    private func spawnSecondaryPop() {
        let R = layout.coreRadius
        let ox = reactorCenter.x + CGFloat.random(in: -(R * 1.8)...(R * 1.8))
        let oy = reactorCenter.y + CGFloat.random(in: -(R * 1.6)...(R * 1.6))
        let origin = CGPoint(x: ox, y: oy)

        flashIntensity = max(flashIntensity, 0.6)
        shakeAmplitude = max(shakeAmplitude, 12)

        for _ in 0..<24 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let sp = CGFloat.random(in: 160...600)
            let color: SKColor = [SKColor(red: 1, green: 200 / 255, blue: 90 / 255, alpha: 1), SKColor(red: 1, green: 110 / 255, blue: 60 / 255, alpha: 1), SKColor(red: 1, green: 240 / 255, blue: 200 / 255, alpha: 1)].randomElement()!
            particles.spawnSpark(at: origin, velocity: CGVector(dx: cos(angle) * sp, dy: sin(angle) * sp), gravity: 120, drag: 1.4, life: CGFloat.random(in: 0.4...1), radius: CGFloat.random(in: 1.5...3), color: color, zPosition: 93)
        }
        for _ in 0..<5 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let sp = CGFloat.random(in: 20...90)
            particles.spawnSmoke(at: origin, velocity: CGVector(dx: cos(angle) * sp, dy: sin(angle) * sp - 20), gravity: -14, drag: 0.8, life: CGFloat.random(in: 1.4...2.6), radius: CGFloat.random(in: 9...18), growthRate: CGFloat.random(in: 10...20), zPosition: 60)
        }
        particles.spawnRing(at: origin, radius: 8, growthRate: 620, life: 0.5, color: SKColor(red: 1, green: 220 / 255, blue: 150 / 255, alpha: 1), lineWidth: 3, zPosition: 94)
        particles.burstShards(at: origin, count: 9, color: SKColor(red: 205 / 255, green: 165 / 255, blue: 120 / 255, alpha: 1))
    }

}

// MARK: - ForgeStoneNode

/// Container for a single machined-titanium hex node: face, bevel strokes,
/// center plate, selection halo/pulse, and its number label.
private final class ForgeStoneNode: SKNode {
    let hexShadow = SKShapeNode()
    let halo = SKSpriteNode()
    let hex = SKShapeNode()
    let hexBevelLight = SKShapeNode()
    let hexBevelDark = SKShapeNode()
    let plate = SKShapeNode()
    let pulseOverlay = SKSpriteNode()
    let plateStroke = SKShapeNode()
    let labelShadow = SKLabelNode()
    let label = SKLabelNode()
    var bobPhase: CGFloat = 0

    override init() {
        super.init()
        addChild(hexShadow)
        addChild(halo)
        addChild(hex)
        addChild(hexBevelLight)
        addChild(hexBevelDark)
        addChild(plate)
        addChild(pulseOverlay)
        addChild(plateStroke)
        addChild(labelShadow)
        addChild(label)

        halo.blendMode = .add
        pulseOverlay.blendMode = .add

        hexShadow.fillColor = SKColor.black.withAlphaComponent(0.45)
        hexShadow.strokeColor = .clear
        hexShadow.glowWidth = 6

        hex.strokeColor = .clear
        hex.fillColor = .white

        hexBevelLight.fillColor = .clear
        hexBevelLight.strokeColor = SKColor.white.withAlphaComponent(0.28)
        hexBevelDark.fillColor = .clear
        hexBevelDark.strokeColor = SKColor.black.withAlphaComponent(0.5)

        plate.strokeColor = .clear
        plate.fillColor = .white
        plateStroke.fillColor = .clear

        labelShadow.fontColor = SKColor.black.withAlphaComponent(0.55)
        labelShadow.verticalAlignmentMode = .center
        labelShadow.horizontalAlignmentMode = .center
        labelShadow.zPosition = 1

        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - ForgeBeamNode

/// A selection beam from an orbiting node into the core: soft glow underlay,
/// bright filament, and three traveling energy dots.
private final class ForgeBeamNode: SKNode {
    let glowPath = SKShapeNode()
    let corePath = SKShapeNode()

    override init() {
        super.init()

        addChild(glowPath)
        addChild(corePath)

        glowPath.fillColor = .clear
        glowPath.lineWidth = 6
        glowPath.lineCap = .round
        glowPath.blendMode = .add

        corePath.fillColor = .clear
        corePath.strokeColor = SKColor.white.withAlphaComponent(0.8)
        corePath.lineWidth = 2
        corePath.lineCap = .round
        corePath.blendMode = .add
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
