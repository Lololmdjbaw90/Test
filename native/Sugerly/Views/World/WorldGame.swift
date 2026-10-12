import SceneKit
import UIKit
import simd

// Sugar World itself: a candy plaza with cotton-candy trees, little houses,
// trampolines, a cloud island, balls and blocks you can knock around, and a
// spiral tower to climb for a daily star. You walk with the stick, jump with
// the button and drag anywhere else to turn the camera.
@MainActor
final class WorldGame: NSObject, UIGestureRecognizerDelegate {
    let view = SCNView(frame: .zero)
    let scene = SCNScene()
    let net: WorldNet
    let me = Avatar3D()

    // From the screen.
    var stick = SIMD2<Float>(0, 0)
    var onStar: (() -> Void)?
    var onBounce: (() -> Void)?
    var onTapPlayer: ((String) -> Void)?
    var onChatLine: ((String, String) -> Void)?
    var onJoined: ((WorldNet.Player) -> Void)?

    // Feel: speeds and gravity in body units per second.
    private let walkSpeed: Float = 16
    private let jumpSpeed: Float = 50
    private let gravity: Float = 150
    private let radius: Float = 1.0
    private let height: Float = 5.0

    private(set) var pos = SIMD3<Float>(0, 0.05, 16)
    private var vel = SIMD3<Float>(0, 0, 0)
    private var yaw: Float = .pi
    private var grounded = true
    private var lastGrounded: CFTimeInterval = 0
    private var jumpAt: CFTimeInterval = 0
    private let spawn = SIMD3<Float>(0, 0.05, 16)

    // Follow position, but keep the heading chosen by the player's drag.
    // Movement is camera-relative, so steering the camera towards velocity
    // would keep turning both the camera and the player during a strafe.
    private var camYaw: Float = 0
    private var camPitch: Float = 0.3
    private var camDistance: Float = 14
    private var shownDistance: Float = 14
    private var camFocus = SIMD3<Float>(0, 4.5, 16)
    private var panTouchCount = 0
    private let cameraNode = SCNNode()
    private let sun = SCNNode()

    struct Solid {
        var lo: SIMD3<Float>
        var hi: SIMD3<Float>
        var bounce: Float = 0
    }
    private var solids: [Solid] = []

    @MainActor
    private final class Remote {
        let avatar = Avatar3D()
        var tag: SCNNode?
        var bubble: SCNNode?
        var snaps: [(t: CFTimeInterval, pose: WorldNet.Pose)] = []
    }
    private var remotes: [String: Remote] = [:]
    private var myBubble: SCNNode?

    private var star: SCNNode?
    private var starPos = SIMD3<Float>(0, 0, 0)
    private var starTaken = false
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var lastSend: CFTimeInterval = 0
    private var clock: Float = 0

    init(net: WorldNet, look: AvatarLook) {
        self.net = net
        super.init()
        setUpView()
        buildWorld()
        me.apply(look)
        me.root.position = SCNVector3(pos.x, pos.y, pos.z)
        me.root.eulerAngles.y = yaw
        me.root.physicsBody = Self.bodyShape(kinematic: true)
        scene.rootNode.addChildNode(me.root)
        snapCameraToPlayer()
        starTaken = WorldRewards.claimedToday
        star?.isHidden = starTaken
        net.onPose = { [weak self] id, pose in self?.gotPose(id, pose) }
        net.onLook = { [weak self] id, look in self?.remote(id).avatar.apply(look) }
        net.onLeave = { [weak self] id in self?.removeRemote(id) }
        net.onEmote = { [weak self] id, name in
            guard let self, let emote = Avatar3D.Emote(rawValue: name) else { return }
            self.remote(id).avatar.play(emote)
        }
        net.onJoin = { [weak self] player in self?.onJoined?(player) }
        net.onChat = { [weak self] id, text in
            self?.say(text, from: id)
            self?.onChatLine?(id, text)
        }
    }

    // MARK: running

