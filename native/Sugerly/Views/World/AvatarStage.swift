import SwiftUI
import SceneKit
import Metal

// A little 3D stage with an avatar on a turntable: drag sideways to turn it.
struct AvatarStage: UIViewRepresentable {
    enum Framing { case full, upper, head, back }

    var look: AvatarLook
    var spin = false
    var framing: Framing = .full
    // The clothes studio shows what you're painting before it's saved.
    var shirtImage: UIImage? = nil
    var pantsImage: UIImage? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let c = context.coordinator
        let view = SCNView(frame: .zero)
        view.scene = c.scene
        view.pointOfView = c.camera
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.rendersContinuously = false
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.panned(_:)))
        view.addGestureRecognizer(pan)
        c.update(look, shirt: shirtImage, pants: pantsImage)
        c.frame(framing)
        c.setSpin(spin)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        c.update(look, shirt: shirtImage, pants: pantsImage)
        c.frame(framing)
        c.setSpin(spin)
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene = SCNScene()
        let camera = SCNNode()
        private let turntable = SCNNode()
        private let avatar = Avatar3D()
        private var shown: AvatarLook?
        private weak var shownShirt: UIImage?
        private weak var shownPants: UIImage?
        private var framing: Framing?
        private var spinning = false

        override init() {
            super.init()
            AvatarSnapshot.light(scene)
            let cam = SCNCamera()
            cam.fieldOfView = 30
            cam.zNear = 0.5
            cam.zFar = 100
            camera.camera = cam
            scene.rootNode.addChildNode(camera)
            avatar.rest()
            turntable.addChildNode(avatar.root)
            scene.rootNode.addChildNode(turntable)
            let floor = SCNNode(geometry: SCNCylinder(radius: 2.2, height: 0.12))
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(hex: 0xFFFFFF).withAlphaComponent(0.65)
            m.lightingModel = .constant
            floor.geometry?.materials = [m]
            floor.position = SCNVector3(0, -0.06, 0)
            turntable.addChildNode(floor)
        }

        func update(_ look: AvatarLook, shirt: UIImage?, pants: UIImage?) {
            guard look != shown || shirt !== shownShirt || pants !== shownPants else { return }
            shown = look
            shownShirt = shirt
            shownPants = pants
            avatar.apply(look, shirtImage: shirt, pantsImage: pants)
        }

        func frame(_ f: Framing) {
            guard f != framing else { return }
            framing = f
            AvatarSnapshot.aim(camera, f)
            if f == .back { turntable.eulerAngles.y = .pi } else if !spinning { turntable.eulerAngles.y = -0.35 }
        }

        func setSpin(_ on: Bool) {
            guard on != spinning else { return }
            spinning = on
            turntable.removeAction(forKey: "spin")
            if on { turntable.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 9)), forKey: "spin") }
        }

        @objc func panned(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            turntable.removeAction(forKey: "spin")
            spinning = false
            turntable.eulerAngles.y += Float(t.x) * 0.012
            g.setTranslation(.zero, in: g.view)
        }
    }
}

// Pictures of avatars wearing things, for the catalog and the editor.
@MainActor
enum AvatarSnapshot {
    private static var cache: [String: UIImage] = [:]
    private static let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    private static let scene = SCNScene()
    private static let camera = SCNNode()
    private static let turntable = SCNNode()
    private static var avatar: Avatar3D?

    static let mannequin: AvatarLook = {
        var look = AvatarLook()
        look.shirt = ""
        look.pants = ""
        look.face = "cute"
        return look
    }()

    static func light(_ scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 560
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 720
        key.eulerAngles = SCNVector3(-0.5, 0.45, 0)
        scene.rootNode.addChildNode(key)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 260
        rim.light?.color = UIColor(hex: 0xFFD6E6)
        rim.eulerAngles = SCNVector3(-0.3, .pi * 0.85, 0)
        scene.rootNode.addChildNode(rim)
    }

    static func aim(_ camera: SCNNode, _ f: AvatarStage.Framing) {
        switch f {
        case .full, .back:
            camera.position = SCNVector3(0, 2.75, 13.5)
            camera.look(at: SCNVector3(0, 2.6, 0))
        case .upper:
            camera.position = SCNVector3(0, 3.4, 9)
            camera.look(at: SCNVector3(0, 3.25, 0))
        case .head:
            camera.position = SCNVector3(0, 4.95, 5.6)
            camera.look(at: SCNVector3(0, 4.7, 0))
        }
    }

    // How an item is shown: on a plain body, from the side that shows it best.
    static func framing(for kind: CatalogItem.Kind) -> AvatarStage.Framing {
        switch kind {
        case .shirt: return .upper
        case .pants: return .full
        case .hat, .face: return .head
        case .back: return .back
        }
    }

    static func look(trying item: CatalogItem, on base: AvatarLook) -> AvatarLook {
        var look = base
        switch item.kind {
        case .shirt: look.shirt = item.id; look.shirtURL = item.imageURL
        case .pants: look.pants = item.id; look.pantsURL = item.imageURL
        case .face: look.face = item.lookValue
        case .hat: look.hat = item.id
        case .back: look.extra = item.id
        }
        return look
    }

