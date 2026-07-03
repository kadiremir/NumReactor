import SpriteKit

/// Hand-rolled particle system mirroring `reactor-engine.js`'s `_updP` /
/// `_spawn*` functions 1:1 (counts, velocity ranges, life ranges, colors).
/// Each particle owns a persistent SpriteKit node whose geometry is rebuilt
/// every tick from its simulated position/velocity — the SpriteKit analogue
/// of the JS engine's per-frame canvas redraw.
final class ForgeParticleSystem: SKNode {

    private enum Kind {
        case ring, streak, spark, ember, smoke, shard
    }

    private final class Particle {
        let node: SKShapeNode
        let kind: Kind
        var position: CGPoint
        var velocity: CGVector
        var gravity: CGFloat
        var drag: CGFloat
        var life: CGFloat
        let maxLife: CGFloat
        var radius: CGFloat
        var vr: CGFloat = 0
        let length: CGFloat
        let lineWidth: CGFloat
        var rotation: CGFloat
        let angularVelocity: CGFloat
        let color: SKColor
        let seed: CGFloat
        let hot: Bool

        init(node: SKShapeNode, kind: Kind, position: CGPoint, velocity: CGVector, gravity: CGFloat, drag: CGFloat,
             life: CGFloat, radius: CGFloat, vr: CGFloat, length: CGFloat, lineWidth: CGFloat, rotation: CGFloat,
             angularVelocity: CGFloat, color: SKColor, seed: CGFloat, hot: Bool) {
            self.node = node
            self.kind = kind
            self.position = position
            self.velocity = velocity
            self.gravity = gravity
            self.drag = drag
            self.life = life
            self.maxLife = life
            self.radius = radius
            self.vr = vr
            self.length = length
            self.lineWidth = lineWidth
            self.rotation = rotation
            self.angularVelocity = angularVelocity
            self.color = color
            self.seed = seed
            self.hot = hot
        }
    }

    private var particles: [Particle] = []
    private let maxParticles = 600

    var particleCount: Int { particles.count }

    // MARK: Frame update (mirrors `_updP`)

    func update(dt: CGFloat, time: CGFloat) {
        var survivors: [Particle] = []
        survivors.reserveCapacity(particles.count)

        for p in particles {
            p.life -= dt
            if p.life <= 0 {
                p.node.removeFromParent()
                continue
            }

            switch p.kind {
            case .ring:
                p.radius += p.vr * dt
            default:
                p.position.x += p.velocity.dx * dt
                p.position.y += p.velocity.dy * dt
                p.velocity.dx *= 1 - p.drag * dt
                p.velocity.dy *= 1 - p.drag * dt
                p.velocity.dy += p.gravity * dt
                p.rotation += p.angularVelocity * dt
                if p.kind == .smoke {
                    p.radius += p.vr * dt
                    p.position.x += sin(p.seed + p.life * 2.6) * 16 * dt
                } else if p.hot, particles.count < maxParticles, CGFloat.random(in: 0...1) < 0.45 * dt * 60 {
                    spawnEmber(at: p.position, velocity: CGVector(dx: CGFloat.random(in: -20...20), dy: CGFloat.random(in: -20...20)),
                               gravity: -30, drag: 1.5, life: CGFloat.random(in: 0.2...0.45), radius: CGFloat.random(in: 1...2.4),
                               color: [SKColor(red: 1, green: 0.67, blue: 0.24, alpha: 1), SKColor(red: 1, green: 0.43, blue: 0.2, alpha: 1)].randomElement()!)
                }
            }

            let a = min(max(p.life / p.maxLife, 0), 1)
            render(p, alpha: a, time: time)
            survivors.append(p)
        }

        particles = survivors
    }