    func start() {
        guard link == nil else { return }
        let target = FrameTarget { [weak self] in self?.frame() }
        let link = CADisplayLink(target: target, selector: #selector(FrameTarget.step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastFrame = CACurrentMediaTime()
        view.isPlaying = true
    }

    func stop() {
        link?.invalidate()
        link = nil
        view.isPlaying = false
    }

    func jump() { jumpAt = CACurrentMediaTime() }

    // Wave, dance, cheer or sit (everyone sees it); walking stops it.
    func emote(_ e: Avatar3D.Emote) {
        me.play(e)
        net.emote(e.rawValue)
    }

    func turnCamera(dx: Float, dy: Float) {
        camYaw -= dx * 0.0065
        camPitch = min(1.3, max(-0.3, camPitch + dy * 0.005))
    }

    func zoom(_ scale: Float) {
        camDistance = min(40, max(6, camDistance / max(scale, 0.01)))
    }

    func wear(_ look: AvatarLook) {
        me.apply(look)
        net.updateLook(look)
    }

    func respawn() {
        pos = spawn
        vel = .zero
        snapCameraToPlayer()
    }

    // Who's under a tap, if anyone.
    func player(at point: CGPoint) -> String? {
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node {
                if let id = remotes.first(where: { $0.value.avatar.root === n })?.key { return id }
                node = n.parent
            }
        }
        return nil
    }

