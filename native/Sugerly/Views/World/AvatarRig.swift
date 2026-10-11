import SceneKit
import simd
import UIKit

// The 3D body from BoyR6.obj: six blocks (head, body, two arms, two legs).
// The file's arms, body and legs carry no picture mapping, so each block is
// unfolded here like a box (see ClothTemplate) and the head gets a flat
// "face" mapping on its front. Faces point +Z; the feet stand on y = 0.

struct AvatarMesh {
    struct Part {
        let part: BodyPart
        let geometry: SCNGeometry
        let pivot: SCNVector3      // joint (shoulder, hip, neck) in model space
        let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)
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
            parts[part] = Part(part: part, geometry: geometry, pivot: joint(part, lo, hi), bounds: (lo, hi))
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
        let block = ClothTemplate.block(for: part)
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
                    if let block {
                        uvs.append(boxUV(rel, flat, block))
                    } else {
                        // Head: the face picture is projected from the front.
                        uvs.append(flat.z > 0.2 ? CGPoint(x: CGFloat(rel.x), y: CGFloat(1 - rel.y)) : CGPoint(x: 0.02, y: 0.02))
                    }
                }
            }
        }
        let indices: [Int32] = (0..<Int32(verts.count)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [
            SCNGeometrySource(vertices: verts),
            SCNGeometrySource(normals: norms),
            SCNGeometrySource(textureCoordinates: uvs),
        ], elements: [element])
        return geometry
    }

    // Where a point on a block lands in that block's unfolded picture (0…1).
    private static func boxUV(_ rel: SIMD3<Float>, _ n: SIMD3<Float>, _ block: ClothTemplate.Block) -> CGPoint {
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
        let r = block.local(face)
        // Keep a hair inside the face so edges don't pick up the next face.
        fu = min(max(fu, 0.01), 0.99)
        fv = min(max(fv, 0.01), 0.99)
        return CGPoint(x: (r.minX + fu * r.width) / block.width, y: (r.minY + fv * r.height) / block.height)
    }

    // If the model file is missing: plain blocks of the same sizes.
    private static func fallback() -> AvatarMesh {
        func box(_ part: BodyPart, _ c: SIMD3<Float>, _ s: SIMD3<Float>) -> Part {
            let g = SCNBox(width: CGFloat(s.x), height: CGFloat(s.y), length: CGFloat(s.z), chamferRadius: 0.06)
            let node = SCNNode(geometry: g)
            node.position = SCNVector3(c.x, c.y, c.z)
            let flat = node.flattenedClone().geometry ?? g
            let lo = c - s / 2, hi = c + s / 2
            return Part(part: part, geometry: flat, pivot: joint(part, lo, hi), bounds: (lo, hi))
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
    static let unit: CGFloat = 80   // pixels per body unit on the blocks

    // A block's picture: its skin colour, then pants, then the shirt on top.
    static func texture(_ part: BodyPart, look: AvatarLook, shirt: UIImage?, pants: UIImage?) -> UIImage {
        if part == .head { return face(look.face, skin: look.color(.head)) }
        guard let block = ClothTemplate.block(for: part) else { return UIImage() }
        let size = CGSize(width: block.width * unit, height: block.height * unit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(hex: look.color(part)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let layers: [UIImage?]
            switch part {
            case .torso: layers = [pants, shirt]
            case .rightArm, .leftArm: layers = [shirt]
            default: layers = [pants]
            }
            for layer in layers {
                guard let layer, let cg = layer.cgImage else { continue }
                // The template may be any size: find this block in it.
                let scale = CGFloat(cg.width) / ClothTemplate.side
                let src = block.frame.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
                guard let crop = cg.cropping(to: src) else { continue }
                UIImage(cgImage: crop).draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    // The head's picture: skin with a face drawn on the front.
    static func face(_ name: String, skin: UInt32) -> UIImage {
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            UIColor(hex: skin).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            drawFace(name, in: cg, side: side)
        }
    }

    // Also used for the little face pictures in the catalog.
    static func drawFace(_ name: String, in cg: CGContext, side s: CGFloat) {
        let ink = UIColor(hex: 0x2A1F33)
        let blush = UIColor(hex: 0xFF8FB1).withAlphaComponent(0.75)
        let eyeY = s * 0.43, mouthY = s * 0.58
        let lx = s * 0.36, rx = s * 0.64
        func eye(_ x: CGFloat, _ w: CGFloat = 0.075, _ h: CGFloat = 0.1) {
            cg.setFillColor(ink.cgColor)
            cg.fillEllipse(in: CGRect(x: x - s * w / 2, y: eyeY - s * h / 2, width: s * w, height: s * h))
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: x - s * 0.012, y: eyeY - s * 0.035, width: s * 0.024, height: s * 0.024))
        }
        func cheeks() {
            cg.setFillColor(blush.cgColor)
            cg.fillEllipse(in: CGRect(x: lx - s * 0.1, y: eyeY + s * 0.05, width: s * 0.1, height: s * 0.055))
            cg.fillEllipse(in: CGRect(x: rx, y: eyeY + s * 0.05, width: s * 0.1, height: s * 0.055))
        }
        func stroke(_ build: (CGMutablePath) -> Void, width: CGFloat = 0.022) {
            let p = CGMutablePath()
            build(p)
            cg.setStrokeColor(ink.cgColor)
            cg.setLineWidth(s * width)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.addPath(p)
            cg.strokePath()
        }
        func closedEye(_ x: CGFloat, happy: Bool) {
            stroke { p in
                p.move(to: CGPoint(x: x - s * 0.045, y: eyeY + (happy ? s * 0.01 : 0)))
                p.addQuadCurve(to: CGPoint(x: x + s * 0.045, y: eyeY + (happy ? s * 0.01 : 0)),
                               control: CGPoint(x: x, y: eyeY + (happy ? -s * 0.05 : s * 0.04)))
            }
        }
        func smile(_ w: CGFloat = 0.07, _ depth: CGFloat = 0.05) {
            stroke { p in
                p.move(to: CGPoint(x: s * 0.5 - s * w, y: mouthY))
                p.addQuadCurve(to: CGPoint(x: s * 0.5 + s * w, y: mouthY), control: CGPoint(x: s * 0.5, y: mouthY + s * depth))
            }
        }
        func catMouth() {
            stroke { p in
                p.move(to: CGPoint(x: s * 0.44, y: mouthY - s * 0.01))
                p.addQuadCurve(to: CGPoint(x: s * 0.5, y: mouthY), control: CGPoint(x: s * 0.47, y: mouthY + s * 0.04))
                p.addQuadCurve(to: CGPoint(x: s * 0.56, y: mouthY - s * 0.01), control: CGPoint(x: s * 0.53, y: mouthY + s * 0.04))
            }
        }
        func heartEye(_ x: CGFloat) {
            let r = s * 0.032
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: eyeY + r * 1.6))
            p.addCurve(to: CGPoint(x: x - r * 1.6, y: eyeY - r * 0.2), control1: CGPoint(x: x - r * 0.6, y: eyeY + r), control2: CGPoint(x: x - r * 1.6, y: eyeY + r * 0.4))
            p.addArc(center: CGPoint(x: x - r * 0.8, y: eyeY - r * 0.5), radius: r * 0.85, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addArc(center: CGPoint(x: x + r * 0.8, y: eyeY - r * 0.5), radius: r * 0.85, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addCurve(to: CGPoint(x: x, y: eyeY + r * 1.6), control1: CGPoint(x: x + r * 1.6, y: eyeY + r * 0.4), control2: CGPoint(x: x + r * 0.6, y: eyeY + r))
            cg.setFillColor(UIColor(hex: 0xF0457A).cgColor)
            cg.addPath(p)
            cg.fillPath()
        }

        switch name {
        case "smile":
            eye(lx); eye(rx); smile(0.09, 0.07)
        case "wink":
            eye(lx); closedEye(rx, happy: true); cheeks(); smile()
        case "sleepy":
            closedEye(lx, happy: false); closedEye(rx, happy: false); cheeks()
            stroke { p in p.addEllipse(in: CGRect(x: s * 0.48, y: mouthY - s * 0.01, width: s * 0.04, height: s * 0.035)) }
        case "wow":
            eye(lx, 0.085, 0.12); eye(rx, 0.085, 0.12); cheeks()
            cg.setFillColor(ink.cgColor)
            cg.fillEllipse(in: CGRect(x: s * 0.47, y: mouthY - s * 0.01, width: s * 0.06, height: s * 0.07))
        case "love":
            heartEye(lx); heartEye(rx); cheeks(); smile(0.08, 0.06)
        case "cat":
            closedEye(lx, happy: true); closedEye(rx, happy: true); cheeks(); catMouth()
            stroke({ p in
                for side in [-1.0, 1.0] as [CGFloat] {
                    for dy in [-0.012, 0.018] as [CGFloat] {
                        p.move(to: CGPoint(x: s * 0.5 + side * s * 0.17, y: mouthY + s * dy))
                        p.addLine(to: CGPoint(x: s * 0.5 + side * s * 0.27, y: mouthY + s * dy * 1.6))
                    }
                }
            }, width: 0.01)
        case "cool":
            cg.setFillColor(ink.cgColor)
            let glass = CGMutablePath()
            glass.addRoundedRect(in: CGRect(x: lx - s * 0.09, y: eyeY - s * 0.05, width: s * 0.17, height: s * 0.1), cornerWidth: s * 0.03, cornerHeight: s * 0.03)
            glass.addRoundedRect(in: CGRect(x: rx - s * 0.08, y: eyeY - s * 0.05, width: s * 0.17, height: s * 0.1), cornerWidth: s * 0.03, cornerHeight: s * 0.03)
            glass.addRect(CGRect(x: lx + s * 0.07, y: eyeY - s * 0.03, width: rx - lx - s * 0.14, height: s * 0.02))
            cg.addPath(glass)
            cg.fillPath()
            cg.setFillColor(UIColor.white.withAlphaComponent(0.5).cgColor)
            cg.fill(CGRect(x: lx - s * 0.06, y: eyeY - s * 0.035, width: s * 0.03, height: s * 0.02))
            smile(0.06, 0.035)
        default: // cute
            eye(lx); eye(rx); cheeks()
            stroke { p in
                p.move(to: CGPoint(x: s * 0.45, y: mouthY - s * 0.01))
                p.addQuadCurve(to: CGPoint(x: s * 0.5, y: mouthY), control: CGPoint(x: s * 0.475, y: mouthY + s * 0.035))
                p.addQuadCurve(to: CGPoint(x: s * 0.55, y: mouthY - s * 0.01), control: CGPoint(x: s * 0.525, y: mouthY + s * 0.035))
            }
        }
    }

    static func material(_ image: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.lightingModel = .lambert
        return m
    }
}

// MARK: - one avatar in the scene

@MainActor
final class Avatar3D {
    let root = SCNNode()
    private(set) var look = AvatarLook()
    private var limbs: [BodyPart: SCNNode] = [:]
    private let model = SCNNode()
    private var hatNode: SCNNode?
    private var backNode: SCNNode?
    private var dressing: Task<Void, Never>?
    private var phase: Float = 0

    var head: SCNNode? { limbs[.head] }
    var torso: SCNNode? { limbs[.torso] }

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
    func apply(_ next: AvatarLook, shirtImage: UIImage? = nil, pantsImage: UIImage? = nil) {
        look = next
        dressing?.cancel()
        // Skin and face straight away, clothes as soon as they're here.
        paint(shirt: shirtImage ?? (next.shirt.hasPrefix("b:") ? BuiltInClothes.image(next.shirt) : nil),
              pants: pantsImage ?? (next.pants.hasPrefix("b:") ? BuiltInClothes.image(next.pants) : nil))
        setAccessories(hat: next.hat, back: next.extra)
        guard shirtImage == nil || pantsImage == nil else { return }
        dressing = Task { [weak self] in
            var shirt = shirtImage
            if shirt == nil { shirt = await ClothStore.image(id: next.shirt, url: next.shirtURL) }
            var pants = pantsImage
            if pants == nil { pants = await ClothStore.image(id: next.pants, url: next.pantsURL) }
            guard !Task.isCancelled, let self, self.look == next else { return }
            self.paint(shirt: shirt, pants: pants)
        }
    }

    private func paint(shirt: UIImage?, pants: UIImage?) {
        for (part, node) in limbs {
            node.geometry?.materials = [AvatarPaint.material(AvatarPaint.texture(part, look: look, shirt: shirt, pants: pants))]
        }
    }

    private func setAccessories(hat: String, back: String) {
        hatNode?.removeFromParentNode()
        backNode?.removeFromParentNode()
        hatNode = nil
        backNode = nil
        if let headNode = limbs[.head], let made = Accessories.make(hat) {
            headNode.addChildNode(made)
            hatNode = made
        }
        if let torsoNode = limbs[.torso], let made = Accessories.make(back) {
            torsoNode.addChildNode(made)
            backNode = made
        }
    }

    // Arms and legs: swing while walking, reach up while in the air, a soft
    // sway standing still. `speed` is 0…1 of full walking speed.
    func animate(speed: Float, airborne: Bool, dt: Float, time: Float) {
        phase += dt * (6 + 6 * speed) * (speed > 0.05 ? 1 : 0)
        let swing = sin(phase) * 1.0 * min(speed, 1)
        var arms: (Float, Float) = (swing, -swing)
        var legs: (Float, Float) = (-swing, swing)
        var spread: Float = 0
        if airborne {
            arms = (-2.7, -2.7)
            legs = (-0.25, 0.25)
            spread = 0.08
        } else if speed < 0.05 {
            let idle = sin(time * 1.6) * 0.06
            arms = (idle, -idle)
            legs = (0, 0)
        }
        let k = min(1, dt * 14)
        blend(.rightArm, x: arms.0, z: -spread, k)
        blend(.leftArm, x: arms.1, z: spread, k)
        blend(.rightLeg, x: legs.0, z: 0, k)
        blend(.leftLeg, x: legs.1, z: 0, k)
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

// MARK: - accessories, made from simple shapes

@MainActor
enum Accessories {
    private static func mat(_ hex: UInt32, glow: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex)
        m.lightingModel = .lambert
        if glow { m.emission.contents = UIColor(hex: hex).withAlphaComponent(0.7) }
        return m
    }

    private static func node(_ g: SCNGeometry, _ hex: UInt32, at p: SCNVector3, glow: Bool = false) -> SCNNode {
        g.materials = [mat(hex, glow: glow)]
        let n = SCNNode(geometry: g)
        n.position = p
        n.castsShadow = true
        return n
    }

    // Head pieces sit on the head (its top is about y = 3.1 in the model);
    // back pieces hang on the body (its back is z = -0.5).
    static func make(_ id: String) -> SCNNode? {
        guard !id.isEmpty else { return nil }
        let root = SCNNode()
        root.name = "accessory"
        let top: Float = 3.08
        switch id {
        case "h:bunny":
            for side in [-1, 1] as [Float] {
                let ear = node(SCNCapsule(capRadius: 0.2, height: 1.4), 0xFFFFFF, at: SCNVector3(side * 0.3, top + 0.55, -0.05))
                ear.eulerAngles.z = -side * 0.22
                ear.scale = SCNVector3(1, 1, 0.55)
                let inner = node(SCNCapsule(capRadius: 0.11, height: 1.0), 0xFFB3CB, at: SCNVector3(0, 0, 0.12))
                ear.addChildNode(inner)
                root.addChildNode(ear)
            }
        case "h:cat":
            for side in [-1, 1] as [Float] {
                let ear = node(SCNPyramid(width: 0.5, height: 0.55, length: 0.25), 0x3B3B4F, at: SCNVector3(side * 0.34, top - 0.08, 0))
                ear.eulerAngles.z = -side * 0.25
                root.addChildNode(ear)
                let inner = node(SCNPyramid(width: 0.3, height: 0.36, length: 0.1), 0xFFB3CB, at: SCNVector3(side * 0.34, top - 0.05, 0.1))
                inner.eulerAngles.z = -side * 0.25
                root.addChildNode(inner)
            }
        case "h:bow":
            let bow = SCNNode()
            bow.position = SCNVector3(0.42, top - 0.1, 0.05)
            bow.eulerAngles.z = -0.35
            for side in [-1, 1] as [Float] {
                let loop = node(SCNSphere(radius: 0.26), 0xF25C8A, at: SCNVector3(side * 0.24, 0, 0))
                loop.scale = SCNVector3(1.1, 0.75, 0.45)
                bow.addChildNode(loop)
            }
            bow.addChildNode(node(SCNSphere(radius: 0.11), 0xD9406E, at: SCNVector3(0, 0, 0.04)))
            root.addChildNode(bow)
        case "h:crown":
            let band = node(SCNTube(innerRadius: 0.46, outerRadius: 0.52, height: 0.28), 0xFFD166, at: SCNVector3(0, top + 0.08, 0))
            root.addChildNode(band)
            let gems: [UInt32] = [0xF25C8A, 0x7CBEFF, 0x5FD3B0, 0xB19CFF, 0xFF9F5A]
            for i in 0..<5 {
                let a = Float(i) / 5 * .pi * 2
                let spike = node(SCNCone(topRadius: 0, bottomRadius: 0.11, height: 0.32), 0xFFD166, at: SCNVector3(cos(a) * 0.49, top + 0.36, sin(a) * 0.49))
                root.addChildNode(spike)
                root.addChildNode(node(SCNSphere(radius: 0.07), gems[i], at: SCNVector3(cos(a) * 0.52, top + 0.08, sin(a) * 0.52)))
            }
        case "h:cap":
            let dome = node(SCNSphere(radius: 0.64), 0x7CBEFF, at: SCNVector3(0, top - 0.32, 0))
            dome.scale = SCNVector3(1, 0.7, 1)
            root.addChildNode(dome)
            let brim = node(SCNCylinder(radius: 0.42, height: 0.06), 0x2F80E0, at: SCNVector3(0, top - 0.3, 0.55))
            brim.scale = SCNVector3(1, 1, 0.75)
            root.addChildNode(brim)
            root.addChildNode(node(SCNSphere(radius: 0.08), 0xFFFFFF, at: SCNVector3(0, top + 0.13, 0)))
        case "h:halo":
            let ring = node(SCNTorus(ringRadius: 0.42, pipeRadius: 0.06), 0xFFE58A, at: SCNVector3(0, top + 0.45, 0), glow: true)
            root.addChildNode(ring)
            ring.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.08, z: 0, duration: 1.2), .moveBy(x: 0, y: -0.08, z: 0, duration: 1.2)])))
        case "h:phones":
            let arc = node(SCNTorus(ringRadius: 0.66, pipeRadius: 0.06), 0xF7A1C4, at: SCNVector3(0, top - 0.55, 0))
            arc.eulerAngles.x = .pi / 2
            arc.eulerAngles.z = .pi / 2
            root.addChildNode(arc)
            for side in [-1, 1] as [Float] {
                let cup = node(SCNCylinder(radius: 0.26, height: 0.16), 0xF27BA3, at: SCNVector3(side * 0.66, top - 0.6, 0))
                cup.eulerAngles.z = .pi / 2
                root.addChildNode(cup)
            }
        case "h:flower":
            let flower = SCNNode()
            flower.position = SCNVector3(-0.45, top - 0.05, 0.2)
            for i in 0..<6 {
                let a = Float(i) / 6 * .pi * 2
                let petal = node(SCNSphere(radius: 0.11), 0xFFFFFF, at: SCNVector3(cos(a) * 0.15, sin(a) * 0.15, 0))
                petal.scale = SCNVector3(1, 1, 0.5)
                flower.addChildNode(petal)
            }
            flower.addChildNode(node(SCNSphere(radius: 0.09), 0xFFD166, at: SCNVector3(0, 0, 0.04)))
            root.addChildNode(flower)
        case "x:wings":
            for side in [-1, 1] as [Float] {
                let wing = node(SCNSphere(radius: 0.8), 0xD9CCFF, at: SCNVector3(side * 0.75, 1.35, -0.7), glow: true)
                wing.scale = SCNVector3(1.0, 1.25, 0.12)
                wing.eulerAngles.z = side * 0.5
                wing.opacity = 0.85
                root.addChildNode(wing)
                wing.runAction(.repeatForever(.sequence([
                    .rotateBy(x: 0, y: CGFloat(side) * 0.25, z: 0, duration: 0.6),
                    .rotateBy(x: 0, y: CGFloat(-side) * 0.25, z: 0, duration: 0.6),
                ])))
            }
        case "x:backpack":
            let bag = node(SCNBox(width: 1.3, height: 1.4, length: 0.6, chamferRadius: 0.22), 0xF7A1C4, at: SCNVector3(0, 1.0, -0.78))
            root.addChildNode(bag)
            for side in [-1, 1] as [Float] {
                let ear = node(SCNCapsule(capRadius: 0.14, height: 0.6), 0xF7A1C4, at: SCNVector3(side * 0.32, 1.85, -0.78))
                ear.eulerAngles.z = -side * 0.2
                root.addChildNode(ear)
            }
            root.addChildNode(node(SCNSphere(radius: 0.12), 0xFFFFFF, at: SCNVector3(0, 1.05, -1.1)))
        case "x:cape":
            let cape = node(SCNBox(width: 1.9, height: 2.6, length: 0.08, chamferRadius: 0.04), 0xE0508A, at: SCNVector3(0, 0.75, -0.58))
            cape.eulerAngles.x = 0.12
            root.addChildNode(cape)
        default:
            return nil
        }
        return root
    }
}