    private func render(_ p: Particle, alpha: CGFloat, time: CGFloat) {
        let node = p.node
        switch p.kind {
        case .ring:
            node.position = p.position
            node.path = CGPath(ellipseIn: CGRect(x: -p.radius, y: -p.radius, width: p.radius * 2, height: p.radius * 2), transform: nil)
            node.alpha = alpha * 0.9

        case .streak, .spark:
            let speed = max(1, hypot(p.velocity.dx, p.velocity.dy))
            let dirX = p.velocity.dx / speed, dirY = p.velocity.dy / speed
            let len = p.kind == .spark ? min(p.length, speed * 0.03) : p.length
            let tail = CGPoint(x: p.position.x - dirX * len, y: p.position.y - dirY * len)
            let path = CGMutablePath()
            path.move(to: p.position)
            path.addLine(to: tail)
            node.path = path
            node.position = .zero
            node.alpha = alpha

        case .ember:
            node.position = p.position
            node.alpha = alpha * (0.6 + 0.4 * sin(time * 26 + p.seed))

        case .smoke:
            node.position = p.position
            node.path = CGPath(ellipseIn: CGRect(x: -p.radius, y: -p.radius, width: p.radius * 2, height: p.radius * 2), transform: nil)
            let born = 1 - alpha
            let al = min(1, born * 6) * pow(alpha, 1.25) * 0.5
            node.fillColor = ForgeTheme.mix(SKColor(red: 0.59, green: 0.42, blue: 0.31, alpha: 1), SKColor(red: 0.2, green: 0.22, blue: 0.24, alpha: 1), min(born * 1.7, 1))
            node.alpha = al

        case .shard:
            node.position = p.position
            node.zRotation = p.rotation
            node.alpha = alpha
        }
    }

    // MARK: Spawners (mirror the JS engine's `_spawn*` helpers)

    private func makeShapeNode(fill: Bool, blend: SKBlendMode, zPosition: CGFloat) -> SKShapeNode {
        let node = SKShapeNode()
        node.blendMode = blend
        node.zPosition = zPosition
        node.strokeColor = .clear
        node.fillColor = fill ? .white : .clear
        addChild(node)
        return node
    }

    @discardableResult
    private func spawnParticle(kind: Kind, position: CGPoint, velocity: CGVector, gravity: CGFloat, drag: CGFloat,
                                life: CGFloat, radius: CGFloat, vr: CGFloat, length: CGFloat, lineWidth: CGFloat,
                                color: SKColor, rotation: CGFloat, angularVelocity: CGFloat, seed: CGFloat,
                                hot: Bool, blend: SKBlendMode, zPosition: CGFloat) -> Particle {
        let node = makeShapeNode(fill: kind == .shard || kind == .smoke, blend: blend, zPosition: zPosition)
        switch kind {
        case .ring:
            node.strokeColor = color
            node.lineWidth = lineWidth
            node.glowWidth = lineWidth * 1.6
            node.fillColor = .clear
        case .streak, .spark:
            node.strokeColor = color
            node.lineWidth = lineWidth
            node.lineCap = .round
            node.glowWidth = lineWidth * 0.8
        case .ember:
            node.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            node.fillColor = color
            node.glowWidth = radius * 2.6
        case .smoke:
            node.fillColor = color
        case .shard:
            node.path = ForgeTheme.hexPath(radius: radius, rotation: 0)
            node.fillColor = color
            node.glowWidth = radius * 0.5
        }
        let p = Particle(node: node, kind: kind, position: position, velocity: velocity, gravity: gravity, drag: drag,
                          life: life, radius: radius, vr: vr, length: length, lineWidth: lineWidth, rotation: rotation,
                          angularVelocity: angularVelocity, color: color, seed: seed, hot: hot)
        particles.append(p)
        return p
    }

    func spawnRing(at point: CGPoint, radius: CGFloat, growthRate: CGFloat, life: CGFloat, color: SKColor, lineWidth: CGFloat, zPosition: CGFloat = 30) {
        spawnParticle(kind: .ring, position: point, velocity: .zero, gravity: 0, drag: 0, life: life, radius: radius,
                      vr: growthRate, length: 0, lineWidth: lineWidth, color: color, rotation: 0, angularVelocity: 0,
                      seed: 0, hot: false, blend: .add, zPosition: zPosition)
    }

    func spawnSpark(at point: CGPoint, velocity: CGVector, gravity: CGFloat = 0, drag: CGFloat, life: CGFloat, radius: CGFloat, color: SKColor, zPosition: CGFloat = 32) {
        spawnParticle(kind: .spark, position: point, velocity: velocity, gravity: gravity, drag: drag, life: life,
                      radius: radius, vr: 0, length: 16, lineWidth: radius, color: color, rotation: 0, angularVelocity: 0,
                      seed: 0, hot: false, blend: .add, zPosition: zPosition)
    }