    // MARK: each frame

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = Float(min(1.0 / 20.0, max(0.0, now - lastFrame)))
        lastFrame = now
        clock += dt
        movePlayer(dt, now: now)
        moveCamera(dt)
        moveOthers(dt, now: now)
        if now - lastSend > 1.0 / 12.0 {
            lastSend = now
            let flat = SIMD2<Float>(vel.x, vel.z)
            net.send(WorldNet.Pose(pos: pos, yaw: yaw, speed: min(1, simd_length(flat) / walkSpeed), air: !grounded))
        }
        checkStar()
    }

    private func movePlayer(_ dt: Float, now: CFTimeInterval) {
        let forward = SIMD3<Float>(-sin(camYaw), 0, -cos(camYaw))
        let right = SIMD3<Float>(cos(camYaw), 0, -sin(camYaw))
        var move = right * stick.x + forward * stick.y
        let amount = min(1, simd_length(move))
        if amount > 0.001 { move = simd_normalize(move) * amount }
        let accel: Float = grounded ? 16 : 7
        let k = min(1, accel * dt)
        vel.x += (move.x * walkSpeed - vel.x) * k
        vel.z += (move.z * walkSpeed - vel.z) * k

        // A jump pressed a moment early, or just after walking off an edge, still counts.
        if now - jumpAt < 0.15 && (grounded || now - lastGrounded < 0.12) {
            vel.y = jumpSpeed
            grounded = false
            jumpAt = 0
            lastGrounded = 0
        }
        vel.y = max(vel.y - gravity * dt, -140)
        collide(vel * dt, now: now)
        if pos.y < -60 { respawn() }

        if amount > 0.1 {
            let want = atan2(move.x, move.z)
            yaw = Self.turn(yaw, toward: want, by: min(1, dt * 12))
        }
        me.root.position = SCNVector3(pos.x, pos.y, pos.z)
        me.root.eulerAngles.y = yaw
        let flat = SIMD2<Float>(vel.x, vel.z)
        me.animate(speed: min(1, simd_length(flat) / walkSpeed), airborne: !grounded, dt: dt, time: clock)
        sun.position = SCNVector3(pos.x, pos.y, pos.z)
    }

    private func snapCameraToPlayer() {
        camFocus = pos + SIMD3<Float>(0, 4.5, 0)
        shownDistance = camDistance
        moveCamera(0)
    }

    private func moveCamera(_ dt: Float) {
        let target = pos + SIMD3<Float>(0, 4.5, 0)
        camFocus += (target - camFocus) * min(1, dt * 18)
        let flat = cos(camPitch) * camDistance
        let offset = SIMD3<Float>(sin(camYaw) * flat, sin(camPitch) * camDistance, cos(camYaw) * flat)
        let length = max(0.001, simd_length(offset))
        let direction = offset / length

        // Something in the way: come in front of it (and ease back out).
        var wanted = camDistance
        for s in solids {
            if let t = Self.rayHit(camFocus, direction, s, limit: camDistance) {
                // The zoom limit must not push the eye back through a wall
                // when the player is standing close to it.
                wanted = min(wanted, max(0.05, t - 0.4))
            }
        }
        shownDistance = wanted < shownDistance ? wanted : shownDistance + (wanted - shownDistance) * min(1, dt * 5)
        var eye = camFocus + direction * shownDistance
        eye.y = max(eye.y, 0.8)
        cameraNode.position = SCNVector3(eye.x, eye.y, eye.z)
        cameraNode.look(at: SCNVector3(camFocus.x, camFocus.y, camFocus.z))
    }

    // Where a ray first enters a box (nil if it misses it before `limit`).
    private static func rayHit(_ origin: SIMD3<Float>, _ dir: SIMD3<Float>, _ s: Solid, limit: Float) -> Float? {
        var near: Float = 0
        var far = limit
        for i in 0..<3 {
            let o = origin[i], d = dir[i]
            if abs(d) < 0.000001 {
                if o < s.lo[i] || o > s.hi[i] { return nil }
                continue
            }
            var t1 = (s.lo[i] - o) / d
            var t2 = (s.hi[i] - o) / d
            if t1 > t2 { swap(&t1, &t2) }
            near = max(near, t1)
            far = min(far, t2)
            if near > far { return nil }
        }
        // Starting inside the box (your head in a doorway) doesn't count.
        return near > 0.05 ? near : nil
    }

    // Others are drawn a little in the past, smoothly between their updates.
    private func moveOthers(_ dt: Float, now: CFTimeInterval) {
        let shownAt = now - 0.15
        for (_, r) in remotes {
            guard let latest = r.snaps.last else { continue }
            var p = latest.pose.pos
            var facing = latest.pose.yaw
            if let i = r.snaps.lastIndex(where: { $0.t <= shownAt }), i + 1 < r.snaps.count {
                let a = r.snaps[i], b = r.snaps[i + 1]
                let span = max(0.001, b.t - a.t)
                let k = Float(min(1, max(0, (shownAt - a.t) / span)))
                p = simd_mix(a.pose.pos, b.pose.pos, SIMD3<Float>(repeating: k))
                facing = Self.turn(a.pose.yaw, toward: b.pose.yaw, by: k)
                if i > 0 { r.snaps.removeFirst(i) }
            }
            r.avatar.root.position = SCNVector3(p.x, p.y, p.z)
            r.avatar.root.eulerAngles.y = facing
            r.avatar.animate(speed: latest.pose.speed, airborne: latest.pose.air, dt: dt, time: clock)
        }
    }

    // MARK: bumping into things

    private func hit(_ p: SIMD3<Float>) -> Solid? {
        for s in solids {
            if p.x + radius > s.lo.x && p.x - radius < s.hi.x
                && p.y + height > s.lo.y && p.y < s.hi.y
                && p.z + radius > s.lo.z && p.z - radius < s.hi.z { return s }
        }
        return nil
    }

    // Small ledges (stairs, kerbs) are walked up instead of blocking you.
    private func stepUp(_ s: Solid) -> Bool {
        let rise = s.hi.y - pos.y
        guard grounded, rise > 0, rise <= 1.3 else { return false }
        var p = pos
        p.y = s.hi.y + 0.001
        guard hit(p) == nil else { return false }
        pos = p
        return true
    }

    private func collide(_ delta: SIMD3<Float>, now: CFTimeInterval) {
        let steps = max(1, Int(ceil(simd_length(delta) / 0.45)))
        let d = delta / Float(steps)
        var landed = false
        for _ in 0..<steps {
            if d.x != 0 {
                pos.x += d.x
                if let s = hit(pos), !stepUp(s) {
                    pos.x = d.x > 0 ? s.lo.x - radius - 0.001 : s.hi.x + radius + 0.001
                    vel.x = 0
                }
            }
            if d.z != 0 {
                pos.z += d.z
                if let s = hit(pos), !stepUp(s) {
                    pos.z = d.z > 0 ? s.lo.z - radius - 0.001 : s.hi.z + radius + 0.001
                    vel.z = 0
                }
            }
            pos.y += d.y
            if let s = hit(pos) {
                if d.y <= 0 {
                    pos.y = s.hi.y
                    if s.bounce > 0 {
                        vel.y = s.bounce
                        onBounce?()
                        break
                    }
                    vel.y = 0
                    landed = true
                } else {
                    pos.y = s.lo.y - height - 0.001
                    vel.y = min(vel.y, 0)
                }
            }
        }
        grounded = landed
        if landed { lastGrounded = now }
    }

    private static func turn(_ from: Float, toward to: Float, by k: Float) -> Float {
        var diff = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if diff > .pi { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        return from + diff * k
    }

    // MARK: the daily star

    private func checkStar() {
        guard !starTaken, let star else { return }
        let body = pos + SIMD3<Float>(0, 2.5, 0)
        guard simd_distance(body, starPos) < 3.5 else { return }
        starTaken = true
        star.runAction(.sequence([.group([.scale(to: 2.2, duration: 0.35), .fadeOut(duration: 0.35)]), .hide()]))
        onStar?()
    }

    // MARK: other players

    private func remote(_ id: String) -> Remote {
        if let r = remotes[id] { return r }
        let r = Remote()
        let info = net.players[id]
        r.avatar.apply(info?.look ?? .starter)
        r.avatar.root.physicsBody = Self.bodyShape(kinematic: true)
        let tag = WorldLabels.tag(info?.name ?? "Player")
        tag.position = SCNVector3(0, 6.5, 0)
        r.avatar.root.addChildNode(tag)
        r.tag = tag
        r.avatar.root.opacity = 0
        r.avatar.root.runAction(.fadeIn(duration: 0.35))
        scene.rootNode.addChildNode(r.avatar.root)
        remotes[id] = r
        return r
    }

    private func gotPose(_ id: String, _ pose: WorldNet.Pose) {
        let r = remote(id)
        if r.snaps.isEmpty { r.avatar.root.position = SCNVector3(pose.pos.x, pose.pos.y, pose.pos.z) }
        r.snaps.append((CACurrentMediaTime(), pose))
        if r.snaps.count > 40 { r.snaps.removeFirst(r.snaps.count - 40) }
    }

    private func removeRemote(_ id: String) {
        guard let r = remotes.removeValue(forKey: id) else { return }
        r.avatar.root.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
    }

    // A speech bubble over someone's head (you too) for a few seconds.
    func say(_ text: String, from id: String?) {
        let bubble = WorldLabels.bubble(text)
        let owner: SCNNode
        if let id {
            let r = remote(id)
            r.bubble?.removeFromParentNode()
            r.bubble = bubble
            owner = r.avatar.root
        } else {
            myBubble?.removeFromParentNode()
            myBubble = bubble
            owner = me.root
        }
        bubble.position = SCNVector3(0, id == nil ? 6.6 : 7.7, 0)
        bubble.opacity = 0
        owner.addChildNode(bubble)
        bubble.runAction(.sequence([.fadeIn(duration: 0.2), .wait(duration: 7), .fadeOut(duration: 0.4), .removeFromParentNode()]))
    }

    // MARK: setting up

    private static func bodyShape(kinematic: Bool) -> SCNPhysicsBody {
        let box = SCNBox(width: 2.6, height: 5, length: 1.6, chamferRadius: 0)
        let shape = SCNPhysicsShape(shapes: [SCNPhysicsShape(geometry: box, options: nil)],
                                    transforms: [NSValue(scnMatrix4: SCNMatrix4MakeTranslation(0, 2.5, 0))])
        let body = SCNPhysicsBody(type: kinematic ? .kinematic : .dynamic, shape: shape)
        body.categoryBitMask = 2
        return body
    }

    private func setUpView() {
        view.scene = scene
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isMultipleTouchEnabled = true
        view.allowsCameraControl = false
        view.backgroundColor = UIColor(hex: 0xFFE3F0)
        view.hideGraphicsHUD()

        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.3
        camera.zFar = 600
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        // Keep the pan alive through a pinch so the remaining finger can
        // resume looking without having to lift and touch the screen again.
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: pan)
        tap.require(toFail: pinch)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer.view === view, otherGestureRecognizer.view === view else { return false }
        return (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
            || (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let touches = g.numberOfTouches
        let translation = g.translation(in: view)
        defer { g.setTranslation(.zero, in: view) }
        switch g.state {
        case .began:
            panTouchCount = touches
        case .changed:
            // Adding/removing a finger moves the gesture's centre. Discard
            // that sample, and never turn while two fingers are zooming.
            if touches == 1 && panTouchCount == 1 {
                turnCamera(dx: Float(translation.x), dy: Float(translation.y))
            }
            panTouchCount = touches
        case .ended, .cancelled, .failed:
            panTouchCount = 0
        default: break
        }
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard g.state == .began || g.state == .changed else { return }
        zoom(Float(g.scale))
        g.scale = 1
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        if let id = player(at: g.location(in: view)) { onTapPlayer?(id) }
    }

    private func buildWorld() {
        scene.background.contents = WorldLabels.sky()
        scene.fogStartDistance = 140
        scene.fogEndDistance = 320
        scene.fogColor = UIColor(hex: 0xFFE3F0)
        scene.physicsWorld.gravity = SCNVector3(0, -70, 0)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(hex: 0xFFF4F8)
        scene.rootNode.addChildNode(ambient)

        let light = SCNLight()
        light.type = .directional
        light.intensity = 900
        light.color = UIColor(hex: 0xFFF8EE)
        light.castsShadow = true
        light.shadowMode = .forward
        light.shadowSampleCount = 4
        light.shadowRadius = 3
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.orthographicScale = 70
        light.shadowColor = UIColor(white: 0, alpha: 0.22)
        light.automaticallyAdjustsShadowProjection = false
        light.zNear = 1
        light.zFar = 300
        let lamp = SCNNode()
        lamp.light = light
        lamp.position = SCNVector3(0, 0, 0)
        lamp.eulerAngles = SCNVector3(-1.05, 0.55, 0)
        // The light's own node sits back along its direction.
        let holder = SCNNode()
        holder.addChildNode(lamp)
        lamp.position = SCNVector3(26, 87, 43)
        sun.addChildNode(holder)
        scene.rootNode.addChildNode(sun)

        // Grass, the plaza and its path ring.
        block(SIMD3(-130, -4, -130), SIMD3(130, 0, 130), 0xC4EED0, chamfer: 0)
        decor(SCNCylinder(radius: 26, height: 0.06), 0xFFE1EC, at: SIMD3(0, 0.03, 0))
        decor(SCNTube(innerRadius: 26, outerRadius: 28, height: 0.08), 0xFFC6DA, at: SIMD3(0, 0.04, 0))
        let dots: [UInt32] = [0xFFFFFF, 0xFFD166, 0xF7A1C4]
        for i in 0..<14 {
            let a = Float(i) / 14 * 2 * .pi
            decor(SCNSphere(radius: 0.45), dots[i % 3], at: SIMD3(cos(a) * 30, 0.3, sin(a) * 30))
        }

        // Mimi on her pedestal in the middle.
        block(SIMD3(-4, 0, -4), SIMD3(4, 2.4, 4), 0xFFFFFF)
        block(SIMD3(-4.6, 0, -4.6), SIMD3(4.6, 0.8, 4.6), 0xF7A1C4)
        if let mimi = UIImage(named: "MimiRose") {
            let h: CGFloat = 11
            let plane = SCNPlane(width: h * mimi.size.width / max(1, mimi.size.height), height: h)
            let m = SCNMaterial()
            m.diffuse.contents = mimi
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.transparencyMode = .aOne
            plane.materials = [m]
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(0, 2.4 + Float(h) / 2, 0)
            let face = SCNBillboardConstraint()
            face.freeAxes = .Y
            node.constraints = [face]
            scene.rootNode.addChildNode(node)
            solids.append(Solid(lo: SIMD3(-1.8, 2.4, -1.8), hi: SIMD3(1.8, 12, 1.8)))
        }

        // Cotton-candy trees all around.
        let foliage: [UInt32] = [0xF7A1C4, 0xC9B6FF, 0xA8E6CF, 0xFFD6A5, 0xA9D6FF]
        var seed: UInt64 = 7
        func random() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 33) / Float(UInt32.max >> 1)
        }
        for i in 0..<34 {
            let a = Float(i) / 34 * 2 * .pi + random() * 0.15
            let r: Float = 42 + random() * 70
            let p = SIMD3<Float>(cos(a) * r, 0, sin(a) * r)
            if simd_distance(p, SIMD3(40, 0, 30)) < 18 || simd_distance(p, SIMD3(-20, 0, 2)) < 16 { continue }
            tree(at: p, color: foliage[i % foliage.count], size: 0.8 + random() * 0.6)
        }

        // Little houses.
        house(at: SIMD3(-52, 0, -34), wall: 0xFFF1E6, roof: 0xF27BA3)
        house(at: SIMD3(54, 0, -40), wall: 0xEAF6FF, roof: 0x7C5CF0)
        house(at: SIMD3(-56, 0, 46), wall: 0xF0FFF6, roof: 0x16A37F)

        // The spiral tower: hop up the candy steps to the star on top.
        let towerAt = SIMD3<Float>(40, 0, 30)
        let steps = 15
        let topY: Float = 2.5 + Float(steps - 1) * 3.0 + 2.5
        block(SIMD3(towerAt.x - 2.6, 0, towerAt.z - 2.6), SIMD3(towerAt.x + 2.6, topY - 1, towerAt.z + 2.6), 0xFFFFFF)
        block(SIMD3(towerAt.x - 5, topY - 1, towerAt.z - 5), SIMD3(towerAt.x + 5, topY, towerAt.z + 5), 0xFFD166)
        let candy: [UInt32] = [0xF27BA3, 0xB19CFF, 0x5FD3B0, 0x7CBEFF, 0xFFAA80]
        for i in 0..<steps {
            let a = Float(i) * 0.62 + 2.2
            let c = towerAt + SIMD3<Float>(cos(a) * 10, 0, sin(a) * 10)
            let top: Float = 2.5 + Float(i) * 3.0
            let half: Float = i % 4 == 3 ? 2.0 : 2.6
            block(SIMD3(c.x - half, top - 1, c.z - half), SIMD3(c.x + half, top, c.z + half), candy[i % candy.count])
        }
        starPos = SIMD3(towerAt.x, topY + 2.5, towerAt.z)
        let starNode = WorldLabels.starNode()
        starNode.position = SCNVector3(starPos.x, starPos.y, starPos.z)
        scene.rootNode.addChildNode(starNode)
        star = starNode

        // Trampolines up to the cloud island.
        trampoline(at: SIMD3(-20, 0, 12))
        trampoline(at: SIMD3(-31, 0, 2))
        block(SIMD3(-27, 27, -14), SIMD3(-13, 29, -2), 0xFFFFFF, chamfer: 0.9)
        for (x, z) in [(-24, -11), (-16, -5), (-21, -4)] as [(Float, Float)] {
            decor(SCNSphere(radius: 2.4), 0xFFFFFF, at: SIMD3(x, 29.2, z))
        }
        tree(at: SIMD3(-18, 29, -10), color: 0xF7A1C4, size: 0.7)

        // Balls and blocks to knock around.
        let palettes: [[UInt32]] = [[0xF27BA3, 0xFFFFFF, 0xFFD166], [0x7CBEFF, 0xFFFFFF, 0x5FD3B0], [0xB19CFF, 0xFFFFFF, 0xFFAA80]]
        let spots: [SIMD3<Float>] = [SIMD3(8, 3, 4), SIMD3(-9, 3, 6), SIMD3(5, 3, -12)]
        for (i, p) in spots.enumerated() { ball(at: p, colors: palettes[i]) }
        for row in 0..<3 {
            for col in 0..<(3 - row) {
                let x = Float(14) + Float(col) * 2.1 + Float(row) * 1.05
                let y = Float(1) + Float(row) * 2.05
                crate(at: SIMD3(x, y, -8), color: candy[(row + col) % candy.count])
            }
        }

        // Soft walls at the edge of the world.
        let edge: Float = 124
        solids.append(Solid(lo: SIMD3(-edge - 4, -10, -edge - 4), hi: SIMD3(-edge, 200, edge + 4)))
        solids.append(Solid(lo: SIMD3(edge, -10, -edge - 4), hi: SIMD3(edge + 4, 200, edge + 4)))
        solids.append(Solid(lo: SIMD3(-edge - 4, -10, -edge - 4), hi: SIMD3(edge + 4, 200, -edge)))
        solids.append(Solid(lo: SIMD3(-edge - 4, -10, edge), hi: SIMD3(edge + 4, 200, edge + 4)))

        // Clouds drifting high up.
        for i in 0..<9 {
            let a = Float(i) / 9 * 2 * .pi
            let cloud = SCNNode()
            for k in 0..<4 {
                let puff = SCNNode(geometry: Self.solidColor(SCNSphere(radius: CGFloat(5 + k % 2 * 2)), 0xFFFFFF, lit: false))
                puff.position = SCNVector3(Float(k) * 5 - 7, Float(k % 2) * 2, 0)
                cloud.addChildNode(puff)
            }
            cloud.position = SCNVector3(cos(a) * 140, 70 + Float(i % 3) * 12, sin(a) * 140)
            cloud.runAction(.repeatForever(.sequence([.moveBy(x: 12, y: 0, z: 4, duration: 14), .moveBy(x: -12, y: 0, z: -4, duration: 14)])))
            scene.rootNode.addChildNode(cloud)
        }
    }

    private static func solidColor(_ g: SCNGeometry, _ hex: UInt32, lit: Bool = true) -> SCNGeometry {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex)
        m.lightingModel = lit ? .lambert : .constant
        g.materials = [m]
        return g
    }

    @discardableResult
    private func block(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>, _ hex: UInt32, chamfer: CGFloat = 0.25, bounce: Float = 0) -> SCNNode {
        let size = hi - lo
        let c = (lo + hi) / 2
        let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: min(chamfer, CGFloat(min(size.x, min(size.y, size.z))) / 2))
        let node = SCNNode(geometry: Self.solidColor(box, hex))
        node.position = SCNVector3(c.x, c.y, c.z)
        node.castsShadow = true
        node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        scene.rootNode.addChildNode(node)
        solids.append(Solid(lo: lo, hi: hi, bounce: bounce))
        return node
    }

    private func decor(_ g: SCNGeometry, _ hex: UInt32, at p: SIMD3<Float>) {
        let node = SCNNode(geometry: Self.solidColor(g, hex))
        node.position = SCNVector3(p.x, p.y, p.z)
        scene.rootNode.addChildNode(node)
    }

    private func tree(at p: SIMD3<Float>, color: UInt32, size: Float) {
        let trunkH = 5 * size
        let trunk = SCNNode(geometry: Self.solidColor(SCNCylinder(radius: CGFloat(0.7 * size), height: CGFloat(trunkH)), 0xC79A7B))
        trunk.position = SCNVector3(p.x, p.y + trunkH / 2, p.z)
        trunk.castsShadow = true
        trunk.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        scene.rootNode.addChildNode(trunk)
        for (dx, dy, r) in [(0, 1.0, 3.4), (-1.6, 0.2, 2.4), (1.7, 0.4, 2.5), (0.2, 2.6, 2.4)] as [(Float, Float, Float)] {
            let puff = SCNNode(geometry: Self.solidColor(SCNSphere(radius: CGFloat(r * size)), color))
            puff.position = SCNVector3(p.x + dx * size, p.y + trunkH + dy * size, p.z)
            puff.castsShadow = true
            scene.rootNode.addChildNode(puff)
        }
        let w = 0.8 * size
        solids.append(Solid(lo: SIMD3(p.x - w, p.y, p.z - w), hi: SIMD3(p.x + w, p.y + trunkH, p.z + w)))
    }

    private func house(at p: SIMD3<Float>, wall: UInt32, roof: UInt32) {
        block(SIMD3(p.x - 7, p.y, p.z - 6), SIMD3(p.x + 7, p.y + 9, p.z + 6), wall, chamfer: 0.4)
        let top = SCNNode(geometry: Self.solidColor(SCNPyramid(width: 16, height: 6, length: 14), roof))
        top.position = SCNVector3(p.x, p.y + 9, p.z)
        top.castsShadow = true
        scene.rootNode.addChildNode(top)
        solids.append(Solid(lo: SIMD3(p.x - 4, p.y + 9, p.z - 3), hi: SIMD3(p.x + 4, p.y + 12, p.z + 3)))
        let door = SCNNode(geometry: Self.solidColor(SCNBox(width: 3, height: 5, length: 0.3, chamferRadius: 0.2), roof))
        door.position = SCNVector3(p.x, p.y + 2.5, p.z + 6.1)
        scene.rootNode.addChildNode(door)
        for side in [-1, 1] as [Float] {
            let window = SCNNode(geometry: Self.solidColor(SCNBox(width: 2.4, height: 2.4, length: 0.3, chamferRadius: 0.3), 0xBFE3FF))
            window.position = SCNVector3(p.x + side * 4, p.y + 5.5, p.z + 6.1)
            scene.rootNode.addChildNode(window)
        }
    }

    private func trampoline(at p: SIMD3<Float>) {
        let base = SCNNode(geometry: Self.solidColor(SCNCylinder(radius: 2.8, height: 0.9), 0xFFFFFF))
        base.position = SCNVector3(p.x, p.y + 0.45, p.z)
        base.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        scene.rootNode.addChildNode(base)
        let pad = SCNNode(geometry: Self.solidColor(SCNCylinder(radius: 2.4, height: 0.1), 0xF27BA3))
        pad.position = SCNVector3(p.x, p.y + 0.95, p.z)
        scene.rootNode.addChildNode(pad)
        solids.append(Solid(lo: SIMD3(p.x - 2.5, p.y, p.z - 2.5), hi: SIMD3(p.x + 2.5, p.y + 1, p.z + 2.5), bounce: 95))
    }

    private func ball(at p: SIMD3<Float>, colors: [UInt32]) {
        let sphere = SCNSphere(radius: 1.6)
        let m = SCNMaterial()
        m.diffuse.contents = WorldLabels.stripes(colors)
        m.lightingModel = .lambert
        sphere.materials = [m]
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(p.x, p.y, p.z)
        node.castsShadow = true
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: sphere, options: nil))
        body.mass = 0.4
        body.restitution = 0.75
        body.friction = 0.4
        body.rollingFriction = 0.05
        body.damping = 0.15
        node.physicsBody = body
        scene.rootNode.addChildNode(node)
    }

    private func crate(at p: SIMD3<Float>, color: UInt32) {
        let box = SCNBox(width: 2, height: 2, length: 2, chamferRadius: 0.3)
        let node = SCNNode(geometry: Self.solidColor(box, color))
        node.position = SCNVector3(p.x, p.y, p.z)
        node.castsShadow = true
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: box, options: nil))
        body.mass = 0.6
        body.restitution = 0.2
        body.friction = 0.7
        node.physicsBody = body
        scene.rootNode.addChildNode(node)
    }
}

