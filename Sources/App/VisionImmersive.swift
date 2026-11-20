#if os(visionOS)
import simd
import SwiftUI
import RealityKit
import AstroCore

/// Apple Vision Pro: a table-top orrery around you. Sun + planets + the Moon at their real positions
/// (AstroCore ephemeris), distances compressed (sqrt of AU) so Neptune sits ~1.6 m from the Sun,
/// sizes exaggerated so every planet is visible. Time follows the app's clock (rate and pause).
struct SolarImmersiveView: View {
    @EnvironmentObject var model: AppModel
    @State private var nodes: [BodyID: Entity] = [:]
    static let ids: [BodyID] = [.sun, .mercury, .venus, .earth, .moon, .mars, .jupiter, .saturn, .uranus, .neptune]

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.position = [0, 0.95, -1.25]        // in front of the viewer, below eye height
            root.orientation = simd_quatf(angle: 0.25, axis: [1, 0, 0])
            content.add(root)
            var made: [BodyID: Entity] = [:]
            for id in Self.ids {
                let e = Self.sphere(for: id)
                root.addChild(e)
                made[id] = e
                if id != .sun && id != .moon { root.addChild(Self.orbitRing(id)) }
            }
            if let saturn = made[.saturn] { saturn.addChild(Self.saturnRing()) }
            let light = PointLight()
            light.light.intensity = 40000
            light.light.attenuationRadius = 10
            root.addChild(light)
            nodes = made
            Self.place(made, jd: model.viewer.clock.jd)
        } update: { _ in }
        .task {
            while !Task.isCancelled {
                Self.place(nodes, jd: model.viewer.clock.jd)
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    static func scenePos(_ km: V3) -> SIMD3<Float> {
        let s = Frames.eclToScene * km
        let au = length(s) / Frames.au
        guard au > 1e-9 else { return .zero }
        let r = 0.29 * sqrt(au)                  // metres
        let d = s / length(s) * r
        return SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z))
    }

    static func place(_ nodes: [BodyID: Entity], jd: Double) {
        guard !nodes.isEmpty else { return }
        let st = Ephemeris.state(jd: jd)
        for (id, e) in nodes where id != .moon && id != .sun { e.position = scenePos(st[id]) }
        if let m = nodes[.moon], let earth = nodes[.earth] {
            let rel = Frames.eclToScene * (st[.moon] - st[.earth])
            let dir = rel / max(length(rel), 1)
            m.position = earth.position + SIMD3<Float>(Float(dir.x), Float(dir.y), Float(dir.z)) * 0.03
        }
        let w = Float(jd.truncatingRemainder(dividingBy: 1)) * 2 * .pi
        for (id, e) in nodes where id != .sun { e.orientation = simd_quatf(angle: w * (id == .moon ? 0 : 1), axis: [0, 1, 0]) }
    }

    static func radius(_ id: BodyID) -> Float {
        switch id {
        case .sun: return 0.07
        case .jupiter: return 0.032
        case .saturn: return 0.027
        case .uranus, .neptune: return 0.019
        case .earth, .venus: return 0.012
        case .mars: return 0.009
        case .mercury: return 0.007
        case .moon: return 0.004
        default: return 0.006
        }
    }

    static func texture(_ name: String) -> TextureResource? {
        let parts = name.split(separator: ".")
        let base = String(parts[0])
        let exts = parts.count == 2 ? [String(parts[1])] : ["jpg", "png"]
        for ext in exts {
            if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Textures"),
               let t = try? TextureResource.load(contentsOf: url) { return t }
        }
        return nil
    }

    static func sphere(for id: BodyID) -> Entity {
        let body = Catalog.body(id)
        let mesh = MeshResource.generateSphere(radius: radius(id))
        let tex = body.texture.flatMap { texture($0) }
        let e: ModelEntity
        if id == .sun {
            var m = UnlitMaterial(color: UIColor(red: 1, green: 0.78, blue: 0.4, alpha: 1))
            if let t = tex { m.color = .init(tint: UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1), texture: .init(t)) }
            e = ModelEntity(mesh: mesh, materials: [m])
        } else {
            var m = PhysicallyBasedMaterial()
            if let t = tex { m.baseColor = .init(tint: .white, texture: .init(t)) }
            else { m.baseColor = .init(tint: UIColor(red: body.color.0, green: body.color.1, blue: body.color.2, alpha: 1)) }
            m.roughness = 0.9
            e = ModelEntity(mesh: mesh, materials: [m])
        }
        e.components.set(InputTargetComponent())
        e.generateCollisionShapes(recursive: false)
        e.name = id.key
        return e
    }

    static func orbitRing(_ id: BodyID) -> Entity {
        // Thin ring at the planet's mean distance (compressed), drawn as small beads.
        let parent = Entity()
        guard case .planet(let p) = Catalog.body(id).orbit else { return parent }
        let pts = PlanetTheory.orbit(p, jd: AstroTime.j2000, count: 120)
        let bead = MeshResource.generateSphere(radius: 0.0012)
        let mat = UnlitMaterial(color: UIColor(white: 0.6, alpha: 1))
        for q in pts {
            let b = ModelEntity(mesh: bead, materials: [mat])
            b.position = scenePos(q)
            parent.addChild(b)
        }
        return parent
    }

    static func saturnRing() -> Entity {
        let mesh = MeshResource.generatePlane(width: 0.12, depth: 0.12)
        var m = UnlitMaterial(color: .white)
        if let t = texture("saturn_ring.png") { m.color = .init(tint: .white, texture: .init(t)) }
        m.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let e = ModelEntity(mesh: mesh, materials: [m])
        e.orientation = simd_quatf(angle: 0.47, axis: [1, 0, 0])
        return e
    }
}

/// Screenshot runs ("-shot immersive") open the orrery right away.
struct ImmersiveShotOpener: ViewModifier {
    @Environment(\.openImmersiveSpace) private var openSpace
    @EnvironmentObject var model: AppModel
    func body(content: Content) -> some View {
        content.task {
            guard model.immersiveShot, !model.immersiveOpen else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if case .opened = await openSpace(id: "orrery") { model.immersiveOpen = true }
        }
    }
}

/// Top-bar button: open / close the immersive orrery.
struct ImmersiveToggle: View {
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button {
            Task {
                if model.immersiveOpen { await dismissSpace(); model.immersiveOpen = false }
                else if case .opened = await openSpace(id: "orrery") { model.immersiveOpen = true }
            }
        } label: {
            Image(systemName: model.immersiveOpen ? "cube.fill" : "cube")
                .font(.system(size: 17, weight: .regular))
                .frame(width: 34, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("vision.immersive"))
    }
}
#endif