    static func cached(_ item: CatalogItem) -> UIImage? { cache[item.id] }

    // A square picture of the item on a plain body.
    static func image(for item: CatalogItem, side: CGFloat = 300) async -> UIImage? {
        if let hit = cache[item.id] { return hit }
        let dressed = Self.look(trying: item, on: mannequin)
        let shirt = await ClothStore.image(id: dressed.shirt, url: dressed.shirtURL)
        let pants = await ClothStore.image(id: dressed.pants, url: dressed.pantsURL)
        if item.kind.paintable && (item.kind == .shirt ? shirt : pants) == nil { return nil }
        let image = render(dressed, shirt: shirt, pants: pants, framing: Self.framing(for: item.kind), side: side)
        cache[item.id] = image
        return image
    }

    static func render(_ look: AvatarLook, shirt: UIImage?, pants: UIImage?, framing: AvatarStage.Framing, side: CGFloat) -> UIImage {
        if avatar == nil {
            light(scene)
            let cam = SCNCamera()
            cam.fieldOfView = 30
            camera.camera = cam
            scene.rootNode.addChildNode(camera)
            let made = Avatar3D()
            made.rest()
            turntable.addChildNode(made.root)
            scene.rootNode.addChildNode(turntable)
            avatar = made
            renderer.scene = scene
            renderer.pointOfView = camera
        }
        // Clothes go on right away (no download): both pictures are given.
        avatar?.apply(look, shirtImage: shirt ?? UIImage(), pantsImage: pants ?? UIImage())
        aim(camera, framing)
        turntable.eulerAngles.y = framing == .back ? .pi * 0.85 : -0.3
        return renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
    }
}

// Buying, wearing and getting paid for clothes.
@MainActor
enum CatalogShop {
    static let creatorShare = 0.7

    static func owns(_ item: CatalogItem, _ me: UserProfile) -> Bool {
        if item.builtIn && item.price == 0 { return true }
        if me.avatarItems.contains(item.id) { return true }
        return !item.creatorEmail.isEmpty && item.creatorEmail == me.email
    }

    static func wearing(_ item: CatalogItem, _ look: AvatarLook) -> Bool {
        switch item.kind {
        case .shirt: return look.shirt == item.id
        case .pants: return look.pants == item.id
        case .face: return look.face == item.lookValue
        case .hat: return look.hat == item.id
        case .back: return look.extra == item.id
        }
    }

    // Pays and adds it to what you own; the maker's share waits for them.
    static func buy(_ item: CatalogItem, model: AppModel) async throws {
        guard let me = model.me else { throw APIError(message: "Please log in again.") }
        if owns(item, me) { return }
        guard me.coins >= item.price else {
            throw APIError(message: "You need \(item.price - me.coins) more coins.")
        }
        var fields: Doc = ["avatar_items": me.avatarItems + [item.id]]
        if item.price > 0 { fields["coins"] = me.coins - item.price }
        try await model.updateMe(fields)
        guard !item.builtIn else { return }
        try? await FS.change("CatalogItem", item.id, [.increment("sales", 1)])
        if item.price > 0, !item.creatorEmail.isEmpty, item.creatorEmail != me.email {
            let payout = Int((Double(item.price) * creatorShare).rounded(.down))
            let sale: Doc = [
                "item_id": item.id, "item_name": item.name, "buyer_email": me.email, "buyer_name": me.displayName,
                "creator_email": item.creatorEmail, "price": item.price, "payout": payout, "claimed": false,
            ]
            _ = try? await FS.create("CatalogSale", sale)
        }
    }

    static func wear(_ item: CatalogItem, model: AppModel) async {
        guard let me = model.me else { return }
        let look = AvatarSnapshot.look(trying: item, on: me.avatar)
        try? await model.updateMe(["avatar_look": look.json])
    }

    // Coins from people who bought your clothes since you last looked.
    @discardableResult
    static func collect(model: AppModel) async -> Int {
        guard let me = model.me else { return 0 }
        guard let docs = try? await FS.query("CatalogSale", [.equals("creator_email", me.email), .equals("claimed", false)], limit: 200),
              !docs.isEmpty else { return 0 }
        let total = docs.reduce(0) { $0 + max(0, $1.int("payout")) }
        let now = FS.nowISO()
        let writes: [FS.Write] = docs.map { .change("CatalogSale", $0.str("id"), [], set: ["claimed": true, "claimed_date": now]) }
        do {
            try await FS.commit(writes)
        } catch {
            return 0
        }
        guard total > 0 else { return 0 }
        try? await model.addToMe(["coins": total])
        model.showToast("Your clothes earned you \(total) coins!", icon: "sparkles")
        return total
    }

    // The people-made things you own (their pictures live on their records).
    static func ownedMade(_ me: UserProfile) async -> [CatalogItem] {
        let ids = me.avatarItems.filter { !$0.contains(":") }
        guard !ids.isEmpty else { return [] }
        var out: [CatalogItem] = []
        for chunk in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
            let docs = (try? await FS.getMany("CatalogItem", chunk)) ?? [:]
            out += chunk.compactMap { id in docs[id].flatMap { CatalogItem($0) } }
        }
        return out
    }
}