// CADisplayLink keeps a strong hold on its target, so the game isn't the target.
private final class FrameTarget: NSObject {
    let tick: @MainActor () -> Void
    init(_ tick: @escaping @MainActor () -> Void) { self.tick = tick }
    @objc func step() { MainActor.assumeIsolated { tick() } }
}

// Once a day, climbing the tower to the star gives coins.
enum WorldRewards {
    static let coins = 15
    private static var key: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "sugarworld.star." + f.string(from: Date())
    }
    static var claimedToday: Bool { UserDefaults.standard.bool(forKey: key) }
    static func claim() { UserDefaults.standard.set(true, forKey: key) }
}

// Name tags, speech bubbles, the sky, ball stripes and the star.
@MainActor
enum WorldLabels {
    private static func plane(_ image: UIImage, height: CGFloat) -> SCNNode {
        let w = height * image.size.width / max(1, image.size.height)
        let plane = SCNPlane(width: w, height: height)
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.renderingOrder = 20
        node.constraints = [SCNBillboardConstraint()]
        node.castsShadow = false
        return node
    }

    static func tag(_ name: String) -> SCNNode {
        let font = UIFont.systemFont(ofSize: 34, weight: .heavy)
        let text = String(name.prefix(24)) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(hex: 0x3A2440)]
        let size = text.size(withAttributes: attrs)
        let box = CGSize(width: ceil(size.width) + 40, height: 58)
        let image = UIGraphicsImageRenderer(size: box).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: box), cornerRadius: 29)
            UIColor.white.withAlphaComponent(0.88).setFill()
            path.fill()
            text.draw(at: CGPoint(x: 20, y: (58 - size.height) / 2), withAttributes: attrs)
        }
        return plane(image, height: 0.9)
    }

    static func bubble(_ message: String) -> SCNNode {
        let font = UIFont.systemFont(ofSize: 30, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(hex: 0x2A1F33), .paragraphStyle: paragraph]
        let text = message as NSString
        let bounds = text.boundingRect(with: CGSize(width: 360, height: 400), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        let body = CGSize(width: max(80, ceil(bounds.width) + 44), height: ceil(bounds.height) + 32)
        let full = CGSize(width: body.width, height: body.height + 18)
        let image = UIGraphicsImageRenderer(size: full).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: body), cornerRadius: 24)
            path.move(to: CGPoint(x: body.width / 2 - 14, y: body.height - 1))
            path.addLine(to: CGPoint(x: body.width / 2, y: full.height))
            path.addLine(to: CGPoint(x: body.width / 2 + 14, y: body.height - 1))
            UIColor.white.setFill()
            path.fill()
            UIColor(hex: 0xF7A1C4).setStroke()
            path.lineWidth = 3
            path.stroke()
            text.draw(with: CGRect(x: 22, y: 16, width: body.width - 44, height: bounds.height + 4), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        }
        return plane(image, height: full.height / 60)
    }

    static func sky() -> UIImage {
        let size = CGSize(width: 16, height: 512)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(hex: 0x8FD0FF).cgColor, UIColor(hex: 0xCFE9FF).cgColor, UIColor(hex: 0xFFE3F0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    static func stripes(_ colors: [UInt32]) -> UIImage {
        let size = CGSize(width: 240, height: 8)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let band = size.width / 6
            for i in 0..<6 {
                UIColor(hex: colors[i % colors.count]).setFill()
                ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: band, height: size.height))
            }
        }
    }

    static func starNode() -> SCNNode {
        let path = UIBezierPath()
        for i in 0..<10 {
            let a = CGFloat(i) * .pi / 5 - .pi / 2
            let r: CGFloat = i % 2 == 0 ? 1.6 : 0.7
            let p = CGPoint(x: cos(a) * r, y: -sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.5)
        shape.chamferRadius = 0.12
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: 0xFFD166)
        m.emission.contents = UIColor(hex: 0xFFB800).withAlphaComponent(0.6)
        m.lightingModel = .lambert
        shape.materials = [m]
        let node = SCNNode(geometry: shape)
        node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3)))
        let glow = SCNNode(geometry: SCNSphere(radius: 2.2))
        let g = SCNMaterial()
        g.diffuse.contents = UIColor(hex: 0xFFE58A).withAlphaComponent(0.25)
        g.lightingModel = .constant
        glow.geometry?.materials = [g]
        node.addChildNode(glow)
        return node
    }
}