    func spawnStreak(at point: CGPoint, velocity: CGVector, drag: CGFloat, life: CGFloat, length: CGFloat, lineWidth: CGFloat, color: SKColor, zPosition: CGFloat = 33) {
        spawnParticle(kind: .streak, position: point, velocity: velocity, gravity: 0, drag: drag, life: life, radius: 0,
                      vr: 0, length: length, lineWidth: lineWidth, color: color, rotation: 0, angularVelocity: 0,
                      seed: 0, hot: false, blend: .add, zPosition: zPosition)
    }

    func spawnEmber(at point: CGPoint, velocity: CGVector, gravity: CGFloat, drag: CGFloat, life: CGFloat, radius: CGFloat, color: SKColor, zPosition: CGFloat = 34) {
        spawnParticle(kind: .ember, position: point, velocity: velocity, gravity: gravity, drag: drag, life: life,
                      radius: radius, vr: 0, length: 0, lineWidth: 0, color: color, rotation: 0, angularVelocity: 0,
                      seed: CGFloat.random(in: 0...(2 * .pi)), hot: false, blend: .add, zPosition: zPosition)
    }

    func spawnSmoke(at point: CGPoint, velocity: CGVector, gravity: CGFloat, drag: CGFloat, life: CGFloat, radius: CGFloat, growthRate: CGFloat, zPosition: CGFloat = 25) {
        spawnParticle(kind: .smoke, position: point, velocity: velocity, gravity: gravity, drag: drag, life: life,
                      radius: radius, vr: growthRate, length: 0, lineWidth: 0, color: .black, rotation: 0, angularVelocity: 0,
                      seed: CGFloat.random(in: 0...(2 * .pi)), hot: false, blend: .alpha, zPosition: zPosition)
    }

    func spawnShard(at point: CGPoint, velocity: CGVector, gravity: CGFloat, drag: CGFloat, life: CGFloat, radius: CGFloat, color: SKColor, hot: Bool = false, zPosition: CGFloat = 36) {
        spawnParticle(kind: .shard, position: point, velocity: velocity, gravity: gravity, drag: drag, life: life,
                      radius: radius, vr: 0, length: 0, lineWidth: 0, color: color, rotation: CGFloat.random(in: 0...(2 * .pi)),
                      angularVelocity: CGFloat.random(in: -13...13), seed: 0, hot: hot, blend: .add, zPosition: zPosition)
    }

    // MARK: Composite spawns (mirror `_spawnTap` / `_spawnSolveFX`)

    func spawnTapEffect(at point: CGPoint, nodeRadius: CGFloat, accent: SKColor) {
        for _ in 0..<9 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 40...150)
            spawnSpark(at: point, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                       drag: 3, life: CGFloat.random(in: 0.25...0.5), radius: CGFloat.random(in: 1.4...3), color: accent)
        }
        spawnRing(at: point, radius: nodeRadius * 0.6, growthRate: 190, life: 0.4, color: accent, lineWidth: 2)
    }

    func burstShards(at point: CGPoint, count: Int, color: SKColor) {
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 120...470)
            spawnShard(at: point, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                       gravity: 210, drag: 0.6, life: CGFloat.random(in: 0.7...1.6), radius: CGFloat.random(in: 3...8), color: color)
        }
    }

    // MARK: Ambient motes

    func spawnMote(near point: CGPoint, minRadius: CGFloat, maxRadius: CGFloat, color: SKColor) {
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let r = CGFloat.random(in: minRadius...maxRadius)
        let origin = CGPoint(x: point.x + cos(angle) * r, y: point.y + sin(angle) * r)
        spawnEmber(at: origin, velocity: CGVector(dx: CGFloat.random(in: -6...6), dy: CGFloat.random(in: -12...(-2))),
                   gravity: 0, drag: 0.15, life: CGFloat.random(in: 2...5), radius: CGFloat.random(in: 1...2.4), color: color.withAlphaComponent(0.5), zPosition: 5)
    }

    // MARK: Housekeeping

    func removeAll() {
        for p in particles { p.node.removeFromParent() }
        particles.removeAll()
    }
}
