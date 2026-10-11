import SceneKit
import simd
import UIKit

// The 3D body from BoyR6.obj: six blocks (head, body, two arms, two legs).
// The file's blocks carry no picture mapping, so each one is unfolded here
// like a box (ClothTemplate.Net) and clothes from the template are copied
// side by side into that. Faces point +Z; the feet stand on y = 0.

struct AvatarMesh {
    struct Part {
        let part: BodyPart
        let geometry: SCNGeometry
        let pivot: SCNVector3      // joint (shoulder, hip, neck) in model space
    }

    let parts: [BodyPart: Part]
    let feet: Float          // how far below the joints the feet are (lifted to y = 0)
    let height: Float

    @MainActor static let shared: AvatarMesh = load()

    private static func load() -> AvatarMesh {
        let url = Bundle.main.url(forResource: "BoyR6.obj", withExtension: "txt")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var faces: [String: [[(Int, Int)]]] = [:]   // object -> polygons of (position, normal) indices
        var current = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("o ") {
                current = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("v ") {
                positions.append(vector(line))
            } else if line.hasPrefix("vn ") {
                normals.append(vector(line))
            } else if line.hasPrefix("f ") {
                let corners: [(Int, Int)] = line.split(separator: " ").dropFirst().map { corner in
                    let ids = corner.split(separator: "/", omittingEmptySubsequences: false)
                    let v = Int(ids.first ?? "") ?? 0
                    let n = ids.count > 2 ? (Int(ids[2]) ?? 0) : 0
                    return (v - 1, n - 1)
                }
                faces[current, default: []].append(corners)
            }
        }
        if positions.isEmpty { return fallback() }

        let minFoot = positions.map(\.y).min() ?? 0
        let top = positions.map(\.y).max() ?? 5
        var parts: [BodyPart: Part] = [:]
        for part in BodyPart.allCases {
            guard let polys = faces[part.rawValue], !polys.isEmpty else { continue }
            let used = polys.flatMap { poly in poly.map { $0.0 } }.filter { $0 >= 0 && $0 < positions.count }.map { positions[$0] }
            let lo = used.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1) }
            let hi = used.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1) }
            let geometry = build(part, polys, positions, normals, lo, hi)
            parts[part] = Part(part: part, geometry: geometry, pivot: joint(part, lo, hi))
        }
        if parts.count < 6 { return fallback() }
        return AvatarMesh(parts: parts, feet: -minFoot, height: top - minFoot)
    }

    private static func vector(_ line: String) -> SIMD3<Float> {
        let n = line.split(separator: " ").dropFirst().compactMap { Float($0) }
        return n.count >= 3 ? SIMD3(n[0], n[1], n[2]) : .zero
    }

    // Shoulders at the top of the arms, hips at the top of the legs, the neck
    // at the bottom of the head.
    private static func joint(_ part: BodyPart, _ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> SCNVector3 {
        let mid = (lo + hi) / 2
        switch part {
        case .rightArm, .leftArm: return SCNVector3(mid.x, hi.y - 0.5, 0)
        case .rightLeg, .leftLeg: return SCNVector3(mid.x, hi.y, 0)
        case .head: return SCNVector3(0, lo.y + 0.1, 0)
        case .torso: return SCNVector3(mid.x, mid.y, 0)
        }
    }

    private static func build(_ part: BodyPart, _ polys: [[(Int, Int)]], _ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>],
                              _ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> SCNGeometry {
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var uvs: [CGPoint] = []
        let size = simd_max(hi - lo, SIMD3(repeating: 0.0001))
        let net = ClothTemplate.net(for: part)
        for poly in polys where poly.count >= 3 {
            // Fan into triangles.
            for i in 1..<(poly.count - 1) {
                let corners = [poly[0], poly[i], poly[i + 1]]
                let p = corners.map { positions.indices.contains($0.0) ? positions[$0.0] : .zero }
                var flat = simd_cross(p[1] - p[0], p[2] - p[0])
                let length = simd_length(flat)
                flat = length > 0 ? flat / length : SIMD3(0, 0, 1)
                for (k, corner) in corners.enumerated() {
                    let pos = p[k]
                    verts.append(SCNVector3(pos.x, pos.y, pos.z))
                    // The head keeps the file's soft normals; the blocks stay crisp.
                    if part == .head, normals.indices.contains(corner.1) {
                        let n = normals[corner.1]
                        norms.append(SCNVector3(n.x, n.y, n.z))
                    } else {
                        norms.append(SCNVector3(flat.x, flat.y, flat.z))
                    }
                    let rel = (pos - lo) / size
                    if let net {
                        uvs.append(boxUV(rel, flat, net))
                    } else {
                        uvs.append(CGPoint(x: CGFloat(rel.x), y: CGFloat(1 - rel.y)))
                    }
                }
            }
        }
        let indices: [Int32] = (0..<Int32(verts.count)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [
            SCNGeometrySource(vertices: verts),
            SCNGeometrySource(normals: norms),
            SCNGeometrySource(textureCoordinates: uvs),
        ], elements: [element])
    }

    // Where a point on a block lands in that block's unfolded picture (0…1).
    private static func boxUV(_ rel: SIMD3<Float>, _ n: SIMD3<Float>, _ net: ClothTemplate.Net) -> CGPoint {
        let ax = abs(n.x), ay = abs(n.y), az = abs(n.z)
        let x = CGFloat(rel.x), y = CGFloat(rel.y), z = CGFloat(rel.z)
        let face: ClothTemplate.Face
        var fu: CGFloat = 0, fv: CGFloat = 0
        if az >= ax && az >= ay {
            if n.z >= 0 { face = .front; fu = x } else { face = .back; fu = 1 - x }
            fv = 1 - y
        } else if ax >= ay {
            if n.x < 0 { face = .right; fu = z } else { face = .left; fu = 1 - z }
            fv = 1 - y
        } else {
            fu = x
            if n.y >= 0 { face = .top; fv = z } else { face = .bottom; fv = 1 - z }
        }
        let r = net.local(face)
        // Keep a hair inside the face so edges don't pick up the next one.
        fu = min(max(fu, 0.01), 0.99)
        fv = min(max(fv, 0.01), 0.99)
        return CGPoint(x: (r.minX + fu * r.width) / net.width, y: (r.minY + fv * r.height) / net.height)
    }

    // If the model file is missing: plain blocks of the same sizes.
    private static func fallback() -> AvatarMesh {
        func box(_ part: BodyPart, _ c: SIMD3<Float>, _ s: SIMD3<Float>) -> Part {
            let g = SCNBox(width: CGFloat(s.x), height: CGFloat(s.y), length: CGFloat(s.z), chamferRadius: 0.06)
            let node = SCNNode(geometry: g)
            node.position = SCNVector3(c.x, c.y, c.z)
            let flat = node.flattenedClone().geometry ?? g
            return Part(part: part, geometry: flat, pivot: joint(part, c - s / 2, c + s / 2))
        }
        let parts: [BodyPart: Part] = [
            .head: box(.head, SIMD3(0, 2.5, 0), SIMD3(1.2, 1.2, 1.2)),
            .torso: box(.torso, SIMD3(0, 1, 0), SIMD3(2, 2, 1)),
            .rightArm: box(.rightArm, SIMD3(-1.5, 1, 0), SIMD3(1, 2, 1)),
            .leftArm: box(.leftArm, SIMD3(1.5, 1, 0), SIMD3(1, 2, 1)),
            .rightLeg: box(.rightLeg, SIMD3(-0.5, -1, 0), SIMD3(1, 2, 1)),
            .leftLeg: box(.leftLeg, SIMD3(0.5, -1, 0), SIMD3(1, 2, 1)),
        ]
        return AvatarMesh(parts: parts, feet: 2, height: 5.1)
    }
}

// MARK: - pictures for each block

@MainActor
enum AvatarPaint {
    static let unit: CGFloat = 96   // pixels per body unit on the blocks

    // A block's picture: its skin colour, then pants, then the shirt on top,
    // each side copied from where it sits on the template.
    static func texture(_ part: BodyPart, look: AvatarLook, shirt: UIImage?, pants: UIImage?) -> UIImage? {
        guard let net = ClothTemplate.net(for: part), let region = ClothTemplate.region(for: part) else { return nil }
        let layers: [UIImage]
        switch part {
        case .torso: layers = [pants, shirt].compactMap { $0 }
        case .rightArm, .leftArm: layers = [shirt].compactMap { $0 }
        default: layers = [pants].compactMap { $0 }
        }
        guard !layers.isEmpty else { return nil }
        let size = CGSize(width: net.width * unit, height: net.height * unit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(hex: look.color(part)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.interpolationQuality = .high
            for layer in layers {
                guard let cg = layer.cgImage else { continue }
                // The picture may be 1×, 2× or 3× the template size.
                let sx = CGFloat(cg.width) / ClothTemplate.size.width
                let sy = CGFloat(cg.height) / ClothTemplate.size.height
                for face in ClothTemplate.Face.allCases {
                    let src = ClothTemplate.rect(region, face)
                    let crop = CGRect(x: src.minX * sx, y: src.minY * sy, width: src.width * sx, height: src.height * sy).integral
                    guard let piece = cg.cropping(to: crop) else { continue }
                    let dst = net.local(face)
                    UIImage(cgImage: piece).draw(in: CGRect(x: dst.minX * unit, y: dst.minY * unit, width: dst.width * unit, height: dst.height * unit))
                }
            }
        }
    }

    static func material(_ part: BodyPart, look: AvatarLook, shirt: UIImage?, pants: UIImage?) -> SCNMaterial {
        let m = SCNMaterial()
        if let image = texture(part, look: look, shirt: shirt, pants: pants) {
            m.diffuse.contents = image
            m.diffuse.mipFilter = .linear
            m.diffuse.wrapS = .clamp
            m.diffuse.wrapT = .clamp
        } else {
            m.diffuse.contents = UIColor(hex: look.color(part))
        }
        m.lightingModel = .lambert
        return m
    }
}

// MARK: - one avatar in the scene

@MainActor
final class Avatar3D {
    enum Emote: String, CaseIterable, Identifiable {
        case wave, dance, cheer, sit
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .wave: return "hand.wave.fill"
            case .dance: return "figure.dance"
            case .cheer: return "hands.clap.fill"
            case .sit: return "chair.fill"
            }
        }
    }

    let root = SCNNode()
    private(set) var look = AvatarLook()
    private var limbs: [BodyPart: SCNNode] = [:]
    private let model = SCNNode()
    private var dressing: Task<Void, Never>?
    private var phase: Float = 0
    private(set) var emote: Emote?
    private var emoteClock: Float = 0

    init() {
        let mesh = AvatarMesh.shared
        model.position = SCNVector3(0, mesh.feet, 0)
        root.addChildNode(model)
        for part in BodyPart.allCases {
            guard let info = mesh.parts[part], let geometry = info.geometry.copy() as? SCNGeometry else { continue }
            let node = SCNNode(geometry: geometry)
            node.name = part.rawValue
            // Turn around the joint, not the middle of the block.
            node.pivot = SCNMatrix4MakeTranslation(info.pivot.x, info.pivot.y, info.pivot.z)
            node.position = info.pivot
            node.castsShadow = true
            model.addChildNode(node)
            limbs[part] = node
        }
        apply(.starter)
    }

    // Puts on a look; clothes pictures download in the background.
    func apply(_ next: AvatarLook, shirtImage: UIImage? = nil, pantsImage: UIImage? = nil, wait: Bool = false) {
        look = next
        dressing?.cancel()
        paint(shirt: shirtImage, pants: pantsImage)
        let needShirt = shirtImage == nil && !next.shirtURL.isEmpty
        let needPants = pantsImage == nil && !next.pantsURL.isEmpty
        guard !wait, needShirt || needPants else { return }
        dressing = Task { [weak self] in
            var shirt = shirtImage
            if needShirt { shirt = await ClothStore.image(url: next.shirtURL) }
            var pants = pantsImage
            if needPants { pants = await ClothStore.image(url: next.pantsURL) }
            guard !Task.isCancelled, let self, self.look == next else { return }
            self.paint(shirt: shirt, pants: pants)
        }
    }

    private func paint(shirt: UIImage?, pants: UIImage?) {
        for (part, node) in limbs {
            node.geometry?.materials = [AvatarPaint.material(part, look: look, shirt: shirt, pants: pants)]
        }
    }

    func play(_ next: Emote?) {
        emote = next
        emoteClock = 0
    }

    // Arms and legs: swing while walking, reach up while in the air, a soft
    // sway standing still, or an emote. `speed` is 0…1 of walking speed.
    func animate(speed: Float, airborne: Bool, dt: Float, time: Float) {
        phase += dt * (6 + 6 * speed) * (speed > 0.05 ? 1 : 0)
        if speed > 0.15 || airborne { emote = nil }
        let swing = sin(phase) * min(speed, 1)
        var arms: (Float, Float) = (swing, -swing)
        var legs: (Float, Float) = (-swing, swing)
        var spread: (Float, Float) = (0, 0)
        var lift: Float = 0
        var turn: Float = 0
        if airborne {
            arms = (-2.7, -2.7)
            legs = (-0.25, 0.25)
            spread = (-0.08, 0.08)
        } else if let emote {
            emoteClock += dt
            let t = emoteClock
            switch emote {
            case .wave:
                arms = (-2.9, 0)
                spread = (-0.35 - 0.35 * sin(t * 9), 0)
            case .dance:
                let beat = sin(t * 7)
                arms = (-1.4 + beat * 0.9, -1.4 - beat * 0.9)
                legs = (beat * 0.35, -beat * 0.35)
                lift = abs(sin(t * 7)) * 0.25
                turn = sin(t * 3.5) * 0.35
            case .cheer:
                let bounce = abs(sin(t * 8))
                arms = (-2.9, -2.9)
                spread = (-0.25 - bounce * 0.2, 0.25 + bounce * 0.2)
                lift = bounce * 0.35
            case .sit:
                legs = (-1.55, -1.55)
                arms = (-0.6, -0.6)
                lift = -1.45
            }
            if emote != .sit && t > 4 { self.emote = nil }
        } else if speed < 0.05 {
            let idle = sin(time * 1.6) * 0.06
            arms = (idle, -idle)
            legs = (0, 0)
        }
        let k = min(1, dt * 14)
        blend(.rightArm, x: arms.0, z: spread.0, k)
        blend(.leftArm, x: arms.1, z: spread.1, k)
        blend(.rightLeg, x: legs.0, z: 0, k)
        blend(.leftLeg, x: legs.1, z: 0, k)
        let base = AvatarMesh.shared.feet
        model.position.y += (base + lift - model.position.y) * k
        model.eulerAngles.y += (turn - model.eulerAngles.y) * k
    }

    private func blend(_ part: BodyPart, x: Float, z: Float, _ k: Float) {
        guard let node = limbs[part] else { return }
        var e = node.eulerAngles
        e.x += (x - e.x) * k
        e.z += (z - e.z) * k
        node.eulerAngles = e
    }

    // Standing pose (for the avatar editor).
    func rest() {
        for (_, node) in limbs { node.eulerAngles = SCNVector3Zero }
    }
}
